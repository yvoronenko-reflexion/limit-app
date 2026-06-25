import XCTest
@testable import LimitCore

final class WarningSchedulerTests: XCTestCase {
    func testNoWarningsWhenAmpleTime() {
        XCTAssertTrue(WarningScheduler.due(remaining: 1000, alreadyFired: []).isEmpty)
    }

    func testFiresFiveMinuteThreshold() {
        XCTAssertEqual(WarningScheduler.due(remaining: 300, alreadyFired: []), [300])
        XCTAssertEqual(WarningScheduler.due(remaining: 299, alreadyFired: []), [300])
    }

    func testDoesNotRefireAlreadyFired() {
        XCTAssertEqual(WarningScheduler.due(remaining: 250, alreadyFired: [300]), [])
    }

    func testCrossingMultipleAtOnceReturnsAllUnfired() {
        // From a fresh state straight to expiry, all thresholds are due.
        XCTAssertEqual(WarningScheduler.due(remaining: 0, alreadyFired: []), [300, 180, 60, 0])
    }

    func testMessagesAreDistinct() {
        XCTAssertEqual(WarningScheduler.message(for: 0).title, "Time's up")
        XCTAssertEqual(WarningScheduler.message(for: 60).title, "1 minute left")
        XCTAssertEqual(WarningScheduler.message(for: 300).title, "5 minutes left")
    }
}
