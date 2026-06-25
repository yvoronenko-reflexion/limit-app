import XCTest
@testable import LimitCore

final class UsageLoggerTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-test-\(UUID().uuidString).jsonl")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    func testAppendThenLoadRoundTrips() {
        let logger = UsageLogger(url: url)
        let start = Date(timeIntervalSince1970: 1_000_000)
        logger.append(start: start, end: start.addingTimeInterval(120))
        logger.append(start: start.addingTimeInterval(300), end: start.addingTimeInterval(360))

        let records = logger.load()
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].durationSeconds, 120)
        XCTAssertEqual(records[1].durationSeconds, 60)
    }

    func testLoadSkipsMalformedLines() throws {
        let good = #"{"start":"1970-01-01T00:00:00Z","end":"1970-01-01T00:01:00Z","durationSeconds":60}"#
        try "\(good)\nnot json\n\n".write(to: url, atomically: true, encoding: .utf8)

        let records = UsageLogger(url: url).load()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].durationSeconds, 60)
    }

    func testLoadMissingFileIsEmpty() {
        XCTAssertTrue(UsageLogger(url: url).load().isEmpty)
    }

    func testByDayGroupsAndSortsNewestFirst() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let boundary = DayBoundary(resetHour: 0, resetMinute: 0, calendar: cal)

        func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int) -> Date {
            var c = DateComponents(); c.year = y; c.month = mo; c.day = d; c.hour = h
            return cal.date(from: c)!
        }

        let records = [
            UsageLogger.Record(start: date(2026, 6, 24, 9), end: date(2026, 6, 24, 9), durationSeconds: 600),
            UsageLogger.Record(start: date(2026, 6, 24, 14), end: date(2026, 6, 24, 14), durationSeconds: 300),
            UsageLogger.Record(start: date(2026, 6, 25, 10), end: date(2026, 6, 25, 10), durationSeconds: 1200),
        ]

        let days = UsageSummary.byDay(records, boundary: boundary)
        XCTAssertEqual(days.map(\.dayKey), ["2026-06-25", "2026-06-24"])
        XCTAssertEqual(days[0].totalSeconds, 1200)
        XCTAssertEqual(days[0].sessionCount, 1)
        XCTAssertEqual(days[1].totalSeconds, 900)
        XCTAssertEqual(days[1].sessionCount, 2)
    }
}
