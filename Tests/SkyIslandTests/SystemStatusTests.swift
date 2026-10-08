import Foundation
import Combine
import XCTest
import IslandCore
@testable import SkyIsland

final class SystemStatusTests: XCTestCase {
    func testNativeSystemReaderReturnsRealMetrics() throws {
        let reader = NativeSystemStatusReader()
        let initial = reader.read()
        XCTAssertNil(initial.cpu, "The first sample is a baseline, not a fabricated CPU percentage")
        XCTAssertEqual(try XCTUnwrap(initial.memory).total, Double(ProcessInfo.processInfo.physicalMemory))
        XCTAssertNotNil(initial.disk)
        // Kernel statistics can reuse a cached snapshot for short intervals.
        Thread.sleep(forTimeInterval: 1.1)
        let sample = reader.read()
        let cpu = try XCTUnwrap(sample.cpu)
        XCTAssertTrue((0...100).contains(cpu.total))
        let memory = try XCTUnwrap(sample.memory)
        XCTAssertTrue((0...memory.total).contains(memory.used))
        XCTAssertNotNil(memory.swap)
        XCTAssertGreaterThan(sample.uptime, 0)
        XCTAssertTrue(sample.issues.isEmpty, sample.issues.joined(separator: "; "))
    }

    @MainActor func testLiveSamplingPublishesValidHistory() async throws {
        let service = SystemStatusService()
        defer { service.stop() }
        let sampled = expectation(description: "Live CPU sample")
        var subscription: AnyCancellable?
        subscription = service.$snapshot.first(where: { $0.cpu != nil }).sink { _ in sampled.fulfill() }
        await fulfillment(of: [sampled], timeout: 4)
        subscription?.cancel()
        XCTAssertNotNil(service.snapshot.cpu)
        XCTAssertFalse(service.cpuHistory.points.isEmpty)
        XCTAssertFalse(service.memoryHistory.points.isEmpty)
        XCTAssertFalse(service.isPreview)
        XCTAssertNotEqual(service.connection.state, .unknown)
    }

    func testNativeNetworkCountersAndRatesAreReadable() throws {
        let reader = NativeNetworkReader()
        let counters = try reader.counters()
        XCTAssertEqual(Set(counters.map(\.identifier)).count, counters.count)
        XCTAssertNil(try reader.read(at: Date()))
        Thread.sleep(forTimeInterval: 0.1)
        if let rate = try reader.read(at: Date()) {
            XCTAssertGreaterThanOrEqual(rate.download, 0); XCTAssertTrue(rate.download.isFinite)
            XCTAssertGreaterThanOrEqual(rate.upload, 0); XCTAssertTrue(rate.upload.isFinite)
        }
    }
    @MainActor func testNetworkNoticesUseTransitionsAndDoNotAppearAtStartup() {
        let service = SystemStatusService(start: false)
        service.updateConnection(NetworkConnectionInfo(state: .connected, transport: "Wi-Fi"))
        XCTAssertNil(service.connectionNotice)
        service.updateConnection(NetworkConnectionInfo(state: .disconnected))
        XCTAssertTrue(service.connectionNotice?.isDisconnected == true)
        service.updateConnection(NetworkConnectionInfo(state: .connected, transport: "以太网"))
        XCTAssertFalse(service.connectionNotice?.isDisconnected == true)
        XCTAssertEqual(service.connectionNotice?.text, "网络连接已恢复")
        service.stop(); XCTAssertNil(service.connectionNotice)
    }
}
