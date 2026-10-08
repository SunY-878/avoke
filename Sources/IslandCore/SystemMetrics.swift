import Foundation

public struct CPUUsage: Equatable, Sendable {
    public let user: Double
    public let system: Double
    public let idle: Double
    public var total: Double { min(100, max(0, user + system)) }
}

public struct CPUCounters: Sendable {
    public let user: UInt32
    public let system: UInt32
    public let idle: UInt32
    public let nice: UInt32
    public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32 = 0) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }
    /// Kernel tick counters are cumulative and can wrap. Normalize across all cores.
    public func usage(since previous: CPUCounters) -> CPUUsage? {
        let user = Double(self.user &- previous.user) + Double(nice &- previous.nice)
        let system = Double(self.system &- previous.system)
        let idle = Double(self.idle &- previous.idle)
        let total = user + system + idle
        guard total > 0 else { return nil }
        return CPUUsage(user: user / total * 100, system: system / total * 100, idle: idle / total * 100)
    }
}

public struct MemoryUsage: Equatable, Sendable {
    public let total: Double
    public let app: Double
    public let wired: Double
    public let compressed: Double
    public let swap: Double?
    public var used: Double { min(total, app + wired + compressed) }
    public var percentage: Double? { total > 0 ? used / total * 100 : nil }

    public init(total: Double, app: Double, wired: Double, compressed: Double, swap: Double?) {
        func safe(_ value: Double) -> Double { value.isFinite ? max(0, value) : 0 }
        self.total = safe(total); self.app = safe(app); self.wired = safe(wired)
        self.compressed = safe(compressed); self.swap = swap.map(safe)
    }
}

public struct DiskUsage: Equatable, Sendable {
    public let total: Double
    public let available: Double
    public var used: Double { total - available }
    public var percentage: Double? { total > 0 ? used / total * 100 : nil }
    public init(total: Double, available: Double) {
        self.total = total.isFinite ? max(0, total) : 0
        self.available = available.isFinite ? min(self.total, max(0, available)) : 0
    }
}

public enum ThermalLevel: String, Sendable {
    case nominal, fair, serious, critical, unknown
    public var label: String {
        switch self { case .nominal: "正常"; case .fair: "轻度"; case .serious: "较高"; case .critical: "严重"; case .unknown: "未知" }
    }
}

public struct SystemSnapshot: Sendable {
    public var cpu: CPUUsage?
    public var memory: MemoryUsage?
    public var disk: DiskUsage?
    public var network: NetworkRate?
    public var thermal: ThermalLevel
    public var uptime: TimeInterval
    public var sampledAt: Date?
    public var issues: [String]
    public init(cpu: CPUUsage? = nil, memory: MemoryUsage? = nil, disk: DiskUsage? = nil, network: NetworkRate? = nil,
                thermal: ThermalLevel = .unknown, uptime: TimeInterval = 0, sampledAt: Date? = nil, issues: [String] = []) {
        self.cpu = cpu; self.memory = memory; self.disk = disk; self.thermal = thermal
        self.network = network
        self.uptime = uptime; self.sampledAt = sampledAt; self.issues = issues
    }
}

public struct TrendPoint: Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public let value: Double
}

public struct MetricHistory: Sendable {
    public private(set) var points: [TrendPoint] = []
    public let capacity: Int
    public init(capacity: Int = 60) { self.capacity = max(1, capacity) }
    public mutating func append(_ value: Double?, at date: Date) {
        guard let value, value.isFinite else { return }
        // An interruption produces a new trend instead of connecting across sleep.
        if let last = points.last, date.timeIntervalSince(last.date) > 3 { points.removeAll(keepingCapacity: true) }
        if points.last?.date == date { points.removeLast() }
        points.append(TrendPoint(date: date, value: min(100, max(0, value))))
        if points.count > capacity { points.removeFirst(points.count - capacity) }
    }
}
