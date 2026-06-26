import XCTest
@testable import LimitCore

/// Tests for the crash-safe in-flight session checkpoint (`OpenSession`) and its
/// round-trip through `SettingsStore`.
final class OpenSessionTests: XCTestCase {
    private var url: URL!

    override func setUpWithError() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("open-session-test-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: finalized()

    func testFinalizedReturnsRecordSpanningStartToLastActive() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let checkpoint = OpenSession(start: start, lastActive: start.addingTimeInterval(180))
        let record = checkpoint.finalized()
        XCTAssertEqual(record?.start, start)
        XCTAssertEqual(record?.end, start.addingTimeInterval(180))
        XCTAssertEqual(record?.durationSeconds, 180)
    }

    func testFinalizedIsNilWhenNothingElapsed() {
        // A checkpoint written the instant a session opened (lastActive == start) carries no
        // recoverable time, so it must not produce a zero-length session record.
        let start = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertNil(OpenSession(start: start, lastActive: start).finalized())
    }

    func testFinalizedIsNilOnClockSkew() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertNil(OpenSession(start: start, lastActive: start.addingTimeInterval(-5)).finalized())
    }

    // MARK: SettingsStore round-trip

    func testStoreRoundTripsAndClears() {
        let store = SettingsStore(openSessionURL: url)
        XCTAssertNil(store.loadOpenSession())

        let start = Date(timeIntervalSince1970: 2_000_000)
        let checkpoint = OpenSession(start: start, lastActive: start.addingTimeInterval(42))
        store.saveOpenSession(checkpoint)
        XCTAssertEqual(store.loadOpenSession(), checkpoint)

        store.clearOpenSession()
        XCTAssertNil(store.loadOpenSession())
    }

    // MARK: End-to-end lifecycle (drives the shipped recovery code)

    /// Full crash path through the real `SettingsStore.recoverOpenSession(into:)` that the
    /// app calls on launch: a checkpoint left by an unclean exit is finalized into the
    /// usage log, the checkpoint is cleared, and a second launch logs nothing more (no
    /// double count).
    func testUncleanExitRecoversThenIsIdempotent() throws {
        let logURL = url.deletingLastPathComponent()
            .appendingPathComponent("usage-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: logURL) }
        let store = SettingsStore(openSessionURL: url)
        let logger = UsageLogger(url: logURL)

        // App is running: a session opened and was checkpointed as it grew (5s cadence),
        // then the process died without closing it — checkpoint survives on disk.
        let start = Date(timeIntervalSince1970: 3_000_000)
        store.saveOpenSession(OpenSession(start: start, lastActive: start.addingTimeInterval(600)))

        // Next launch recovers it.
        let recovered = store.recoverOpenSession(into: logger)
        XCTAssertEqual(recovered?.durationSeconds, 600)
        XCTAssertEqual(logger.load().map(\.durationSeconds), [600])
        XCTAssertNil(store.loadOpenSession(), "checkpoint must be cleared after recovery")

        // A subsequent launch finds nothing to recover and must not re-log the stretch.
        XCTAssertNil(store.recoverOpenSession(into: logger))
        XCTAssertEqual(logger.load().count, 1)
    }

    /// Clean close path: closing a session clears the checkpoint, so a later launch has
    /// nothing to recover — the session is logged exactly once, by the close, not again by
    /// recovery.
    func testCleanCloseLeavesNothingToRecover() {
        let logURL = url.deletingLastPathComponent()
            .appendingPathComponent("usage-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: logURL) }
        let store = SettingsStore(openSessionURL: url)
        let logger = UsageLogger(url: logURL)

        let start = Date(timeIntervalSince1970: 4_000_000)
        store.saveOpenSession(OpenSession(start: start, lastActive: start))   // session opens
        logger.append(start: start, end: start.addingTimeInterval(300))       // close writes it
        store.clearOpenSession()                                              // close clears checkpoint

        XCTAssertNil(store.recoverOpenSession(into: logger))                  // nothing orphaned
        XCTAssertEqual(logger.load().map(\.durationSeconds), [300])           // logged once only
    }
}
