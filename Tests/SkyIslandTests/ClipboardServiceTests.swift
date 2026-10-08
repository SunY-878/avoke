import AppKit
import XCTest
import IslandCore
@testable import SkyIsland

final class ClipboardServiceTests: XCTestCase {
    @MainActor func testImagesAndFileListsAreCapturedAndCopied() throws {
        let suite = "app.skyisland.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: defaults); prefs.persistHistory = false; prefs.haptics = false
        let board = NSPasteboard(name: NSPasteboard.Name(suite)); defer { board.releaseGlobally() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(suite).appendingPathComponent("history.json")
        let service = ClipboardService(preferences: prefs, pasteboard: board, storageURL: url)
        defer { service.stop() }
        board.clearContents(); board.writeObjects([DemoArtwork.make()]); service.poll()
        let image = try XCTUnwrap(service.entries.first)
        XCTAssertEqual(image.kind, .image)
        XCTAssertNotNil(image.data.flatMap(NSImage.init(data:)))
        service.copy(image); XCTAssertNotNil(board.data(forType: .png))
        let files = [URL(fileURLWithPath: "/tmp/sky-island-a.txt"), URL(fileURLWithPath: "/tmp/sky-island-b.txt")]
        board.clearContents(); board.writeObjects(files.map { $0 as NSURL }); service.poll()
        let entry = try XCTUnwrap(service.entries.first)
        XCTAssertEqual(entry.kind, .files); XCTAssertEqual(entry.fileURLs, files.map(\.absoluteString))
        service.copy(entry)
        XCTAssertEqual((board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]), files)
    }

    @MainActor func testCaptureDeduplicationPauseCopyAndSensitivity() throws {
        let suite = "app.skyisland.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: defaults); prefs.persistHistory = false; prefs.haptics = false
        let board = NSPasteboard(name: NSPasteboard.Name(suite))
        defer { board.releaseGlobally() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(suite).appendingPathComponent("history.json")
        let service = ClipboardService(preferences: prefs, pasteboard: board, storageURL: url)
        defer { service.stop() }
        board.clearContents(); board.setString("  text with spacing\n", forType: .string); service.poll()
        XCTAssertEqual(service.entries.count, 1)
        let first = try XCTUnwrap(service.entries.first)
        service.pin(first.id)
        board.clearContents(); board.setString("  text with spacing\n", forType: .string); service.poll()
        XCTAssertEqual(service.entries.count, 1); XCTAssertTrue(service.entries[0].isPinned)
        prefs.capturePaused = true
        board.clearContents(); board.setString("ignored", forType: .string); service.poll()
        prefs.capturePaused = false; service.poll()
        XCTAssertEqual(service.entries.count, 1)
        board.clearContents(); board.setString("secret", forType: .string)
        board.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")); service.poll()
        XCTAssertEqual(service.entries.count, 1)
        service.copy(first)
        XCTAssertEqual(board.string(forType: .string), "  text with spacing\n")
        service.poll(); XCTAssertEqual(service.entries.count, 1)
    }

    @MainActor func testPersistenceReloadAndRemoval() throws {
        let suite = "app.skyisland.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: defaults)
        let board = NSPasteboard(name: NSPasteboard.Name(suite))
        defer { board.releaseGlobally() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        let service = ClipboardService(preferences: prefs, pasteboard: board, storageURL: url)
        board.clearContents(); board.setString("https://apple.com", forType: .string); service.poll(); service.stop()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let reloaded = ClipboardService(preferences: prefs, pasteboard: board, storageURL: url)
        XCTAssertEqual(reloaded.entries.first?.kind, .link)
        XCTAssertEqual(reloaded.entries.first?.text, "https://apple.com")
        prefs.persistHistory = false; reloaded.stop(); service.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor func testDemoPreservesMemoryHistoryAndDoesNotChangePasteboard() {
        let suite = "app.skyisland.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: defaults); prefs.persistHistory = false; prefs.haptics = false
        let board = NSPasteboard(name: NSPasteboard.Name(suite)); defer { board.releaseGlobally() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(suite).appendingPathComponent("history.json")
        let service = ClipboardService(preferences: prefs, pasteboard: board, storageURL: url)
        defer { service.stop() }
        board.clearContents(); board.setString("real content", forType: .string); service.poll()
        service.setDemo(true)
        if let entry = service.entries.first { service.copy(entry) }
        XCTAssertEqual(board.string(forType: .string), "real content")
        service.setDemo(false)
        XCTAssertEqual(service.entries.map(\.text), ["real content"])
    }
}
