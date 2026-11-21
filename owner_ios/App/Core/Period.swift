import SwiftUI

/// The date range the summary, orders and expenses tabs show. Shared by the tabs.
@Observable
final class Period {
    var key = "today"
    var from: Date = .now
    var to: Date = .now
    /// Bumped on every change so screens can reload with .task(id:)
    var version = 0

    static let options: [(String, String)] = [("today", "اليوم"), ("yest", "أمس"), ("week", "٧ أيام"), ("month", "هذا الشهر"), ("last", "الشهر الماضي")]

    init() { set("today") }

    var fromStr: String { ymd(from) }
    var toStr: String { ymd(to) }

    func set(_ k: String) {
        let cal = muscat
        let today = cal.startOfDay(for: .now)
        key = k
        switch k {
        case "yest":
            from = cal.date(byAdding: .day, value: -1, to: today)!; to = from
        case "week":
            to = today; from = cal.date(byAdding: .day, value: -6, to: today)!
        case "month":
            to = today; from = cal.date(from: cal.dateComponents([.year, .month], from: today))!
        case "last":
            let firstThis = cal.date(from: cal.dateComponents([.year, .month], from: today))!
            from = cal.date(byAdding: .month, value: -1, to: firstThis)!
            to = cal.date(byAdding: .day, value: -1, to: firstThis)!
        default:
            key = "today"; from = today; to = today
        }
        version += 1
    }

    func custom(_ a: Date, _ b: Date) {
        let cal = muscat
        let x = cal.startOfDay(for: min(a, b)), y = cal.startOfDay(for: max(a, b))
        key = "custom"; from = x; to = y
        version += 1
    }

    var days: [Date] {
        var out: [Date] = []
        var d = from
        while d <= to { out.append(d); d = muscat.date(byAdding: .day, value: 1, to: d)! }
        return out
    }

    /// The same dates one month back, to compare with: today against the same day last month,
    /// this month so far against the same days of last month, last month against the month before.
    var previous: (Date, Date, [Date]) {
        let cal = muscat
        func back(_ d: Date) -> Date { cal.date(byAdding: .month, value: -1, to: d)! }   // 31 Mar → 28/29 Feb
        var pFrom = back(from), pTo = back(to)
        if key == "last" {   // a whole month: the whole month before it
            pFrom = back(from)
            pTo = cal.date(byAdding: .day, value: -1, to: from)!
        }
        var list: [Date] = []
        var d = pFrom
        while d <= pTo { list.append(d); d = cal.date(byAdding: .day, value: 1, to: d)! }
        return (pFrom, pTo, list)
    }

    /// "18 أكتوبر" or "1–18 أكتوبر": the dates compared with.
    var previousText: String {
        let (a, b, _) = previous
        let f = DateFormatter(); f.locale = Locale(identifier: "ar_OM"); f.timeZone = muscat.timeZone
        f.dateFormat = "d MMMM"
        if muscat.isDate(a, inSameDayAs: b) { return f.string(from: a) }
        let dOnly = DateFormatter(); dOnly.locale = f.locale; dOnly.timeZone = f.timeZone; dOnly.dateFormat = "d"
        return "\(dOnly.string(from: a))–\(f.string(from: b))"
    }

    var label: String {
        if key == "custom" { return "\(fromStr.suffix(5)) ← \(toStr.suffix(5))" }
        return Period.options.first { $0.0 == key }?.1 ?? ""
    }

    var vsText: String {
        switch key {
        case "today": return "نفس اليوم الشهر الماضي"
        case "yest": return "نفس اليوم الشهر الماضي"
        case "month": return "نفس الأيام الشهر الماضي"
        case "last": return "الشهر اللي قبله"
        default: return "نفس الفترة الشهر الماضي"
        }
    }
}

/// Capsules for the period, plus a custom range.
struct PeriodBar: View {
    @Environment(Period.self) private var period
    @State private var picking = false
    @State private var a = Date.now
    @State private var b = Date.now

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Period.options.map { $0.0 }, id: \.self) { k in
                    capsule(Period.options.first { $0.0 == k }?.1 ?? k, on: period.key == k) { period.set(k) }
                }
                capsule(period.key == "custom" ? period.label : "تاريخ", on: period.key == "custom", icon: "calendar") {
                    a = period.from; b = period.to; picking = true
                }
            }
            .padding(.horizontal, 16)
        }
        .sheet(isPresented: $picking) {
            NavigationStack {
                Form {
                    DatePicker("من", selection: $a, in: ...Date.now, displayedComponents: .date)
                    DatePicker("إلى", selection: $b, in: ...Date.now, displayedComponents: .date)
                }
                .navigationTitle("فترة مخصصة")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { picking = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("تم") { period.custom(a, b); picking = false } }
                }
            }
            .presentationDetents([.medium])
        }
    }

    private func capsule(_ t: String, on: Bool, icon: String? = nil, _ action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap(); withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { action() }
        } label: {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.footnote) }
                Text(t).font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .foregroundStyle(on ? Color.heroFG : Color.ink)
            .frame(minHeight: 44)
            .background(on ? Color.heroBG : Color.cardBG, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(Pressable())
    }
}
