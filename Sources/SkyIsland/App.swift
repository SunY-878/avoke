import AppKit
import SwiftUI
import IslandCore

@main enum SkyIslandMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var preferences: Preferences!
    private var media: MediaService!
    private var clipboard: ClipboardService!
    private var system: SystemStatusService?
    private var awake: KeepAwakeService?
    private var model: IslandModel!
    private var island: IslandWindowController?
    private var statusItem: NSStatusItem?
    private var shortcut: GlobalShortcut?
    private var terminationSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = CommandLine.arguments.firstIndex(of: "--render-previews"), CommandLine.arguments.count > index + 1 {
            PreviewRenderer.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            NSApp.terminate(nil); return
        }
        if CommandLine.arguments.contains("--check-system") {
            system = SystemStatusService()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                guard let self, let system = self.system else { return }
                let sample = system.snapshot
                let result: [String: Any] = ["cpuPercent": sample.cpu.map { $0.total as Any } ?? NSNull(),
                    "memoryPercent": sample.memory?.percentage.map { $0 as Any } ?? NSNull(),
                    "memoryUsedBytes": sample.memory.map { $0.used as Any } ?? NSNull(),
                    "memoryTotalBytes": sample.memory.map { $0.total as Any } ?? NSNull(),
                    "diskAvailableBytes": sample.disk.map { $0.available as Any } ?? NSNull(),
                    "downloadBytesPerSecond": sample.network.map { $0.download as Any } ?? NSNull(),
                    "uploadBytesPerSecond": sample.network.map { $0.upload as Any } ?? NSNull(),
                    "networkStatus": system.connection.state.rawValue, "networkTransport": system.connection.transport,
                    "thermalState": sample.thermal.rawValue, "logicalProcessors": system.processorCount,
                    "uptimeSeconds": sample.uptime, "issues": sample.issues]
                if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
                   let text = String(data: data, encoding: .utf8) { print(text) }
                system.stop(); NSApp.terminate(nil)
            }
            return
        }
        if CommandLine.arguments.contains("--check-media") {
            media = MediaService(); media.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self else { return }
                let result: [String: Any] = ["connected": self.media.connectionIssue == nil,
                                            "hasTrack": self.media.track != nil, "hasArtwork": self.media.artwork != nil,
                                            "isPlaying": self.media.track?.isPlaying ?? false]
                if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
                   let text = String(data: data, encoding: .utf8) { print(text) }
                self.media.stop(); NSApp.terminate(nil)
            }
            return
        }
        // Reopening the app uses the existing instance instead of creating overlapping islands.
        let other = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "app.skyisland.mac")
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let other { other.activate(options: []); NSApp.terminate(nil); return }
        signal(SIGTERM, SIG_IGN)
        let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termination.setEventHandler { NSApp.terminate(nil) }
        termination.resume(); terminationSignal = termination
        preferences = Preferences(); media = MediaService()
        clipboard = ClipboardService(preferences: preferences)
        let system = SystemStatusService(); self.system = system
        let awake = KeepAwakeService(); self.awake = awake
        model = IslandModel(preferences: preferences, media: media, clipboard: clipboard, system: system, awake: awake)
        island = IslandWindowController(model: model)
        media.start()
        if CommandLine.arguments.contains("--demo") {
            media.setDemo(true); clipboard.setDemo(true)
            model.open(tab: .music); model.pinned = true
        }
        setupMenu()
        setupEditingMenu()
        shortcut = GlobalShortcut { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.model.expanded { self.model.close() }
                else { self.model.open(); self.model.pinned = true; self.island?.panel.makeKey() }
            }
        }
        if shortcut?.isRegistered != true { model.settingsMessage = "⌥ Space 已被其他应用占用，仍可从菜单栏呼出。" }
    }

    func applicationWillTerminate(_ notification: Notification) {
        island?.stop(); media?.stop(); clipboard?.stop(); system?.stop(); awake?.stop(); shortcut = nil
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model?.open(); model?.pinned = true; return false
    }

    private func setupMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let image = NSImage(systemSymbolName: "capsule.inset.filled", accessibilityDescription: "Sky Island") {
            image.isTemplate = true; item.button?.image = image
        }
        item.button?.toolTip = "Sky Island · 天际岛"
        let menu = NSMenu(); menu.delegate = self
        menu.addItem(NSMenuItem(title: "Sky Island · 天际岛", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        add("展开灵动岛", action: #selector(toggleIsland), to: menu, tag: 1)
        add("剪贴板历史", action: #selector(showClipboard), to: menu)
        add("系统状态", action: #selector(showSystem), to: menu)
        add("防休眠…", action: #selector(showAwake), to: menu)
        add("设置…", action: #selector(showSettings), to: menu)
        menu.addItem(.separator())
        add("暂停剪贴板记录", action: #selector(toggleCapture), to: menu, tag: 2)
        add("隐藏灵动岛", action: #selector(toggleVisibility), to: menu, tag: 3)
        add("体验演示", action: #selector(toggleDemo), to: menu, tag: 4)
        menu.addItem(.separator())
        add("保持显示器常亮", action: #selector(startDisplayAwake), to: menu, tag: 5)
        add("后台运行（显示器可关闭）", action: #selector(startBackgroundAwake), to: menu, tag: 6)
        add("结束防休眠", action: #selector(stopAwake), to: menu, tag: 7)
        menu.addItem(.separator())
        add("退出 Sky Island", action: #selector(quit), to: menu)
        item.menu = menu; statusItem = item
    }
    private func setupEditingMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        let quitItem = NSMenuItem(title: "退出 Sky Island", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self; appMenu.addItem(quitItem)
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "编辑"); editItem.submenu = edit; main.addItem(editItem)
        for (title, selector, key) in [("撤销", Selector(("undo:")), "z"),
                                       ("剪切", #selector(NSText.cut(_:)), "x"),
                                       ("复制", #selector(NSText.copy(_:)), "c"),
                                       ("粘贴", #selector(NSText.paste(_:)), "v"),
                                       ("全选", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(NSMenuItem(title: title, action: selector, keyEquivalent: key))
        }
        NSApp.mainMenu = main
    }
    private func add(_ title: String, action: Selector, to menu: NSMenu, tag: Int = 0) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; item.tag = tag; menu.addItem(item)
    }
    func menuWillOpen(_ menu: NSMenu) {
        menu.item(withTag: 1)?.title = model.expanded ? "收起灵动岛" : "展开灵动岛   ⌥ Space"
        menu.item(withTag: 2)?.state = preferences.capturePaused ? .on : .off
        menu.item(withTag: 3)?.title = model.visible ? "隐藏灵动岛" : "显示灵动岛"
        menu.item(withTag: 4)?.title = media.isDemo ? "结束演示" : "体验演示"
        menu.item(withTag: 5)?.state = awake?.session?.mode == .display ? .on : .off
        menu.item(withTag: 6)?.state = awake?.session?.mode == .background ? .on : .off
        menu.item(withTag: 7)?.isEnabled = awake?.isActive == true
    }
    @objc private func toggleIsland() { model.toggle(); if model.expanded { model.pinned = true } }
    @objc private func showClipboard() { model.open(tab: .clipboard); model.pinned = true; island?.panel.makeKey() }
    @objc private func showSystem() { model.open(tab: .system); model.pinned = true }
    @objc private func showAwake() { model.open(tab: .awake); model.pinned = true }
    @objc private func startDisplayAwake() {
        if let awake { awake.start(mode: .display, duration: awake.selectedDuration.seconds) }; showAwake()
    }
    @objc private func startBackgroundAwake() {
        if let awake { awake.start(mode: .background, duration: awake.selectedDuration.seconds) }; showAwake()
    }
    @objc private func stopAwake() { awake?.stop() }
    @objc private func showSettings() { model.open(tab: .settings); model.pinned = true }
    @objc private func toggleCapture() { preferences.capturePaused.toggle() }
    @objc private func toggleVisibility() { model.visible.toggle(); if !model.visible { model.close() } }
    @objc private func toggleDemo() {
        let enabled = !media.isDemo; media.setDemo(enabled); clipboard.setDemo(enabled)
        if enabled { model.open(tab: .music); model.pinned = true }
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
