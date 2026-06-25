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

    /// Read every logged session, oldest first. Malformed lines are skipped so a single
    /// bad record can't hide the rest of the history.
    public func load() -> [Record] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return data.split(separator: 0x0A).compactMap { line in
            try? decoder.decode(Record.self, from: Data(line))
        }
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
