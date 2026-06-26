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

    func testExtensionsRoundTripAndDoNotLeakIntoSessions() {
        let logger = UsageLogger(url: url)
        let start = Date(timeIntervalSince1970: 1_000_000)
        logger.append(start: start, end: start.addingTimeInterval(120))
        logger.appendExtension(at: start.addingTimeInterval(200), addedSeconds: 900)
        logger.append(start: start.addingTimeInterval(300), end: start.addingTimeInterval(360))
        logger.appendExtension(at: start.addingTimeInterval(400), addedSeconds: 1800)

        // Sessions must not include the extension lines.
        XCTAssertEqual(logger.load().map(\.durationSeconds), [120, 60])

        let extensions = logger.loadExtensions()
        XCTAssertEqual(extensions.map(\.addedSeconds), [900, 1800])
        XCTAssertEqual(extensions[0].at, start.addingTimeInterval(200))
    }

    func testOldSessionOnlyLogStillDecodes() throws {
        // A log written before extensions existed (no `kind` field) must keep working.
        let line = #"{"start":"1970-01-01T00:00:00Z","end":"1970-01-01T00:01:00Z","durationSeconds":60}"#
        try "\(line)\n".write(to: url, atomically: true, encoding: .utf8)

        let logger = UsageLogger(url: url)
        XCTAssertEqual(logger.load().count, 1)
        XCTAssertTrue(logger.loadExtensions().isEmpty)
    }
}
