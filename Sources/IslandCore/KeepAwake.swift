import Foundation

public enum PowerAssertionKind: String, Sendable {
    case display = "PreventUserIdleDisplaySleep"
    case system = "PreventUserIdleSystemSleep"
    case disk = "PreventDiskIdle"
}

public enum KeepAwakeMode: String, CaseIterable, Sendable {
    case display, background
    public var title: String { self == .display ? "显示器常亮" : "后台运行" }
    public var description: String {
        self == .display ? "显示器、系统与磁盘保持唤醒" : "显示器可正常关闭，系统与磁盘保持唤醒"
    }
    public var assertions: [PowerAssertionKind] { self == .display ? [.display, .system, .disk] : [.system, .disk] }
    public var command: String { self == .display ? "caffeinate -dim" : "caffeinate -im" }
}

public enum KeepAwakeDuration: Int, CaseIterable, Sendable {
    case fifteenMinutes = 900, thirtyMinutes = 1800, oneHour = 3600, twoHours = 7200, unlimited = 0
    public var seconds: TimeInterval? { self == .unlimited ? nil : Double(rawValue) }
    public var label: String {
        switch self { case .fifteenMinutes: "15 分"; case .thirtyMinutes: "30 分"; case .oneHour: "1 小时"; case .twoHours: "2 小时"; case .unlimited: "不限" }
    }
}

public struct KeepAwakeSession: Sendable {
    public let mode: KeepAwakeMode
    public let startedAt: Date
    public let expiresAt: Date?
    public init(mode: KeepAwakeMode, startedAt: Date = Date(), duration: TimeInterval?) {
        self.mode = mode; self.startedAt = startedAt
        expiresAt = duration.map { startedAt.addingTimeInterval(max(0, $0)) }
    }
    public func remaining(at date: Date = Date()) -> TimeInterval? { expiresAt.map { max(0, $0.timeIntervalSince(date)) } }
    public func hasExpired(at date: Date = Date()) -> Bool { expiresAt.map { date >= $0 } ?? false }
}
