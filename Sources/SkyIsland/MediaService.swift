import AppKit
import Combine
import IslandCore

// All mutable parsing state is confined to the serial reader queue.
private final class MediaStreamBuffer: @unchecked Sendable {
    var bytes = Data()
    var accumulator = MediaAccumulator()
}

@MainActor final class MediaService: ObservableObject {
    @Published private(set) var track: MediaTrack?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var tint = Accent.blue.color
    @Published private(set) var connectionIssue: String?
    @Published private(set) var isDemo = false
    private var liveTrack: MediaTrack?
    private var stream: Process?
    private var pipe: Pipe?
    private var commands: [UUID: Process] = [:]
    private var generation = UUID()
    private let reader = DispatchQueue(label: "app.skyisland.media-reader", qos: .utility)
    private var paths: (script: String, framework: String)? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let script = resources.appendingPathComponent("mediaremote-adapter.pl").path
        let framework = resources.appendingPathComponent("MediaRemoteAdapter.framework").path
        guard FileManager.default.fileExists(atPath: script), FileManager.default.fileExists(atPath: framework) else { return nil }
        return (script, framework)
    }

    var playerName: String {
        guard let id = track?.bundleIdentifier, !id.isEmpty else { return "系统媒体" }
        if isDemo { return "Sky Island · 演示" }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return "系统媒体" }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    func start() {
        guard stream == nil else { return }
        guard let paths else { connectionIssue = "媒体组件未找到，请使用 Scripts/build.sh 构建应用。"; return }
        let process = Process(), output = Pipe()
        let token = UUID(); generation = token
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [paths.script, paths.framework, "stream", "--no-diff", "--micros", "--debounce=80"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // Each stream owns its buffer; stale callbacks cannot modify a new stream.
        let buffer = MediaStreamBuffer()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { handle.readabilityHandler = nil; return }
            self?.reader.async {
                buffer.bytes.append(chunk)
                guard buffer.bytes.count < 16_000_000 else { buffer.bytes.removeAll(); return }
                while let end = buffer.bytes.firstIndex(of: 10) {
                    let line = Data(buffer.bytes[..<end]); buffer.bytes.removeSubrange(...end)
                    guard !line.isEmpty else { continue }
                    do {
                        let snapshot = try buffer.accumulator.consume(line)
                        DispatchQueue.main.async { [weak self] in
                            guard let self, self.generation == token else { return }
                            self.liveTrack = snapshot
                            self.connectionIssue = nil
                            if !self.isDemo { self.present(snapshot) }
                        }
                    } catch { /* Ignore malformed individual updates, retain the last valid snapshot. */ }
                }
            }
        }
        process.terminationHandler = { [weak self] stopped in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.pipe?.fileHandleForReading.readabilityHandler = nil
                self.stream = nil; self.pipe = nil; self.liveTrack = nil
                if !self.isDemo { self.present(nil) }
                self.connectionIssue = "媒体连接已停止（\(stopped.terminationStatus)），可在设置中重新连接。"
            }
        }
        do { try process.run(); stream = process; pipe = output; connectionIssue = nil }
        catch { output.fileHandleForReading.readabilityHandler = nil; connectionIssue = "无法连接系统媒体：\(error.localizedDescription)" }
    }

    func stop() {
        generation = UUID()
        pipe?.fileHandleForReading.readabilityHandler = nil
        stream?.terminationHandler = nil
        if stream?.isRunning == true { stream?.terminate() }
        stream = nil; pipe = nil
        for process in commands.values where process.isRunning { process.terminate() }
        commands.removeAll()
    }

    func reconnect() { stop(); start() }

    func command(_ id: Int) {
        if isDemo {
            guard var demo = track else { return }
            demo.elapsed = demo.position(); demo.sampledAt = Date()
            if id == 2 { demo.isPlaying.toggle() }
            if id == 4 || id == 5 { demo.elapsed = 0 }
            present(demo); return
        }
        execute(["send", String(id)])
    }

    func seek(to position: Double) {
        guard let track, track.duration > 0 else { return }
        let safe = max(0, min(track.duration, position))
        if isDemo {
            var demo = track; demo.elapsed = safe; demo.sampledAt = Date(); present(demo)
        } else { execute(["seek", String(Int64(safe * 1_000_000))]) }
    }

    func openPlayer() {
        guard let id = track?.bundleIdentifier, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    func setDemo(_ enabled: Bool) {
        isDemo = enabled
        if enabled {
            let image = DemoArtwork.make()
            present(MediaTrack(title: "Midnight, somewhere", artist: "Sky Island", album: "A little closer to the sky",
                               bundleIdentifier: "app.skyisland.demo", isPlaying: true, duration: 238, elapsed: 83,
                               artworkData: image.tiffRepresentation))
        } else { present(liveTrack) }
    }

    private func execute(_ args: [String]) {
        guard let paths else { return }
        let process = Process(), id = UUID()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [paths.script, paths.framework] + args
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.commands.removeValue(forKey: id)
                if process.terminationStatus != 0 { self?.connectionIssue = "播放器未响应此操作。" }
            }
        }
        do { try process.run(); commands[id] = process }
        catch { connectionIssue = "媒体操作失败：\(error.localizedDescription)" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let process = self?.commands[id], process.isRunning else { return }
            process.terminate()
        }
    }

    private func present(_ value: MediaTrack?) {
        let artworkChanged = track?.artworkData != value?.artworkData
        track = value
        if artworkChanged || value == nil {
            artwork = value?.artworkData.flatMap(NSImage.init(data:))
            tint = artwork.flatMap(Self.averageColor) ?? Accent.blue.color
        }
    }

    private static func averageColor(_ image: NSImage) -> NSColor? {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8,
                                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: 8, height: 8))
        NSGraphicsContext.restoreGraphicsState()
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        for y in 0..<8 { for x in 0..<8 {
            if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                r += color.redComponent; g += color.greenComponent; b += color.blueComponent
            }
        } }
        let color = NSColor(srgbRed: r / 64, green: g / 64, blue: b / 64, alpha: 1)
        return NSColor(calibratedHue: color.hueComponent, saturation: min(0.65, max(0.3, color.saturationComponent)),
                       brightness: max(0.75, color.brightnessComponent), alpha: 1)
    }
}
