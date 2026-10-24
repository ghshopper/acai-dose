import SwiftUI

struct CustomerItem: Identifiable { let id: Int; let j: J }

struct CustomersView: View {
    @Environment(Toaster.self) private var toaster
    @State private var all: [J] = []
    @State private var loading = false
    @State private var q = ""
    @State private var sort = "last"
    @State private var offersOnly = false
    @State private var open: CustomerItem?
    @State private var adding = false

    private func daysAgo(_ t: String) -> Int {
        guard let d = parseStamp(t) else { return 99999 }
        return muscat.dateComponents([.day], from: d, to: .now).day ?? 99999
    }
    private func ago(_ t: String) -> String {
        let n = daysAgo(t)
        if n == 99999 { return "-" }
        if n == 0 { return "اليوم" }
        if n == 1 { return "أمس" }
        return "قبل \(n) يوم"
    }

    private var list: [J] {
        let s = q.trimmingCharacters(in: .whitespaces).lowercased()
        var l = all.filter { c in
            if offersOnly && c["offers"].int != 1 { return false }
            if s.isEmpty { return true }
            return ["name", "phone", "car_plate", "car_desc", "note"].contains { c[$0].string.lowercased().contains(s) }
        }
        l.sort { a, b in
            switch sort {
            case "orders": return a["orders"].int > b["orders"].int
            case "spent": return a["spent"].double > b["spent"].double
            case "away": return daysAgo(a["last_at"].string) > daysAgo(b["last_at"].string)
            default: return daysAgo(a["last_at"].string) < daysAgo(b["last_at"].string)
            }
        }
        return l
    }

