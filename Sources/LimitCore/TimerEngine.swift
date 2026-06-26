import Foundation

/// Owns the countdown for the current budget day. Pure and synchronous so it can be
/// unit-tested without timers or system state; the app drives `tickActive()` once per
/// active second.
public final class TimerEngine {
    public var state: DayState
    public var dailyLimit: Int
    public var boundary: DayBoundary

    public init(state: DayState, dailyLimit: Int, boundary: DayBoundary) {
        self.state = state
        self.dailyLimit = dailyLimit
        self.boundary = boundary
    }

    /// If `now` falls in a different budget day than the current state, reset the
    /// budget to the daily limit. Returns true if a reset happened.
    @discardableResult
    public func rolloverIfNeeded(now: Date) -> Bool {
        let key = boundary.dayKey(for: now)
        guard key != state.dayKey else { return false }
        state = DayState(dayKey: key, remainingSeconds: dailyLimit, firedThresholds: [])
        return true
    }

    /// Consume one second of budget. No-op at zero (never goes negative).
    public func tickActive() {
        if state.remainingSeconds > 0 {
            state.remainingSeconds -= 1
        }
    }

    /// Adjust today's budget by a signed amount (e.g. a parent-approved
    /// extension, or a deduction). Remaining is clamped at 0 so it never goes
    /// negative. Clears fired warning thresholds so warnings re-fire as the new
    /// budget counts down.
    public func extend(by seconds: Int) {
        guard seconds != 0 else { return }
        state.remainingSeconds = max(0, state.remainingSeconds + seconds)
        state.firedThresholds = []
    }

    public var isExpired: Bool { state.remainingSeconds <= 0 }
}
