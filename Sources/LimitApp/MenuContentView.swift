import SwiftUI
import AppKit

struct MenuContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    private var mood: TimeMood {
        .make(remaining: model.remainingSeconds, limit: model.settings.dailyLimitSeconds)
    }

    var body: some View {
        VStack(spacing: 12) {
            BudgetRing(remaining: model.remainingSeconds, limit: model.settings.dailyLimitSeconds)
                .padding(.top, 4)

            Text(mood.blurb)
                .font(.headline)
                .foregroundStyle(mood.color)

            HStack(spacing: 6) {
                Image(systemName: model.isActive ? "play.circle.fill" : "pause.circle.fill")
                    .foregroundStyle(model.isActive ? Color.green : .secondary)
                Text(model.isActive ? "Counting · \(model.statusText)" : "Paused · \(model.statusText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                ProgressView(value: Double(model.usedSeconds),
                             total: Double(max(1, model.settings.dailyLimitSeconds)))
                    .tint(mood.color)
                Text("Used \(minutes(model.usedSeconds)) of \(minutes(model.settings.dailyLimitSeconds)) today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button { showSettings() } label: {
                Label("Settings…", systemImage: "gearshape.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .keyboardShortcut(",", modifiers: .command)

            Button { NSApp.terminate(nil) } label: {
                Label("Quit Limit", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(width: 264)
    }

    private func minutes(_ seconds: Int) -> String {
        "\(max(0, seconds) / 60) min"
    }

    private func showSettings() {
        // A menu-bar (.accessory) app isn't active, so the Settings window can
        // open behind everything else — activate first, then open. Using the
        // SwiftUI openSettings action is reliable here; poking the responder
        // chain via showSettingsWindow: silently does nothing once the menu-bar
        // popover has closed.
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }
}
