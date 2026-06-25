import XCTest
@testable import LimitCore

final class DayBoundaryTests: XCTestCase {
    private func calendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        return cal
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ cal: Calendar) -> Date {
        var comps = DateComponents()
        comps.year = y; comps.month = mo; comps.day = d; comps.hour = h; comps.minute = mi
        return cal.date(from: comps)!
    }

    func testMidnightReset() {
        let cal = calendar()
        let boundary = DayBoundary(resetHour: 0, resetMinute: 0, calendar: cal)
        XCTAssertEqual(boundary.dayKey(for: date(2026, 6, 25, 0, 0, cal)), "2026-06-25")
        XCTAssertEqual(boundary.dayKey(for: date(2026, 6, 25, 10, 30, cal)), "2026-06-25")
        XCTAssertEqual(boundary.dayKey(for: date(2026, 6, 25, 23, 59, cal)), "2026-06-25")
    }

    func testCustomResetHourSplitsTheDay() {
        let cal = calendar()
        let boundary = DayBoundary(resetHour: 6, resetMinute: 0, calendar: cal)
        // Before 06:00 belongs to the previous budget day.
        XCTAssertEqual(boundary.dayKey(for: date(2026, 6, 25, 5, 59, cal)), "2026-06-24")
        // At/after 06:00 is the new budget day.
        XCTAssertEqual(boundary.dayKey(for: date(2026, 6, 25, 6, 0, cal)), "2026-06-25")
        XCTAssertEqual(boundary.dayKey(for: date(2026, 6, 25, 23, 0, cal)), "2026-06-25")
    }

    func testKeyChangesAcrossMidnightBoundary() {
        let cal = calendar()
        let boundary = DayBoundary(resetHour: 0, resetMinute: 0, calendar: cal)
        let before = boundary.dayKey(for: date(2026, 6, 25, 23, 59, cal))
        let after = boundary.dayKey(for: date(2026, 6, 26, 0, 1, cal))
        XCTAssertEqual(before, "2026-06-25")
        XCTAssertEqual(after, "2026-06-26")
        XCTAssertNotEqual(before, after)
    }

    func testSpringForwardDSTDay() {
        // 2026-03-08 is US DST spring-forward (02:00 -> 03:00). A custom 02:30 reset
        // doesn't exist that day; matchingPolicy .nextTime must still yield a stable key.
        let cal = calendar()
        let boundary = DayBoundary(resetHour: 2, resetMinute: 30, calendar: cal)
        XCTAssertEqual(boundary.dayKey(for: date(2026, 3, 8, 12, 0, cal)), "2026-03-08")
        XCTAssertEqual(boundary.dayKey(for: date(2026, 3, 9, 12, 0, cal)), "2026-03-09")
    }
}
