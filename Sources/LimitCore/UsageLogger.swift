import Foundation

/// Append-only log of active-use sessions and parent-granted time extensions as JSON
/// Lines. Session lines have no `kind`; extension lines carry `"kind":"extension"`, so the
/// two are distinguishable and old session-only logs keep decoding unchanged.
public final class UsageLogger {
    public struct Record: Codable, Equatable {
        public let start: Date
        public let end: Date
        public let durationSeconds: Int

        public init(start: Date, end: Date) {
            self.start = start
            self.end = end
            self.durationSeconds = max(0, Int(end.timeIntervalSince(start)))
        }
    }

    /// A parent-granted budget extension (the "+15/+30/+60 min" actions at the lock).
    public struct Extension: Codable, Equatable {
        public let kind: String
        public let at: Date
        public let addedSeconds: Int

        public init(at: Date, addedSeconds: Int) {
            self.kind = "extension"
            self.at = at
            self.addedSeconds = addedSeconds
        }
    }

    /// Used to peek a line's `kind` discriminator before decoding it concretely.
    private struct Kind: Decodable { let kind: String? }

    private let url: URL
    private let encoder: JSONEncoder

    public init(url: URL = AppPaths.usageLog) {
        self.url = url
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    public func append(start: Date, end: Date) {
        write(Record(start: start, end: end))
    }

    public func appendExtension(at: Date, addedSeconds: Int) {
        write(Extension(at: at, addedSeconds: max(0, addedSeconds)))
    }

    private func write<T: Encodable>(_ value: T) {
        guard var line = try? encoder.encode(value) else { return }
        line.append(0x0A) // newline
        appendData(line)
    }

    /// Read every logged session, oldest first. Extension lines and malformed lines are
    /// skipped so a single bad record can't hide the rest of the history.
    public func load() -> [Record] {
        decodeLines().sessions
    }

    /// Read every logged extension, oldest first.
    public func loadExtensions() -> [Extension] {
        decodeLines().extensions
    }

    /// Decode the whole log once into its two record kinds (oldest first).
    private func decodeLines() -> (sessions: [Record], extensions: [Extension]) {
        guard let data = try? Data(contentsOf: url) else { return ([], []) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var sessions: [Record] = []
        var extensions: [Extension] = []
        for line in data.split(separator: 0x0A) {
            let bytes = Data(line)
            if (try? decoder.decode(Kind.self, from: bytes))?.kind == "extension" {
                if let ext = try? decoder.decode(Extension.self, from: bytes) {
                    extensions.append(ext)
                }
            } else if let record = try? decoder.decode(Record.self, from: bytes) {
                sessions.append(record)
            }
        }
        return (sessions, extensions)
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

/// A per-budget-day rollup of usage sessions, suitable for display.
public struct DailyUsage: Identifiable, Equatable {
    public let dayKey: String          // yyyy-MM-dd budget day
    public let totalSeconds: Int
    public let sessionCount: Int
    public var id: String { dayKey }

    public init(dayKey: String, totalSeconds: Int, sessionCount: Int) {
        self.dayKey = dayKey
        self.totalSeconds = totalSeconds
        self.sessionCount = sessionCount
    }
}

public enum UsageSummary {
    /// Group sessions into per-budget-day totals (newest day first). A session is
    /// attributed to the budget day of its start instant, matching how the limit is spent.
    public static func byDay(_ records: [UsageLogger.Record], boundary: DayBoundary) -> [DailyUsage] {
        var totals: [String: (seconds: Int, count: Int)] = [:]
        for record in records {
            let key = boundary.dayKey(for: record.start)
            let current = totals[key] ?? (0, 0)
            totals[key] = (current.seconds + record.durationSeconds, current.count + 1)
        }
        return totals
            .map { DailyUsage(dayKey: $0.key, totalSeconds: $0.value.seconds, sessionCount: $0.value.count) }
            .sorted { $0.dayKey > $1.dayKey }
    }
}
