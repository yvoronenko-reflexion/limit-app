import Foundation
import AppKit

/// Tracks whether the Mac is "actively used" by this user. Event-driven flags
/// (lock/unlock, display sleep, fast-user-switch) are combined at poll time with a
/// fresh on-console + idle check to produce a snapshot.
///
/// active = on-console session AND not locked AND display awake AND not idle.
public final class ActivityMonitor {
    public struct Snapshot {
        public let active: Bool
        public let reason: String
    }

    private var screenLocked = false
    private var displayAsleep = false
    private var sessionActive = true

    private let workspaceCenter = NSWorkspace.shared.notificationCenter
    private let distributedCenter = DistributedNotificationCenter.default()
    private var observers: [NSObjectProtocol] = []

    public init() {
        subscribe()
    }

    deinit {
        observers.forEach { workspaceCenter.removeObserver($0) }
        // Distributed observers are torn down on process exit; this object lives app-long.
    }

    private func subscribe() {
        func observeDistributed(_ name: String, _ handler: @escaping () -> Void) {
            let token = distributedCenter.addObserver(forName: Notification.Name(name),
                                                      object: nil, queue: .main) { _ in
                handler()
            }
            observers.append(token)
        }
        func observeWorkspace(_ name: Notification.Name, _ handler: @escaping () -> Void) {
            let token = workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
                handler()
            }
            observers.append(token)
        }

        observeDistributed("com.apple.screenIsLocked") { [weak self] in self?.screenLocked = true }
        observeDistributed("com.apple.screenIsUnlocked") { [weak self] in self?.screenLocked = false }

        observeWorkspace(NSWorkspace.screensDidSleepNotification) { [weak self] in self?.displayAsleep = true }
        observeWorkspace(NSWorkspace.screensDidWakeNotification) { [weak self] in self?.displayAsleep = false }
        observeWorkspace(NSWorkspace.willSleepNotification) { [weak self] in self?.displayAsleep = true }
        observeWorkspace(NSWorkspace.didWakeNotification) { [weak self] in self?.displayAsleep = false }
        observeWorkspace(NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.sessionActive = false }
        observeWorkspace(NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in self?.sessionActive = true }
    }

    public func snapshot(idleThreshold: Int) -> Snapshot {
        if !sessionActive || !SessionState.isOnConsole() {
            return Snapshot(active: false, reason: "Switched out")
        }
        if screenLocked {
            return Snapshot(active: false, reason: "Locked")
        }
        if displayAsleep {
            return Snapshot(active: false, reason: "Display asleep")
        }
        if IdleTime.seconds() >= Double(idleThreshold) {
            return Snapshot(active: false, reason: "Idle")
        }
        return Snapshot(active: true, reason: "Active")
    }
}
