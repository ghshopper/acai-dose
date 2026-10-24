import SwiftUI
import Charts

struct SummaryView: View {
    @Environment(Period.self) private var period
    @Environment(Toaster.self) private var toaster
    @State private var s: Stats?
    @State private var prev: Stats?
    @State private var err: String?
    @State private var loading = false
    @State private var sheet: QuickSheet?

    enum QuickSheet: String, Identifiable { case expense, sale, customer; var id: String { rawValue } }

    private var greeting: String {
        let h = muscat.component(.hour, from: .now)
        return h < 12 ? "صباح الخير" : "مساء الخير"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(greeting).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 20)
                PeriodBar().padding(.bottom, 4)
                Group {
                    if let s {
                        hero(s)
                        quick
                        grid(s)
                        SectionHeader(title: "طرق الدفع والحسابات", note: "المفروض يوصلك = المبيعات − العمولة")
                        payments(s)
                        if s.daily.count > 1 {
                            SectionHeader(title: "المبيعات اليومية", note: "\(money(s.sales)) ر.ع")
                            chart(s)
                        }
                        SectionHeader(title: "الأكثر طلباً", note: BizStore.shared.current == .karak ? "العدد" : "عدد الأكواب")
                        products(s)
                    } else if let err {
                        EmptyNote(text: err, icon: "wifi.exclamationmark")
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(60)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 30)
        }
        .background(Color.pageBG)
        .navigationTitle("الملخص")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if loading { ProgressView() } else { BizSwitcher() }
            }
        }
        .refreshable { await load() }
        .task(id: period.version) { await load() }
        .sheet(item: $sheet) { which in
            switch which {
            case .expense: AddExpenseSheet { done("انحفظ المصروف") }
            case .sale: AppSaleSheet { done("انحفظت المبيعات") }
            case .customer: AddCustomerSheet { done("انضاف العميل") }
            }
        }
    }

    private func done(_ msg: String) { toaster.show(msg); Task { await load() } }

    private func load() async {
        loading = true
        defer { loading = false }
        let (pFrom, pTo, pDays) = period.previous
        let days = period.days
        do {
            async let a = API.shared.get("range", ["from": period.fromStr, "to": period.toStr])
            async let b = API.shared.get("range", ["from": ymd(pFrom), "to": ymd(pTo)])
            let (r1, r2) = try await (a, b)
            BizStore.shared.absorb(r1)
            s = Stats(r1, days: days)
            prev = Stats(r2, days: pDays)
            err = nil
        } catch {
            err = errText(error)
        }
    }

    // MARK: pieces

    private func hero(_ s: Stats) -> some View {
        let total = max(s.sales, 0.0001)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("صافي الربح").font(.headline).foregroundStyle(Color.lilac)
                Spacer()
                if let prev { DeltaBadge(now: s.net, before: prev.net, onDark: true) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(money(s.net)).font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(s.net < 0 ? Color(red: 1, green: 0.7, blue: 0.7) : Color.cream)
                Text("ر.ع").font(.headline).foregroundStyle(Color.lilac)
            }
            GeometryReader { g in
                HStack(spacing: 0) {
                    if s.sales <= 0 { Rectangle().fill(Color.brand2) } else {
                        Rectangle().fill(Color.cream).frame(width: g.size.width * max(0, s.net) / total)
                        Rectangle().fill(Color.accent2).frame(width: g.size.width * s.comm / total)
                        Rectangle().fill(Color(red: 0.78, green: 0.42, blue: 0.54)).frame(width: g.size.width * min(s.exp, total) / total)
                        Spacer(minLength: 0)
                    }
                }
                .background(Color.brand2)
            }
            .frame(height: 12).clipShape(Capsule())
            HStack(spacing: 14) {
                legend(.cream, "الصافي")
                legend(.accent2, "العمولات \(money(s.comm))")
                legend(Color(red: 0.78, green: 0.42, blue: 0.54), "المصاريف \(money(s.exp))")
            }
            if let prev {
                Text("\(period.vsText): \(money(prev.net))").font(.caption.weight(.semibold)).foregroundStyle(Color.lilac)
            }
        }
        .padding(20)
        .background(LinearGradient(colors: [.brand, .brand2], startPoint: .topTrailing, endPoint: .bottomLeading),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 10, height: 10)
            Text(t).font(.caption.weight(.semibold)).foregroundStyle(Color.cream)
        }
    }

    private var quick: some View {
        HStack(spacing: 10) {
            quickBtn("plus.circle.fill", "مصروف") { sheet = .expense }
            quickBtn("bag.fill", "مبيعات تطبيق") { sheet = .sale }
            quickBtn("person.badge.plus", "عميل جديد") { sheet = .customer }
        }
    }

    private func quickBtn(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title3).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Color.brand, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(label).font(.footnote.weight(.semibold)).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(Color.cardBG, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func grid(_ s: Stats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            stat("chart.bar.fill", "إجمالي المبيعات", s.sales, "\(s.orderCount) طلب · متوسط \(money(s.avg))", before: prev?.sales)
            stat("creditcard.fill", "المصاريف", s.exp, "\(s.expCount) مصروف", before: prev?.exp, lowerIsBetter: true)
            let unit = BizStore.shared.current == .karak ? "صنف" : "كوب"
            stat("globe", "الموقع", s.site, "\(s.siteOrders) طلب · \(s.siteCups) \(unit)", share: s.pct(s.site))
            stat("house.fill", "المحل", s.shop, "\(s.shopOrders) عملية · \(s.shopCups) \(unit)", share: s.pct(s.shop))
            stat("bag.fill", "التطبيقات", s.appGross, kChannels.map(\.1).joined(separator: " و"), share: s.pct(s.appGross))
            stat("percent", "العمولات", s.comm, "تخصمها التطبيقات")
        }
    }

    private func stat(_ icon: String, _ label: String, _ v: Double, _ sub: String, share: Int? = nil, before: Double? = nil, lowerIsBetter: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption).foregroundStyle(Color.ink)
                Text(label).font(.footnote.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                if let before { DeltaBadge(now: v, before: before, lowerIsBetter: lowerIsBetter) }
            }
            Text(money(v)).font(.title2.bold()).monospacedDigit().foregroundStyle(Color.ink)
            Text(share == nil ? sub : "\(sub) · \(share!)%").font(.caption2.weight(.medium)).foregroundStyle(.secondary).lineLimit(2)
            if let share { ThinBar(value: Double(share) / 100) }
        }
        .card(14)
    }

    private func payments(_ s: Stats) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(s.methods) { m in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(m.name).font(.headline)
                        Spacer()
                        Tag(text: m.isApp ? "تحويل" : "بالدرج", bg: m.isApp ? Color.accent2.opacity(0.18) : Color.ink.opacity(0.14))
                    }
                    Text(money(m.net)).font(.title2.bold()).monospacedDigit().foregroundStyle(Color.ink)
                    row("المبيعات", money(m.gross))
                    if m.isApp { row("العمولة", money(m.comm)) }
                    row("الطلبات", "\(m.n)")
                }
                .card(14)
            }
            if s.unpaidCount > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("طلبات موقع غير مستلمة").font(.subheadline.weight(.semibold))
                    Text(money(s.unpaidTotal)).font(.title2.bold()).monospacedDigit().foregroundStyle(Color.ink)
                    row("الطلبات", "\(s.unpaidCount)")
                }
                .card(14)
            }
        }
    }

    private func row(_ a: String, _ b: String) -> some View {
        HStack {
            Text(a).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(b).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func chart(_ s: Stats) -> some View {
        let today = muscat.startOfDay(for: .now)
        return Chart(s.daily) { d in
            BarMark(x: .value("اليوم", d.id, unit: .day), y: .value("المبيعات", d.v))
                .foregroundStyle(muscat.isDate(d.id, inSameDayAs: today) ? Color.accent2 : Color.ink)
                .cornerRadius(5)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: max(1, s.daily.count / 7))) { _ in
                AxisValueLabel(format: .dateTime.day(), centered: true)
            }
        }
        .frame(height: 190)
        .card()
    }

    private func products(_ s: Stats) -> some View {
        Group {
            if s.products.isEmpty {
                EmptyNote(text: "ما فيه طلبات في هالفترة", icon: "cup.and.saucer")
            } else {
                let top = Double(max(s.products.first?.n ?? 1, 1))
                VStack(spacing: 12) {
                    ForEach(s.products) { p in
                        HStack(spacing: 10) {
                            Text(p.id).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                            ThinBar(value: Double(p.n) / top, color: .ink, height: 10).frame(width: 120)
                            Text("\(p.n)").font(.subheadline.bold()).monospacedDigit().frame(width: 36, alignment: .trailing)
                        }
                    }
                }
                .card()
            }
        }
    }
}
