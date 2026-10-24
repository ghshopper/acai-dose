import SwiftUI

/// Shared shell for the small "add something" sheets: a form with Cancel / Save.
struct FormSheet<Content: View>: View {
    let title: String
    var saveText = "احفظ"
    let busy: Bool
    let err: String
    let canSave: Bool
    let onSave: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                content()
                if !err.isEmpty { Section { Text(err).foregroundStyle(Color.bad).font(.subheadline.weight(.semibold)) } }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if busy { ProgressView() } else { Button(saveText, action: onSave).bold().disabled(!canSave) }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

struct AddExpenseSheet: View {
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var cat = kCats[0]
    @State private var amount = ""
    @State private var note = ""
    @State private var busy = false
    @State private var err = ""

    var body: some View {
        FormSheet(title: "مصروف جديد", busy: busy, err: err, canSave: Double(amount) ?? 0 > 0, onSave: { Task { await save() } }) {
            Section {
                DatePicker("التاريخ", selection: $date, in: ...Date.now, displayedComponents: .date)
                Picker("النوع", selection: $cat) { ForEach(kCats, id: \.self) { Text($0).tag($0) } }
            }
            Section {
                HStack {
                    TextField("المبلغ", text: $amount).keyboardType(.decimalPad).font(.title2.bold())
                    Text("ر.ع").foregroundStyle(.secondary)
                }
                TextField("ملاحظة (اختياري)", text: $note)
            }
        }
    }

    private func save() async {
        guard let a = Double(amount), a > 0 else { err = "اكتب المبلغ"; return }
        busy = true; err = ""
        do {
            try await API.shared.post("add_expense", ["expense_date": ymd(date), "category": cat, "amount": a, "note": note.trimmingCharacters(in: .whitespaces)])
            onDone(); dismiss()
        } catch { err = errText(error); busy = false }
    }
}

struct AppSaleSheet: View {
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now
    @State private var ch = "talabat"
    @State private var pcts: [String: Double] = [:]
    @State private var gross = ""
    @State private var pct = ""
    @State private var count = ""
    @State private var note = ""
    @State private var busy = false
    @State private var err = ""

    var body: some View {
        let g = Double(gross) ?? 0, p = Double(pct) ?? 0
        FormSheet(title: "مبيعات التطبيقات", busy: busy, err: err, canSave: g > 0, onSave: { Task { await save() } }) {
            Section {
                Picker("التطبيق", selection: $ch) { ForEach(kChannels.map { $0.0 }, id: \.self) { Text(kChannelNames[$0] ?? $0).tag($0) } }
                    .pickerStyle(.segmented)
                    .onChange(of: ch) { _, v in pct = pcts[v].map(shortNumber) ?? "" }
                DatePicker("التاريخ", selection: $date, in: ...Date.now, displayedComponents: .date)
            } footer: { Text("من كشف طلبات أو سنونو أو خدمة، لليوم كامل") }
            Section {
                HStack { TextField("المبيعات", text: $gross).keyboardType(.decimalPad).font(.title2.bold()); Text("ر.ع").foregroundStyle(.secondary) }
                HStack { TextField("العمولة", text: $pct).keyboardType(.decimalPad); Text("%").foregroundStyle(.secondary) }
                TextField("عدد الطلبات", text: $count).keyboardType(.numberPad)
                TextField("ملاحظة (اختياري)", text: $note)
            }
            if g > 0 {
                Section { LabeledContent("يوصلك تقريباً") { Text("\(money(g - g * p / 100)) ر.ع").bold().foregroundStyle(Color.ink) } }
            }
        }
        .task {
            if let r = try? await API.shared.get("settings") {
                pcts = r["commissions"].dict.mapValues(\.double)
                pct = pcts[ch].map(shortNumber) ?? ""
            }
        }
    }

    private func save() async {
        guard let g = Double(gross), g > 0 else { err = "اكتب مبلغ المبيعات"; return }
        let p = Double(pct.isEmpty ? "0" : pct) ?? -1
        guard p >= 0 && p <= 100 else { err = "نسبة العمولة بين 0 و 100"; return }
        busy = true; err = ""
        var body: [String: Any] = ["sale_date": ymd(date), "channel": ch, "gross": g, "commission_pct": p, "note": note.trimmingCharacters(in: .whitespaces)]
        if let n = Int(count) { body["orders_count"] = n }
        do { try await API.shared.post("add_sale", body); onDone(); dismiss() } catch { err = errText(error); busy = false }
    }
}

struct AddCustomerSheet: View {
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""
    @State private var name = ""
    @State private var offers = true
    @State private var busy = false
    @State private var err = ""

    var body: some View {
        FormSheet(title: "عميل جديد", saveText: "أضف", busy: busy, err: err, canSave: phone.count == 8, onSave: { Task { await save() } }) {
            Section {
                HStack {
                    Text("+968").foregroundStyle(.secondary)
                    TextField("9XXXXXXX", text: $phone).keyboardType(.numberPad).font(.title3.weight(.semibold))
                        .onChange(of: phone) { _, v in let d = String(v.filter(\.isNumber).prefix(8)); if d != v { phone = d } }
                }
                .environment(\.layoutDirection, .leftToRight)
                TextField("الاسم (اختياري)", text: $name)
            } header: { Text("رقم الجوال") }
            Section { Toggle("يبي يوصله العروض", isOn: $offers) } footer: { Text("تنضاف له بطاقة ولاء على طول") }
        }
    }

    private func save() async {
        guard phone.range(of: #"^[279]\d{7}$"#, options: .regularExpression) != nil else { err = "الرقم لازم ٨ أرقام"; return }
        busy = true; err = ""
        do {
            try await API.shared.post("customer_add", ["phone": "+968\(phone)", "name": name.trimmingCharacters(in: .whitespaces), "offers": offers])
            onDone(); dismiss()
        } catch { err = errText(error); busy = false }
    }
}
