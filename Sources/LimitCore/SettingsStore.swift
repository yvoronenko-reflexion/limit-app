import Foundation

/// Loads and saves `Settings` and `DayState` to JSON files.
public final class SettingsStore {
    private let settingsFile: JSONFile<Settings>
    private let stateFile: JSONFile<DayState>

    public init(settingsURL: URL = AppPaths.settingsFile, stateURL: URL = AppPaths.stateFile) {
        settingsFile = JSONFile(url: settingsURL)
        stateFile = JSONFile(url: stateURL)
    }

    public func loadSettings() -> Settings { settingsFile.read() ?? Settings() }
    public func saveSettings(_ settings: Settings) { settingsFile.write(settings) }

    public func loadState() -> DayState? { stateFile.read() }
    public func saveState(_ state: DayState) { stateFile.write(state) }
}
