import Foundation

/// A crash-safe checkpoint of the session currently being accumulated. The in-flight
/// session otherwise lives only in memory and is written to the usage log when it closes
/// (idle/lock) or at clean termination — so an *unclean* exit (crash, SIGKILL, logout,
/// shutdown, or a watchdog/LaunchAgent relaunch) silently drops the open stretch even
/// though the budget (saved every few seconds) already charged it.
///
/// To bound that loss, the open session is checkpointed to disk as it grows. `lastActive`
/// is the most recent instant it was confirmed alive; on the next launch an orphaned
/// checkpoint is `finalized()` into a real session `start -> lastActive`, recovering all
/// but the last few seconds of the stretch.
public struct OpenSession: Codable, Equatable {
    public let start: Date
    public let lastActive: Date

    public init(start: Date, lastActive: Date) {
        self.start = start
        self.lastActive = lastActive
    }

    /// The session record to log when recovering this checkpoint after an unclean exit,
    /// or nil if nothing elapsed (degenerate or clock-skewed checkpoint).
    public func finalized() -> UsageLogger.Record? {
        lastActive > start ? UsageLogger.Record(start: start, end: lastActive) : nil
    }
}
