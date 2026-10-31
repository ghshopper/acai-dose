import SwiftUI

/// Money the delivery apps owe the shop (sales after commission minus their transfers) and the company account balance.
struct AccountsView: View {
    @Environment(Toaster.self) private var toaster
    @State private var r: J?
    @State private var err: String?
    @State private var payFor: EditBox?       // channel row the transfer sheet is for
    @State private var moveReq: KindBox?      // money in / out / from my pocket, for one account
    @State private var openingFor: String?    // account whose opening balance is being set
    @State private var opening = ""
    @State private var naming: String?        // "" = new account, else the account being renamed
    @State private var accName = ""
    @State private var toDelete: J?
    @State private var editingMove: EditBox?

    var body: some View {
        Group {
            if let r { content(r) }
            else if let err { EmptyNote(text: err, icon: "wifi.exclamationmark") }
            else { ProgressView() }
        }
        .navigationTitle("الحسابات")
        .refreshable { await load() }
        .task { await load() }
        .sheet(item: $payFor) { b in
            PayoutSheet(channel: b.j, accounts: r?["accounts"].array ?? []) { toaster.show("انسجّل التحويل"); Task { await load() } }
        }
        .sheet(item: $editingMove) { b in
            MoveEditSheet(move: b.j, accounts: r?["accounts"].array ?? []) { toaster.show("انعدّلت"); Task { await load() } }
        }
        .sheet(item: $moveReq) { b in
            BankMoveSheet(kind: b.kind, acct: b.acct, acctName: b.name) { toaster.show("انحفظ"); Task { await load() } }
        }
        .alert("الرصيد الافتتاحي", isPresented: Binding(get: { openingFor != nil }, set: { if !$0 { openingFor = nil } })) {
            TextField("0.000", text: $opening).keyboardType(.decimalPad)
            Button("إلغاء", role: .cancel) {}
            Button("احفظ") { let k = openingFor ?? "main"; Task { await post("bank_opening", ["acct": k, "amount": Double(opening) ?? 0], "انحفظ الرصيد") } }
        } message: { Text("كم كان في الحساب قبل ما يبدأ التطبيق يحسب") }
        .alert(naming == "" ? "حساب جديد" : "اسم الحساب", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("مثلاً: حساب المغسلة", text: $accName)
            if naming == "" { TextField("الرصيد الحين (اختياري)", text: $opening).keyboardType(.decimalPad) }
            Button("إلغاء", role: .cancel) {}
            Button("احفظ") {
                var b: [String: Any] = ["name": accName.trimmingCharacters(in: .whitespaces)]
                if let k = naming, !k.isEmpty { b["k"] = k } else { b["opening"] = Double(opening) ?? 0 }
                Task { await post("bank_account_save", b, "انحفظ الحساب") }
            }
        }
        .confirmationDialog("تحذف هذي الحركة؟", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button("احذف", role: .destructive) { if let m = toDelete { Task { await post("move_delete", ["type": m["type"].string, "id": m["id"].int], "انحذفت") } } }
            Button("إلغاء", role: .cancel) {}
        }
    }

