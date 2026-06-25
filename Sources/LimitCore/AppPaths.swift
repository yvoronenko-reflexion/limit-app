import Foundation

/// Filesystem locations for persisted data, under
/// ~/Library/Application Support/limit-app/.
public enum AppPaths {
    public static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("limit-app", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var settingsFile: URL { supportDir.appendingPathComponent("settings.json") }
    public static var stateFile: URL { supportDir.appendingPathComponent("state.json") }
    public static var usageLog: URL { supportDir.appendingPathComponent("usage.jsonl") }
}
