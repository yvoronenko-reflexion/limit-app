import SwiftUI
import LimitCore

/// Read-only history of recorded active-use sessions, grouped into per-day totals with an
/// expandable list of the individual sessions for each day. Opened from settings, so it's
/// already behind the parent PIN.
struct UsageLogView: View {
    @ObservedObject var model: AppModel

    @State private var days: [DailyUsage] = []
    @State private var sessions: [UsageLogger.Record] = []

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
                    DayRow(day: day, sessions: sessionsFor(day))
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
        days = model.dailyUsage()
    }

    private func sessionsFor(_ day: DailyUsage) -> [UsageLogger.Record] {
        sessions.filter { boundaryKey($0.start) == day.dayKey }
    }

    private func boundaryKey(_ date: Date) -> String {
        DayBoundary(resetHour: model.settings.resetHour,
                    resetMinute: model.settings.resetMinute).dayKey(for: date)
    }
}

private struct DayRow: View {
    let day: DailyUsage
    let sessions: [UsageLogger.Record]

    var body: some View {
        DisclosureGroup {
            ForEach(sessions) { record in
                HStack {
                    Text("\(Self.time.string(from: record.start))–\(Self.time.string(from: record.end))")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(AppModel.format(seconds: record.durationSeconds))
                        .font(.caption).monospacedDigit()
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

extension UsageLogger.Record: Identifiable {
    public var id: Date { start }
}
