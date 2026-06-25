import Foundation

/// Pure decision logic for v2 enforcement, kept out of the AppKit layer so it can be
/// unit-tested headlessly. The app calls `shouldLock` each tick and presents/dismisses
/// the lock overlay accordingly.
public enum Enforcement {
    /// Whether the parent-PIN lock overlay should be on screen.
    ///
    /// Locks only when enforcement is enabled *and* the budget is exhausted. As soon as
    /// the budget goes positive again — via a parent extension or the daily rollover —
    /// this returns false and the overlay is dismissed.
    public static func shouldLock(remainingSeconds: Int, enforcementEnabled: Bool) -> Bool {
        guard enforcementEnabled else { return false }
        return remainingSeconds <= 0
    }
}
