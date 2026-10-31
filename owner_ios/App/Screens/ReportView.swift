import SwiftUI

/// Both shops' numbers for a period on one page, and the same as a tidy WhatsApp message for the partners.
struct ReportView: View {
    @Environment(Period.self) private var period
    @State private var sinceStart = false
    @State private var data: [Biz: J] = [:]
    @State private var errs: [Biz: String] = [:]
    @State private var loading = false

    private var from: String { sinceStart ? "2024-01-01" : period.fromStr }
    private var to: String { period.toStr }

    var body: some View {
        List {
            Section {
                PeriodBar().listRowInsets(EdgeInsets()).listRowBackground(Color.clear).disabled(sinceStart).opacity(sinceStart ? 0.4 : 1)
                Toggle("من يوم الافتتاح لين اليوم", isOn: $sinceStart)
            }
            if data.count > 1 { total }
            ForEach(Biz.allCases) { b in
                if let r = data[b] { shop(b, r) }
                else if let e = errs[b] {
                    Section(b.name) { Text(e == errText("login_required") ? "سجّل دخول \(b.name) مرة وحدة من زر المحل، وبعدها يطلع هني" : e).foregroundStyle(.secondary) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("تقرير الشركاء")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if loading { ProgressView() } else {
                    ShareLink(item: message) { Label("شارك", systemImage: "square.and.arrow.up") }.disabled(data.isEmpty)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !data.isEmpty {
                Button { openURL("https://wa.me/?text=" + (message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) } label: {
                    Label("أرسل على الواتساب", systemImage: "paperplane.fill").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent).tint(Color(red: 0.15, green: 0.83, blue: 0.4))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
        .refreshable { await load() }
        .task(id: "\(period.version)-\(sinceStart)") { await load() }
    }

    // MARK: pieces

    private var total: some View {
        let net = data.values.reduce(0) { $0 + $1["net"].double }
        let sales = data.values.reduce(0) { $0 + $1["sales"].double }
        let bank = data.values.reduce(0) { $0 + $1["bank"].double }
        let owed = data.values.reduce(0) { $0 + $1["owed_total"].double }
        let mine = data.values.reduce(0) { $0 + $1["owner_in"].double }
        return Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("المحلين مع بعض").font(.subheadline.weight(.semibold)).foregroundStyle(Color.lilac)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(money(net)).font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(net < 0 ? Color(red: 1, green: 0.7, blue: 0.7) : Color.cream)
                    Text("ر.ع صافي").font(.headline).foregroundStyle(Color.lilac)
                }
                pair("المبيعات", sales); pair("في حسابات الشركة", bank); pair("باقي عند التطبيقات", owed)
                if mine > 0 { pair("دفعت من جيبك", mine) }
            }
            .padding(18)
            .background(LinearGradient(colors: [.brand, .brand2], startPoint: .topTrailing, endPoint: .bottomLeading), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
        }
    }

    private func pair(_ a: String, _ v: Double) -> some View {
        HStack {
            Text(a).font(.footnote.weight(.semibold)).foregroundStyle(Color.lilac)
            Spacer()
            Text(money(v)).font(.footnote.bold()).monospacedDigit().foregroundStyle(Color.cream)
        }
    }

    private func shop(_ b: Biz, _ r: J) -> some View {
        Section {
            row("المبيعات", r["sales"].double, bold: true, note: "\(r["orders"].int) طلب")
            row("   كاش", r["pay"]["cash"].double)
            row("   بطاقة", r["pay"]["card"].double)
            row("   التطبيقات", r["pay"]["apps"].double)
            if r["pay"]["open"].double > 0 { row("   طلبات موقع ما انستلمت", r["pay"]["open"].double) }
            row("عمولات التطبيقات", -r["commission"].double)
            row("المصاريف الشهرية", -r["running_total"].double)
            ForEach(r["running"].dict.sorted { $0.value.double > $1.value.double }, id: \.key) { k, v in row("   \(k)", -v.double) }
            row("الصافي من الشغل", r["net_running"].double, bold: true)
            if r["one_off_total"].double > 0 {
                row("مصاريف مرة وحدة", -r["one_off_total"].double)
                ForEach(r["one_off"].dict.sorted { $0.value.double > $1.value.double }, id: \.key) { k, v in row("   \(k)", -v.double) }
                row("الصافي بعدها", r["net"].double, bold: true)
            }
            row("في حساب الشركة", r["bank"].double, bold: true)
            ForEach(r["owed"].array, id: \.self) { o in row("باقي عند \(o["ar"].string)", o["owed"].double) }
            if r["owner_in"].double > 0 { row("دفعت من جيبك", r["owner_in"].double) }
            if r["withdrawn"].double > 0 { row("سحوبات", -r["withdrawn"].double) }
        } header: { Text(b.name).font(.headline) }
    }

    private func row(_ a: String, _ v: Double, bold: Bool = false, note: String = "") -> some View {
        HStack {
            Text(a).font(bold ? .subheadline.weight(.bold) : .subheadline).foregroundStyle(bold ? Color.primary : Color.secondary)
            if !note.isEmpty { Text(note).font(.caption).foregroundStyle(.tertiary) }
            Spacer()
            Text(money(v)).font(bold ? .subheadline.bold() : .subheadline).monospacedDigit()
                .foregroundStyle(v < 0 ? Color.bad : (bold ? Color.ink : Color.primary))
        }
    }

    // MARK: data

    private func load() async {
        loading = true
        defer { loading = false }
        var d: [Biz: J] = [:], e: [Biz: String] = [:]
        for b in Biz.allCases {
            do { d[b] = try await API.shared.get("report", ["from": from, "to": to], biz: b) } catch { e[b] = errText(error) }
        }
        data = d; errs = e
    }

    /// The WhatsApp message: one block per shop, then both together.
    private var message: String {
        func m(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.3f", v) }
        var lines: [String] = ["📊 تقرير \(sinceStart ? "من الافتتاح" : from) – \(to)"]
        for b in Biz.allCases {
            guard let r = data[b] else { continue }
            lines += ["", "*\(b.name)*",
                      "المبيعات: \(m(r["sales"].double))",
                      "  كاش \(m(r["pay"]["cash"].double)) · بطاقة \(m(r["pay"]["card"].double)) · تطبيقات \(m(r["pay"]["apps"].double))"]
            if r["commission"].double > 0 { lines.append("عمولات التطبيقات: \(m(r["commission"].double))") }
            let run = r["running"].dict.sorted { $0.value.double > $1.value.double }.map { "\($0.key) \(m($0.value.double))" }.joined(separator: " · ")
            lines.append("المصاريف الشهرية: \(m(r["running_total"].double))" + (run.isEmpty ? "" : "\n  \(run)"))
            lines.append("الصافي من الشغل: \(m(r["net_running"].double))")
            if r["one_off_total"].double > 0 {
                let once = r["one_off"].dict.map { "\($0.key) \(m($0.value.double))" }.joined(separator: " · ")
                lines.append("مصاريف مرة وحدة: \(m(r["one_off_total"].double))\n  \(once)")
                lines.append("الصافي بعدها: \(m(r["net"].double))")
            }
            lines.append("💳 في حساب الشركة: \(m(r["bank"].double))")
            let owed = r["owed"].array.map { "\($0["ar"].string) \(m($0["owed"].double))" }.joined(separator: " · ")
            if !owed.isEmpty { lines.append("⏳ باقي عند التطبيقات: \(owed)") }
            if r["owner_in"].double > 0 { lines.append("دفعت من جيبي: \(m(r["owner_in"].double))") }
            if r["withdrawn"].double > 0 { lines.append("سحوبات: \(m(r["withdrawn"].double))") }
        }
        if data.count > 1 {
            let v = data.values
            lines += ["", "*المجموع*",
                      "الصافي: \(m(v.reduce(0) { $0 + $1["net"].double }))",
                      "في الحسابات: \(m(v.reduce(0) { $0 + $1["bank"].double }))",
                      "باقي عند التطبيقات: \(m(v.reduce(0) { $0 + $1["owed_total"].double }))"]
        }
        return lines.joined(separator: "\n")
    }
}
