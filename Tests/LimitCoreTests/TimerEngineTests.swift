import XCTest
@testable import LimitCore

final class TimerEngineTests: XCTestCase {
    private func makeEngine(remaining: Int = 7200, limit: Int = 7200,
                            dayKey: String = "2026-06-25",
                            calendar: Calendar = .current) -> TimerEngine {
        let boundary = DayBoundary(resetHour: 0, resetMinute: 0, calendar: calendar)
        let state = DayState(dayKey: dayKey, remainingSeconds: remaining)
        return TimerEngine(state: state, dailyLimit: limit, boundary: boundary)
    }

    func testTickActiveDecrementsBySecond() {
        let engine = makeEngine(remaining: 100)
        for _ in 0 ..< 5 { engine.tickActive() }
        XCTAssertEqual(engine.state.remainingSeconds, 95)
    }

    func testTickStopsAtZeroAndNeverGoesNegative() {
        let engine = makeEngine(remaining: 2)
        for _ in 0 ..< 5 { engine.tickActive() }
        XCTAssertEqual(engine.state.remainingSeconds, 0)
        XCTAssertTrue(engine.isExpired)
    }

    func testExtendAddsTimeAndClearsFiredThresholds() {
        let engine = makeEngine(remaining: 30)
        engine.state.firedThresholds = [300, 180, 60]
        engine.extend(by: 600)
        XCTAssertEqual(engine.state.remainingSeconds, 630)
        XCTAssertTrue(engine.state.firedThresholds.isEmpty)
    }

    func testExtendIgnoresZero() {
        let engine = makeEngine(remaining: 50)
        engine.extend(by: 0)
        XCTAssertEqual(engine.state.remainingSeconds, 50)
    }

    func testExtendByNegativeDeductsTime() {
        let engine = makeEngine(remaining: 50)
        engine.extend(by: -10)
        XCTAssertEqual(engine.state.remainingSeconds, 40)
    }

    func testExtendClampsAtZero() {
        let engine = makeEngine(remaining: 50)
        engine.extend(by: -100)
        XCTAssertEqual(engine.state.remainingSeconds, 0)
    }

    func testRolloverResetsBudgetOnNewDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let engine = makeEngine(remaining: 10, limit: 7200, dayKey: "2026-06-24", calendar: cal)
        engine.state.firedThresholds = [300]

        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 25; comps.hour = 12
        let now = cal.date(from: comps)!

        XCTAssertTrue(engine.rolloverIfNeeded(now: now))
        XCTAssertEqual(engine.state.dayKey, "2026-06-25")
        XCTAssertEqual(engine.state.remainingSeconds, 7200)
        XCTAssertTrue(engine.state.firedThresholds.isEmpty)
    }

    func testNoRolloverWithinSameDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let engine = makeEngine(remaining: 500, dayKey: "2026-06-25", calendar: cal)

        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 25; comps.hour = 23; comps.minute = 59
        let now = cal.date(from: comps)!

        XCTAssertFalse(engine.rolloverIfNeeded(now: now))
        XCTAssertEqual(engine.state.remainingSeconds, 500)
    }
}