    private func content(_ r: J) -> some View {
        let bank = r["bank"]
        return List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(r["accounts"].array.count > 1 ? "في كل الحسابات" : "رصيد حساب الشركة").font(.subheadline.weight(.semibold)).foregroundStyle(Color.lilac)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(money(r["total_balance"].isNull ? bank["balance"] : r["total_balance"])).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Color.cream)
                        Text("ر.ع").font(.headline).foregroundStyle(Color.lilac)
                    }
                    if r["accounts"].array.count > 1 {
                        ForEach(r["accounts"].array, id: \.self) { a in
                            HStack {
                                Text(a["name"].string).font(.footnote.weight(.semibold)).foregroundStyle(Color.lilac)
                                Spacer()
                                Text(money(a["balance"])).font(.footnote.bold()).monospacedDigit().foregroundStyle(Color.cream)
                            }
                        }
                    }
                    HStack {
                        Text("باقي على التطبيقات").font(.footnote.weight(.semibold)).foregroundStyle(Color.lilac)
                        Spacer()
                        Text("\(money(r["owed_total"])) ر.ع").font(.footnote.bold()).monospacedDigit().foregroundStyle(Color.accent2)
                    }
                }
                .padding(18)
                .background(LinearGradient(colors: [.brand, .brand2], startPoint: .topTrailing, endPoint: .bottomLeading), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
            }

            Section {
                ForEach(r["channels"].array, id: \.self) { c in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(c["ar"].string).font(.headline)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 0) {
                                Text("باقي عليهم").font(.caption2).foregroundStyle(.secondary)
                                Text("\(money(c["owed"])) ر.ع").font(.title3.bold()).monospacedDigit()
                                    .foregroundStyle(c["owed"].double > 0.0005 ? Color.ink : Color.good)
                            }
                        }
                        line("المبيعات", money(c["gross"]))
                        line("العمولة", "− " + money(c["commission"]))
                        line("المفروض يحولون", money(c["net"]))
                        line("حوّلوا", money(c["paid"]) + (c["last_paid"].string.isEmpty ? "" : " · آخر مرة \(c["last_paid"].string)"))
                        if r["accounts"].array.count > 1 {
                            HStack {
                                Text("يحوّلون على").font(.subheadline).foregroundStyle(.secondary)
                                Spacer()
                                Picker("", selection: Binding(get: { c["acct"].string.isEmpty ? "main" : c["acct"].string },
                                                              set: { v in Task { await post("channel_account", ["channel": c["k"].string, "acct": v], "انحفظ") } })) {
                                    ForEach(r["accounts"].array, id: \.self) { a in Text(a["name"].string).tag(a["k"].string) }
                                }
                                .labelsHidden()
                            }
                        }
                        Button { payFor = EditBox(j: c) } label: { Label("سجّل تحويل من \(c["ar"].string)", systemImage: "arrow.down.circle.fill") }
                            .buttonStyle(.borderless).padding(.top, 2)
                    }
                    .padding(.vertical, 4)
                }
            } header: { Text("التطبيقات") } footer: { Text("المبيعات من الكاشير ومبيعات التطبيقات اللي تدخلها، بعد العمولة، ناقص اللي حولوه") }

            ForEach(r["accounts"].array, id: \.self) { a in
                let k = a["k"].string, main = k == "main"
                Section {
                    line("الرصيد الافتتاحي", money(a["opening"]))
                    if main { line("مبيعات البطاقة", money(a["card"])) }
                    line("تحويلات التطبيقات", money(a["payouts"]))
                    line("إيداعات ومن جيبي", money(a["in"]))
                    if main { line("المصاريف", "− " + money(a["expenses"])) }
                    line("سحوبات ومدفوعات", "− " + money(a["out"]))
                    HStack {
                        Text("الرصيد").font(.subheadline.weight(.bold))
                        Spacer()
                        Text("\(money(a["balance"])) ر.ع").font(.headline).monospacedDigit().foregroundStyle(a["balance"].double < 0 ? Color.bad : Color.ink)
                    }
                    HStack(spacing: 16) {
                        Button { moveReq = KindBox(kind: "in", acct: k, name: a["name"].string) } label: { Label("إيداع", systemImage: "plus.circle.fill") }.buttonStyle(.borderless)
                        Button { moveReq = KindBox(kind: "out", acct: k, name: a["name"].string) } label: { Label("سحب / دفع", systemImage: "minus.circle.fill") }.buttonStyle(.borderless).tint(.bad)
                        Button { moveReq = KindBox(kind: "cap", acct: k, name: a["name"].string) } label: { Label("من جيبي", systemImage: "person.crop.circle.badge.plus") }.buttonStyle(.borderless).tint(.good)
                    }
                    HStack(spacing: 16) {
                        Button("الافتتاحي") { opening = shortNumber(a["opening"].double); openingFor = k }.buttonStyle(.borderless).font(.footnote)
                        Button("غيّر الاسم") { accName = a["name"].string; naming = k }.buttonStyle(.borderless).font(.footnote)
                        if !main {
                            Spacer()
                            Button("احذف", role: .destructive) { Task { await post("bank_account_delete", ["k": k], "انحذف الحساب") } }.buttonStyle(.borderless).font(.footnote)
                        }
                    }
                } header: { Text(a["name"].string) } footer: {
                    if main { Text("مبيعات البطاقة تدخله، والمصاريف تنقص منه. الكاش يظل في الدرج لين تسجّله «إيداع».") }
                }
            }
            Section {
                Button { accName = ""; opening = ""; naming = "" } label: { Label("أضف حساب ثاني", systemImage: "building.columns.fill") }
            } footer: { Text("مثلاً حساب تحوّل عليه طلبات، وتختاره فوق عند التطبيق") }

            Section {
                let moves = r["moves"].array
                if moves.isEmpty { Text("ما فيه حركات للحين").foregroundStyle(.secondary) }
                ForEach(moves, id: \.self) { m in
                    let out = m["type"].string == "out"
                    Button { editingMove = EditBox(j: m) } label: {
                    HStack {
                        Image(systemName: out ? "arrow.up.right.circle.fill" : "arrow.down.left.circle.fill").foregroundStyle(out ? Color.bad : Color.good)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(m)).font(.subheadline.weight(.semibold))
                            Text(m["date"].string + (r["accounts"].array.count > 1 && !m["acct_name"].string.isEmpty ? " · \(m["acct_name"].string)" : "") + (m["note"].string.isEmpty ? "" : " · \(m["note"].string)")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text((out ? "− " : "+ ") + money(m["amount"])).font(.subheadline.bold()).monospacedDigit().foregroundStyle(out ? Color.bad : Color.good)
                    }
                    .foregroundStyle(Color.primary)
                    }
                    .swipeActions {
                        Button(role: .destructive) { toDelete = m } label: { Label("احذف", systemImage: "trash") }
                        Button { editingMove = EditBox(j: m) } label: { Label("عدّل", systemImage: "pencil") }.tint(.accent2)
                    }
                }
            } header: { Text("آخر الحركات") } footer: { Text("اضغط على أي حركة عشان تعدّل المبلغ أو التاريخ") }
        }
        .listStyle(.insetGrouped)
    }

    private func title(_ m: J) -> String {
        switch m["type"].string {
        case "payout": return "تحويل من \(kChannelNames[m["channel"].string] ?? m["channel"].string)"
        case "in": return "إيداع"
        case "cap": return "دفعت من جيبي"
        default: return "سحب / دفع"
        }
    }

    private func line(_ a: String, _ b: String) -> some View {
        HStack {
            Text(a).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(b).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }

    private func load() async {
        do { r = try await API.shared.get("accounts"); err = nil } catch { err = errText(error) }
    }

    private func post(_ a: String, _ body: [String: Any], _ done: String) async {
        do { try await API.shared.post(a, body); toaster.show(done) } catch { toaster.show(errText(error), ok: false) }
        await load()
    }
}

