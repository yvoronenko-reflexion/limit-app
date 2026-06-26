import Foundation

/// Tiny Codable-on-disk helper with atomic writes.
public struct JSONFile<T: Codable> {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func read() -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    public func write(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Remove the file, so a subsequent `read()` returns nil.
    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
