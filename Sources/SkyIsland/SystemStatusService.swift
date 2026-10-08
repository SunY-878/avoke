import Foundation
import Combine
import Darwin
import IslandCore
import Network

/// The serial sampling queue owns all mutable reader state.
final class NativeSystemStatusReader: @unchecked Sendable {
    private let host = mach_host_self()
    private var previousCPU: CPUCounters?
    private var previousDate: Date?
    private var cachedDisk: DiskUsage?
    private var diskReadAt: Date?
    private var diskIssue: String?
    private let networkReader = NativeNetworkReader()

    deinit { mach_port_deallocate(mach_task_self_, host) }

    func read(at date: Date = Date()) -> SystemSnapshot {
        var snapshot = SystemSnapshot(thermal: thermalLevel(), uptime: ProcessInfo.processInfo.systemUptime, sampledAt: date)
        if let last = previousDate, date.timeIntervalSince(last) > 3 { previousCPU = nil }
        previousDate = date
        var cpu = host_cpu_load_info_data_t()
        var cpuCount = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let cpuResult = withUnsafeMutablePointer(to: &cpu) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(cpuCount)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &cpuCount)
            }
        }
        if cpuResult == KERN_SUCCESS {
            let current = CPUCounters(user: cpu.cpu_ticks.0, system: cpu.cpu_ticks.1, idle: cpu.cpu_ticks.2, nice: cpu.cpu_ticks.3)
            snapshot.cpu = previousCPU.flatMap { current.usage(since: $0) }
            previousCPU = current
        } else { previousCPU = nil; snapshot.issues.append("CPU 数据暂不可用") }

        var vm = vm_statistics64_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let vmResult = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &vmCount)
            }
        }
        if vmResult == KERN_SUCCESS {
            let pageSize = Double(vm_page_size)
            // Anonymous resident pages exclude file cache; subtract reclaimable pages.
            let appPages = max(0, Double(vm.internal_page_count) - Double(vm.purgeable_count))
            var swap = xsw_usage(), size = MemoryLayout<xsw_usage>.size
            let swapResult = sysctlbyname("vm.swapusage", &swap, &size, nil, 0)
            snapshot.memory = MemoryUsage(total: Double(ProcessInfo.processInfo.physicalMemory),
                                          app: appPages * pageSize, wired: Double(vm.wire_count) * pageSize,
                                          compressed: Double(vm.compressor_page_count) * pageSize,
                                          swap: swapResult == 0 ? Double(swap.xsu_used) : nil)
            if swapResult != 0 { snapshot.issues.append("交换空间数据暂不可用") }
        } else { snapshot.issues.append("内存数据暂不可用") }

        do { snapshot.network = try networkReader.read(at: date) }
        catch { snapshot.issues.append("网络速率暂不可用") }

        // Filesystem capacity can be expensive. Refresh it separately every 15 seconds.
        if diskReadAt == nil || date.timeIntervalSince(diskReadAt!) >= 15 {
            diskReadAt = date
            do {
                let home = URL(fileURLWithPath: NSHomeDirectory())
                let values = try home.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
                guard let total = values.volumeTotalCapacity, total > 0,
                      let available = values.volumeAvailableCapacityForImportantUsage ?? values.volumeAvailableCapacity.map(Int64.init) else {
                    cachedDisk = nil; diskIssue = "磁盘容量暂不可用"; snapshot.disk = nil
                    snapshot.issues.append(diskIssue!); return snapshot
                }
                cachedDisk = DiskUsage(total: Double(total), available: Double(available)); diskIssue = nil
            } catch { cachedDisk = nil; diskIssue = "磁盘容量暂不可用" }
        }
        snapshot.disk = cachedDisk
        if let diskIssue { snapshot.issues.append(diskIssue) }
        return snapshot
    }

    private func thermalLevel() -> ThermalLevel {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .unknown
        }
    }
}

