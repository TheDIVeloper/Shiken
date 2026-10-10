import Foundation
import UserNotifications

/// Opt-in, quiet reminders that a subject has revision planned.
///
/// Deliberately minimal, for reasons that are the same reasons the backlog has
/// no total:
///
/// - Off by default. A reminder you did not ask for is an interruption.
/// - One notification per day at most, not one per subject. Four subjects means
///   four badges, and four badges is a nag.
/// - Wording states a fact, never a verdict. "Chemistry: 60m planned" is
///   information. "You are behind on Chemistry" is pressure, and pressure makes
///   people delete the app.
/// - Nothing is scheduled for a past assessment or an unopened plan.
@Observable
final class ReminderScheduler {
    private enum Keys {
        static let enabled = "remindersEnabled"
        static let hour = "remindersHour"
        static let minute = "remindersMinute"
        static let lastNotifiedDay = "remindersLastNotifiedDay"
    }

    /// Summary for the day's plan, if there is one worth mentioning.
    struct Summary: Equatable, Sendable {
        let subjectName: String
        let minutes: Int
    }

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.enabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.enabled) }
    }

    var time: Date {
        get {
            let stored = UserDefaults.standard.double(forKey: Keys.hour)
            guard stored > 0 else { return Self.defaultTime }
            var components = DateComponents()
            components.hour = Int(stored)
            components.minute = Int(UserDefaults.standard.double(forKey: Keys.minute))
            return Calendar.current.date(from: components) ?? Self.defaultTime
        }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            UserDefaults.standard.set(Double(components.hour ?? 17), forKey: Keys.hour)
            UserDefaults.standard.set(Double(components.minute ?? 0), forKey: Keys.minute)
        }
    }

    static let defaultTime: Date = {
        var components = DateComponents()
        components.hour = 17
        components.minute = 0
        return Calendar.current.date(from: components) ?? .now
    }()

    private let center = UNUserNotificationCenter.current()

    /// Asks for permission. Returns whether the user granted it, so Settings can
    /// reflect reality rather than optimism.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Schedules one notification for the next occurrence of the chosen time.
    ///
    /// The trigger repeats daily, so there is no need to re-schedule tomorrow.
    /// The body is filled in at the moment of scheduling, which means it reflects
    /// the plan as it stands now — accurate enough for a nudge, and cheap.
    func schedule(for summary: Summary?) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyID])
        guard isEnabled, let summary, summary.minutes > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(summary.subjectName): \(summary.minutes)m planned"
        content.body = "Your plan for today."
        content.sound = nil

        let fire = Calendar.current.dateComponents(
            [.hour, .minute], from: time
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: fire, repeats: true)
        let request = UNNotificationRequest(
            identifier: Self.dailyID, content: content, trigger: trigger
        )
        center.add(request)
    }

    func cancelAll() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.dailyID])
    }

    /// The subject leading today's plan, if any. One message, never a list.
    static func summary(from overview: Overview) -> Summary? {
        guard let today = overview.today else { return nil }
        let planned = today.subjects
            .filter { !$0.isSyntheticOnly }
            .max { $0.totalMinutes < $1.totalMinutes }
        guard let planned, planned.totalMinutes > 0 else { return nil }
        return Summary(subjectName: planned.name, minutes: planned.totalMinutes)
    }

    private static let dailyID = "shiken.dailyPlan"
}

extension PlannedSubject {
    /// A subject whose rows are all stand-ins is not a real plan worth notifying
    /// about, so it is skipped.
    var isSyntheticOnly: Bool {
        !entries.isEmpty && entries.allSatisfy(\.isSynthetic)
    }
}