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

/// A run of active use, formed by merging sessions separated by only a small gap. Spans
/// from the first sub-session's start to the last's end; `idleSeconds` is the total of the
/// (sub-threshold) gaps swallowed inside it.
public struct UsageBlock: Equatable {
    public var start: Date
    public var end: Date
    public var idleSeconds: Int

    public init(start: Date, end: Date, idleSeconds: Int) {
        self.start = start
        self.end = end
        self.idleSeconds = idleSeconds
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

    /// Merge sessions (oldest first) into blocks, collapsing any gap `<= mergeGap` into the
    /// preceding block and accumulating it as idle time. Overlapping/zero-length records are
    /// folded in too. Empty/degenerate records are dropped.
    public static func blocks(_ records: [UsageLogger.Record], mergeGap: TimeInterval) -> [UsageBlock] {
        let sorted = records.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        var result: [UsageBlock] = []
        for r in sorted {
            guard var last = result.last else {
                result.append(UsageBlock(start: r.start, end: r.end, idleSeconds: 0))
                continue
            }
            let gap = r.start.timeIntervalSince(last.end)
            if gap <= mergeGap {
                last.end = max(last.end, r.end)
                if gap > 0 { last.idleSeconds += Int(gap.rounded()) }
                result[result.count - 1] = last
            } else {
                result.append(UsageBlock(start: r.start, end: r.end, idleSeconds: 0))
            }
        }
        return result
    }

    /// A compact, human-readable usage summary suitable for an iMessage body, e.g.
    ///
    ///     Usage:
    ///     10:00 -- 10:20 (with 5 minute idle time)
    ///     11:00 -- 13:00 (with 30 minute idle time)
    ///     14:30 -- 14:45
    ///
    /// A log made of many tiny bursts would print one line each, so the merge gap is widened
    /// (along a fixed ladder) until the block count fits `maxLines` — short logs stay
    /// detailed, long ones compress, and the largest gap always collapses everything.
    public static func brief(_ records: [UsageLogger.Record],
                             maxLines: Int = 12,
                             timeZone: TimeZone = .current) -> String {
        let sorted = records.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return "Usage: none" }

        let ladder: [TimeInterval] = [60, 120, 300, 600, 900, 1800, 3600, 7200, 14400, 86400]
        var chosen = blocks(sorted, mergeGap: ladder.last!)
        for gap in ladder {
            chosen = blocks(sorted, mergeGap: gap)
            if chosen.count <= maxLines { break }
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm"
        fmt.timeZone = timeZone
        fmt.locale = Locale(identifier: "en_US_POSIX")

        var lines = ["Usage:"]
        for block in chosen {
            var line = "\(fmt.string(from: block.start)) -- \(fmt.string(from: block.end))"
            let idleMinutes = (block.idleSeconds + 30) / 60
            if idleMinutes >= 1 { line += " (with \(idleMinutes) minute idle time)" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
