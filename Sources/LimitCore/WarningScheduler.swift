import Foundation

/// Decides which countdown warnings are due. Warnings fire reactively as the budget
/// crosses each threshold (rather than being pre-scheduled by wall-clock) because the
/// countdown pauses whenever the Mac isn't actively used.
public enum WarningScheduler {
    /// Seconds-before-expiry at which to warn, plus 0 = "time's up".
    public static let thresholds = [300, 180, 60, 0]

    /// Thresholds whose moment has arrived (`remaining <= t`) and that haven't fired yet.
    public static func due(remaining: Int, alreadyFired: Set<Int>) -> [Int] {
        thresholds
            .filter { remaining <= $0 && !alreadyFired.contains($0) }
            .sorted(by: >)
    }

    /// (title, body) for a notification at `threshold`.
    public static func message(for threshold: Int) -> (title: String, body: String) {
        switch threshold {
        case 0:
            return ("Time's up", "The daily screen-time limit has been reached.")
        case 60:
            return ("1 minute left", "1 minute of screen time remaining today.")
        default:
            let mins = threshold / 60
            return ("\(mins) minutes left", "\(mins) minutes of screen time remaining today.")
        }
    }
}
