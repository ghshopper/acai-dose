import Foundation
import UserNotifications

/// End-of-day notification: after closing, a notification with each shop's sales, expenses, net and the cash that should be in the drawer.
/// iOS wakes the app in the background (not at an exact minute), so a plain reminder is also set for the chosen time;
/// the real report replaces it as soon as the app gets the numbers.
enum DailyReport {
    private static let d = UserDefaults.standard
    static var enabled: Bool {
        get { d.bool(forKey: "report_on") }
        set { d.set(newValue, forKey: "report_on") }
    }
    /// Minutes after midnight; default 00:30 (Karak Dose closes at 12).
    static var minute: Int {
        get { d.object(forKey: "report_min") as? Int ?? 30 }
        set { d.set(newValue, forKey: "report_min") }
    }
    private static var lastDay: String {
        get { d.string(forKey: "report_last") ?? "" }
        set { d.set(newValue, forKey: "report_last") }
    }
    private static let id = "daily-report"
    private static var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Muscat")!; return c }

    static func ymd(_ date: Date) -> String {
        let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone; f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// The last report time that has passed, and the business day it reports on (a time before 6 am reports on the day before).
    private static func lastMoment(_ now: Date = .now) -> (Date, String) {
        let start = cal.startOfDay(for: now)
        var t = cal.date(byAdding: .minute, value: minute, to: start)!
        if t > now { t = cal.date(byAdding: .day, value: -1, to: t)! }
        let day = minute < 6 * 60 ? cal.date(byAdding: .day, value: -1, to: t)! : t
        return (t, ymd(day))
    }

    /// A plain reminder at the next report time (replaced by the real numbers when the app gets them).
    static func scheduleFallback() {
        let c = UNUserNotificationCenter.current()
        guard enabled else { c.removePendingNotificationRequests(withIdentifiers: [id]); return }
        let content = UNMutableNotificationContent()
        content.title = "تقرير اليوم"
        content.body = "المحل سكّر. افتح التطبيق وشوف المبيعات والمصاريف والصافي."
        content.sound = .default
        var comps = DateComponents(); comps.hour = minute / 60; comps.minute = minute % 60
        c.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }

    /// If the report time has passed and today's report wasn't sent yet: fetch both shops and post it.
    @MainActor
    static func check() async {
        guard enabled else { return }
        let (_, day) = lastMoment()
        guard day != lastDay else { return }
        var lines: [String] = []
        var total = 0.0
        for b in Biz.allCases {
            guard let r = try? await API.shared.get("day_report", ["day": day], biz: b) else { continue }
            total += r["net"].double
            var s = "\(b.name): \(money(r["sales"])) ر.ع (\(r["orders"].int) طلب)"
            if r["expenses"].double > 0 { s += " · مصاريف \(money(r["expenses"]))" }
            s += " · الصافي \(money(r["net"]))"
            s += "\nالمفروض في الدرج \(money(r["cash_expected"]))"
            if let top = r["top"].array.first, !top["name"].string.isEmpty { s += " · الأكثر: \(top["name"].string) ×\(top["qty"].int)" }
            lines.append(s)
        }
        guard !lines.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = "تقرير \(day)"
        content.body = lines.joined(separator: "\n")
        if lines.count > 1 { content.subtitle = "صافي المحلين \(money(total)) ر.ع" }
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        lastDay = day
        scheduleFallback()
    }
}
