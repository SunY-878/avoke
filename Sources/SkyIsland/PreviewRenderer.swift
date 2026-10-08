import AppKit
import SwiftUI
import IslandCore

@MainActor enum PreviewRenderer {
    static func render(to directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let suite = "app.skyisland.preview.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let preferences = Preferences(defaults: defaults)
            let media = MediaService(); media.setDemo(true)
            let clipboard = ClipboardService(preferences: preferences, start: false); clipboard.setDemo(true)
            let system = SystemStatusService.preview()
            let awake = KeepAwakeService.preview(active: false)
            let model = IslandModel(preferences: preferences, media: media, clipboard: clipboard, system: system, awake: awake)
            let states: [(String, Bool, IslandTab, Bool)] = [("music", true, .music, false), ("clipboard", true, .clipboard, false),
                ("settings", true, .settings, false), ("system", true, .system, false), ("notch-system", true, .system, true),
                ("awake", true, .awake, false), ("notch-awake", true, .awake, true), ("awake-inactive", true, .awake, false),
                ("awake-display", true, .awake, false), ("compact", false, .music, false),
                ("notch-music", true, .music, true), ("notch-compact", false, .music, true), ("awake-compact", false, .awake, false),
                ("network-notice", false, .system, false), ("idle", false, .music, false)]
            for (name, expanded, tab, notch) in states {
                model.expanded = expanded; model.selectedTab = tab
                model.hasNotch = notch
                if ["awake", "notch-awake", "awake-compact"].contains(name) { awake.setPreviewMode(.background) }
                else { awake.setPreviewMode(name == "awake-display" ? .display : nil) }
                if name == "awake-compact" || name == "idle" { media.setDemo(false) }
                if name == "network-notice" { system.updateConnection(NetworkConnectionInfo(state: .disconnected)) }
                if name == "idle" { awake.stop(); system.stop() }
                let view = IslandView(model: model, preferences: preferences, media: media, clipboard: clipboard)
                    .frame(width: 600, height: 520).padding(.top, 26)
                    .background(Color(red: 0.075, green: 0.085, blue: 0.115))
                let host = NSHostingView(rootView: view)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 546), styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = host; window.display()
                host.layoutSubtreeIfNeeded()
                // Rendering with the actual AppKit host also verifies native controls.
                RunLoop.main.run(until: Date().addingTimeInterval(0.15))
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                if let data = bitmap.representation(using: .png, properties: [:]) { try data.write(to: directory.appendingPathComponent("\(name).png")) }
                window.orderOut(nil)
            }
            print("Rendered previews to \(directory.path)")
        } catch { fputs("Preview render failed: \(error)\n", stderr) }
    }
}
