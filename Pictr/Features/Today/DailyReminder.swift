import Foundation
import Observation
import UserNotifications

/// Which upcoming days get an On This Day notification. Pure, so it is testable.
enum ReminderPlan {
    struct Entry: Equatable {
        var fireDate: DateComponents
        var photoCount: Int
    }

    /// Days after `today` (tomorrow first) that have photos from earlier years.
    static func entries(from today: Date, days: Int, hour: Int, minute: Int, earliestYear: Int,
                        range: OnThisDayRange = .day, calendar: Calendar = .current,
                        count: ([DateInterval]) -> Int) -> [Entry] {
        let start = calendar.startOfDay(for: today)
        return (1...max(days, 1)).compactMap { offset -> Entry? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let windows = OnThisDay.windows(on: date, earliestYear: earliestYear, range: range, calendar: calendar)
            guard !windows.isEmpty else { return nil }
            let photos = count(windows)
            guard photos > 0 else { return nil }
            var fire = calendar.dateComponents([.year, .month, .day], from: date)
            fire.hour = hour
            fire.minute = minute
            return Entry(fireDate: fire, photoCount: photos)
        }
    }

    static func body(photoCount: Int, range: OnThisDayRange = .day) -> String {
        photoCount == 1
            ? "1 photo from \(range.phrase) in past years is waiting."
            : "\(photoCount) photos from \(range.phrase) in past years are waiting."
    }
}

/// Opt-in daily On This Day notification. Local only; schedules two weeks ahead
/// with real counts and skips days with nothing to show.
@MainActor
@Observable
final class DailyReminder {
    private static let enabledKey = "dailyReminder.enabled"
    private static let minutesKey = "dailyReminder.minutes"
    private static let idPrefix = "onthisday-"
    private static let horizon = 14

    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }
    /// Minutes after midnight.
    var minutes: Int {
        didSet { UserDefaults.standard.set(minutes, forKey: Self.minutesKey) }
    }
    private(set) var isDenied = false
    private(set) var scheduledCount = 0

    init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        minutes = defaults.object(forKey: Self.minutesKey) as? Int ?? 9 * 60
    }

    /// Asks for permission the first time; turns itself back off if refused.
    func enable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        isDenied = !granted
        isEnabled = granted
        return granted
    }

    func refreshPermission() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        isDenied = status == .denied
        if isDenied { isEnabled = false }
    }

    func reschedule(client: any PhotoLibraryClient, decided: Set<String>) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) })
        scheduledCount = 0
        guard isEnabled else { return }

        let hour = minutes / 60, minute = minutes % 60, horizon = Self.horizon
        let range = Prefs.onThisDayRange
        let entries = await Task.detached(priority: .utility) { () -> [ReminderPlan.Entry] in
            guard let earliest = client.earliestAssetDate() else { return [] }
            return ReminderPlan.entries(from: .now, days: horizon, hour: hour, minute: minute,
                                        earliestYear: Calendar.current.component(.year, from: earliest),
                                        range: range) { windows in
                client.reviewItems(in: windows).filter { !decided.contains($0.id) }.count
            }
        }.value

        for entry in entries {
            let content = UNMutableNotificationContent()
            content.title = "On this day"
            content.body = ReminderPlan.body(photoCount: entry.photoCount, range: range)
            content.sound = .default
            content.threadIdentifier = "onthisday"
            let trigger = UNCalendarNotificationTrigger(dateMatching: entry.fireDate, repeats: false)
            let id = Self.idPrefix + [entry.fireDate.year, entry.fireDate.month, entry.fireDate.day]
                .map { String($0 ?? 0) }.joined(separator: "-")
            if (try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))) != nil {
                scheduledCount += 1
            }
        }
    }
}
