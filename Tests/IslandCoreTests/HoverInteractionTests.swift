import XCTest
@testable import IslandCore

final class HoverInteractionTests: XCTestCase {
    func testHoverDelayAndBriefPassThrough() {
        var hover = HoverInteraction()
        XCTAssertNil(hover.update(inside: true, expanded: false, pinned: false, heldOpen: false, now: 0, hoverDelay: 0.18))
        XCTAssertNil(hover.update(inside: false, expanded: false, pinned: false, heldOpen: false, now: 0.1, hoverDelay: 0.18))
        XCTAssertNil(hover.update(inside: true, expanded: false, pinned: false, heldOpen: false, now: 1, hoverDelay: 0.18))
        XCTAssertEqual(hover.update(inside: true, expanded: false, pinned: false, heldOpen: false, now: 1.2, hoverDelay: 0.18), .expand)
    }
    func testLeaveGraceAndPinOrMenuKeepsOpen() {
        var hover = HoverInteraction()
        XCTAssertNil(hover.update(inside: false, expanded: true, pinned: false, heldOpen: false, now: 0, hoverDelay: 0.18))
        XCTAssertNil(hover.update(inside: false, expanded: true, pinned: true, heldOpen: false, now: 2, hoverDelay: 0.18))
        XCTAssertNil(hover.update(inside: false, expanded: true, pinned: false, heldOpen: true, now: 3, hoverDelay: 0.18))
        XCTAssertNil(hover.update(inside: false, expanded: true, pinned: false, heldOpen: false, now: 4, hoverDelay: 0.18))
        XCTAssertEqual(hover.update(inside: false, expanded: true, pinned: false, heldOpen: false, now: 4.5, hoverDelay: 0.18), .collapse)
    }
    func testEscapeRequiresPointerToLeaveBeforeReopening() {
        var hover = HoverInteraction(); hover.didClose()
        XCTAssertNil(hover.update(inside: true, expanded: false, pinned: false, heldOpen: false, now: 100, hoverDelay: 0.18))
        XCTAssertNil(hover.update(inside: true, expanded: false, pinned: false, heldOpen: false, now: 200, hoverDelay: 0.18))
        _ = hover.update(inside: false, expanded: false, pinned: false, heldOpen: false, now: 201, hoverDelay: 0.18)
        _ = hover.update(inside: true, expanded: false, pinned: false, heldOpen: false, now: 202, hoverDelay: 0.18)
        XCTAssertEqual(hover.update(inside: true, expanded: false, pinned: false, heldOpen: false, now: 203, hoverDelay: 0.18), .expand)
    }
}
