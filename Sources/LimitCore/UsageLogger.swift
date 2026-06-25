import Foundation

/// Append-only log of active-use sessions (start, end, duration) as JSON Lines.
public final class UsageLogger {
    public struct Record: Codable, Equatable {
        public let start: Date
        public let end: Date
        public let durationSeconds: Int
    }

    private let url: URL
    private let encoder: JSONEncoder

    public init(url: URL = AppPaths.usageLog) {
        self.url = url
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    public func append(start: Date, end: Date) {
        let record = Record(start: start, end: end,
                            durationSeconds: max(0, Int(end.timeIntervalSince(start))))
        guard var line = try? encoder.encode(record) else { return }
        line.append(0x0A) // newline
        appendData(line)
    }

    private func appendData(_ data: Data) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}
