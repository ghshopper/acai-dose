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
            VStack(alignment: .leading, spacing: 14) {
                header.padding(.horizontal, 16)
                PeriodBar()
                Group {
                    if let s {
                        hero(s)
                        compare(s)
                        payments(s)
                        quick
                        if s.daily.count > 1 { chart(s) }
                        products(s)
                    } else if let err {
                        EmptyNote(text: err, icon: "wifi.exclamationmark")
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(60)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 24)
        }
        .background(Color.pageBG.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
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

    /// Logo, greeting and the shop picker, as on the new design.
    private var header: some View {
        HStack(spacing: 12) {
            Image(BizStore.shared.current == .karak ? "karak-white" : "logo-cream")
                .resizable().scaledToFit().frame(width: 34, height: 34)
                .frame(width: 50, height: 50)
                .background(Color.barBG, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                BizMenu()
            }
            Spacer()
            if loading { ProgressView().frame(width: 48, height: 48) }
            NavigationLink { BusinessView() } label: {
                Image(systemName: "chart.pie.fill").font(.title3)
                    .foregroundStyle(Color.ink)
                    .frame(width: 48, height: 48)
                    .background(Color.cardBG, in: Circle())
            }
            .accessibilityLabel("البزنس")
        }
        .padding(.top, 8)
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

    /// Net profit on the brand colour, with sales, orders and expenses under it.
    private func hero(_ s: Stats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("صافي الربح · \(period.label)").font(.subheadline.weight(.semibold)).opacity(0.8)
                Spacer()
                if let prev { pill(now: s.net, before: prev.net) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(money(s.net)).font(.system(size: 42, weight: .heavy, design: .rounded)).monospacedDigit()
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text("ر.ع").font(.headline).opacity(0.8)
            }
            HStack(spacing: 8) {
                mini("المبيعات", money(s.sales))
                mini("الطلبات", "\(s.orderCount)")
                mini("المصاريف", money(s.exp))
            }
            .padding(.top, 6)
            if s.comm > 0 {
                Text("بعد خصم عمولة التطبيقات \(money(s.comm)) ر.ع").font(.caption.weight(.semibold)).opacity(0.75)
            }
        }
        .foregroundStyle(Color.heroFG)
        .padding(20)
        .background {
            ZStack(alignment: .topLeading) {
                Color.heroBG
                Circle().fill(Color.heroBG2).frame(width: 190, height: 190).offset(x: -60, y: -70)
            }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
    }

    private func mini(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.semibold)).opacity(0.75)
            Text(value).font(.subheadline.weight(.heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.heroFG.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// "▲ 12%" on the hero colour.
    private func pill(now: Double, before: Double) -> some View {
        Group {
            if before > 0 || now > 0 {
                let pct = before <= 0 ? 100 : (now - before) / abs(before) * 100
                Text("\(pct >= 0 ? "▲" : "▼") \(Int(abs(pct).rounded()))%")
                    .font(.caption.bold()).monospacedDigit()
                    .environment(\.layoutDirection, .leftToRight)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .foregroundStyle(Color.popFG)
                    .background(Color.pop, in: Capsule())
            }
        }
    }

    /// This period against the same dates last month: sales, orders and net side by side.
    private func compare(_ s: Stats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("مقارنة بالشهر الماضي").font(.headline).foregroundStyle(Color.ink)
                Spacer()
                Text(period.previousText).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            if let prev {
                cmpRow("المبيعات", s.sales, prev.sales, money)
                cmpRow("الطلبات", Double(s.orderCount), Double(prev.orderCount)) { "\(Int($0))" }
                cmpRow("صافي الربح", s.net, prev.net, money)
                if period.key == "today" {
                    Text("اليوم لسا ما خلص، والشهر الماضي يوم كامل").font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .card(16)
    }

    private func cmpRow(_ label: String, _ now: Double, _ before: Double, _ fmt: (Double) -> String) -> some View {
        let top = max(abs(now), abs(before), 0.0001)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.subheadline.weight(.semibold))
                Spacer()
                DeltaBadge(now: now, before: before)
            }
            HStack(spacing: 8) {
                Text("الحين").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                ThinBar(value: max(0, now) / top, color: .ink, track: Color.wellBG, height: 10)
                Text(fmt(now)).font(.caption.bold()).monospacedDigit().frame(width: 74, alignment: .trailing)
            }
            HStack(spacing: 8) {
                Text("قبل").font(.caption2.weight(.semibold)).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                ThinBar(value: max(0, before) / top, color: Color.ink.opacity(0.35), track: Color.wellBG, height: 10)
                Text(fmt(before)).font(.caption.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary).frame(width: 74, alignment: .trailing)
            }
        }
    }

    private var quick: some View {
        HStack(spacing: 10) {
            quickBtn("plus", "مصروف") { sheet = .expense }
            quickBtn("bag.fill", "مبيعات تطبيق") { sheet = .sale }
            quickBtn("person.badge.plus", "عميل جديد") { sheet = .customer }
        }
    }

    private func quickBtn(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.headline).foregroundStyle(Color.popFG)
                    .frame(width: 42, height: 42).background(Color.pop, in: Circle())
                Text(label).font(.footnote.weight(.semibold)).foregroundStyle(Color.ink)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(Color.cardBG, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// Cash, card and the delivery apps: amounts, share of sales, and against last month.
    private func payments(_ s: Stats) -> some View {
        let cash = s.methods.first { $0.id == "cash" }?.gross ?? 0
        let card = s.methods.first { $0.id == "card" }?.gross ?? 0
        let apps = s.appGross
        let pCash = prev?.methods.first { $0.id == "cash" }?.gross
        let pCard = prev?.methods.first { $0.id == "card" }?.gross
        let pApps = prev?.appGross
        let total = max(cash + card + apps, 0.0001)
        let appColor = Color.accent2
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("المبيعات حسب الدفع").font(.headline).foregroundStyle(Color.ink)
                Spacer()
                Text("\(money(cash + card + apps)) ر.ع").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            GeometryReader { g in
                HStack(spacing: 3) {
                    if cash + card + apps <= 0 { Capsule().fill(Color.wellBG) } else {
                        if cash > 0 { Capsule().fill(Color.ink).frame(width: max(6, (g.size.width - 6) * cash / total)) }
                        if card > 0 { Capsule().fill(Color.lilac).frame(width: max(6, (g.size.width - 6) * card / total)) }
                        if apps > 0 { Capsule().fill(appColor).frame(width: max(6, (g.size.width - 6) * apps / total)) }
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(height: 12)
            HStack(spacing: 10) {
                payTile("كاش", "banknote.fill", cash, pCash, Color.ink, s.pct(cash))
                payTile("فيزا", "creditcard.fill", card, pCard, Color.lilac, s.pct(card))
                payTile("التطبيقات", "bag.fill", apps, pApps, appColor, s.pct(apps))
            }
            let appList = s.methods.filter { $0.isApp && ($0.gross > 0 || $0.n > 0) }
            if !appList.isEmpty {
                VStack(spacing: 8) {
                    ForEach(appList) { m in
                        HStack(spacing: 10) {
                            Circle().fill(appColor).frame(width: 8, height: 8)
                            Text(m.name).font(.subheadline.weight(.semibold))
                            Text("\(m.n) طلب").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(money(m.gross)).font(.subheadline.bold()).monospacedDigit()
                                if m.comm > 0 { Text("يوصلك \(money(m.net))").font(.caption2).foregroundStyle(.secondary).monospacedDigit() }
                            }
                        }
                    }
                }
                .padding(12)
                .background(Color.wellBG, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            if s.unpaidCount > 0 {
                Text("طلبات موقع ما استلمت: \(s.unpaidCount) · \(money(s.unpaidTotal)) ر.ع").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .card(16)
    }

    private func payTile(_ name: String, _ icon: String, _ v: Double, _ before: Double?, _ color: Color, _ share: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption.bold()).foregroundStyle(color == Color.lilac ? Color.ink : color)
                Text(name).font(.caption.weight(.bold)).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(money(v)).font(.headline.weight(.heavy)).monospacedDigit().foregroundStyle(Color.ink).lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 4) {
                Text("\(share)%").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let before { DeltaBadge(now: v, before: before) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.wellBG, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func chart(_ s: Stats) -> some View {
        let today = muscat.startOfDay(for: .now)
        return Chart(s.daily) { d in
            BarMark(x: .value("اليوم", d.id, unit: .day), y: .value("المبيعات", d.v))
                .foregroundStyle(muscat.isDate(d.id, inSameDayAs: today) ? Color.accent2 : Color.ink)
                .cornerRadius(8)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: max(1, s.daily.count / 7))) { _ in
                AxisValueLabel(format: .dateTime.day(), centered: true)
            }
        }
        .frame(height: 170)
        .padding(.top, 4)
        .safeAreaInset(edge: .top, spacing: 8) {
            HStack {
                Text("المبيعات اليومية").font(.headline).foregroundStyle(Color.ink)
                Spacer()
                Text("\(money(s.sales)) ر.ع").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .card(16)
    }

    private func products(_ s: Stats) -> some View {
        Group {
            if s.products.isEmpty {
                EmptyNote(text: "ما فيه طلبات في هالفترة", icon: "cup.and.saucer")
            } else {
                let top = Double(max(s.products.first?.n ?? 1, 1))
                VStack(spacing: 12) {
                    HStack {
                        Text("الأكثر طلباً").font(.headline).foregroundStyle(Color.ink)
                        Spacer()
                        Text(BizStore.shared.current == .karak ? "العدد" : "عدد الأكواب").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    ForEach(s.products.prefix(8)) { p in
                        HStack(spacing: 10) {
                            Text(p.id).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                            ThinBar(value: Double(p.n) / top, color: .ink, track: Color.wellBG, height: 10).frame(width: 120)
                            Text("\(p.n)").font(.subheadline.bold()).monospacedDigit().frame(width: 36, alignment: .trailing)
                        }
                    }
                }
                .card(16)
            }
        }
    }
}

/// The shop name as a menu: tap to switch between Açaí Dose and Karak Dose.
struct BizMenu: View {
    var body: some View {
        Menu {
            Picker("المحل", selection: Binding(get: { BizStore.shared.current }, set: { b in Haptics.tap(); BizStore.shared.current = b })) {
                ForEach(Biz.allCases) { b in Text(b.name).tag(b) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(BizStore.shared.current.name).font(.title3.weight(.heavy))
                Image(systemName: "chevron.down").font(.caption.weight(.bold))
            }
            .foregroundStyle(Color.ink)
        }
    }
}
