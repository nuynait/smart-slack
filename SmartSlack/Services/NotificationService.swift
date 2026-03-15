import Foundation
import UserNotifications
import AppKit

@MainActor
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var permissionGranted = false
    @Published var forcePopupScheduleId: UUID?
    @Published var selectedScheduleIdFromNotification: UUID?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        Task { await checkPermission() }
    }

    // MARK: - Permission

    func checkPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permissionGranted = settings.authorizationStatus == .authorized
    }

    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            permissionGranted = granted
        } catch {
            permissionGranted = false
        }
    }

    func openSystemPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Notify

    func notifySessionReady(schedule: Schedule, session: Session) {
        switch schedule.notificationMode {
        case .macosNotification:
            sendMacOSNotification(schedule: schedule, session: session)
        case .forcePopup:
            NSSound(named: "Glass")?.play()
            forcePopupScheduleId = schedule.id
        case .quiet:
            break
        }
    }

    // MARK: - macOS Notification

    private func sendMacOSNotification(schedule: Schedule, session: Session) {
        let content = UNMutableNotificationContent()
        content.title = schedule.name
        if let summary = session.summary {
            content.body = String(summary.prefix(200))
        } else {
            content.body = "New draft ready for review"
        }
        content.sound = .default
        content.userInfo = ["scheduleId": schedule.id.uuidString]

        let request = UNNotificationRequest(
            identifier: "session-\(session.sessionId.uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let idString = userInfo["scheduleId"] as? String,
           let scheduleId = UUID(uuidString: idString) {
            Task { @MainActor in
                selectedScheduleIdFromNotification = scheduleId
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
