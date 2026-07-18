import Foundation
import UserNotifications

/// New issues ship weekly on Saturdays and there is no push backend, so a
/// repeating local notification stands in: Saturday 9:00 AM Pacific, generic
/// copy. Tapping it just opens the app; the feed's launch refresh picks up
/// the new issue.
enum NotificationScheduler {
    static let weeklyIdentifier = "weekly-new-issue"

    /// Requests authorization (plain first-launch prompt) and, if granted,
    /// ensures the weekly reminder is scheduled exactly once — pending
    /// requests are checked first so relaunches don't stack duplicates.
    /// Denial or failure is silent.
    static func scheduleWeeklyIssueReminder() async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
            return
        }

        let pending = await center.pendingNotificationRequests()
        guard !pending.contains(where: { $0.identifier == weeklyIdentifier }) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Workspaces"
        content.body = "A new workspace is featured — the latest issue is out now."
        content.sound = .default

        var components = DateComponents()
        components.timeZone = TimeZone(identifier: "America/Los_Angeles")
        components.weekday = 7 // Saturday
        components.hour = 9
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        try? await center.add(UNNotificationRequest(
            identifier: weeklyIdentifier,
            content: content,
            trigger: trigger
        ))
    }
}
