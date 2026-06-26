import XCTest
@testable import LimitCore

/// Tests for `UsageSummary` — the pure logic that turns logged sessions into per-day
/// totals (`byDay`), merged usage blocks (`blocks`), and the compact iMessage body
/// (`brief`). Logger I/O lives in `UsageLoggerTests`.
final class UsageSummaryTests: XCTestCase {

    // MARK: Fixtures

    /// "2026-06-25 HH:MM:SS" in UTC → Date, for readable fixtures.
    private func at(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var c = DateComponents()
        c.year = 2026; c.month = 6; c.day = 25
        c.hour = hour; c.minute = minute; c.second = second
        return cal.date(from: c)!
    }

    private func session(_ sh: Int, _ sm: Int, _ eh: Int, _ em: Int) -> UsageLogger.Record {
        UsageLogger.Record(start: at(sh, sm), end: at(eh, em))
    }

    private let utc = TimeZone(identifier: "UTC")!

    /// Active seconds a block represents = wall span minus the idle it swallowed. This is
    /// the quantity that should equal time charged against the budget.
    private func activeSeconds(_ block: UsageBlock) -> Int {
        Int(block.end.timeIntervalSince(block.start)) - block.idleSeconds
    }

    // MARK: blocks()

    func testBlocksEmpty() {
        XCTAssertTrue(UsageSummary.blocks([], mergeGap: 60).isEmpty)
    }

