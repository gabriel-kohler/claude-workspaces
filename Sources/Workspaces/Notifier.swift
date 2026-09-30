import Foundation
import UserNotifications

/// macOS notifications. Only available when running from the .app bundle.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    private var onOpen: (@MainActor (UUID) -> Void)?
    private var available: Bool { Bundle.main.bundleIdentifier != nil }

    func setUp(onOpen: @escaping @MainActor (UUID) -> Void) {
        self.onOpen = onOpen
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func post(title: String, body: String, sessionId: UUID) {
        guard available else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["session": sessionId.uuidString]
        // Same identifier per session: a newer alert replaces the older one.
        let request = UNNotificationRequest(identifier: sessionId.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let raw = response.notification.request.content.userInfo["session"] as? String
        if let raw, let id = UUID(uuidString: raw), let onOpen {
            DispatchQueue.main.async { MainActor.assumeIsolated { onOpen(id) } }
        }
        completionHandler()
    }
}