@MainActor final class SystemStatusService: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot()
    @Published private(set) var cpuHistory = MetricHistory()
    @Published private(set) var memoryHistory = MetricHistory()
    @Published private(set) var connection = NetworkConnectionInfo()
    @Published private(set) var connectionNotice: NetworkNotice?
    private(set) var isPreview = false
    let processorCount = ProcessInfo.processInfo.activeProcessorCount
    private let reader = NativeSystemStatusReader()
    private let queue = DispatchQueue(label: "app.skyisland.system-sampling", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var generation = UUID()
    private var pathMonitor: NWPathMonitor?
    private var noticeGeneration = UUID()

    init(start: Bool = true) { if start { self.start() } }
    func start() {
        guard timer == nil, !isPreview else { return }
        let token = UUID(); generation = token
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let state: NetworkConnectionState
            switch path.status {
            case .satisfied: state = .connected
            case .unsatisfied: state = .disconnected
            case .requiresConnection: state = .requiresConnection
            @unknown default: state = .unknown
            }
            let transport: String
            if path.usesInterfaceType(.wiredEthernet) { transport = "以太网" }
            else if path.usesInterfaceType(.wifi) { transport = "Wi-Fi" }
            else if path.usesInterfaceType(.cellular) { transport = "蜂窝网络" }
            else if path.usesInterfaceType(.other) { transport = "其他网络 / VPN" }
            else { transport = "" }
            let connection = NetworkConnectionInfo(state: state, transport: transport)
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.updateConnection(connection)
            }
        }
        pathMonitor = monitor; monitor.start(queue: queue)
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(150))
        let reader = self.reader
        source.setEventHandler { [weak self] in
            let sample = reader.read()
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.snapshot = sample
                if let date = sample.sampledAt {
                    self.cpuHistory.append(sample.cpu?.total, at: date)
                    self.memoryHistory.append(sample.memory?.percentage, at: date)
                }
            }
        }
        timer = source; source.resume()
    }
    func stop() {
        generation = UUID(); timer?.cancel(); timer = nil
        pathMonitor?.cancel(); pathMonitor = nil
        noticeGeneration = UUID(); connectionNotice = nil
    }
    deinit { timer?.cancel(); pathMonitor?.cancel() }

    func updateConnection(_ next: NetworkConnectionInfo) {
        let previous = connection.state
        guard connection != next else { return }
        connection = next
        let notice: NetworkNotice?
        if previous == .connected && (next.state == .disconnected || next.state == .requiresConnection) {
            notice = NetworkNotice(text: "网络连接已断开", isDisconnected: true)
        } else if (previous == .disconnected || previous == .requiresConnection) && next.state == .connected {
            notice = NetworkNotice(text: "网络连接已恢复", isDisconnected: false)
        } else { notice = nil }
        guard let notice else { return }
        connectionNotice = notice
        let token = UUID(); noticeGeneration = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if self?.noticeGeneration == token { self?.connectionNotice = nil }
        }
    }

    static func preview() -> SystemStatusService {
        let service = SystemStatusService(start: false); service.isPreview = true
        let gib = 1_073_741_824.0, date = Date()
        service.snapshot = SystemSnapshot(cpu: CPUCounters(user: 17, system: 7, idle: 76).usage(since: CPUCounters(user: 0, system: 0, idle: 0)),
                                          memory: MemoryUsage(total: 24 * gib, app: 10.4 * gib, wired: 2.1 * gib, compressed: 1.8 * gib, swap: 0.5 * gib),
                                          disk: DiskUsage(total: 512 * gib, available: 198 * gib), network: NetworkRate(download: 3.6 * 1_048_576, upload: 428 * 1024), thermal: .nominal, uptime: 93600, sampledAt: date)
        service.connection = NetworkConnectionInfo(state: .connected, transport: "Wi-Fi")
        for index in 0..<60 {
            let time = date.addingTimeInterval(Double(index - 59))
            service.cpuHistory.append(24 + sin(Double(index) * 0.34) * 10 + cos(Double(index) * 0.63) * 5, at: time)
            service.memoryHistory.append(59.6 + sin(Double(index) * 0.15) * 2, at: time)
        }
        return service
    }
}
