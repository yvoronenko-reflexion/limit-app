import XCTest
@testable import LimitCore

final class EnforcementTests: XCTestCase {
    func testNoLockWhenDisabled() {
        XCTAssertFalse(Enforcement.shouldLock(remainingSeconds: 0, enforcementEnabled: false))
        XCTAssertFalse(Enforcement.shouldLock(remainingSeconds: -30, enforcementEnabled: false))
    }

    func testLocksAtAndBelowZeroWhenEnabled() {
        XCTAssertTrue(Enforcement.shouldLock(remainingSeconds: 0, enforcementEnabled: true))
        XCTAssertTrue(Enforcement.shouldLock(remainingSeconds: -1, enforcementEnabled: true))
    }

    func testNoLockWhileTimeRemains() {
        XCTAssertFalse(Enforcement.shouldLock(remainingSeconds: 1, enforcementEnabled: true))
        XCTAssertFalse(Enforcement.shouldLock(remainingSeconds: 3600, enforcementEnabled: true))
    }
}
