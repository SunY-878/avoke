import AppKit
import Combine
import IslandCore

@MainActor final class ClipboardService: ObservableObject {
    @Published private(set) var entries: [ClipboardEntry] = []
    @Published private(set) var copiedID: UUID?
    @Published private(set) var storageIssue: String?
    private var history: ClipboardHistory
    private let preferences: Preferences
    private let pasteboard: NSPasteboard
    private let storageURL: URL
    private let disk = DispatchQueue(label: "app.skyisland.clipboard-storage", qos: .utility)
    private var lastChange: Int
    private var timer: Timer?
    private var subscriptions = Set<AnyCancellable>()
    private var isDemo = false
    private var preDemoHistory: ClipboardHistory?
    private var copyToken = UUID()

    init(preferences: Preferences, pasteboard: NSPasteboard = .general, storageURL: URL? = nil, start: Bool = true) {
        self.preferences = preferences; self.pasteboard = pasteboard
        self.storageURL = storageURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SkyIsland/clipboard.json")
        lastChange = pasteboard.changeCount
        history = ClipboardHistory(limit: preferences.historyLimit)
        if start { load() }
        preferences.$historyLimit.dropFirst().sink { [weak self] value in
            guard let self else { return }; self.history.limit = value; self.history.trim(); self.publish()
        }.store(in: &subscriptions)
        preferences.$persistHistory.dropFirst().sink { [weak self] enabled in
            // @Published emits before the value is assigned; persist with the emitted value.
            self?.save(enabled: enabled)
        }.store(in: &subscriptions)
        if start {
            timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                DispatchQueue.main.async { self?.poll() }
            }
            RunLoop.main.add(timer!, forMode: .common)
        }
    }

    func stop() { timer?.invalidate(); timer = nil; disk.sync {} }

    func poll() {
        guard pasteboard.changeCount != lastChange else { return }
        lastChange = pasteboard.changeCount
        guard !preferences.capturePaused, !isDemo,
              !ClipboardEntry.isSensitive(types: pasteboard.types?.map(\.rawValue) ?? []) else { return }
        let source = NSWorkspace.shared.frontmostApplication?.localizedName ?? "应用"
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if !urls.isEmpty {
            history.insert(ClipboardEntry(kind: .files, fileURLs: urls.map(\.absoluteString), source: source))
        } else if let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard text.utf8.count <= 1_000_000 else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = URL(string: trimmed)
            let kind: ClipboardKind = (url?.scheme == "http" || url?.scheme == "https") && !trimmed.contains(where: \.isWhitespace) ? .link : .text
            history.insert(ClipboardEntry(kind: kind, text: text, source: source))
        } else if let image = NSImage(pasteboard: pasteboard), let data = Self.normalizedPNG(image), data.count <= 3_000_000 {
            history.insert(ClipboardEntry(kind: .image, data: data, source: source))
        } else { return }
        publish()
    }

    func copy(_ entry: ClipboardEntry) {
        // Demo content is intentionally isolated from the user's pasteboard.
        if !isDemo {
            pasteboard.clearContents()
            switch entry.kind {
            case .text, .link: pasteboard.setString(entry.text, forType: .string)
            case .image:
                if let data = entry.data { pasteboard.setData(data, forType: .png) }
            case .files:
                pasteboard.writeObjects(entry.fileURLs.compactMap { URL(string: $0) as NSURL? })
            }
            lastChange = pasteboard.changeCount
        }
        copiedID = entry.id
        let token = UUID(); copyToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if self?.copyToken == token { self?.copiedID = nil }
        }
        if preferences.haptics { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
    }

    func pin(_ id: UUID) { history.togglePin(id); publish() }
    func delete(_ id: UUID) { history.remove(id); publish() }
    func clear() { history.clear(); publish() }

    func setDemo(_ enabled: Bool) {
        guard enabled != isDemo else { return }
        if enabled { preDemoHistory = history }
        isDemo = enabled
        if enabled {
            history.clear()
            history.insert(ClipboardEntry(kind: .text, text: "把片刻的灵感，留在触手可及的地方。", date: Date().addingTimeInterval(-120), source: "备忘录", isPinned: true))
            history.insert(ClipboardEntry(kind: .link, text: "https://developer.apple.com/design/", date: Date().addingTimeInterval(-70), source: "Safari"))
            history.insert(ClipboardEntry(kind: .text, text: "let smallThings = makeSomethingWonderful()", date: Date().addingTimeInterval(-45), source: "Xcode"))
            history.insert(ClipboardEntry(kind: .image, data: Self.normalizedPNG(DemoArtwork.make()), date: Date().addingTimeInterval(-20), source: "预览"))
            entries = history.sorted
        } else {
            if let previous = preDemoHistory { history = previous }
            preDemoHistory = nil
            history.limit = preferences.historyLimit; history.trim()
            entries = history.sorted
            save(enabled: preferences.persistHistory)
            lastChange = pasteboard.changeCount
        }
    }

    private func load() {
        guard preferences.persistHistory else { entries = []; return }
        do {
            guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
            let attributes = try FileManager.default.attributesOfItem(atPath: storageURL.path)
            guard (attributes[.size] as? NSNumber)?.intValue ?? 0 < 40_000_000 else { storageIssue = "历史文件过大，已跳过。"; return }
            let values = try JSONDecoder().decode([ClipboardEntry].self, from: Data(contentsOf: storageURL))
            history = ClipboardHistory(entries: values.filter { ($0.data?.count ?? 0) <= 3_000_000 && $0.text.utf8.count <= 1_000_000 }, limit: preferences.historyLimit)
            entries = history.sorted
        } catch { storageIssue = "无法读取剪贴板历史：\(error.localizedDescription)" }
    }

    private func publish() {
        // Bound total memory / disk consumption, including pinned entries.
        while history.entries.reduce(0, { $0 + ($1.data?.count ?? 0) + $1.text.utf8.count }) > 24_000_000 {
            guard let oldest = history.entries.last(where: { !$0.isPinned }) ?? history.entries.last else { break }
            history.remove(oldest.id)
        }
        entries = history.sorted
        if !isDemo { save(enabled: preferences.persistHistory) }
    }

    private func save(enabled: Bool) {
        guard !isDemo else { return }
        let snapshot = history.entries, url = storageURL
        disk.async { [weak self] in
            do {
                if enabled {
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                            attributes: [.posixPermissions: 0o700])
                    let data = try JSONEncoder().encode(snapshot)
                    try data.write(to: url, options: [.atomic])
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                } else if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                DispatchQueue.main.async { self?.storageIssue = nil }
            } catch {
                DispatchQueue.main.async { self?.storageIssue = "无法保存历史：\(error.localizedDescription)" }
            }
        }
    }

    private static func normalizedPNG(_ image: NSImage) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(1, 1600 / max(image.size.width, image.size.height))
        let width = max(1, Int(image.size.width * scale)), height = max(1, Int(image.size.height * scale))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}