    func testBlocksSingleSessionHasNoIdle() {
        let blocks = UsageSummary.blocks([session(10, 0, 10, 30)], mergeGap: 60)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].start, at(10, 0))
        XCTAssertEqual(blocks[0].end, at(10, 30))
        XCTAssertEqual(blocks[0].idleSeconds, 0)
    }

    func testBlocksMergesGapAtOrUnderThreshold() {
        // A gap exactly equal to mergeGap merges (the test is `<=`).
        let blocks = UsageSummary.blocks(
            [session(10, 0, 10, 10), session(10, 11, 10, 20)], mergeGap: 60)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].start, at(10, 0))
        XCTAssertEqual(blocks[0].end, at(10, 20))
        XCTAssertEqual(blocks[0].idleSeconds, 60)
    }

    func testBlocksSplitsGapJustOverThreshold() {
        // 61s gap is one second past the 60s mergeGap, so it does not merge.
        let a = UsageLogger.Record(start: at(10, 0), end: at(10, 10))
        let b = UsageLogger.Record(start: at(10, 10, 1) + 60, end: at(10, 20))
        let blocks = UsageSummary.blocks([a, b], mergeGap: 60)
        XCTAssertEqual(blocks.count, 2)
    }

    func testBlocksAccumulatesMultipleIdleGaps() {
        // Three sessions, two 60s gaps between them, all merged into one block.
        let blocks = UsageSummary.blocks(
            [session(10, 0, 10, 5), session(10, 6, 10, 10), session(10, 11, 10, 15)],
            mergeGap: 120)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].idleSeconds, 120) // two 60s gaps
    }

    func testBlocksSortsUnorderedInput() {
        let blocks = UsageSummary.blocks(
            [session(11, 0, 11, 30), session(10, 0, 10, 20)], mergeGap: 60)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].start, at(10, 0))
        XCTAssertEqual(blocks[1].start, at(11, 0))
    }

    func testBlocksFoldsOverlappingSessionsWithoutPhantomIdle() {
        let blocks = UsageSummary.blocks(
            [session(10, 0, 10, 30), session(10, 20, 10, 40)], mergeGap: 60)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].start, at(10, 0))
        XCTAssertEqual(blocks[0].end, at(10, 40))
        XCTAssertEqual(blocks[0].idleSeconds, 0)
    }

    func testBlocksFoldsFullyContainedSession() {
        // Inner session entirely inside the outer must not shrink the block's end.
        let blocks = UsageSummary.blocks(
            [session(10, 0, 10, 40), session(10, 10, 10, 20)], mergeGap: 60)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].end, at(10, 40))
        XCTAssertEqual(blocks[0].idleSeconds, 0)
    }

    func testBlocksDropsDegenerateSessions() {
        // Zero-length and reversed records are filtered before merging.
        let zero = UsageLogger.Record(start: at(10, 0), end: at(10, 0))
        let reversed = UsageLogger.Record(start: at(10, 30), end: at(10, 20))
        let real = session(11, 0, 11, 10)
        let blocks = UsageSummary.blocks([zero, reversed, real], mergeGap: 60)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].start, at(11, 0))
    }

    // MARK: The accounting invariant — "the numbers add up"

    /// The headline property: a block's active seconds (span − idle) must equal the sum of
    /// the durations of the sessions it merged. If this holds for every merge gap, the
    /// summary can never invent or lose charged time — any mismatch a parent sees against
    /// the budget comes from sessions missing in the log, not from summarization.
    func testActiveSecondsEqualsSummedSessionDurationsAcrossLadder() {
        let records = [
            session(9, 0, 9, 20),
            session(9, 25, 9, 40),
            session(10, 30, 10, 45),
            session(10, 46, 10, 50),
            session(14, 0, 14, 5),
        ]
        let total = records.reduce(0) { $0 + $1.durationSeconds }
        // Every rung of the ladder must conserve charged time.
        for gap in [60.0, 120, 300, 600, 1800, 3600, 86400] {
            let blocks = UsageSummary.blocks(records, mergeGap: gap)
            let active = blocks.reduce(0) { $0 + activeSeconds($1) }
            XCTAssertEqual(active, total, "charged time not conserved at mergeGap=\(gap)")
        }
    }

    // MARK: brief()

    func testBriefEmpty() {
        XCTAssertEqual(UsageSummary.brief([]), "Usage: none")
    }

    func testBriefDropsDegenerateOnlyAsNone() {
        let zero = UsageLogger.Record(start: at(10, 0), end: at(10, 0))
        XCTAssertEqual(UsageSummary.brief([zero]), "Usage: none")
    }

    func testBriefSingleSession() {
        let summary = UsageSummary.brief([session(10, 0, 10, 20)], timeZone: utc)
        XCTAssertEqual(summary, "Usage:\n10:00 -- 10:20")
    }

    func testBriefKeepsShortLogDetailed() {
        // A 3-minute gap exceeds the smallest (60s) merge gap, so with room to spare the
        // two bursts stay separate.
        let records = [session(10, 0, 10, 10), session(10, 13, 10, 20)]
        XCTAssertEqual(UsageSummary.brief(records, timeZone: utc),
                       "Usage:\n10:00 -- 10:10\n10:13 -- 10:20")
    }

    func testBriefKeepsLargeGapsAsSeparateBlocks() {
        let records = [session(10, 0, 10, 20), session(11, 0, 11, 30)]
        XCTAssertEqual(UsageSummary.brief(records, timeZone: utc),
                       "Usage:\n10:00 -- 10:20\n11:00 -- 11:30")
    }

    func testBriefMergesAndReportsIdleWhenCompressing() {
        // Forced to one line: the two bursts collapse and the 3-minute gap surfaces as idle.
        let records = [session(10, 0, 10, 10), session(10, 13, 10, 20)]
        XCTAssertEqual(UsageSummary.brief(records, maxLines: 1, timeZone: utc),
                       "Usage:\n10:00 -- 10:20 (with 3 minute idle time)")
    }

    func testBriefIdleRoundsToNearestMinute() {
        // 90s gap rounds up to 2 minutes ((90+30)/60 = 2).
        let a = UsageLogger.Record(start: at(10, 0), end: at(10, 1))
        let b = UsageLogger.Record(start: at(10, 2, 30), end: at(10, 4))
        XCTAssertEqual(UsageSummary.brief([a, b], maxLines: 1, timeZone: utc),
                       "Usage:\n10:00 -- 10:04 (with 2 minute idle time)")
    }

    func testBriefSubThirtySecondIdleNotAnnotated() {
        // A 29s gap rounds to 0 minutes, so no idle clause is printed even though merged.
        let a = UsageLogger.Record(start: at(10, 0), end: at(10, 1))
        let b = UsageLogger.Record(start: at(10, 1, 29), end: at(10, 2))
        XCTAssertEqual(UsageSummary.brief([a, b], maxLines: 1, timeZone: utc),
                       "Usage:\n10:00 -- 10:02")
    }

    func testBriefWidensGapToFitMaxLines() {
        // 30 one-minute sessions, each 1 minute apart. One line each would be 30 blocks;
        // widening the merge gap must collapse them under maxLines.
        var records: [UsageLogger.Record] = []
        for i in 0..<30 {
            let start = at(9, 0).addingTimeInterval(Double(i) * 120) // every 2 min
            records.append(UsageLogger.Record(start: start, end: start.addingTimeInterval(60)))
        }
        let summary = UsageSummary.brief(records, maxLines: 5, timeZone: utc)
        let lines = summary.split(separator: "\n")
        XCTAssertEqual(lines.first, "Usage:")
        XCTAssertLessThanOrEqual(lines.count - 1, 5)
    }

    func testBriefHonoursTimeZone() {
        // Same instant, two zones: the printed wall-clock hour shifts.
        let r = [session(10, 0, 10, 20)]
        let ny = UsageSummary.brief(r, timeZone: TimeZone(identifier: "America/New_York")!)
        XCTAssertEqual(ny, "Usage:\n06:00 -- 06:20") // UTC-4 in June (EDT)
    }

    /// Regression for the reported "numbers don't add up" message: feed the exact shape the
    /// parent saw (ten short sessions) and confirm the summary faithfully reflects only the
    /// ~66 minutes that were actually logged — i.e. brief neither invents nor hides time, so
    /// the shortfall vs the 2h budget is upstream in session capture, not here.
    func testBriefReflectsExactlyTheLoggedTime() {
        let records = [
            session(1, 27, 1, 33), session(10, 29, 10, 34), session(10, 46, 10, 47),
            session(10, 51, 11, 9), session(12, 4, 12, 19), session(12, 37, 12, 57),
            session(14, 41, 14, 42),
        ]
        let loggedMinutes = records.reduce(0) { $0 + $1.durationSeconds } / 60
        XCTAssertEqual(loggedMinutes, 66) // far short of the 120-minute budget
        // brief, with maxLines headroom, must not merge across the big gaps.
        let lines = UsageSummary.brief(records, timeZone: utc).split(separator: "\n").count - 1
        XCTAssertEqual(lines, records.count)
    }

    // MARK: byDay()

    func testByDayGroupsAndSortsNewestFirst() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let boundary = DayBoundary(resetHour: 0, resetMinute: 0, calendar: cal)

        func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int) -> Date {
            var c = DateComponents(); c.year = y; c.month = mo; c.day = d; c.hour = h
            return cal.date(from: c)!
        }

        let records = [
            UsageLogger.Record(start: date(2026, 6, 24, 9), end: date(2026, 6, 24, 9).addingTimeInterval(600)),
            UsageLogger.Record(start: date(2026, 6, 24, 14), end: date(2026, 6, 24, 14).addingTimeInterval(300)),
            UsageLogger.Record(start: date(2026, 6, 25, 10), end: date(2026, 6, 25, 10).addingTimeInterval(1200)),
        ]

        let days = UsageSummary.byDay(records, boundary: boundary)
        XCTAssertEqual(days.map(\.dayKey), ["2026-06-25", "2026-06-24"])
        XCTAssertEqual(days[0].totalSeconds, 1200)
        XCTAssertEqual(days[0].sessionCount, 1)
        XCTAssertEqual(days[1].totalSeconds, 900)
        XCTAssertEqual(days[1].sessionCount, 2)
    }

    func testByDayAttributesSessionToStartDay() {
        // A session that starts just before the reset boundary belongs to the earlier day,
        // even if it ends after midnight.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let boundary = DayBoundary(resetHour: 0, resetMinute: 0, calendar: cal)

        let start = at(23, 50)              // 2026-06-25 23:50 UTC
        let end = start.addingTimeInterval(1200) // crosses into 2026-06-26
        let days = UsageSummary.byDay([UsageLogger.Record(start: start, end: end)], boundary: boundary)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].dayKey, "2026-06-25")
        XCTAssertEqual(days[0].totalSeconds, 1200)
    }
}
