import SwiftUI
import Charts

/// The whole business on one page: where the money comes from, where it goes, what is left,
/// the last 12 months side by side, and where the money sits now.
struct BusinessView: View {
    @Environment(Period.self) private var period
    @State private var reports: [Biz: J] = [:]
    @State private var monthsBy: [Biz: [J]] = [:]
    @State private var errs: [Biz: String] = [:]
    @State private var pick = "all"
    @State private var loading = false

    static let shopColor: [Biz: Color] = [.acai: Color(red: 0x8E / 255, green: 0x3B / 255, blue: 0x86 / 255), .karak: Color(red: 0.6, green: 0.6, blue: 0.6)]

    /// The report the detail sections show: one shop, or both added together.
    private var sel: J? {
        if pick == "all" { return reports.isEmpty ? nil : combined }
        return Biz(rawValue: pick).flatMap { reports[$0] }
    }
    private var months: [J] {
        if pick == "all" { return combinedMonths }
        return Biz(rawValue: pick).flatMap { monthsBy[$0] } ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                PeriodBar()
                Group {
                    if reports.isEmpty && !errs.isEmpty {
                        EmptyNote(text: errs.values.first ?? "", icon: "wifi.exclamationmark")
                    } else if reports.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(60)
                    } else {
                        hero(combined, title: reports.count > 1 ? "المحلين مع بعض" : (reports.keys.first?.name ?? ""))
                        shops
                        if reports.count > 1 { table }
                        ForEach(Biz.allCases) { b in
                            if reports[b] == nil, let e = errs[b] {
                                Text(e == errText("login_required") ? "سجّل دخول \(b.name) مرة وحدة من زر المحل، وبعدها يطلع هني" : "\(b.name): \(e)")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Picker("", selection: $pick) {
                            Text("المحلين").tag("all")
                            ForEach(Biz.allCases) { b in Text(b.name).tag(b.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.top, 6)
                        if let r = sel {
                            perRial(r)
                            income(r)
                            spending(r)
                            if months.filter({ $0["sales"].double > 0 }).count > 1 { trend }
                            cash(r)
                        }
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
        .task(id: period.version) { await load() }
    }

    // MARK: both shops

    /// Both reports added together, in the same shape as one report.
    private var combined: J {
        let rs = Biz.allCases.compactMap { reports[$0] }
        let multi = rs.count > 1
        func sum(_ k: String) -> Double { rs.reduce(0) { $0 + $1[k].double } }
        func merge(_ k: String) -> [String: Any] {
            var d: [String: Double] = [:]
            for r in rs { for (c, v) in r[k].dict { d[c, default: 0] += v.double } }
            return d
        }
        var pay: [String: Any] = [:]
        for f in ["cash", "card", "apps", "open"] { pay[f] = rs.reduce(0) { $0 + $1["pay"][f].double } }
        var apps: [String: (String, Double)] = [:]
        for r in rs { for a in r["apps"].array { let k = a["k"].string; apps[k] = (a["ar"].string, (apps[k]?.1 ?? 0) + a["gross"].double) } }
        var accounts: [[String: Any]] = [], owed: [[String: Any]] = []
        for b in Biz.allCases {
            guard let r = reports[b] else { continue }
            for x in r["accounts"].array { accounts.append(["name": multi ? "\(b.name) · \(x["name"].string)" : x["name"].string, "balance": x["balance"].double]) }
            for o in r["owed"].array { owed.append(["ar": multi ? "\(o["ar"].string) (\(b.name))" : o["ar"].string, "owed": o["owed"].double]) }
        }
        return J([
            "sales": sum("sales"), "orders": sum("orders"), "commission": sum("commission"),
            "running": merge("running"), "running_total": sum("running_total"),
            "one_off": merge("one_off"), "one_off_total": sum("one_off_total"),
            "net": sum("net"), "net_running": sum("net_running"), "owner_in": sum("owner_in"), "withdrawn": sum("withdrawn"),
            "pay": pay, "apps": apps.map { ["k": $0.key, "ar": $0.value.0, "gross": $0.value.1] },
            "accounts": accounts, "owed": owed,
        ] as [String: Any])
    }

    private var combinedMonths: [J] {
        var out: [String: [String: Double]] = [:]
        var order: [String] = []
        for b in Biz.allCases {
            for m in monthsBy[b] ?? [] {
                let k = m["month"].string
                if out[k] == nil { out[k] = [:]; order.append(k) }
                for f in ["sales", "commission", "expenses", "net", "orders"] { out[k]![f, default: 0] += m[f].double }
            }
        }
        return order.sorted().map { k in
            var d: [String: Any] = [:]
            for (f, v) in out[k] ?? [:] { d[f] = v }
            d["month"] = k
            return J(d)
        }
    }

    /// The two shops side by side; tap one to see its details below.
    private var shops: some View {
        HStack(spacing: 10) {
            ForEach(Biz.allCases) { b in
                if let r = reports[b] {
                    let sl = r["sales"].double, net = r["net"].double
                    Button { withAnimation { pick = pick == b.rawValue ? "all" : b.rawValue } } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Circle().fill(Self.shopColor[b] ?? .gray).frame(width: 10, height: 10)
                                Text(b.name).font(.subheadline.weight(.bold))
                            }
                            Text(money(net)).font(.title2.weight(.heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                                .foregroundStyle(net < 0 ? Color.bad : Color.ink)
                            Text("صافي · هامش \(sl > 0 ? Int((net / sl * 100).rounded()) : 0)%").font(.caption).foregroundStyle(.secondary)
                            Divider()
                            kv("المبيعات", money(sl))
                            kv("المصاريف", money(r["commission"].double + r["running_total"].double + r["one_off_total"].double))
                            kv("الطلبات", "\(r["orders"].int)")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(Color.cardBG, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(pick == b.rawValue ? (Self.shopColor[b] ?? .gray) : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func kv(_ a: String, _ v: String) -> some View {
        HStack {
            Text(a).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            Text(v).font(.footnote.bold()).monospacedDigit()
        }
    }

    /// Every number for both shops in one table.
    private var table: some View {
        let a = reports[.acai], k = reports[.karak]
        func cell(_ r: J?, _ f: (J) -> Double, money m: Bool = true) -> String {
            guard let r else { return "—" }
            let v = f(r); return m ? money(v) : String(Int(v.rounded()))
        }
        let rows: [(String, (J) -> Double, Bool)] = [
            ("المبيعات", { $0["sales"].double }, true),
            ("كاش", { $0["pay"]["cash"].double }, true),
            ("فيزا", { $0["pay"]["card"].double }, true),
            ("التطبيقات", { $0["pay"]["apps"].double }, true),
            ("عمولات", { $0["commission"].double }, true),
            ("المصاريف", { $0["running_total"].double + $0["one_off_total"].double }, true),
            ("الصافي", { $0["net"].double }, true),
            ("الطلبات", { $0["orders"].double }, false),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            header("المحلين جنب بعض", nil)
            HStack {
                Text("").frame(width: 72, alignment: .leading)
                Text("أساي").font(.caption.bold()).foregroundStyle(Self.shopColor[.acai]!).frame(maxWidth: .infinity, alignment: .trailing)
                Text("كرك").font(.caption.bold()).foregroundStyle(Self.shopColor[.karak]!).frame(maxWidth: .infinity, alignment: .trailing)
                Text("المجموع").font(.caption.bold()).frame(maxWidth: .infinity, alignment: .trailing)
            }
            ForEach(rows.indices, id: \.self) { i in
                let row = rows[i]
                let bold = row.0 == "الصافي" || row.0 == "المبيعات"
                HStack {
                    Text(row.0).font(bold ? .footnote.bold() : .footnote).frame(width: 72, alignment: .leading)
                    Text(cell(a, row.1, money: row.2)).font(.footnote).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                    Text(cell(k, row.1, money: row.2)).font(.footnote).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                    Text(cell(combined, row.1, money: row.2)).font(.footnote.bold()).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                }
                if i < rows.count - 1 { Divider() }
            }
        }
        .card(16)
    }

    // MARK: numbers

    private func sales(_ r: J) -> Double { r["sales"].double }
    private func costs(_ r: J) -> Double { r["commission"].double + r["running_total"].double + r["one_off_total"].double }

    // MARK: pieces

    /// Net profit, margin, and the three big numbers.
    private func hero(_ r: J, title: String) -> some View {
        let s = sales(r), net = r["net"].double
        let margin = s > 0 ? net / s * 100 : 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(title) · \(period.label)").font(.subheadline.weight(.semibold)).opacity(0.8)
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
            Text("صافي الربح").font(.caption.weight(.semibold)).opacity(0.75)
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
        var rs: [Biz: J] = [:], ms: [Biz: [J]] = [:], es: [Biz: String] = [:]
        let from = period.fromStr, to = period.toStr
        await withTaskGroup(of: (Biz, J?, [J], String?).self) { g in
            for b in Biz.allCases {
                g.addTask {
                    do {
                        async let x = API.shared.get("report", ["from": from, "to": to], biz: b)
                        async let y = API.shared.get("months", [:], biz: b)
                        let (r, m) = try await (x, y)
                        return (b, r, m.array, nil)
                    } catch { return (b, nil, [], errText(error)) }
                }
            }
            for await (b, r, m, e) in g {
                if let r { rs[b] = r; ms[b] = m }
                if let e { es[b] = e }
            }
        }
        reports = rs; monthsBy = ms; errs = es
    }
}

