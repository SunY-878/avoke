import Foundation

public struct MediaTrack: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var bundleIdentifier: String
    public var isPlaying: Bool
    public var duration: Double
    public var elapsed: Double
    public var sampledAt: Date
    public var playbackRate: Double
    public var artworkData: Data?
    public var prohibitsSkip: Bool

    public init(title: String, artist: String = "", album: String = "", bundleIdentifier: String = "",
                isPlaying: Bool = false, duration: Double = 0, elapsed: Double = 0,
                sampledAt: Date = Date(), playbackRate: Double = 1, artworkData: Data? = nil,
                prohibitsSkip: Bool = false) {
        self.title = title; self.artist = artist; self.album = album
        self.bundleIdentifier = bundleIdentifier; self.isPlaying = isPlaying
        self.duration = duration.isFinite ? max(0, duration) : 0
        self.elapsed = elapsed.isFinite ? max(0, elapsed) : 0
        self.sampledAt = sampledAt; self.playbackRate = playbackRate.isFinite ? max(0, playbackRate) : 1
        self.artworkData = artworkData; self.prohibitsSkip = prohibitsSkip
    }

    public var identity: String { bundleIdentifier + "\u{1f}" + title + "\u{1f}" + artist + "\u{1f}" + album }

    public func position(at date: Date = Date()) -> Double {
        let delta = isPlaying ? max(0, date.timeIntervalSince(sampledAt)) * playbackRate : 0
        let value = elapsed + delta
        return duration > 0 ? min(duration, value) : value
    }

    public static func timeLabel(_ seconds: Double) -> String {
        let safe = seconds.isFinite ? min(max(0, seconds), 359_999) : 0
        let seconds = Int(safe)
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
                              : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Handles both complete MediaRemote snapshots and its null-removing deltas.
public struct MediaAccumulator {
    private var metadata: [String: Any] = [:]
    public init() {}

    public mutating func consume(_ data: Data, receivedAt: Date = Date()) throws -> MediaTrack? {
        let value = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        if value is NSNull { metadata = [:]; return nil }
        guard let envelope = value as? [String: Any] else { return nil }
        let payload = envelope["payload"] as? [String: Any] ?? envelope
        if envelope["diff"] as? Bool != true { metadata = [:] }
        for (key, value) in payload {
            if value is NSNull { metadata.removeValue(forKey: key) }
            else { metadata[key] = value }
        }
        guard let title = metadata["title"] as? String, !title.isEmpty else { return nil }
        func number(_ key: String) -> Double? { (metadata[key] as? NSNumber)?.doubleValue }
        let timestamp = number("timestampEpochMicros").map { Date(timeIntervalSince1970: $0 / 1_000_000) } ?? receivedAt
        let artwork = (metadata["artworkData"] as? String).flatMap { Data(base64Encoded: $0) }
        return MediaTrack(title: title, artist: metadata["artist"] as? String ?? "",
                          album: metadata["album"] as? String ?? "",
                          bundleIdentifier: metadata["parentApplicationBundleIdentifier"] as? String
                            ?? metadata["bundleIdentifier"] as? String ?? "",
                          isPlaying: metadata["playing"] as? Bool ?? false,
                          duration: number("durationMicros").map { $0 / 1_000_000 } ?? number("duration") ?? 0,
                          elapsed: number("elapsedTimeMicros").map { $0 / 1_000_000 } ?? number("elapsedTime") ?? 0,
                          sampledAt: timestamp, playbackRate: number("playbackRate") ?? 1,
                          artworkData: artwork, prohibitsSkip: metadata["prohibitsSkip"] as? Bool ?? false)
    }
}
