import Foundation

/// Loads and saves `Settings` and `DayState` to JSON files.
public final class SettingsStore {
    private let settingsFile: JSONFile<Settings>
    private let stateFile: JSONFile<DayState>
    private let openSessionFile: JSONFile<OpenSession>

    public init(settingsURL: URL = AppPaths.settingsFile,
                stateURL: URL = AppPaths.stateFile,
                openSessionURL: URL = AppPaths.openSessionFile) {
        settingsFile = JSONFile(url: settingsURL)
        stateFile = JSONFile(url: stateURL)
        openSessionFile = JSONFile(url: openSessionURL)
    }

    public func loadSettings() -> Settings { settingsFile.read() ?? Settings() }
    public func saveSettings(_ settings: Settings) { settingsFile.write(settings) }

    public func loadState() -> DayState? { stateFile.read() }
    public func saveState(_ state: DayState) { stateFile.write(state) }

    /// The in-flight session checkpoint (see `OpenSession`). `nil` once there's no open
    /// session — cleared whenever one closes cleanly.
    public func loadOpenSession() -> OpenSession? { openSessionFile.read() }
    public func saveOpenSession(_ session: OpenSession) { openSessionFile.write(session) }
    public func clearOpenSession() { openSessionFile.clear() }

    /// Recover the session orphaned by a previous unclean exit: finalize the persisted
    /// checkpoint into `logger`, then clear it so the next launch can't log it twice. The
    /// budget already charged the stretch, so this just makes the usage log agree. Returns
    /// the recovered record, or nil if there was no (recoverable) checkpoint.
    @discardableResult
    public func recoverOpenSession(into logger: UsageLogger) -> UsageLogger.Record? {
        guard let checkpoint = loadOpenSession() else { return nil }
        clearOpenSession()
        guard let record = checkpoint.finalized() else { return nil }
        logger.append(start: record.start, end: record.end)
        return record
    }
}