struct KindBox: Identifiable { let kind: String; var acct = "main"; var name = ""; var id: String { kind + acct } }

/// Picker of the shop's accounts, shown only when there is more than one.
struct AccountPicker: View {
    let accounts: [J]
    @Binding var acct: String
    var body: some View {
        if accounts.count > 1 {
            Picker("على حساب", selection: $acct) { ForEach(accounts, id: \.self) { a in Text(a["name"].string).tag(a["k"].string) } }
        }
    }
}

/// Records money a delivery app transferred.
struct PayoutSheet: View {
    let channel: J
    var accounts: [J] = []
    let onDone: () -> Void
    @State private var acct = "main"
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var date = Date.now
    @State private var note = ""
    @State private var busy = false
    @State private var err = ""

    var body: some View {
        FormSheet(title: "تحويل من \(channel["ar"].string)", busy: busy, err: err, canSave: (Double(amount) ?? 0) > 0, onSave: { Task { await save() } }) {
            Section {
                HStack { TextField("المبلغ", text: $amount).keyboardType(.decimalPad).font(.title2.bold()); Text("ر.ع").foregroundStyle(.secondary) }
                if channel["owed"].double > 0.0005 {
                    Button("كل الباقي: \(money(channel["owed"])) ر.ع") { amount = shortNumber(channel["owed"].double) }
                }
                DatePicker("تاريخ التحويل", selection: $date, in: ...Date.now, displayedComponents: .date)
                AccountPicker(accounts: accounts, acct: $acct)
                TextField("ملاحظة (اختياري)", text: $note)
            } footer: { Text("باقي عليهم الحين \(money(channel["owed"])) ر.ع") }
        }
        .onAppear { acct = channel["acct"].string.isEmpty ? "main" : channel["acct"].string }
    }

