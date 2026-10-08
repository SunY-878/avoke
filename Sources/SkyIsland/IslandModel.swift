import AppKit
import Combine

enum IslandTab: String { case music, clipboard, system, awake, settings }

@MainActor final class IslandModel: ObservableObject {
    @Published var expanded = false
    @Published var selectedTab: IslandTab = .clipboard
    @Published var pinned = false
    @Published var visible = true
    @Published var hasNotch = false
    @Published var notchWidth: CGFloat = 180
    @Published var notchHeight: CGFloat = 32
    @Published var launchAtLogin = false
    @Published var settingsMessage: String?
    @Published var displayNames: [(id: String, name: String)] = []
    let preferences: Preferences
    let media: MediaService
    let clipboard: ClipboardService
    let system: SystemStatusService
    let awake: KeepAwakeService
    var onOpen: (() -> Void)?
    var onClose: (() -> Void)?
    var onLoginChange: ((Bool) -> Void)?
    private var subscriptions = Set<AnyCancellable>()

    init(preferences: Preferences, media: MediaService, clipboard: ClipboardService, system: SystemStatusService, awake: KeepAwakeService) {
        self.preferences = preferences; self.media = media; self.clipboard = clipboard
        self.system = system
        self.awake = awake
        // Geometry depends on live media and preferences too.
        preferences.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        media.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        awake.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &subscriptions)
        system.$connectionNotice.dropFirst().sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
    }

    var scale: CGFloat { CGFloat(min(1.15, max(0.85, preferences.islandScale))) }
    var attached: Bool { hasNotch && preferences.topOffset < 1 }
    var topInset: CGFloat { attached ? notchHeight + 8 : 18 }
    var baseWidth: CGFloat {
        if expanded { return 520 }
        if system.connectionNotice != nil { return attached ? notchWidth + 112 : 248 }
        if attached { return notchWidth + (media.track != nil ? 190 : (awake.isActive ? 96 : 72)) }
        return media.track != nil ? 296 : (awake.isActive ? 232 : 194)
    }
    var baseHeight: CGFloat {
        if expanded {
            switch selectedTab {
            case .music: return 330 + topInset
            case .clipboard: return 428 + topInset
            case .system: return 452 + topInset
            case .awake: return 426 + topInset
            case .settings: return 418 + topInset
            }
        }
        return attached ? max(36, notchHeight + 4) : 38
    }
    var width: CGFloat { expanded || !attached ? baseWidth * scale : baseWidth }
    var height: CGFloat { expanded || !attached ? baseHeight * scale : baseHeight }
    var effectiveScale: CGFloat { expanded || !attached ? scale : 1 }

    func open(tab: IslandTab? = nil) {
        visible = true
        if let tab { selectedTab = tab }
        else if !expanded {
            if system.connectionNotice != nil { selectedTab = .system }
            else if media.track != nil { selectedTab = .music }
            else { selectedTab = awake.isActive ? .awake : .clipboard }
        }
        expanded = true; onOpen?()
    }
    func close() { pinned = false; expanded = false; onClose?() }
    func toggle() { expanded ? close() : open() }
}
