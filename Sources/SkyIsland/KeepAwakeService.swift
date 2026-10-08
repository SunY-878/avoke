import Foundation
import Combine
import IOKit.pwr_mgt
import IslandCore

protocol PowerAssertionBackend: AnyObject {
    func create(_ kind: PowerAssertionKind, duration: TimeInterval?) throws -> UInt32
    func release(_ id: UInt32)
}

final class NativePowerAssertionBackend: PowerAssertionBackend {
    private var owned = Set<UInt32>()
    func create(_ kind: PowerAssertionKind, duration: TimeInterval?) throws -> UInt32 {
        var properties: [String: Any] = [kIOPMAssertionTypeKey: kind.rawValue,
                                        kIOPMAssertionNameKey: "Sky Island · \(kind.rawValue)",
                                        kIOPMAssertionLevelKey: kIOPMAssertionLevelOn]
        if let duration {
            properties[kIOPMAssertionTimeoutKey] = max(0.01, duration)
            properties[kIOPMAssertionTimeoutActionKey] = kIOPMAssertionTimeoutActionRelease
        }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithProperties(properties as CFDictionary, &id)
        guard result == kIOReturnSuccess else {
            throw NSError(domain: "SkyIsland.Power", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "macOS 未能创建防休眠请求（\(result)）"])
        }
        owned.insert(id); return id
    }
    func release(_ id: UInt32) {
        let result = IOPMAssertionRelease(id)
        if result == kIOReturnSuccess || result == kIOReturnNotFound { owned.remove(id) }
    }
    deinit { for id in owned { IOPMAssertionRelease(id) } }
}

@MainActor final class KeepAwakeService: ObservableObject {
    @Published private(set) var session: KeepAwakeSession?
    @Published var selectedMode: KeepAwakeMode = .background
    @Published var selectedDuration: KeepAwakeDuration = .oneHour
    @Published private(set) var message: String?
    private(set) var isPreview = false
    private let backend: PowerAssertionBackend
    private var assertions: [UInt32] = []
    private var expiryTimer: Timer?
    private var generation = UUID()
    private var displaySleepProcess: Process?
    var isActive: Bool { session != nil }

    init(backend: PowerAssertionBackend = NativePowerAssertionBackend()) { self.backend = backend }

    func start() { start(mode: selectedMode, duration: selectedDuration.seconds) }
    func start(mode: KeepAwakeMode, duration: TimeInterval?) {
        guard !isPreview else { return }
        var acquired: [UInt32] = []
        do {
            for kind in mode.assertions { acquired.append(try backend.create(kind, duration: duration)) }
        } catch {
            for id in acquired { backend.release(id) }
            message = "开启失败：\(error.localizedDescription)"; return
        }
        // Acquire the replacement first; a failed change keeps the current session alive.
        expiryTimer?.invalidate()
        for id in assertions { backend.release(id) }
        assertions = acquired
        selectedMode = mode; message = nil; generation = UUID()
        let token = generation
        let value = KeepAwakeSession(mode: mode, duration: duration); session = value
        if let deadline = value.expiresAt {
            let timer = Timer(fire: deadline, interval: 0, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, self.generation == token else { return }
                    self.stop(); self.message = "定时已结束，已恢复正常休眠。"
                }
            }
            expiryTimer = timer; RunLoop.main.add(timer, forMode: .common)
        } else { expiryTimer = nil }
    }

    func stop() {
        generation = UUID(); expiryTimer?.invalidate(); expiryTimer = nil
        for id in assertions { backend.release(id) }
        assertions.removeAll(); session = nil; message = nil
        if displaySleepProcess?.isRunning == true { displaySleepProcess?.terminate() }
        displaySleepProcess = nil
    }

    func sleepDisplay() {
        guard !isPreview, session?.mode == .background, displaySleepProcess == nil else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self, self.displaySleepProcess === process else { return }
                self.displaySleepProcess = nil
                if process.terminationStatus != 0 { self.message = "macOS 未能立即关闭显示器，可等待系统自动关屏。" }
            }
        }
        do { try process.run(); displaySleepProcess = process }
        catch { message = "关屏失败：\(error.localizedDescription)" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if self?.displaySleepProcess === process, process.isRunning { process.terminate() }
        }
    }

    static func preview(active: Bool = true) -> KeepAwakeService {
        let service = KeepAwakeService(); service.isPreview = true
        service.setPreviewMode(active ? .background : nil)
        return service
    }
    func setPreviewMode(_ mode: KeepAwakeMode?) {
        guard isPreview else { return }
        selectedMode = mode ?? .background
        session = mode.map { KeepAwakeSession(mode: $0, startedAt: Date().addingTimeInterval(-1200), duration: 3600) }
    }
    deinit {
        expiryTimer?.invalidate()
        for id in assertions { backend.release(id) }
        if displaySleepProcess?.isRunning == true { displaySleepProcess?.terminate() }
    }
}