    private func save() async {
        guard let a = Double(amount), a > 0 else { err = "اكتب المبلغ"; return }
        busy = true; err = ""
        do {
            try await API.shared.post("payout_add", ["channel": channel["k"].string, "amount": a, "date": ymd(date), "note": note.trimmingCharacters(in: .whitespaces), "acct": acct])
            onDone(); dismiss()
        } catch { err = errText(error); busy = false }
    }
}

/// Other money into or out of the company account.
struct BankMoveSheet: View {
    let kind: String
    var acct = "main"
    var acctName = ""
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var date = Date.now
    @State private var note = ""
    @State private var busy = false
    @State private var err = ""

    var body: some View {
        FormSheet(title: kind == "out" ? "سحب أو دفع من الحساب" : kind == "cap" ? "دفعت من جيبي للمحل" : "إيداع في الحساب", busy: busy, err: err, canSave: (Double(amount) ?? 0) > 0, onSave: { Task { await save() } }) {
            Section {
                HStack { TextField("المبلغ", text: $amount).keyboardType(.decimalPad).font(.title2.bold()); Text("ر.ع").foregroundStyle(.secondary) }
                DatePicker("التاريخ", selection: $date, in: ...Date.now, displayedComponents: .date)
                TextField(kind == "out" ? "على شنو؟ (إيجار، سحب…)" : kind == "cap" ? "على شنو؟ (رواتب، إيجار…)" : "من وين؟ (كاش الدرج…)", text: $note)
            } footer: { if !acctName.isEmpty { Text(acctName) } }
        }
    }

    private func save() async {
        guard let a = Double(amount), a > 0 else { err = "اكتب المبلغ"; return }
        busy = true; err = ""
        do {
            try await API.shared.post("bank_move_add", ["kind": kind, "amount": a, "date": ymd(date), "note": note.trimmingCharacters(in: .whitespaces), "acct": acct])
            onDone(); dismiss()
        } catch { err = errText(error); busy = false }
    }
}

/// Change a recorded transfer, deposit or withdrawal.
struct MoveEditSheet: View {
    let move: J
    var accounts: [J] = []
    let onDone: () -> Void
    @State private var acct = "main"
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var date = Date.now
    @State private var note = ""
    @State private var channel = ""
    @State private var kind = "in"
    @State private var busy = false
    @State private var err = ""

    private var isPayout: Bool { move["type"].string == "payout" }

    var body: some View {
        FormSheet(title: isPayout ? "عدّل التحويل" : "عدّل الحركة", busy: busy, err: err, canSave: (Double(amount) ?? 0) > 0, onSave: { Task { await save() } }) {
            Section {
                if isPayout {
                    Picker("التطبيق", selection: $channel) { ForEach(kChannels.map { $0.0 }, id: \.self) { k in Text(kChannelNames[k] ?? k).tag(k) } }
                } else {
                    Picker("النوع", selection: $kind) { Text("إيداع").tag("in"); Text("من جيبي").tag("cap"); Text("سحب / دفع").tag("out") }.pickerStyle(.segmented)
                }
                HStack { TextField("المبلغ", text: $amount).keyboardType(.decimalPad).font(.title2.bold()); Text("ر.ع").foregroundStyle(.secondary) }
                DatePicker("التاريخ", selection: $date, in: ...Date.now, displayedComponents: .date)
                AccountPicker(accounts: accounts, acct: $acct)
                TextField("ملاحظة (اختياري)", text: $note)
            }
        }
        .onAppear {
            acct = move["acct"].string.isEmpty ? "main" : move["acct"].string
            let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "Asia/Muscat"); f.dateFormat = "yyyy-MM-dd"
            date = f.date(from: move["date"].string) ?? .now
            amount = shortNumber(move["amount"].double)
            note = move["note"].string
            channel = move["channel"].string
            kind = ["out", "cap"].contains(move["type"].string) ? move["type"].string : "in"
        }
    }

    private func save() async {
        guard let a = Double(amount), a > 0 else { err = "اكتب المبلغ"; return }
        busy = true; err = ""
        do {
            try await API.shared.post("move_update", ["type": move["type"].string, "id": move["id"].int, "amount": a, "date": ymd(date),
                                                      "note": note.trimmingCharacters(in: .whitespaces), "channel": channel, "kind": kind, "acct": acct])
            onDone(); dismiss()
        } catch { err = errText(error); busy = false }
    }
}
