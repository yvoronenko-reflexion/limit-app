import SwiftUI
import AppKit

struct MenuContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.remainingSeconds > 0 ? "Time left today" : "No time left today")
                .font(.headline)

            Text(AppModel.format(seconds: model.remainingSeconds))
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)

            HStack(spacing: 6) {
                Circle()
                    .fill(model.isActive ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(model.isActive ? "Counting · \(model.statusText)" : "Paused · \(model.statusText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Used \(minutes(model.usedSeconds)) of \(minutes(model.settings.dailyLimitSeconds)) today")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button("Settings…") { openSettings() }
                .keyboardShortcut(",", modifiers: .command)
            Button("Quit Limit") { NSApp.terminate(nil) }
        }
        .padding(14)
        .frame(width: 250)
    }

    private var tint: Color {
        switch model.remainingSeconds {
        case ..<0: return .red
        case 0...60: return .red
        case 61...300: return .orange
        default: return .primary
        }
    }

    private func minutes(_ seconds: Int) -> String {
        "\(max(0, seconds) / 60) min"
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        if #available(macOS 14, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
