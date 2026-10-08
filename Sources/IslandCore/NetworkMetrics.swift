import Foundation

public struct InterfaceCounters: Sendable {
    public let identifier: String
    public let received: UInt64
    public let sent: UInt64
    public init(identifier: String, received: UInt64, sent: UInt64) {
        self.identifier = identifier; self.received = received; self.sent = sent
    }
}

public struct NetworkRate: Sendable {
    public let download: Double
    public let upload: Double
    public init(download: Double, upload: Double) { self.download = download; self.upload = upload }
}

public struct NetworkRateAccumulator {
    private var previous: [String: InterfaceCounters] = [:]
    private var sampledAt: Date?
    public init() {}
    public mutating func reset() { previous = [:]; sampledAt = nil }
    public mutating func consume(_ counters: [InterfaceCounters], at date: Date) -> NetworkRate? {
        let current = Dictionary(counters.map { ($0.identifier, $0) }, uniquingKeysWith: { _, latest in latest })
        defer { previous = current; sampledAt = date }
        guard let sampledAt else { return nil }
        let interval = date.timeIntervalSince(sampledAt)
        guard interval > 0, interval <= 3 else { return nil }
        var received: Double = 0, sent: Double = 0, matched = false
        for (id, counter) in current {
            guard let old = previous[id], counter.received >= old.received, counter.sent >= old.sent else { continue }
            // New / reset interfaces establish a baseline instead of producing a spike.
            matched = true
            received += Double(counter.received - old.received)
            sent += Double(counter.sent - old.sent)
        }
        return matched ? NetworkRate(download: received / interval, upload: sent / interval) : nil
    }
}

public enum NetworkConnectionState: String, Sendable {
    case unknown, connected, disconnected, requiresConnection
    public var label: String {
        switch self { case .unknown: "检查中"; case .connected: "已连接"; case .disconnected: "未连接"; case .requiresConnection: "需要连接" }
    }
}

public struct NetworkConnectionInfo: Equatable, Sendable {
    public var state: NetworkConnectionState
    public var transport: String
    public init(state: NetworkConnectionState = .unknown, transport: String = "") { self.state = state; self.transport = transport }
}

public struct NetworkNotice: Equatable, Sendable {
    public let text: String
    public let isDisconnected: Bool
    public init(text: String, isDisconnected: Bool) { self.text = text; self.isDisconnected = isDisconnected }
}
