import XCTest
@testable import IslandCore

final class SystemMetricsTests: XCTestCase {
    func testCPUUsesIntervalDeltaAcrossAllCores() throws {
        let previous = CPUCounters(user: 1000, system: 200, idle: 8000, nice: 50)
        let current = CPUCounters(user: 1020, system: 210, idle: 8065, nice: 55)
        let usage = try XCTUnwrap(current.usage(since: previous))
        XCTAssertEqual(usage.user, 25, accuracy: 0.0001)
        XCTAssertEqual(usage.system, 10, accuracy: 0.0001)
        XCTAssertEqual(usage.total, 35, accuracy: 0.0001)
        XCTAssertEqual(usage.idle, 65, accuracy: 0.0001)
    }
    func testCPUCounterWrapAndZeroInterval() throws {
        let previous = CPUCounters(user: UInt32.max - 4, system: 100, idle: 100)
        let current = CPUCounters(user: 5, system: 110, idle: 180)
        XCTAssertEqual(try XCTUnwrap(current.usage(since: previous)).total, 20, accuracy: 0.0001)
        XCTAssertNil(current.usage(since: current))
    }
    func testMemoryUsesAppWiredAndCompressedAndBoundsValues() {
        let memory = MemoryUsage(total: 100, app: 30, wired: 10, compressed: 20, swap: 5)
        XCTAssertEqual(memory.used, 60); XCTAssertEqual(memory.percentage, 60)
        // Disk-backed swap is not added to resident physical memory.
        XCTAssertEqual(memory.swap, 5)
        let overcommitted = MemoryUsage(total: 100, app: 95, wired: 10, compressed: 20, swap: nil)
        XCTAssertEqual(overcommitted.percentage, 100)
        let invalid = MemoryUsage(total: 0, app: .nan, wired: -1, compressed: .infinity, swap: nil)
        XCTAssertNil(invalid.percentage); XCTAssertEqual(invalid.used, 0)
    }
    func testDiskAvailableCapacityIsBounded() {
        let disk = DiskUsage(total: 500, available: 200)
        XCTAssertEqual(disk.used, 300); XCTAssertEqual(disk.percentage, 60)
        XCTAssertEqual(DiskUsage(total: 100, available: 150).used, 0)
        XCTAssertNil(DiskUsage(total: 0, available: 0).percentage)
    }
    func testTrendsAreBoundedAndResetAfterInterruptedSampling() {
        let start = Date(timeIntervalSince1970: 1000)
        var history = MetricHistory(capacity: 60)
        for index in 0..<100 { history.append(Double(index), at: start.addingTimeInterval(Double(index))) }
        XCTAssertEqual(history.points.count, 60)
        XCTAssertEqual(history.points.first?.value, 40)
        history.append(nil, at: start.addingTimeInterval(100)); XCTAssertEqual(history.points.count, 60)
        history.append(.nan, at: start.addingTimeInterval(100)); XCTAssertEqual(history.points.count, 60)
        history.append(120, at: start.addingTimeInterval(105))
        XCTAssertEqual(history.points.count, 1); XCTAssertEqual(history.points.first?.value, 100)
    }
}
