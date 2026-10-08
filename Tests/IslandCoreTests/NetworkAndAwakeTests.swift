import XCTest
@testable import IslandCore

final class NetworkAndAwakeTests: XCTestCase {
    func testNetworkRatesUseCounterDeltasAndActualInterval() throws {
        var accumulator = NetworkRateAccumulator()
        let time = Date(timeIntervalSince1970: 1000)
        XCTAssertNil(accumulator.consume([InterfaceCounters(identifier: "en0", received: 1000, sent: 2000), InterfaceCounters(identifier: "en1", received: 3000, sent: 4000)], at: time))
        let value = try XCTUnwrap(accumulator.consume([InterfaceCounters(identifier: "en0", received: 1400, sent: 2100), InterfaceCounters(identifier: "en1", received: 3200, sent: 4200)], at: time.addingTimeInterval(2)))
        XCTAssertEqual(value.download, 300); XCTAssertEqual(value.upload, 150)
    }
    func testNetworkResetAndNewInterfacesDoNotCreateSpikes() throws {
        var accumulator = NetworkRateAccumulator()
        let time = Date(timeIntervalSince1970: 1000)
        _ = accumulator.consume([InterfaceCounters(identifier: "en0", received: 1000, sent: 1000)], at: time)
        XCTAssertNil(accumulator.consume([InterfaceCounters(identifier: "en0", received: 10, sent: 10)], at: time.addingTimeInterval(1)))
        let value = try XCTUnwrap(accumulator.consume([InterfaceCounters(identifier: "en0", received: 20, sent: 20), InterfaceCounters(identifier: "en2", received: 9_000_000, sent: 9_000_000)], at: time.addingTimeInterval(2)))
        XCTAssertEqual(value.download, 10); XCTAssertEqual(value.upload, 10)
        XCTAssertNil(accumulator.consume([InterfaceCounters(identifier: "en0", received: 1000, sent: 1000)], at: time.addingTimeInterval(20)))
    }
    func testZeroTrafficAndNonPositiveIntervals() throws {
        var accumulator = NetworkRateAccumulator()
        let time = Date(timeIntervalSince1970: 1000)
        let counters = [InterfaceCounters(identifier: "en0", received: 50, sent: 50)]
        _ = accumulator.consume(counters, at: time)
        XCTAssertNil(accumulator.consume(counters, at: time))
        XCTAssertEqual(try XCTUnwrap(accumulator.consume(counters, at: time.addingTimeInterval(1))).download, 0)
    }
    func testRateFormattingAndUnavailableValues() {
        XCTAssertEqual(DataRateFormat.label(nil), "—")
        XCTAssertEqual(DataRateFormat.label(.infinity), "—")
        XCTAssertEqual(DataRateFormat.label(-1), "—")
        XCTAssertEqual(DataRateFormat.label(0), "0 B/s")
        XCTAssertEqual(DataRateFormat.label(1500), "1.5 KB/s")
        XCTAssertEqual(DataRateFormat.label(2_500_000), "2.5 MB/s")
    }
    func testAwakeModesKeepDisksAndSystemAwakeWithOptionalDisplay() {
        XCTAssertEqual(KeepAwakeMode.background.assertions, [.system, .disk])
        XCTAssertFalse(KeepAwakeMode.background.assertions.contains(.display))
        XCTAssertEqual(KeepAwakeMode.display.assertions, [.display, .system, .disk])
        XCTAssertEqual(KeepAwakeMode.background.command, "caffeinate -im")
        XCTAssertEqual(KeepAwakeMode.display.command, "caffeinate -dim")
    }
    func testAwakeDeadlineIsFiniteOrUnlimited() {
        let time = Date(timeIntervalSince1970: 1000)
        let timed = KeepAwakeSession(mode: .background, startedAt: time, duration: 60)
        XCTAssertEqual(timed.remaining(at: time.addingTimeInterval(10)), 50)
        XCTAssertEqual(timed.remaining(at: time.addingTimeInterval(100)), 0)
        XCTAssertTrue(timed.hasExpired(at: time.addingTimeInterval(60)))
        let unlimited = KeepAwakeSession(mode: .display, startedAt: time, duration: nil)
        XCTAssertNil(unlimited.remaining()); XCTAssertFalse(unlimited.hasExpired())
        XCTAssertNil(KeepAwakeDuration.unlimited.seconds)
    }
}
