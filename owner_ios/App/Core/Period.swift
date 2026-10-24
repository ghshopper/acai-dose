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

    /// The same number of days just before, to compare with.
    var previous: (Date, Date, [Date]) {
        let n = days.count
        let pFrom = muscat.date(byAdding: .day, value: -n, to: from)!
        let pTo = muscat.date(byAdding: .day, value: -1, to: from)!
        let list = (0..<n).map { muscat.date(byAdding: .day, value: $0, to: pFrom)! }
        return (pFrom, pTo, list)
    }

    var label: String {
        if key == "custom" { return "\(fromStr.suffix(5)) ← \(toStr.suffix(5))" }
        return Period.options.first { $0.0 == key }?.1 ?? ""
    }

    var vsText: String {
        switch key {
        case "today": return "مقارنة بأمس"
        case "yest": return "مقارنة باليوم اللي قبله"
        case "month": return "مقارنة بنفس عدد الأيام قبلها"
        default: return "مقارنة بالفترة اللي قبلها"
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
            Haptics.tap(); action()
        } label: {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.footnote) }
                Text(t).font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .foregroundStyle(on ? Color.white : Color.primary)
            .background(on ? Color.brand : Color.cardBG, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
