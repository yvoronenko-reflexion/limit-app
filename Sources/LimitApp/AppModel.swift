import Foundation
import Combine
import AppKit
import LimitCore

/// Coordinates the timer, activity detection, logging, and notifications, and exposes
/// observable state to the SwiftUI views. The 1 Hz tick is the heartbeat: it rolls the
/// budget day over, samples activity, decrements the budget only while active, fires
/// warnings, logs sessions, and persists state.
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var isActive: Bool = false
    @Published private(set) var statusText: String = "—"
    @Published private(set) var menuBarTitle: String = "--:--"
    @Published private(set) var settings: Settings

    private let store: SettingsStore
    private let activity = ActivityMonitor()
    private let logger = UsageLogger()
    private let notifier = NotificationManager()
    private let engine: TimerEngine

    private var ticker: Timer?
    private var openSessionStart: Date?
    private var ticksSinceSave = 0

    /// v2 enforcement overlay. Created lazily (needs `self`); only touched on the main
    /// thread from the tick / UI actions.
    private lazy var lock = LockController(model: self)

    private init() {
        let store = SettingsStore()
        let settings = store.loadSettings()
        let boundary = DayBoundary(resetHour: settings.resetHour, resetMinute: settings.resetMinute)
        let key = boundary.dayKey(for: Date())

        let state: DayState
        if let loaded = store.loadState(), loaded.dayKey == key {
            state = loaded
        } else {
            state = DayState(dayKey: key, remainingSeconds: settings.dailyLimitSeconds)
        }

        self.store = store
        self.settings = settings
        self.engine = TimerEngine(state: state, dailyLimit: settings.dailyLimitSeconds, boundary: boundary)

        remainingSeconds = state.remainingSeconds
        updateMenuTitle()
    }

    // MARK: Lifecycle

    func start() {
        notifier.requestAuthorization()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        tick() // paint initial state immediately
    }

    /// Persist and close any open session (call on quit).
    func flush() {
        closeOpenSession(at: Date())
        store.saveState(engine.state)
    }

    // MARK: Tick

    private func tick() {
        let now = Date()

        if engine.rolloverIfNeeded(now: now) {
            closeOpenSession(at: now)
            store.saveState(engine.state)
        }

        let snapshot = activity.snapshot(idleThreshold: settings.idleThresholdSeconds)
        updateSessionLogging(active: snapshot.active, now: now)

        if snapshot.active {
            engine.tickActive()
        }

        fireDueWarnings()

        isActive = snapshot.active
        statusText = snapshot.reason
        remainingSeconds = engine.state.remainingSeconds
        updateMenuTitle()
        updateLock()

        persistState()
    }

    /// Show or hide the lock overlay to match the current budget + enforcement setting.
    private func updateLock() {
        lock.update(shouldLock: Enforcement.shouldLock(
            remainingSeconds: engine.state.remainingSeconds,
            enforcementEnabled: settings.enforcementEnabled))
    }

    private func fireDueWarnings() {
        var fired = Set(engine.state.firedThresholds)
        let due = WarningScheduler.due(remaining: engine.state.remainingSeconds, alreadyFired: fired)
        guard !due.isEmpty else { return }
        for threshold in due {
            let message = WarningScheduler.message(for: threshold)
            notifier.notify(title: message.title, body: message.body,
                            id: "warn-\(engine.state.dayKey)-\(threshold)")
            fired.insert(threshold)
        }
        engine.state.firedThresholds = fired.sorted()
    }

    // MARK: Usage logging

    private func updateSessionLogging(active: Bool, now: Date) {
        if active {
            if openSessionStart == nil { openSessionStart = now }
        } else {
            closeOpenSession(at: now)
        }
    }

    private func closeOpenSession(at end: Date) {
        guard let start = openSessionStart else { return }
        if end > start { logger.append(start: start, end: end) }
        openSessionStart = nil
    }

    // MARK: Persistence

    private func persistState() {
        ticksSinceSave += 1
        if ticksSinceSave >= 5 {
            store.saveState(engine.state)
            ticksSinceSave = 0
        }
    }

    // MARK: Settings / PIN / extension (used by the UI)

    var usedSeconds: Int { max(0, settings.dailyLimitSeconds - engine.state.remainingSeconds) }

    func updateSettings(_ new: Settings) {
        settings = new
        store.saveSettings(new)
        engine.dailyLimit = new.dailyLimitSeconds
        engine.boundary = DayBoundary(resetHour: new.resetHour, resetMinute: new.resetMinute)
        if engine.state.remainingSeconds > new.dailyLimitSeconds {
            engine.state.remainingSeconds = new.dailyLimitSeconds
        }
        remainingSeconds = engine.state.remainingSeconds
        updateMenuTitle()
        updateLock()
        store.saveState(engine.state)
    }

    func extend(by seconds: Int) {
        engine.extend(by: seconds)
        remainingSeconds = engine.state.remainingSeconds
        updateMenuTitle()
        updateLock()
        store.saveState(engine.state)
    }

    func isPINSet() -> Bool { settings.parentPIN != nil }

    func verifyPIN(_ pin: String) -> Bool {
        guard let stored = settings.parentPIN else { return false }
        return ParentPIN.verify(pin: pin, against: stored)
    }

    func setPIN(_ pin: String) {
        var updated = settings
        updated.parentPIN = ParentPIN.make(pin: pin)
        updateSettings(updated)
    }

    // MARK: Formatting

    private func updateMenuTitle() {
        menuBarTitle = AppModel.format(seconds: max(0, engine.state.remainingSeconds))
    }

    static func format(seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }
}
