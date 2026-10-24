import SwiftUI

/// Menu prices, toppings, shop WhatsApp, loyalty, app commissions and staff accounts.
struct SettingsView: View {
    @Environment(Toaster.self) private var toaster
    @State private var s: J?
    @State private var err: String?
    @State private var wa = ""
    @State private var design = "old"
    @State private var addingItem = false
    @State private var loyOn = true
    @State private var need = 6
    @State private var unit = "cup"
    @State private var loyDirty = false
    @State private var comm: [String: String] = [:]
    @State private var pwFor: J?
    @State private var newPw = ""
    @State private var addingUser = false
    @State private var newUser = ""
    @State private var newUserPw = ""

    var body: some View {
        Group {
            if let s {
                Form {
                    if BizStore.shared.current == .acai {
                    Section {
                        Picker("التصميم", selection: Binding(get: { design }, set: { v in
                            design = v
                            Task { await post("save_design", ["design": v], v == "new" ? "صار الموقع بالتصميم الجديد" : "رجع الموقع للتصميم القديم") }
                        })) {
                            Text("القديم").tag("old")
                            Text("الجديد").tag("new")
                        }
                        .pickerStyle(.segmented)
                        Button { openURL("\(SharedStore.site)/new.html?preview") } label: { Label("شوف التصميم الجديد", systemImage: "eye") }
                        Button { openURL("\(SharedStore.site)/") } label: { Label("افتح الموقع", systemImage: "safari") }
                    } header: { Text("صفحة الطلب") } footer: { Text("اللي تختاره يطلع للزبائن على order.acaiee.com على طول. الطلبات توصلك من التصميمين.") }
                    }
                    let cats = s["cats"].array
                    if cats.isEmpty {
                        Section { ForEach(s["products"].array.filter { $0["kind"].string != "open" }, id: \.self) { p in ProductRow(p: p, save: save) } } header: { Text("المنيو والأسعار") } footer: { Text("اللي تطفيه يختفي من الموقع والكاشير") }
                    } else {
                        Section {
                            ForEach(cats, id: \.self) { c in
                                let items = s["products"].array.filter { $0["cat"].string == c["k"].string }
                                DisclosureGroup {
                                    ForEach(items, id: \.self) { p in ProductRow(p: p, save: save) }
                                } label: {
                                    HStack {
                                        Text(c["ar"].string).font(.body.weight(.semibold))
                                        Spacer()
                                        let out = items.filter { $0["soldout"].int == 1 }.count
                                        if out > 0 { Tag(text: "\(out) خالص", bg: Color.bad.opacity(0.14), fg: .bad) }
                                        Text("\(items.count)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Button { addingItem = true } label: { Label("أضف صنف", systemImage: "plus.circle.fill") }
                        } header: { Text("المنيو والأسعار") } footer: { Text("اللي تطفيه يختفي من الموقع والكاشير. «خالص» يحطه الموظف من الكاشير لما يخلص الصنف.") }
                    }
                    let tops = s["toppings"].array
                    if !tops.isEmpty {
                        Section { ForEach(tops, id: \.self) { t in ToppingRow(t: t, save: save) } } header: { Text("إضافات اصنع أساي باولك") } footer: { Text("تنضاف على سعر الباول") }
                    }
                    Section {
                        HStack {
                            Text("+968").foregroundStyle(.secondary)
                            TextField("9XXXXXXX", text: $wa).keyboardType(.phonePad)
                            Button("احفظ") { Task { await post("save_contact", ["whatsapp": wa.trimmingCharacters(in: .whitespaces)], wa.isEmpty ? "انشال زر الواتساب" : "انحفظ، الزر طالع للزبائن") } }
                        }
                        .environment(\.layoutDirection, .leftToRight)
                    } header: { Text("واتساب المحل") } footer: { Text("يطلع زر للزبائن في صفحة الطلب") }
                    loyalty
                    Section {
                        ForEach(kChannels.map { $0.0 }, id: \.self) { k in
                            HStack {
                                Text(kChannelNames[k] ?? k)
                                Spacer()
                                TextField("0", text: Binding(get: { comm[k] ?? "" }, set: { comm[k] = $0 }))
                                    .keyboardType(.decimalPad).multilineTextAlignment(.center).frame(width: 70)
                                Text("%").foregroundStyle(.secondary)
                            }
                        }
                        Button("احفظ العمولات") {
                            var body: [String: Any] = [:]
                            for (k, _) in kChannels { body[k] = Double(comm[k] ?? "") ?? 0 }
                            Task { await post("save_commissions", body, "انحفظت العمولات") }
                        }
                    } header: { Text("عمولات التطبيقات") } footer: { Text("تنحسب على الطلبات الجديدة") }
                    staff(s["users"].array)
                }
            } else if let err {
                EmptyNote(text: err, icon: "wifi.exclamationmark")
            } else {
                ProgressView()
            }
        }
        .navigationTitle("الإعدادات")
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $addingItem) {
            AddItemSheet(cats: s?["cats"].array ?? []) { toaster.show("انضاف الصنف"); Task { await load() } }
        }
        .alert("كلمة سر جديدة لـ \(pwFor?["username"].string ?? "")", isPresented: Binding(get: { pwFor != nil }, set: { if !$0 { pwFor = nil } })) {
            TextField("٦ حروف أو أكثر", text: $newPw)
            Button("إلغاء", role: .cancel) { newPw = "" }
            Button("احفظ") {
                if let u = pwFor, !newPw.isEmpty { Task { await post("user_update", ["id": u["id"].int, "password": newPw], "تغيرت كلمة السر") } }
                newPw = ""
            }
        }
        .alert("حساب عامل جديد", isPresented: $addingUser) {
            TextField("اسم المستخدم (إنجليزي)", text: $newUser).textInputAutocapitalization(.never)
            TextField("كلمة السر", text: $newUserPw)
            Button("إلغاء", role: .cancel) {}
            Button("أضف") { Task { await post("add_user", ["username": newUser.trimmingCharacters(in: .whitespaces), "password": newUserPw], "انضاف الحساب"); newUser = ""; newUserPw = "" } }
        }
    }

    private var loyalty: some View {
        Section("بطاقة الولاء") {
            Toggle("نظام الولاء شغال", isOn: Binding(get: { loyOn }, set: { loyOn = $0; loyDirty = true }))
            Stepper(value: Binding(get: { need }, set: { need = $0; loyDirty = true }), in: 2...30) {
                HStack { Text("عدد الأختام"); Spacer(); Text("\(need)").bold().monospacedDigit().foregroundStyle(Color.ink) }
            }
            Text("\(need) \(unit == "cup" ? "أكواب" : "طلبات") والي بعده مجاناً (الـ \(need + 1) علينا)").font(.footnote).foregroundStyle(.secondary)
            StampRow(filled: need / 2, need: need, size: need > 8 ? 20 : 26).padding(.vertical, 4)
            Picker("", selection: Binding(get: { unit }, set: { unit = $0; loyDirty = true })) {
                Text("ختم لكل كوب").tag("cup"); Text("ختم لكل طلب").tag("order")
            }
            .pickerStyle(.segmented)
            if loyDirty {
                Button("احفظ نظام الولاء") { Task { await post("save_loyalty", ["on": loyOn, "need": need, "unit": unit], "انحفظ، والبطاقات اللي في المحافظ بتتحدث") } }.bold()
            }
        }
    }

    private func staff(_ users: [J]) -> some View {
        Section("حسابات العمال") {
            ForEach(users, id: \.self) { u in
                let owner = u["role"].string == "owner"
                HStack(spacing: 12) {
                    Image(systemName: owner ? "star.fill" : "person.fill")
                        .foregroundStyle(owner ? Color.cream : Color.ink)
                        .frame(width: 36, height: 36).background(owner ? Color.brand : Color.ink.opacity(0.14), in: Circle())
                    VStack(alignment: .leading) {
                        Text(u["username"].string).font(.body.weight(.semibold))
                        Text(owner ? "صاحب المحل" : (u["active"].int == 1 ? "عامل · شغال" : "عامل · موقوف")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !owner {
                        Button { pwFor = u } label: { Image(systemName: "lock.fill") }.buttonStyle(.borderless)
                        Toggle("", isOn: Binding(get: { u["active"].int == 1 }, set: { v in Task { await post("user_update", ["id": u["id"].int, "active": v], v ? "رجع الحساب يشتغل" : "انوقف الحساب") } }))
                            .labelsHidden()
                    }
                }
            }
            Button { addingUser = true } label: { Label("حساب عامل جديد", systemImage: "person.badge.plus") }
        }
    }

    private func load() async {
        do {
            let r = try await API.shared.get("settings")
            s = r; err = nil
            BizStore.shared.absorb(r)
            loyOn = r["loyalty"]["on"].bool
            need = r["loyalty"]["need"].isNull ? 6 : r["loyalty"]["need"].int
            unit = r["loyalty"]["unit"].string.isEmpty ? "cup" : r["loyalty"]["unit"].string
            loyDirty = false
            design = r["design"].string == "new" ? "new" : "old"
            wa = r["whatsapp"].string.replacingOccurrences(of: "+968", with: "")
            for (k, _) in kChannels { comm[k] = shortNumber(r["commissions"][k].double) }
        } catch { err = errText(error) }
    }

    private func save(_ action: String, _ body: [String: Any], _ done: String) async { await post(action, body, done) }

    private func post(_ action: String, _ body: [String: Any], _ done: String) async {
        do {
            try await API.shared.post(action, body)
            toaster.show(done)
            await load()
        } catch { toaster.show(errText(error), ok: false) }
    }
}

private struct ProductRow: View {
    let p: J
    let save: (String, [String: Any], String) async -> Void
    @State private var price = ""
    @State private var active = false
    @State private var dirty = false
    @State private var editingDesc = false
    @State private var ar = ""
    @State private var en = ""

    init(p: J, save: @escaping (String, [String: Any], String) async -> Void) {
        self.p = p; self.save = save
        _price = State(initialValue: money(p["price"]))
        _active = State(initialValue: p["active"].int == 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(itemName(p)).font(.body.weight(.semibold)).foregroundStyle(active ? Color.primary : Color.secondary).strikethrough(!active)
                        if p["soldout"].int == 1 {
                            Button { Task { await save("soldout", ["id": p["id"].int, "soldout": false], "رجع الصنف") } } label: {
                                Tag(text: "خالص · رجّعه", bg: Color.bad.opacity(0.14), fg: .bad)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    if p["kind"].string == "build" { Text("سعر الباول بدون الإضافات").font(.caption2).foregroundStyle(.secondary) }
                    Button { ar = p["desc_ar"].string; en = p["desc_en"].string; editingDesc = true } label: {
                        Text(p["desc_ar"].string.isEmpty ? "+ أضف وصف" : p["desc_ar"].string).font(.caption).lineLimit(2).foregroundStyle(Color.ink)
                    }
                    .buttonStyle(.borderless)
                }
                Spacer()
                TextField("0.000", text: $price).keyboardType(.decimalPad).multilineTextAlignment(.center)
                    .frame(width: 70).padding(6).background(Color.pageBG, in: RoundedRectangle(cornerRadius: 8))
                    .onChange(of: price) { _, _ in dirty = true }
                Toggle("", isOn: $active).labelsHidden().onChange(of: active) { _, _ in dirty = true }
            }
            if dirty {
                Button {
                    guard let v = Double(price), v >= 0 else { return }
                    Task { await save("save_product", ["id": p["id"].int, "price": v, "active": active], "انحفظ"); dirty = false }
                } label: { Label("احفظ", systemImage: "checkmark") }
                .buttonStyle(.borderless).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .alert("وصف \(p["name_ar"].string)", isPresented: $editingDesc) {
            TextField("بالعربي", text: $ar)
            TextField("English", text: $en)
            Button("إلغاء", role: .cancel) {}
            Button("احفظ") {
                Task { await save("save_product", ["id": p["id"].int, "price": Double(price) ?? 0, "active": active, "desc_ar": ar, "desc_en": en], "انحفظ الوصف") }
            }
        }
    }
}

private struct ToppingRow: View {
    let t: J
    let save: (String, [String: Any], String) async -> Void
    @State private var price = ""
    @State private var active = false
    @State private var dirty = false

    init(t: J, save: @escaping (String, [String: Any], String) async -> Void) {
        self.t = t; self.save = save
        _price = State(initialValue: money(t["price"]))
        _active = State(initialValue: t["active"].int == 1)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(t["name_ar"].string).foregroundStyle(active ? Color.primary : Color.secondary)
            Spacer()
            Text("+").foregroundStyle(.secondary)
            TextField("0.000", text: $price).keyboardType(.decimalPad).multilineTextAlignment(.center)
                .frame(width: 64).padding(6).background(Color.pageBG, in: RoundedRectangle(cornerRadius: 8))
                .onChange(of: price) { _, _ in dirty = true }
            Toggle("", isOn: $active).labelsHidden().onChange(of: active) { _, _ in dirty = true }
            if dirty {
                Button {
                    guard let v = Double(price), v >= 0 else { return }
                    Task { await save("save_topping", ["id": t["id"].int, "price": v, "active": active], "انحفظت الإضافة"); dirty = false }
                } label: { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.good) }
                .buttonStyle(.borderless)
            }
        }
    }
}

/// Owner adds a menu item; Karak Dose items can come in two sizes with a price each.
struct AddItemSheet: View {
    let cats: [J]
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var ar = ""
    @State private var en = ""
    @State private var cat = ""
    @State private var sizes = "one"
    @State private var p1 = ""
    @State private var p2 = ""
    @State private var busy = false
    @State private var err = ""

    private var labels: (String, String, String, String) {
        sizes == "sl" ? ("small", "large", "صغير", "كبير") : ("meal", "regular", "وجبة", "عادي")
    }

    var body: some View {
        FormSheet(title: "صنف جديد", saveText: "أضف", busy: busy, err: err, canSave: !ar.trimmingCharacters(in: .whitespaces).isEmpty && (Double(p1) ?? 0) > 0, onSave: { Task { await save() } }) {
            Section {
                TextField("الاسم بالعربي", text: $ar)
                TextField("English name (للكاشير)", text: $en).environment(\.layoutDirection, .leftToRight)
                if !cats.isEmpty {
                    Picker("القسم", selection: $cat) { ForEach(cats, id: \.self) { c in Text(c["ar"].string).tag(c["k"].string) } }
                }
            }
            Section {
                Picker("الأحجام", selection: $sizes) {
                    Text("سعر واحد").tag("one"); Text("صغير وكبير").tag("sl"); Text("وجبة وعادي").tag("mr")
                }
                .pickerStyle(.segmented)
                HStack { Text(sizes == "one" ? "السعر" : labels.2); Spacer(); TextField("0.000", text: $p1).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100); Text("ر.ع").foregroundStyle(.secondary) }
                if sizes != "one" {
                    HStack { Text(labels.3); Spacer(); TextField("0.000", text: $p2).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100); Text("ر.ع").foregroundStyle(.secondary) }
                }
            }
        }
        .onAppear { if cat.isEmpty { cat = cats.first?["k"].string ?? "" } }
    }

    private func save() async {
        busy = true; err = ""
        var body: [String: Any] = ["name_ar": ar.trimmingCharacters(in: .whitespaces), "name_en": en.trimmingCharacters(in: .whitespaces), "cat": cat]
        if sizes == "one" { body["price"] = Double(p1) ?? 0 }
        else { body["prices"] = [labels.0: Double(p1) ?? 0, labels.1: Double(p2) ?? 0] }
        do { try await API.shared.post("product_add", body); onDone(); dismiss() } catch { err = errText(error); busy = false }
    }
}
