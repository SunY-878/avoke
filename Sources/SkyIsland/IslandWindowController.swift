import AppKit
import SwiftUI
import Combine
import ServiceManagement
import IslandCore

final class IslandPanel: NSPanel {
    var escape: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { escape?() } else { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) { escape?() }
}

@MainActor final class IslandWindowController {
    let model: IslandModel
    let panel: IslandPanel
    private var timer: Timer?
    private var subscriptions = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var interaction = HoverInteraction()
    private var menuTracking = false
    private var anchor: CGPoint = .zero
    private let canvas = CGSize(width: 680, height: 570)

    init(model: IslandModel) {
        self.model = model
        panel = IslandPanel(contentRect: NSRect(origin: .zero, size: canvas), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.isMovable = false; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.becomesKeyOnlyIfNeeded = false
        panel.ignoresMouseEvents = true
        panel.title = "Sky Island"
        panel.contentView = NSHostingView(rootView: IslandView(model: model, preferences: model.preferences, media: model.media, clipboard: model.clipboard))
        panel.escape = { [weak model] in model?.close() }
        model.onClose = { [weak self] in
            self?.interaction.didClose()
            self?.panel.resignKey()
        }
        model.onOpen = { [weak self] in self?.show() }
        model.onLoginChange = { [weak self] enabled in self?.setLogin(enabled) }
        model.launchAtLogin = SMAppService.mainApp.status == .enabled

        model.preferences.$displayID.dropFirst().sink { [weak self] _ in self?.repositionSoon() }.store(in: &subscriptions)
        model.preferences.$topOffset.dropFirst().sink { [weak self] _ in self?.repositionSoon() }.store(in: &subscriptions)
        model.$visible.dropFirst().sink { [weak self] visible in
            DispatchQueue.main.async { if visible { self?.show() } else { self?.panel.orderOut(nil) } }
        }.store(in: &subscriptions)
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { self?.reposition() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { self?.menuTracking = true }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { self?.menuTracking = false; self?.interaction.holdOpen() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { self?.reposition(); self?.show() }
        })
        reposition(); show()
        timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in DispatchQueue.main.async { self?.updatePointer() } }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func show() { if model.visible { panel.orderFrontRegardless() } }
    func stop() {
        timer?.invalidate(); timer = nil
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll(); panel.orderOut(nil)
    }

    private func repositionSoon() { DispatchQueue.main.async { [weak self] in self?.reposition() } }

    func reposition() {
        let screens = NSScreen.screens
        model.displayNames = screens.map { (Self.id($0), $0.localizedName) }
        guard let screen = screens.first(where: { Self.id($0) == model.preferences.displayID }) ?? screens.first else { return }
        model.hasNotch = screen.safeAreaInsets.top > 0
        model.notchHeight = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 32
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            model.notchWidth = max(120, right.minX - left.maxX)
        } else { model.notchWidth = 180 }
        let offset = model.attached ? 0 : max(8, model.preferences.topOffset)
        anchor = CGPoint(x: screen.frame.midX, y: screen.frame.maxY - offset)
        panel.setFrame(NSRect(x: anchor.x - canvas.width / 2, y: anchor.y - canvas.height, width: canvas.width, height: canvas.height), display: true)
    }

    private func updatePointer() {
        guard model.visible else { panel.ignoresMouseEvents = true; return }
        let point = NSEvent.mouseLocation
        let rect = NSRect(x: anchor.x - model.width / 2, y: anchor.y - model.height, width: model.width, height: model.height)
        let inside = rect.contains(point)
        // Transparent canvas never consumes clicks outside the visible island.
        panel.ignoresMouseEvents = !inside
        let heldOpen = menuTracking || NSApp.windows.contains { $0 !== panel && $0.isVisible && $0.isKeyWindow }
        let action = interaction.update(inside: inside, expanded: model.expanded, pinned: model.pinned,
                                        heldOpen: heldOpen, now: Date.timeIntervalSinceReferenceDate,
                                        hoverDelay: model.preferences.hoverDelay)
        switch action {
        case .expand:
            model.open()
            if model.preferences.haptics { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        case .collapse: model.close()
        case nil: break
        }
    }

    private static func id(_ screen: NSScreen) -> String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? screen.localizedName
    }

    private func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            model.launchAtLogin = SMAppService.mainApp.status == .enabled
            model.settingsMessage = SMAppService.mainApp.status == .requiresApproval ? "请在系统设置 → 通用 → 登录项中允许 Sky Island。" : nil
        } catch { model.settingsMessage = "登录项设置失败：\(error.localizedDescription)" }
    }
}
