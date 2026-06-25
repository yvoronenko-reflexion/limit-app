import XCTest
@testable import LimitCore

final class SettingsCodableTests: XCTestCase {
    func testRoundTrip() throws {
        var s = Settings(dailyLimitSeconds: 3600, idleThresholdSeconds: 90)
        s.enforcementEnabled = true
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(s, back)
    }

    /// A settings.json written by a v1 build has no `enforcementEnabled` key; it must
    /// still decode, defaulting enforcement off.
    func testDecodesLegacyJSONMissingNewKeys() throws {
        let legacy = """
        {
            "dailyLimitSeconds": 7200,
            "resetHour": 0,
            "resetMinute": 0,
            "idleThresholdSeconds": 60,
            "parentHandles": [],
            "targetUsername": "kid"
        }
        """.data(using: .utf8)!

        let s = try JSONDecoder().decode(Settings.self, from: legacy)
        XCTAssertEqual(s.dailyLimitSeconds, 7200)
        XCTAssertEqual(s.targetUsername, "kid")
        XCTAssertFalse(s.enforcementEnabled)
        XCTAssertNil(s.parentPIN)
    }

    func testDecodesEnforcementWhenPresent() throws {
        let json = """
        { "enforcementEnabled": true }
        """.data(using: .utf8)!
        let s = try JSONDecoder().decode(Settings.self, from: json)
        XCTAssertTrue(s.enforcementEnabled)
        // Other fields fall back to defaults.
        XCTAssertEqual(s.dailyLimitSeconds, 2 * 60 * 60)
    }
}
