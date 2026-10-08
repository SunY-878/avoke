import Foundation
import Combine
import XCTest
import IOKit.pwr_mgt
import IslandCore
@testable import SkyIsland

private final class FakePowerBackend: PowerAssertionBackend {
    var active: [UInt32: PowerAssertionKind] = [:]
    var failOn: PowerAssertionKind?
    private var nextID: UInt32 = 1
    func create(_ kind: PowerAssertionKind, duration: TimeInterval?) throws -> UInt32 {
        if kind == failOn { throw NSError(domain: "Tests", code: 1) }
        let id = nextID; nextID += 1; active[id] = kind; return id
    }
    func release(_ id: UInt32) { active.removeValue(forKey: id) }
}

final class KeepAwakeTests: XCTestCase {
    @MainActor func testModeSwitchReleasesOldAssertionsAndStopClearsAll() {
        let backend = FakePowerBackend()
        // Each session uses the same injected backend; never execute a display-sleep command.
        let awake = KeepAwakeService(backend: backend)
        awake.start(mode: .display, duration: nil)
        XCTAssertEqual(Set(backend.active.values), Set([.display, .system, .disk]))
        awake.start(mode: .background, duration: 60)
        XCTAssertEqual(Set(backend.active.values), Set([.system, .disk]))
        XCTAssertEqual(backend.active.count, 2)
        awake.stop(); XCTAssertTrue(backend.active.isEmpty); XCTAssertNil(awake.session)
    }
    @MainActor func testFailedReplacementRollsBackAndPreservesRunningSession() {
        let backend = FakePowerBackend()
        let service = KeepAwakeService(backend: backend)
        service.start(mode: .background, duration: nil)
        let ids = Set(backend.active.keys)
        backend.failOn = .system
        service.start(mode: .display, duration: 60)
        XCTAssertEqual(Set(backend.active.keys), ids)
        XCTAssertEqual(service.session?.mode, .background)
        XCTAssertNotNil(service.message)
        service.stop(); XCTAssertTrue(backend.active.isEmpty)
    }
    @MainActor func testExpirationReleasesEveryAssertion() async {
        let backend = FakePowerBackend()
        let awake = KeepAwakeService(backend: backend)
        awake.start(mode: .background, duration: 0.06)
        let finished = expectation(description: "Timed awake session ended")
        let subscription = awake.$session.first(where: { $0 == nil }).sink { _ in finished.fulfill() }
        await fulfillment(of: [finished], timeout: 2)
        subscription.cancel()
        XCTAssertTrue(backend.active.isEmpty); XCTAssertFalse(awake.isActive)
    }
    @MainActor func testCancelledDeadlineCannotStopNewSession() async throws {
        let backend = FakePowerBackend()
        let service = KeepAwakeService(backend: backend)
        service.start(mode: .display, duration: 0.06)
        service.start(mode: .background, duration: nil)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(service.session?.mode, .background)
        XCTAssertEqual(backend.active.count, 2)
        service.stop()
    }
    func testNativePowerAssertionsHaveExpectedTypesAndAreReleased() throws {
        let backend = NativePowerAssertionBackend()
        var ids: [UInt32] = []
        defer { for id in ids { backend.release(id) } }
        for kind in KeepAwakeMode.display.assertions {
            let id = try backend.create(kind, duration: 5); ids.append(id)
            let properties = try XCTUnwrap(IOPMAssertionCopyProperties(id)).takeRetainedValue() as NSDictionary
            XCTAssertEqual(properties[kIOPMAssertionTypeKey] as? String, kind.rawValue)
            XCTAssertEqual((properties[kIOPMAssertionLevelKey] as? NSNumber)?.intValue, Int(kIOPMAssertionLevelOn))
        }
        for id in ids { backend.release(id); XCTAssertNil(IOPMAssertionCopyProperties(id)) }
    }
    @MainActor func testPreviewDoesNotAcquireRealPowerAssertions() {
        let preview = KeepAwakeService.preview()
        XCTAssertTrue(preview.isPreview)
        XCTAssertEqual(preview.session?.mode, .background)
        preview.start(mode: .display, duration: nil)
        XCTAssertEqual(preview.session?.mode, .background)
        preview.stop(); XCTAssertNil(preview.session)
    }
    @MainActor func testIslandRoutesLiveActivitiesAndFitsTheWindow() {
        let suite = "app.skyisland.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        let media = MediaService(), clipboard = ClipboardService(preferences: preferences, start: false)
        let system = SystemStatusService.preview(), awake = KeepAwakeService.preview()
        let model = IslandModel(preferences: preferences, media: media, clipboard: clipboard, system: system, awake: awake)
        model.open(); XCTAssertEqual(model.selectedTab, .awake)
        model.close()
        system.updateConnection(NetworkConnectionInfo(state: .disconnected))
        model.open(); XCTAssertEqual(model.selectedTab, .system)
        model.hasNotch = true; preferences.islandScale = 1.15
        for tab: IslandTab in [.music, .clipboard, .system, .awake, .settings] {
            model.selectedTab = tab
            XCTAssertLessThanOrEqual(model.height, 570); XCTAssertLessThanOrEqual(model.width, 680)
        }
    }
}
