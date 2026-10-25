import SwiftUI

/// Money the delivery apps owe the shop (sales after commission minus their transfers) and the company account balance.
struct AccountsView: View {
    @Environment(Toaster.self) private var toaster
    @State private var r: J?
    @State private var err: String?
    @State private var payFor: EditBox?       // channel row the transfer sheet is for
    @State private var moveKind: String?      // "in" / "out" sheet
    @State private var editingOpening = false
    @State private var opening = ""
    @State private var toDelete: J?

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
            PayoutSheet(channel: b.j) { toaster.show("انسجّل التحويل"); Task { await load() } }
        }
        .sheet(item: Binding(get: { moveKind.map { KindBox(kind: $0) } }, set: { moveKind = $0?.kind })) { b in
            BankMoveSheet(kind: b.kind) { toaster.show("انحفظ"); Task { await load() } }
        }
        .alert("الرصيد الافتتاحي", isPresented: $editingOpening) {
            TextField("0.000", text: $opening).keyboardType(.decimalPad)
            Button("إلغاء", role: .cancel) {}
            Button("احفظ") { Task { await post("bank_opening", ["amount": Double(opening) ?? 0], "انحفظ الرصيد") } }
        } message: { Text("كم كان في حساب الشركة قبل ما يبدأ التطبيق يحسب") }
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
                    Text("رصيد حساب الشركة").font(.subheadline.weight(.semibold)).foregroundStyle(Color.lilac)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(money(bank["balance"])).font(.system(size: 40, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Color.cream)
                        Text("ر.ع").font(.headline).foregroundStyle(Color.lilac)
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
                        Button { payFor = EditBox(j: c) } label: { Label("سجّل تحويل من \(c["ar"].string)", systemImage: "arrow.down.circle.fill") }
                            .buttonStyle(.borderless).padding(.top, 2)
                    }
                    .padding(.vertical, 4)
                }
            } header: { Text("التطبيقات") } footer: { Text("المبيعات من الكاشير ومبيعات التطبيقات اللي تدخلها، بعد العمولة، ناقص اللي حولوه") }

            Section {
                line("الرصيد الافتتاحي", money(bank["opening"]))
                line("مبيعات البطاقة", money(bank["card"]))
                line("تحويلات التطبيقات", money(bank["payouts"]))
                line("إيداعات", money(bank["in"]))
                line("المصاريف", "− " + money(bank["expenses"]))
                line("سحوبات ومدفوعات أخرى", "− " + money(bank["out"]))
                HStack(spacing: 16) {
                    Button { moveKind = "in" } label: { Label("إيداع", systemImage: "plus.circle.fill") }.buttonStyle(.borderless)
                    Button { moveKind = "out" } label: { Label("سحب / دفع", systemImage: "minus.circle.fill") }.buttonStyle(.borderless).tint(.bad)
                    Spacer()
                    Button("الافتتاحي") { opening = shortNumber(bank["opening"].double); editingOpening = true }.buttonStyle(.borderless).font(.footnote)
                }
            } header: { Text("حساب الشركة") } footer: { Text("المصاريف اللي تسجلها في تبويب المصاريف تنقص من الحساب. الكاش يظل في الدرج لين تودعه، سجّله «إيداع» لما توديه البنك") }

            Section("آخر الحركات") {
                let moves = r["moves"].array
                if moves.isEmpty { Text("ما فيه حركات للحين").foregroundStyle(.secondary) }
                ForEach(moves, id: \.self) { m in
                    let out = m["type"].string == "out"
                    HStack {
                        Image(systemName: out ? "arrow.up.right.circle.fill" : "arrow.down.left.circle.fill").foregroundStyle(out ? Color.bad : Color.good)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title(m)).font(.subheadline.weight(.semibold))
                            Text(m["date"].string + (m["note"].string.isEmpty ? "" : " · \(m["note"].string)")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text((out ? "− " : "+ ") + money(m["amount"])).font(.subheadline.bold()).monospacedDigit().foregroundStyle(out ? Color.bad : Color.good)
                    }
                    .swipeActions { Button(role: .destructive) { toDelete = m } label: { Label("احذف", systemImage: "trash") } }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func title(_ m: J) -> String {
        switch m["type"].string {
        case "payout": return "تحويل من \(kChannelNames[m["channel"].string] ?? m["channel"].string)"
        case "in": return "إيداع"
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

struct KindBox: Identifiable { let kind: String; var id: String { kind } }

/// Records money a delivery app transferred.
struct PayoutSheet: View {
    let channel: J
    let onDone: () -> Void
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
                TextField("ملاحظة (اختياري)", text: $note)
            } footer: { Text("باقي عليهم الحين \(money(channel["owed"])) ر.ع") }
        }
    }

    private func save() async {
        guard let a = Double(amount), a > 0 else { err = "اكتب المبلغ"; return }
        busy = true; err = ""
        do {
            try await API.shared.post("payout_add", ["channel": channel["k"].string, "amount": a, "date": ymd(date), "note": note.trimmingCharacters(in: .whitespaces)])
            onDone(); dismiss()
        } catch { err = errText(error); busy = false }
    }
}

/// Other money into or out of the company account.
struct BankMoveSheet: View {
    let kind: String
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var date = Date.now
    @State private var note = ""
    @State private var busy = false
    @State private var err = ""

    var body: some View {
        FormSheet(title: kind == "out" ? "سحب أو دفع من الحساب" : "إيداع في الحساب", busy: busy, err: err, canSave: (Double(amount) ?? 0) > 0, onSave: { Task { await save() } }) {
            Section {
                HStack { TextField("المبلغ", text: $amount).keyboardType(.decimalPad).font(.title2.bold()); Text("ر.ع").foregroundStyle(.secondary) }
                DatePicker("التاريخ", selection: $date, in: ...Date.now, displayedComponents: .date)
                TextField(kind == "out" ? "على شنو؟ (إيجار، سحب…)" : "من وين؟ (كاش الدرج…)", text: $note)
            }
        }
    }

    private func save() async {
        guard let a = Double(amount), a > 0 else { err = "اكتب المبلغ"; return }
        busy = true; err = ""
        do {
            try await API.shared.post("bank_move_add", ["kind": kind, "amount": a, "date": ymd(date), "note": note.trimmingCharacters(in: .whitespaces)])
            onDone(); dismiss()
        } catch { err = errText(error); busy = false }
    }
}
