import SwiftUI

@main
struct LimitMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            // A little weather glyph next to the countdown so the menu bar reads as
            // playful, and hints at how much time is left at a glance.
            let mood = TimeMood.make(remaining: model.remainingSeconds,
                                     limit: model.settings.dailyLimitSeconds)
            Image(systemName: mood.symbol)
            Text(model.menuBarTitle)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.flush()
    }
}
