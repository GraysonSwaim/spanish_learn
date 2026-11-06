import Foundation
import SwiftData
@preconcurrency import UserNotifications

/// The daily reminder of what's waiting (Ajustes › Recordatorio diario). A repeating notification can't say how many, so
/// each of the next days gets its own, counted from the schedule as it stands. They're written again when the app opens or
/// closes. A day with nothing waiting has none, and after a week away it stops.
enum Reminder {
    static let defaultMinutes = 20 * 60
    private static let days = 7
    private static let ids = (0..<days).map { "reminder-\($0)" }

    /// The next `days` times the reminder comes, with how many cards will be waiting if nothing is studied before then.
    static func plan(_ cards: [Card], minutes: Int, now: Date = .now) -> [(date: Date, count: Int)] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        return (0...days)
            .compactMap { cal.date(byAdding: .day, value: $0, to: today) }
            .compactMap { cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: $0) }
            .filter { $0 > now }
            .prefix(days)
            .map { ($0, Scheduler.counts(cards, now: $0).due) }
            .filter { $0.1 > 0 }
    }

    /// Asks iOS for permission, the first time. Whether it's allowed.
    static func ask() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Replaces what's scheduled with what the library says now.
    static func refresh(_ ctx: ModelContext) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        let d = UserDefaults.standard
        guard d.bool(forKey: PrefKey.reminder) else { return }
        let minutes = d.object(forKey: PrefKey.reminderMinutes) == nil ? defaultMinutes : d.integer(forKey: PrefKey.reminderMinutes)
        for (id, reminder) in zip(ids, plan(Deck.allCards(ctx), minutes: minutes)) {
            let content = UNMutableNotificationContent()
            content.body = reminder.count == 1 ? "1 tarjeta para repasar" : "\(reminder.count) tarjetas para repasar"
            content.sound = .default
            let when = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }
}
