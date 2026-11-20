import SwiftUI
import Charts

/// The whole business on one page: where the money comes from, where it goes, what is left,
/// the last 12 months side by side, and where the money sits now.
struct BusinessView: View {
    @Environment(Period.self) private var period
    @State private var r: J?
    @State private var months: [J] = []
    @State private var err: String?
    @State private var loading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PeriodBar()
                Group {
                    if let r {
                        hero(r)
                        perRial(r)
                        income(r)
                        spending(r)
                        if months.count > 1 { trend }
                        cash(r)
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
        .navigationTitle("البزنس")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { if loading { ProgressView() } } }
        .refreshable { await load() }
        .task(id: "\(period.version)-\(BizStore.shared.current.rawValue)") { await load() }
    }

    // MARK: numbers

    private func sales(_ r: J) -> Double { r["sales"].double }
    private func costs(_ r: J) -> Double { r["commission"].double + r["running_total"].double + r["one_off_total"].double }

    // MARK: pieces

    /// Net profit, margin, and the three big numbers.
    private func hero(_ r: J) -> some View {
        let s = sales(r), net = r["net"].double
        let margin = s > 0 ? net / s * 100 : 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("صافي الربح · \(period.label)").font(.subheadline.weight(.semibold)).opacity(0.8)
                Spacer()
                Text("هامش \(Int(margin.rounded()))%").font(.caption.bold()).monospacedDigit()
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .foregroundStyle(Color.popFG).background(Color.pop, in: Capsule())
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(money(net)).font(.system(size: 42, weight: .heavy, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("ر.ع").font(.headline).opacity(0.8)
            }
            HStack(spacing: 8) {
                mini("المبيعات", money(s))
                mini("المصاريف", money(costs(r)))
                mini("الطلبات", "\(r["orders"].int)")
            }
            let days = max(period.days.count, 1)
            HStack(spacing: 8) {
                mini("متوسط الطلب", r["orders"].int > 0 ? money(s / Double(r["orders"].int)) : "—")
                mini("مبيعات اليوم", money(s / Double(days)))
                mini("طلبات اليوم", String(format: "%.0f", Double(r["orders"].int) / Double(days)))
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
            Text(label).font(.caption2.weight(.semibold)).opacity(0.75).lineLimit(1)
            Text(value).font(.subheadline.weight(.heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color.heroFG.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Every rial of sales split into where it went: one bar, then the list.
    private func perRial(_ r: J) -> some View {
        let s = max(sales(r), 0.0001)
        var parts: [(String, Double, Color)] = []
        if r["commission"].double > 0 { parts.append(("عمولات التطبيقات", r["commission"].double, Color.accent2)) }
        if r["running_total"].double > 0 { parts.append(("المصاريف", r["running_total"].double, Color.lilac)) }
        if r["one_off_total"].double > 0 { parts.append(("مرة وحدة", r["one_off_total"].double, Color.ink.opacity(0.35))) }
        let net = r["net"].double
        if net > 0 { parts.append(("ربحك", net, Color.good)) }
        return VStack(alignment: .leading, spacing: 12) {
            header("كل ريال تبيعه، وين يروح", nil)
            GeometryReader { g in
                HStack(spacing: 3) {
                    ForEach(parts.indices, id: \.self) { i in
                        Capsule().fill(parts[i].2).frame(width: max(6, (g.size.width - CGFloat(parts.count) * 3) * min(parts[i].1 / s, 1)))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 16)
            VStack(spacing: 8) {
                ForEach(parts.indices, id: \.self) { i in
                    HStack(spacing: 8) {
                        Circle().fill(parts[i].2).frame(width: 10, height: 10)
                        Text(parts[i].0).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(Int((parts[i].1 / s * 1000).rounded())) بيسة").font(.subheadline.bold()).monospacedDigit()
                    }
                }
                if net < 0 {
                    Text("المصاريف أكثر من المبيعات بـ \(money(-net)) ر.ع في هالفترة").font(.footnote.weight(.semibold)).foregroundStyle(Color.bad)
                }
            }
        }
        .card(16)
    }

    /// Where the money comes from: cash, card, the apps (and each app).
    private func income(_ r: J) -> some View {
        let p = r["pay"]
        let rows: [(String, String, Double)] = [("كاش", "banknote.fill", p["cash"].double), ("فيزا", "creditcard.fill", p["card"].double),
                                                ("التطبيقات", "bag.fill", p["apps"].double), ("موقع ما انستلم", "clock", p["open"].double)].filter { $0.2 > 0 }
        let s = max(sales(r), 0.0001)
        return VStack(alignment: .leading, spacing: 12) {
            header("من وين تجي الفلوس", "\(money(sales(r))) ر.ع")
            ForEach(rows.indices, id: \.self) { i in
                let row = rows[i]
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: row.1).font(.footnote.bold()).frame(width: 22)
                        Text(row.0).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(Int((row.2 / s * 100).rounded()))%").font(.caption.bold()).foregroundStyle(.secondary)
                        Text(money(row.2)).font(.subheadline.bold()).monospacedDigit().frame(minWidth: 80, alignment: .trailing)
                    }
                    ThinBar(value: row.2 / s, color: .ink, track: Color.wellBG, height: 8)
                }
            }
            let apps = r["apps"].array.filter { $0["gross"].double > 0 }
            if !apps.isEmpty {
                VStack(spacing: 8) {
                    ForEach(apps, id: \.self) { a in
                        HStack {
                            Text(a["ar"].string).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(money(a["gross"])).font(.subheadline.bold()).monospacedDigit()
                        }
                    }
                    HStack {
                        Text("عمولاتهم").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text("−" + money(r["commission"])).font(.footnote.bold()).monospacedDigit().foregroundStyle(Color.bad)
                    }
                }
                .padding(12)
                .background(Color.wellBG, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .card(16)
    }

    /// Where the money goes: every expense category, biggest first, with its share of sales.
    private func spending(_ r: J) -> some View {
        let run = r["running"].dict.map { ($0.key, $0.value.double) }.sorted { $0.1 > $1.1 }
        let once = r["one_off"].dict.map { ($0.key, $0.value.double) }.sorted { $0.1 > $1.1 }
        let top = max(run.first?.1 ?? 0, once.first?.1 ?? 0, 0.0001)
        let s = max(sales(r), 0.0001)
        return VStack(alignment: .leading, spacing: 12) {
            header("وين تروح الفلوس", "\(money(r["running_total"].double + r["one_off_total"].double)) ر.ع")
            if run.isEmpty && once.isEmpty {
                Text("ما فيه مصاريف في هالفترة").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(run.indices, id: \.self) { i in catRow(run[i].0, run[i].1, top, s) }
            if !once.isEmpty {
                Text("مصاريف مرة وحدة (معدات وتأسيس)").font(.caption.weight(.bold)).foregroundStyle(.secondary).padding(.top, 4)
                ForEach(once.indices, id: \.self) { i in catRow(once[i].0, once[i].1, top, s) }
            }
        }
        .card(16)
    }

    private func catRow(_ name: String, _ v: Double, _ top: Double, _ s: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                Text("\(Int((v / s * 100).rounded()))% من المبيعات").font(.caption).foregroundStyle(.secondary)
                Text(money(v)).font(.subheadline.bold()).monospacedDigit().frame(minWidth: 80, alignment: .trailing)
            }
            ThinBar(value: v / top, color: .lilac, track: Color.wellBG, height: 8)
        }
    }

    /// The last 12 months: sales and costs as bars, net as a line.
    private var trend: some View {
        let f = DateFormatter(); f.locale = Locale(identifier: "ar_OM"); f.dateFormat = "MMM"
        let p = DateFormatter(); p.dateFormat = "yyyy-MM"; p.locale = Locale(identifier: "en_US_POSIX")
        let data = months.filter { $0["sales"].double > 0 || $0["expenses"].double > 0 }
        let label: (J) -> String = { m in p.date(from: m["month"].string).map { f.string(from: $0) } ?? m["month"].string }
        let best = data.max { $0["net"].double < $1["net"].double }
        return VStack(alignment: .leading, spacing: 12) {
            header("آخر ١٢ شهر", nil)
            Chart {
                ForEach(data, id: \.self) { m in
                    BarMark(x: .value("الشهر", label(m)), y: .value("ر.ع", m["sales"].double))
                        .foregroundStyle(by: .value("", "المبيعات")).position(by: .value("", "المبيعات"))
                    BarMark(x: .value("الشهر", label(m)), y: .value("ر.ع", m["expenses"].double + m["commission"].double))
                        .foregroundStyle(by: .value("", "المصاريف")).position(by: .value("", "المصاريف"))
                    LineMark(x: .value("الشهر", label(m)), y: .value("ر.ع", m["net"].double))
                        .foregroundStyle(Color.good).lineStyle(StrokeStyle(lineWidth: 3)).symbol(.circle)
                }
                RuleMark(y: .value("", 0)).foregroundStyle(Color.ink.opacity(0.3))
            }
            .chartForegroundStyleScale(["المبيعات": Color.ink, "المصاريف": Color.lilac])
            .chartLegend(position: .top, alignment: .leading)
            .frame(height: 220)
            HStack {
                Circle().fill(Color.good).frame(width: 8, height: 8)
                Text("الخط الأخضر صافي الربح").font(.caption).foregroundStyle(.secondary)
            }
            if let best, best["net"].double > 0 {
                Text("أفضل شهر: \(label(best)) بربح \(money(best["net"])) ر.ع").font(.footnote.weight(.semibold))
            }
            VStack(spacing: 6) {
                ForEach(data.reversed(), id: \.self) { m in
                    HStack {
                        Text(label(m)).font(.footnote.weight(.semibold)).frame(width: 60, alignment: .leading)
                        Text(money(m["sales"])).font(.footnote).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                        Text(money(m["expenses"].double + m["commission"].double)).font(.footnote).monospacedDigit().foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
                        Text(money(m["net"])).font(.footnote.bold()).monospacedDigit()
                            .foregroundStyle(m["net"].double < 0 ? Color.bad : Color.good).frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }
            .padding(12)
            .background(Color.wellBG, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .card(16)
    }

    /// Where the money sits now: company accounts, what the apps still owe, money in and out.
    private func cash(_ r: J) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header("وين الفلوس الحين", nil)
            ForEach(r["accounts"].array, id: \.self) { a in line(a["name"].string, a["balance"].double, bold: true) }
            ForEach(r["owed"].array, id: \.self) { o in line("باقي عند \(o["ar"].string)", o["owed"].double) }
            if r["owner_in"].double > 0 { line("دفعت من جيبك (هالفترة)", r["owner_in"].double) }
            if r["withdrawn"].double > 0 { line("سحوبات (هالفترة)", -r["withdrawn"].double) }
        }
        .card(16)
    }

    private func line(_ a: String, _ v: Double, bold: Bool = false) -> some View {
        HStack {
            Text(a).font(bold ? .subheadline.weight(.bold) : .subheadline)
            Spacer()
            Text(money(v)).font(bold ? .subheadline.bold() : .subheadline).monospacedDigit().foregroundStyle(v < 0 ? Color.bad : Color.ink)
        }
    }

    private func header(_ t: String, _ trailing: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(t).font(.headline).foregroundStyle(Color.ink)
            Spacer()
            if let trailing { Text(trailing).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
        }
    }

    // MARK: data

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            async let a = API.shared.get("report", ["from": period.fromStr, "to": period.toStr])
            async let b = API.shared.get("months")
            let (x, y) = try await (a, b)
            r = x; months = y.array; err = nil
        } catch {
            err = errText(error)
        }
    }
}