    var body: some View {
        let repeatN = all.filter { $0["orders"].int > 1 }.count
        List {
            Section {
                HStack(spacing: 8) {
                    kpi("\(all.count)", "عميل")
                    kpi("\(repeatN)", "رجعوا")
                    kpi("\(all.filter { $0["offers"].int == 1 }.count)", "يبون العروض")
                }
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            Section {
                if list.isEmpty && !loading { EmptyNote(text: "ما فيه عملاء", icon: "person.2").listRowBackground(Color.clear) }
                ForEach(list.indices, id: \.self) { i in
                    let c = list[i]
                    Button { open = CustomerItem(id: c["id"].int, j: c) } label: { row(c) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading) {
                            if !c["phone"].string.isEmpty {
                                Button { openURL(waLink(c["phone"].string)) } label: { Label("واتساب", systemImage: "message.fill") }.tint(.good)
                            }
                        }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("العملاء")
        .searchable(text: $q, prompt: "بحث بالاسم أو الرقم أو السيارة")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("الترتيب", selection: $sort) {
                        Text("آخر زيارة").tag("last"); Text("الأكثر طلبات").tag("orders")
                        Text("الأكثر صرف").tag("spent"); Text("غايبين من زمان").tag("away")
                    }
                    Toggle("يبون العروض بس", isOn: $offersOnly)
                } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "person.badge.plus") }
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $open, onDismiss: { Task { await load() } }) { c in CustomerDetail(customer: c.j) }
        .sheet(isPresented: $adding) {
            AddCustomerSheet { toaster.show("انضاف العميل وصارت له بطاقة"); Task { await load() } }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        if let r = try? await API.shared.get("customers") { all = r.array }
    }

    private func kpi(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.title2.bold()).foregroundStyle(Color.ink).monospacedDigit()
            Text(l).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(Color.cardBG, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func row(_ c: J) -> some View {
        let name = c["name"].string.trimmingCharacters(in: .whitespaces)
        let need = c["need"].isNull ? 5 : c["need"].int
        let stamps = c["stamps"].int, free = c["free"].int
        return HStack(spacing: 12) {
            Text(name.isEmpty ? "؟" : String(name.prefix(1)))
                .font(.headline).foregroundStyle(Color.ink)
                .frame(width: 44, height: 44).background(Color.ink.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(name.isEmpty ? "بدون اسم" : name).font(.headline).lineLimit(1)
                    if c["orders"].int >= 5 { Tag(text: "دائم") }
                    if free > 0 { Tag(text: "\(free) مجاني", bg: .accent2, fg: .brand) }
                }
                Text(c["phone"].string).font(.subheadline).foregroundStyle(.secondary).environment(\.layoutDirection, .leftToRight)
                Text("\(c["orders"].int) طلب · \(money(c["spent"])) ر.ع · \(ago(c["last_at"].string))").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ThinBar(value: need > 0 ? Double(stamps) / Double(need) : 0)
                    Text("\(stamps)/\(need)").font(.caption2.bold()).monospacedDigit().foregroundStyle(Color.ink).environment(\.layoutDirection, .leftToRight)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Everything about one customer: loyalty card, contact, notes and order history.
struct CustomerDetail: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Toaster.self) private var toaster
    @State var c: J
    @State private var note = ""
    @State private var orders: [J]?
    @State private var busy = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var offers = false

    init(customer: J) {
        _c = State(initialValue: customer)
        _note = State(initialValue: customer["note"].string)
        _offers = State(initialValue: customer["offers"].int == 1)
    }

    // Local copy of the loyalty numbers (J is immutable)
    @State private var stampsOverride: (Int, Int, Int)?
    private var need: Int { stampsOverride?.2 ?? (c["need"].isNull ? 5 : c["need"].int) }
    private var stamps: Int { stampsOverride?.0 ?? c["stamps"].int }
    private var free: Int { stampsOverride?.1 ?? c["free"].int }
    private var phone: String { c["phone"].string }
    @State private var nameOverride: String?
    private var name: String { (nameOverride ?? c["name"].string).trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Text(phone).font(.headline).foregroundStyle(.secondary).environment(\.layoutDirection, .leftToRight)
                    loyaltyCard
                    HStack(spacing: 10) {
                        action("message.fill", "واتساب", .good) { openURL(waLink(phone)) }
                        action("phone.fill", "اتصال", .brand) { openURL("tel:\(phone)") }
                        action("wallet.pass.fill", "أرسل البطاقة", .accent2, enabled: !c["card_token"].string.isEmpty) { sendCard() }
                    }
                    HStack(spacing: 10) {
                        let n = c["orders"].int
                        num("\(n)", "طلب")
                        num(money(c["spent"]), "ر.ع صرف")
                        num(n > 0 ? money(c["spent"].double / Double(n)) : "-", "متوسط الطلب")
                    }
                    VStack(spacing: 0) {
                        Toggle("يبي يوصله العروض", isOn: $offers)
                            .onChange(of: offers) { _, v in Task { await update(["offers": v ? 1 : 0]) } }
                            .padding(.vertical, 6)
                        Divider()
                        HStack {
                            TextField("ملاحظة (مثلاً: يحب زيادة زبدة)", text: $note, axis: .vertical).lineLimit(1...3)
                            Button("احفظ") { Task { await update(["note": note.trimmingCharacters(in: .whitespaces)]) } }
                                .disabled(note == c["note"].string)
                        }
                        .padding(.vertical, 10)
                    }
                    .card(14)

                    SectionHeader(title: "الطلبات")
                    if let orders {
                        if orders.isEmpty { EmptyNote(text: "ما طلب للحين", icon: "doc.text") }
                        ForEach(orders.indices, id: \.self) { i in orderRow(orders[i]) }
                    } else {
                        ProgressView().padding(20)
                    }
                }
                .padding(16)
            }
            .background(Color.pageBG)
            .navigationTitle(name.isEmpty ? "بدون اسم" : name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button("تعديل") { newName = name; renaming = true } }
            }
            .alert("اسم العميل", isPresented: $renaming) {
                TextField("الاسم", text: $newName)
                Button("إلغاء", role: .cancel) {}
                Button("احفظ") { Task { await update(["name": newName.trimmingCharacters(in: .whitespaces)]); nameOverride = newName } }
            }
            .task { await loadOrders() }
        }
        .presentationDragIndicator(.visible)
    }

    private var loyaltyCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("بطاقة الولاء").font(.headline).foregroundStyle(Color.lilac)
                Spacer()
                Text("\(stamps) / \(need)").font(.headline).monospacedDigit().foregroundStyle(Color.cream).environment(\.layoutDirection, .leftToRight)
            }
            StampRow(filled: stamps, need: need, size: need > 7 ? 24 : 30)
                .padding(12)
                .background(Color.cream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if free > 0 { Tag(text: "\(free) كوب مجاني جاهز", bg: .accent2, fg: .brand, icon: "gift.fill") }
            HStack(spacing: 10) {
                Button { Task { await stamp(-1) } } label: { Label("ختم", systemImage: "minus").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.bordered).tint(.cream)
                Button { Task { await stamp(1) } } label: { Label("أضف ختم", systemImage: "plus").font(.headline).frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.borderedProminent).tint(.accent2).foregroundStyle(Color.brand)
                    .layoutPriority(1)
            }
            .disabled(busy)
            Button("كمّل البطاقة وعطه كوب مجاني (+\(max(need - stamps, 0)))") { Task { await stamp(need - stamps) } }
                .font(.footnote.weight(.semibold)).foregroundStyle(Color.lilac)
                .disabled(busy || need - stamps <= 0)
        }
        .padding(16)
        .background(Color.brand, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func action(_ icon: String, _ label: String, _ color: Color, enabled: Bool = true, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3).foregroundStyle(enabled ? color : Color.secondary)
                Text(label).font(.caption.weight(.semibold)).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(Color.cardBG, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain).disabled(!enabled)
    }

    private func num(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.title3.bold()).monospacedDigit().foregroundStyle(Color.ink).minimumScaleFactor(0.6).lineLimit(1)
            Text(l).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(Color.cardBG, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func orderRow(_ o: J) -> some View {
        let cancelled = o["status"].string == "cancelled"
        let items = o["items"].array.map { "\($0["qty"].int)× \($0["name_ar"].string.isEmpty ? $0["name_en"].string : $0["name_ar"].string)" }.joined(separator: "، ")
        let when = o["created_at"].string
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(String(when.prefix(16))).font(.caption.weight(.semibold)).foregroundStyle(.secondary).environment(\.layoutDirection, .leftToRight)
                Tag(text: o["source"].string == "web" ? "الموقع" : o["source"].string == "curb" ? "من السيارة" : "المحل")
                if o["free_cups"].int > 0 { Tag(text: "مجاني", bg: .accent2) }
                Spacer()
                Text(money(o["total"])).font(.subheadline.bold()).monospacedDigit().strikethrough(cancelled)
            }
            Text(items).font(.subheadline)
            if !o["payment"].string.isEmpty { Text(kPayNames[o["payment"].string] ?? o["payment"].string).font(.caption2).foregroundStyle(.secondary) }
        }
        .opacity(cancelled ? 0.5 : 1)
        .card(12)
    }

    private func loadOrders() async {
        orders = (try? await API.shared.get("customer_orders", ["phone": phone]))?.array ?? []
    }

    private func stamp(_ delta: Int) async {
        guard delta != 0 else { return }
        busy = true
        defer { busy = false }
        let before = free
        do {
            let r = try await API.shared.post("customer_stamps", ["id": c["id"].int, "delta": delta])
            stampsOverride = (r["stamps"].int, r["free"].int, r["need"].isNull ? need : r["need"].int)
            toaster.show(delta > 0 ? (r["free"].int > before ? "صار عنده كوب مجاني" : "انضاف \(delta) ختم") : "انشال ختم")
        } catch {
            toaster.show(errText(error), ok: false)
        }
    }

    private func update(_ body: [String: Any]) async {
        var b = body; b["id"] = c["id"].int
        do {
            try await API.shared.post("customer_update", b)
            toaster.show("انحفظ")
        } catch {
            toaster.show(errText(error), ok: false)
        }
    }

    private func sendCard() {
        let link = "\(SharedStore.site)/card.html?c=\(c["card_token"].string)"
        let msg = "هلا\(name.isEmpty ? "" : " \(name)") 👋\nهذي بطاقة الولاء حقك في أساي دوز (\(stamps)/\(need) ختم):\n\(link)\nتقدر تضيفها لمحفظة جوالك 💜"
        openURL(waLink(phone, text: msg))
    }
}
