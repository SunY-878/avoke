import XCTest
@testable import IslandCore

final class IslandCoreTests: XCTestCase {
    func testPlaybackInterpolationAndClamping() {
        let time = Date(timeIntervalSince1970: 100)
        let track = MediaTrack(title: "Test", isPlaying: true, duration: 180, elapsed: 170, sampledAt: time, playbackRate: 2)
        XCTAssertEqual(track.position(at: time.addingTimeInterval(3)), 176)
        XCTAssertEqual(track.position(at: time.addingTimeInterval(20)), 180)
        XCTAssertEqual(track.position(at: time.addingTimeInterval(-3)), 170)
    }
    func testPauseFreezesProgressAndNonFiniteValuesAreSafe() {
        let track = MediaTrack(title: "Paused", duration: .infinity, elapsed: 30, sampledAt: .distantPast)
        XCTAssertEqual(track.position(), 30)
        XCTAssertEqual(MediaTrack(title: "Bad", elapsed: .nan).position(), 0)
        XCTAssertEqual(MediaTrack.timeLabel(.nan), "0:00")
        XCTAssertEqual(MediaTrack.timeLabel(3723), "1:02:03")
    }
    func testAdapterFullSnapshotAndDelta() throws {
        var accumulator = MediaAccumulator()
        let sample = Data(#"{"type":"data","diff":false,"payload":{"title":"A","artist":"Artist","playing":true,"durationMicros":200000000,"elapsedTimeMicros":10000000,"timestampEpochMicros":100000000,"artworkData":"YWJj"}}"#.utf8)
        let track = try XCTUnwrap(accumulator.consume(sample))
        XCTAssertEqual(track.duration, 200); XCTAssertEqual(track.elapsed, 10)
        XCTAssertEqual(track.position(at: Date(timeIntervalSince1970: 105)), 15)
        let delta = Data(#"{"type":"data","diff":true,"payload":{"playing":false,"artist":null}}"#.utf8)
        let paused = try XCTUnwrap(accumulator.consume(delta))
        XCTAssertEqual(paused.title, "A"); XCTAssertEqual(paused.artist, "")
        XCTAssertFalse(paused.isPlaying); XCTAssertEqual(paused.artworkData, Data("abc".utf8))
    }
    func testNewTrackDoesNotInheritOldArtworkAndEmptyClears() throws {
        var accumulator = MediaAccumulator()
        _ = try accumulator.consume(Data(#"{"title":"A","artworkData":"YWJj"}"#.utf8))
        let track = try XCTUnwrap(accumulator.consume(Data(#"{"type":"data","diff":false,"payload":{"title":"B"}}"#.utf8)))
        XCTAssertNil(track.artworkData)
        XCTAssertNil(try accumulator.consume(Data(#"{"type":"data","diff":false,"payload":{}}"#.utf8)))
        XCTAssertNil(try accumulator.consume(Data("null".utf8)))
    }
    func testDuplicateIsMovedToFrontAndPinSurvives() {
        let original = ClipboardEntry(kind: .text, text: "hello", isPinned: true)
        var history = ClipboardHistory(limit: 2)
        history.insert(original); history.insert(ClipboardEntry(kind: .text, text: "other"))
        history.insert(ClipboardEntry(kind: .text, text: "hello"))
        XCTAssertEqual(history.entries.count, 2)
        XCTAssertEqual(history.entries.first?.id, original.id)
        XCTAssertTrue(history.entries.first?.isPinned == true)
    }
    func testCapacityPreservesPinsAndTrimsOldEntries() {
        let pin = ClipboardEntry(kind: .text, text: "keep", isPinned: true)
        var history = ClipboardHistory(limit: 2)
        history.insert(pin)
        for index in 0..<5 { history.insert(ClipboardEntry(kind: .text, text: "\(index)")) }
        XCTAssertEqual(history.entries.count, 3)
        XCTAssertEqual(history.sorted.first?.id, pin.id)
        XCTAssertEqual(Set(history.entries.map(\.text)), Set(["keep", "3", "4"]))
        history.clear(); XCTAssertTrue(history.entries.isEmpty)
    }
    func testSensitiveTypesExcludedAndExactWhitespacePreserved() {
        XCTAssertTrue(ClipboardEntry.isSensitive(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        XCTAssertTrue(ClipboardEntry.isSensitive(types: ["com.agilebits.onepassword.custom"]))
        XCTAssertFalse(ClipboardEntry.isSensitive(types: ["public.png"]))
        let entry = ClipboardEntry(kind: .text, text: "  Hello\n  World  ", source: "Xcode")
        XCTAssertEqual(entry.text, "  Hello\n  World  ")
        XCTAssertEqual(entry.title, "Hello")
        XCTAssertTrue(entry.matches("hello")); XCTAssertTrue(entry.matches("XCODE"))
    }
    func testHistoryRoundTripIncludesImageAndFiles() throws {
        let entries = [ClipboardEntry(kind: .image, data: Data([1, 2, 3]), isPinned: true),
                       ClipboardEntry(kind: .files, fileURLs: ["file:///tmp/Test.txt"], source: "Finder")]
        XCTAssertEqual(try JSONDecoder().decode([ClipboardEntry].self, from: JSONEncoder().encode(entries)), entries)
        XCTAssertEqual(entries[1].title, "Test.txt")
    }
}
