import SwiftUI
import LimitCore

/// Read-only history of recorded active-use sessions, grouped into per-day totals with an
/// expandable list of the individual sessions for each day. Opened from settings, so it's
/// already behind the parent PIN.
struct UsageLogView: View {
    @ObservedObject var model: AppModel

    @State private var days: [DailyUsage] = []
    @State private var sessions: [UsageLogger.Record] = []
    @State private var extensions: [UsageLogger.Extension] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Usage history", systemImage: "chart.bar.fill")
                    .font(.headline)
                Spacer()
                Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Refresh")
            }

            if days.isEmpty {
                Spacer()
                Text("No usage recorded yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                List(days) { day in
                    DayRow(day: day, entries: entriesFor(day))
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
        .frame(width: 460, height: 520)
        .onAppear(perform: reload)
    }

    private func reload() {
        sessions = model.usageSessions()
        extensions = model.usageExtensions()
        days = model.dailyUsage()
    }

    /// Sessions and extensions for a budget day, interleaved newest-first.
    private func entriesFor(_ day: DailyUsage) -> [DayEntry] {
        let s = sessions
            .filter { boundaryKey($0.start) == day.dayKey }
            .map(DayEntry.session)
        let e = extensions
            .filter { boundaryKey($0.at) == day.dayKey }
            .map(DayEntry.extension)
        return (s + e).sorted { $0.date > $1.date }
    }

    private func boundaryKey(_ date: Date) -> String {
        DayBoundary(resetHour: model.settings.resetHour,
                    resetMinute: model.settings.resetMinute).dayKey(for: date)
    }
}

/// One row in the usage list: a session (start–end + duration) or a parent-granted
/// extension. Both carry a timestamp so the day's entries can be sorted together.
enum DayEntry: Identifiable {
    case session(UsageLogger.Record)
    case `extension`(UsageLogger.Extension)

    var date: Date {
        switch self {
        case .session(let r): return r.start
        case .extension(let e): return e.at
        }
    }

    var id: String {
        switch self {
        case .session(let r): return "s-\(r.start.timeIntervalSince1970)"
        case .extension(let e): return "x-\(e.at.timeIntervalSince1970)"
        }
    }
}

private struct DayRow: View {
    let day: DailyUsage
    let entries: [DayEntry]

    var body: some View {
        DisclosureGroup {
            ForEach(entries) { entry in
                switch entry {
                case .session(let record):
                    HStack {
                        Text("\(Self.time.string(from: record.start))–\(Self.time.string(from: record.end))")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(AppModel.format(seconds: record.durationSeconds))
                            .font(.caption).monospacedDigit()
                    }
                case .extension(let ext):
                    HStack {
                        Label(Self.time.string(from: ext.at), systemImage: "plus.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                        Spacer()
                        Text("+\(ext.addedSeconds / 60) min")
                            .font(.caption.weight(.medium)).monospacedDigit()
                            .foregroundStyle(.green)
                    }
                }
            }
        } label: {
            HStack {
                Text(Self.dayLabel(day.dayKey))
                    .font(.body.weight(.medium))
                Spacer()
                Text("\(day.totalSeconds / 60) min")
                    .monospacedDigit()
                Text("· \(day.sessionCount) session\(day.sessionCount == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static func dayLabel(_ key: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: key) else { return key }
        let out = DateFormatter()
        out.dateStyle = .full
        out.timeStyle = .none
        return out.string(from: date)
    }
}
