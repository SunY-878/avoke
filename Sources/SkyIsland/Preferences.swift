import AppKit
import Combine

enum Accent: String, CaseIterable {
    case blue, mint, violet
    var label: String { switch self { case .blue: "天际蓝"; case .mint: "薄荷绿"; case .violet: "鸢尾紫" } }
    var color: NSColor {
        switch self {
        case .blue: NSColor(srgbRed: 0.38, green: 0.65, blue: 1, alpha: 1)
        case .mint: NSColor(srgbRed: 0.36, green: 0.88, blue: 0.73, alpha: 1)
        case .violet: NSColor(srgbRed: 0.70, green: 0.56, blue: 1, alpha: 1)
        }
    }
}

@MainActor final class Preferences: ObservableObject {
    private let defaults: UserDefaults
    @Published var accent: Accent { didSet { defaults.set(accent.rawValue, forKey: "accent") } }
    @Published var islandScale: Double { didSet { defaults.set(islandScale, forKey: "islandScale") } }
    @Published var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: "hoverDelay") } }
    @Published var topOffset: Double { didSet { defaults.set(topOffset, forKey: "topOffset") } }
    @Published var historyLimit: Int { didSet { defaults.set(historyLimit, forKey: "historyLimit") } }
    @Published var persistHistory: Bool { didSet { defaults.set(persistHistory, forKey: "persistHistory") } }
    @Published var capturePaused: Bool { didSet { defaults.set(capturePaused, forKey: "capturePaused") } }
    @Published var displayID: String { didSet { defaults.set(displayID, forKey: "displayID") } }
    @Published var haptics: Bool { didSet { defaults.set(haptics, forKey: "haptics") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["accent": "blue", "islandScale": 1.0, "hoverDelay": 0.18,
                                     "topOffset": 0.0, "historyLimit": 100, "persistHistory": true,
                                     "capturePaused": false, "displayID": "", "haptics": true])
        accent = Accent(rawValue: defaults.string(forKey: "accent") ?? "") ?? .blue
        islandScale = defaults.double(forKey: "islandScale")
        hoverDelay = defaults.double(forKey: "hoverDelay")
        topOffset = defaults.double(forKey: "topOffset")
        historyLimit = defaults.integer(forKey: "historyLimit")
        persistHistory = defaults.bool(forKey: "persistHistory")
        capturePaused = defaults.bool(forKey: "capturePaused")
        displayID = defaults.string(forKey: "displayID") ?? ""
        haptics = defaults.bool(forKey: "haptics")
    }
}
