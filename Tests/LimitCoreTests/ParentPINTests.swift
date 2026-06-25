import XCTest
@testable import LimitCore

final class ParentPINTests: XCTestCase {
    func testVerifyCorrectPIN() {
        let stored = ParentPIN.make(pin: "1234", saltProvider: { Data([1, 2, 3, 4]) })
        XCTAssertTrue(ParentPIN.verify(pin: "1234", against: stored))
    }

    func testVerifyWrongPIN() {
        let stored = ParentPIN.make(pin: "1234", saltProvider: { Data([1, 2, 3, 4]) })
        XCTAssertFalse(ParentPIN.verify(pin: "0000", against: stored))
        XCTAssertFalse(ParentPIN.verify(pin: "", against: stored))
        XCTAssertFalse(ParentPIN.verify(pin: "12345", against: stored))
    }

    func testDoesNotStorePlaintext() {
        let stored = ParentPIN.make(pin: "secret-pin", saltProvider: { Data([9]) })
        XCTAssertFalse(stored.hashBase64.contains("secret"))
        XCTAssertNotEqual(stored.hashBase64, "secret-pin")
    }

    func testDifferentSaltsProduceDifferentHashes() {
        let a = ParentPIN.make(pin: "1234", saltProvider: { Data([1]) })
        let b = ParentPIN.make(pin: "1234", saltProvider: { Data([2]) })
        XCTAssertNotEqual(a.hashBase64, b.hashBase64)
        // ...but each still verifies its own.
        XCTAssertTrue(ParentPIN.verify(pin: "1234", against: a))
        XCTAssertTrue(ParentPIN.verify(pin: "1234", against: b))
    }
}
