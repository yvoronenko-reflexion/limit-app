import Foundation
import UserNotifications

/// Thin wrapper over UNUserNotificationCenter for immediate local notifications.
/// (Requires a bundled, signed app to actually deliver — works from the .app, not
/// from a bare `swift run` executable.)
public final class NotificationManager {
    private let center = UNUserNotificationCenter.current()

    public init() {}

    public func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Deliver a notification immediately (nil trigger).
    public func notify(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request)
    }
}
