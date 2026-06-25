import Foundation

/// User-configurable settings, persisted to settings.json.
public struct Settings: Codable, Equatable {
    /// Daily active-use budget, in seconds. Default 2 hours.
    public var dailyLimitSeconds: Int
    /// Local time-of-day at which the budget resets (default 00:00).
    public var resetHour: Int
    public var resetMinute: Int
    /// No-input duration (seconds) after which time stops counting (default 60s).
    public var idleThresholdSeconds: Int
    /// Salted hash of the parent PIN. Nil until a PIN is set.
    public var parentPIN: ParentPIN.Stored?
    /// iMessage handles (phone/email) to notify in v3. Stored now, used later.
    public var parentHandles: [String]
    /// macOS short username this instance limits (informational in v1; the app
    /// runs inside that user's session).
    public var targetUsername: String

    public init(
        dailyLimitSeconds: Int = 2 * 60 * 60,
        resetHour: Int = 0,
        resetMinute: Int = 0,
        idleThresholdSeconds: Int = 60,
        parentPIN: ParentPIN.Stored? = nil,
        parentHandles: [String] = [],
        targetUsername: String = NSUserName()
    ) {
        self.dailyLimitSeconds = dailyLimitSeconds
        self.resetHour = resetHour
        self.resetMinute = resetMinute
        self.idleThresholdSeconds = idleThresholdSeconds
        self.parentPIN = parentPIN
        self.parentHandles = parentHandles
        self.targetUsername = targetUsername
    }
}

/// Per-budget-day mutable state, persisted to state.json so it survives restarts.
public struct DayState: Codable, Equatable {
    /// Identifies the current budget day, e.g. "2026-06-25" (see `DayBoundary`).
    public var dayKey: String
    /// Seconds of budget left for `dayKey`.
    public var remainingSeconds: Int
    /// Warning thresholds (seconds-before-zero) already notified for `dayKey`.
    public var firedThresholds: [Int]

    public init(dayKey: String, remainingSeconds: Int, firedThresholds: [Int] = []) {
        self.dayKey = dayKey
        self.remainingSeconds = remainingSeconds
        self.firedThresholds = firedThresholds
    }
}
