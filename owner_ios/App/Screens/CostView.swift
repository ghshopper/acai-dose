import SwiftUI

/// "1.25 كغ", "300 غ" or "12 حبة".
func qfmt(_ q: Double, _ unit: String) -> String {
    if unit == "pc" { return "\(q == q.rounded() ? String(Int(q)) : String(format: "%.1f", q)) حبة" }
    if abs(q) >= 1000 {
        var s = String(format: "%.2f", q / 1000)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return "\(s) كغ"
    }
    return "\(Int(q.rounded())) غ"
}

struct PurchaseSheetToken: Identifiable { let id = UUID() }
struct RecipeItem: Identifiable { let id: Int; let p: J }
struct DiffItem: Identifiable { let id = UUID(); let rows: [J] }

/// Cost of each drink, stock with stocktakes, purchases and ingredient prices.
struct CostView: View {
    @Environment(Toaster.self) private var toaster
    @State private var c: J?
    @State private var st: J?
    @State private var err: String?
    @State private var tab = 0
    @State private var buying = false
    @State private var counting = false
    @State private var recipe: RecipeItem?
    @State private var diff: DiffItem?
    @State private var priceFor: J?
    @State private var qty = ""
    @State private var price = ""
    @State private var addingIng = false
    @State private var delPurchase: J?

    private var ings: [J] { c?["ingredients"].array ?? [] }
    private func ing(_ id: Int) -> J? { ings.first { $0["id"].int == id } }

    var body: some View {
        Group {
            if c != nil && st != nil {
                List {
                    Section {
                        Picker("", selection: $tab) { Text("الأكواب").tag(0); Text("المخزون").tag(1); Text("الأسعار").tag(2) }
                            .pickerStyle(.segmented)
                            .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                    }
                    switch tab {
                    case 0: cups
                    case 1: stock
                    default: prices
                    }
                }
                .listStyle(.insetGrouped)
            } else if let err {
                EmptyNote(text: err, icon: "wifi.exclamationmark")
            } else { ProgressView() }
        }
        .navigationTitle("التكلفة والمخزون")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { buying = true } label: { Label("شراء", systemImage: "cart.badge.plus") }.disabled(c == nil)
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $buying) { BuySheet(ingredients: ings.filter { $0["active"].int == 1 }) { toaster.show("انسجل الشراء"); Task { await load() } } }
        .sheet(isPresented: $counting) {
            CountSheet(rows: st?["ingredients"].array ?? []) { rows in
                Task {
                    await load()
                    if rows.isEmpty { toaster.show("انحفظ الجرد، ومن الحين النظام يحسب المخزون") } else { diff = DiffItem(rows: rows) }
                }
            }
        }
        .sheet(item: $recipe) { r in RecipeSheet(product: r.p, ingredients: ings) { toaster.show("انحفظت الوصفة"); Task { await load() } } }
        .sheet(item: $diff) { d in DiffSheet(rows: d.rows) }
        .alert(priceFor?["name_ar"].string ?? "", isPresented: Binding(get: { priceFor != nil }, set: { if !$0 { priceFor = nil } })) {
            TextField(priceFor?["unit"].string == "pc" ? "الكمية (حبة)" : "الكمية (غرام)", text: $qty).keyboardType(.decimalPad)
            TextField("المبلغ (ر.ع)", text: $price).keyboardType(.decimalPad)
            Button("إلغاء", role: .cancel) {}
            Button("احفظ") { if let i = priceFor { Task { await savePrice(i) } } }
        } message: { Text("اكتب آخر مرة اشتريت: الكمية وبكم") }
        .sheet(isPresented: $addingIng) { AddIngredientSheet { toaster.show("انضاف المكوّن"); Task { await load() } } }
        .confirmationDialog("تحذف هذا الشراء؟", isPresented: Binding(get: { delPurchase != nil }, set: { if !$0 { delPurchase = nil } }), titleVisibility: .visible) {
            Button("احذف", role: .destructive) { if let p = delPurchase { Task { await deletePurchase(p) } } }
            Button("إلغاء", role: .cancel) {}
        } message: { Text("إذا كان مسجل في المصاريف ينحذف منها بعد.") }
    }

    // MARK: tabs

    @ViewBuilder private var cups: some View {
        let noPrice = ings.filter { $0["active"].int == 1 && $0["unit_cost"].double == 0 }.map { $0["name_ar"].string }
        if !noPrice.isEmpty {
            Section {
                Label("باقي تحط سعر: \(noPrice.joined(separator: "، ")). بدون السعر التكلفة تطلع أقل من الحقيقة.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.orange)
            }
        }
        Section {
            ForEach((c?["products"].array ?? []).filter { $0["kind"].string != "build" || !$0["recipe"].array.isEmpty }, id: \.self) { p in
                Button { recipe = RecipeItem(id: p["id"].int, p: p) } label: { cupRow(p) }.buttonStyle(.plain)
            }
        } footer: { Text("اضغط على المشروب تعدّل وصفته") }
    }

    private func cupRow(_ p: J) -> some View {
        let has = !p["recipe"].array.isEmpty
        let price = p["price"].double, cost = p["cost"].double, prof = price - cost
        let pct = price > 0 ? Int((prof / price * 100).rounded()) : 0
        let color: Color = pct >= 60 ? .good : pct >= 45 ? .orange : .bad
        return HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(p["name_ar"].string).font(.body.weight(.semibold))
                    if p["active"].int != 1 { Tag(text: "مخفي") }
                }
                Text(has ? "البيع \(money(price)) · التكلفة \(money(cost)) · الربح \(money(prof))" : "ما فيه وصفة · اضغط وأضفها")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if has {
                Text("\(pct)%").font(.headline).monospacedDigit().foregroundStyle(color)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
                    .environment(\.layoutDirection, .leftToRight)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var stock: some View {
        let rows = st?["ingredients"].array ?? []
        let counts = st?["counts"].array ?? []
        Section {
            Text(counts.isEmpty ? "ما سويت جرد للحين. سوّ أول جرد، ومن بعده النظام يحسب اللي المفروض يكون عندك."
                 : "آخر جرد: \(String(counts[0]["at"].string.prefix(16)))\n«المفروض عندك» = الجرد + اللي اشتريته − اللي انستخدم في الأكواب المباعة.")
                .font(.subheadline)
            Button { counting = true } label: { Label(counts.isEmpty ? "سوّ أول جرد" : "سوّ جرد جديد", systemImage: "checkmark.seal.fill").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
        }
        if !counts.isEmpty {
            Section("المفروض عندك الحين") {
                ForEach(rows, id: \.self) { r in
                    let u = r["unit"].string
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r["name_ar"].string).font(.body.weight(.semibold))
                            if !r["last_at"].isNull {
                                Text("جرد \(qfmt(r["last_qty"].double, u)) · اشتريت \(qfmt(r["bought"].double, u)) · انستخدم \(qfmt(r["used"].double, u))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(r["expected"].isNull ? "-" : qfmt(r["expected"].double, u)).font(.headline).foregroundStyle(Color.ink)
                    }
                }
            }
        }
    }

    @ViewBuilder private var prices: some View {
        Section {
            ForEach(ings, id: \.self) { i in
                Button {
                    qty = i["pack_qty"].double > 0 ? String(Int(i["pack_qty"].double.rounded())) : ""
                    price = i["pack_price"].double > 0 ? money(i["pack_price"]) : ""
                    priceFor = i
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(i["name_ar"].string).font(.body.weight(.semibold))
                            Text(i["pack_qty"].double > 0 ? "\(qfmt(i["pack_qty"].double, i["unit"].string)) بـ \(money(i["pack_price"])) ر.ع" : "ما فيه سعر")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        let uc = i["unit_cost"].double
                        Text(uc == 0 ? "-" : (i["unit"].string == "pc" ? "\(money(uc)) / حبة" : "\(money(uc * 1000)) / كغ"))
                            .font(.subheadline.bold()).foregroundStyle(Color.ink)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Button { addingIng = true } label: { Label("مكوّن جديد", systemImage: "plus") }
        } header: { Text("أسعار المكونات") } footer: { Text("اضغط للتعديل") }
        let pur = c?["purchases"].array ?? []
        if !pur.isEmpty {
            Section("آخر المشتريات") {
                ForEach(pur, id: \.self) { p in
                    let i = ing(p["ingredient_id"].int)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(i?["name_ar"].string ?? "?") · \(qfmt(p["qty"].double, i?["unit"].string ?? "g"))").font(.body.weight(.semibold))
                            Text(p["date"].string + (p["note"].string.isEmpty ? "" : " · \(p["note"].string)") + (p["expense"].bool ? " · في المصاريف" : ""))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(money(p["price"])).font(.headline).monospacedDigit()
                    }
                    .swipeActions { Button(role: .destructive) { delPurchase = p } label: { Label("احذف", systemImage: "trash") } }
                }
            }
        }
    }

    // MARK: data

    private func load() async {
        do {
            async let a = API.shared.get("costing")
            async let b = API.shared.get("stock")
            let (x, y) = try await (a, b)
            c = x; st = y; err = nil
        } catch { err = errText(error) }
    }

    private func savePrice(_ i: J) async {
        do {
            try await API.shared.post("ingredient_save", ["id": i["id"].int, "name_ar": i["name_ar"].string, "name_en": i["name_en"].string, "unit": i["unit"].string,
                                                          "pack_qty": Double(qty) ?? 0, "pack_price": Double(price) ?? 0])
            Haptics.notify(.success)
            await load()
        } catch { toaster.show(errText(error), ok: false) }
    }

    private func deletePurchase(_ p: J) async {
        do { try await API.shared.post("purchase_delete", ["id": p["id"].int]); await load() } catch { toaster.show(errText(error), ok: false) }
    }
}

// MARK: - Sheets

private struct BuySheet: View {
    let ingredients: [J]
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var ing = 0
    @State private var qty = ""
    @State private var price = ""
    @State private var note = ""
    @State private var expense = true
    @State private var busy = false
    @State private var err = ""

    var body: some View {
        let pc = ingredients.first { $0["id"].int == ing }?["unit"].string == "pc"
        FormSheet(title: "شراء", busy: busy, err: err, canSave: (Double(qty) ?? 0) > 0 && Double(price) != nil, onSave: { Task { await save() } }) {
            Section {
                Picker("الصنف", selection: $ing) { ForEach(ingredients, id: \.self) { Text($0["name_ar"].string).tag($0["id"].int) } }
                HStack { TextField(pc ? "الكمية" : "الكمية", text: $qty).keyboardType(.decimalPad); Text(pc ? "حبة" : "غرام").foregroundStyle(.secondary) }
                HStack { TextField("المبلغ", text: $price).keyboardType(.decimalPad); Text("ر.ع").foregroundStyle(.secondary) }
                TextField("ملاحظة (اختياري)، مثلاً: المورد", text: $note)
            }
            Section { Toggle("سجّلها في المصاريف", isOn: $expense) }
        }
        .onAppear { if ing == 0 { ing = ingredients.first?["id"].int ?? 0 } }
    }

    private func save() async {
        guard let q = Double(qty), q > 0, let p = Double(price), p >= 0 else { err = "اكتب الكمية والمبلغ"; return }
        busy = true; err = ""
        do {
            try await API.shared.post("purchase_add", ["date": ymd(.now), "ingredient_id": ing, "qty": q, "price": p, "note": note.trimmingCharacters(in: .whitespaces), "as_expense": expense])
            onDone(); dismiss()
        } catch { err = errText(error); busy = false }
    }
}

private struct AddIngredientSheet: View {
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var unit = "g"
    @State private var busy = false
    @State private var err = ""

    var body: some View {
        FormSheet(title: "مكوّن جديد", saveText: "أضف", busy: busy, err: err, canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty, onSave: { Task { await save() } }) {
            Section {
                TextField("الاسم، مثلاً: مانجو", text: $name)
                Picker("القياس", selection: $unit) { Text("بالغرام").tag("g"); Text("بالحبة").tag("pc") }.pickerStyle(.segmented)
            }
        }
        .presentationDetents([.medium])
    }

    private func save() async {
        busy = true
        let n = name.trimmingCharacters(in: .whitespaces)
        do { try await API.shared.post("ingredient_save", ["name_ar": n, "name_en": n, "unit": unit]); onDone(); dismiss() }
        catch { err = errText(error); busy = false }
    }
}

private struct CountSheet: View {
    let rows: [J]
    let onDone: ([J]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var vals: [Int: String] = [:]
    @State private var busy = false
    @State private var err = ""

    var body: some View {
        FormSheet(title: "الجرد", saveText: "احفظ الجرد", busy: busy, err: err, canSave: vals.values.contains { !$0.isEmpty }, onSave: { Task { await save() } }) {
            Section {
                ForEach(rows, id: \.self) { r in
                    let id = r["id"].int
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(r["name_ar"].string)
                            Spacer()
                            TextField("0", text: Binding(get: { vals[id] ?? "" }, set: { vals[id] = $0 }))
                                .keyboardType(.decimalPad).multilineTextAlignment(.center).frame(width: 90)
                                .padding(6).background(Color.pageBG, in: RoundedRectangle(cornerRadius: 8))
                            Text(r["unit"].string == "pc" ? "حبة" : "غ").foregroundStyle(.secondary).frame(width: 30)
                        }
                        if !r["expected"].isNull { Text("المفروض \(qfmt(r["expected"].double, r["unit"].string))").font(.caption2).foregroundStyle(.secondary) }
                    }
                }
            } footer: { Text("اكتب الموجود عندك الحين: بالغرام، والأكواب والأغطية بالحبة. اللي ما عديته خلّه فاضي.") }
        }
    }

    private func save() async {
        let items: [[String: Any]] = vals.compactMap { k, v in
            let t = v.trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : ["ingredient_id": k, "qty": Double(t) ?? 0]
        }
        busy = true; err = ""
        do {
            let r = try await API.shared.post("stock_count", ["items": items])
            Haptics.notify(.success)
            onDone(r["diff"].array); dismiss()
        } catch { err = errText(error); busy = false }
    }
}

private struct DiffSheet: View {
    let rows: [J]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rows, id: \.self) { r in
                        let d = r["diff"].double
                        HStack {
                            Text(r["name_ar"].string).font(.body.weight(.semibold))
                            Spacer()
                            Text("\(d > 0 ? "+" : "")\(qfmt(d, r["unit"].string))").bold().foregroundStyle(d < 0 ? Color.bad : Color.good)
                            Text(money(r["value"])).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                } footer: { Text("بالسالب يعني ناقص عن المفروض: هدر، أو زيادة في الكميات، أو بيع ما انسجل. الفرق البسيط طبيعي.") }
            }
            .navigationTitle("الفرق بين الجرد والمفروض")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تمام") { dismiss() } } }
        }
    }
}

private struct RecipeLine: Identifiable { let id = UUID(); var ing: Int; var qty: String }

private struct RecipeSheet: View {
    let product: J
    let ingredients: [J]
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var lines: [RecipeLine] = []
    @State private var busy = false
    @State private var err = ""

    private func ing(_ id: Int) -> J? { ingredients.first { $0["id"].int == id } }
    private var cost: Double { lines.reduce(0) { $0 + (Double($1.qty) ?? 0) * (ing($1.ing)?["unit_cost"].double ?? 0) } }

    var body: some View {
        let price = product["price"].double
        FormSheet(title: product["name_ar"].string, saveText: "احفظ", busy: busy, err: err, canSave: true, onSave: { Task { await save() } }) {
            Section {
                HStack {
                    VStack(alignment: .leading) {
                        Text("التكلفة \(money(cost))").font(.headline)
                        Text("البيع \(money(price))").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(price > 0 ? "\(Int(((price - cost) / price * 100).rounded()))%" : "-").font(.largeTitle.bold()).foregroundStyle(Color.accent2)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            Section {
                ForEach($lines) { $l in
                    HStack {
                        Picker("", selection: $l.ing) { ForEach(ingredients, id: \.self) { Text($0["name_ar"].string).tag($0["id"].int) } }
                            .labelsHidden()
                        Spacer()
                        TextField("0", text: $l.qty).keyboardType(.decimalPad).multilineTextAlignment(.center).frame(width: 70)
                            .padding(6).background(Color.pageBG, in: RoundedRectangle(cornerRadius: 8))
                        Text(ing(l.ing)?["unit"].string == "pc" ? "حبة" : "غ").foregroundStyle(.secondary).frame(width: 28)
                    }
                }
                .onDelete { lines.remove(atOffsets: $0) }
                Button { lines.append(RecipeLine(ing: ingredients.first?["id"].int ?? 0, qty: "")) } label: { Label("مكوّن", systemImage: "plus") }
            } header: { Text("الوصفة") } footer: { Text("اسحب على السطر عشان تحذفه") }
        }
        .onAppear {
            if lines.isEmpty {
                lines = product["recipe"].array.map { r in
                    let q = r["qty"].double
                    return RecipeLine(ing: r["ingredient_id"].int, qty: q == q.rounded() ? String(Int(q)) : String(q))
                }
            }
        }
    }

    private func save() async {
        busy = true; err = ""
        let items: [[String: Any]] = lines.compactMap { l in
            guard let q = Double(l.qty), q > 0 else { return nil }
            return ["ingredient_id": l.ing, "qty": q]
        }
        do { try await API.shared.post("recipe_save", ["product_id": product["id"].int, "items": items]); onDone(); dismiss() }
        catch { err = errText(error); busy = false }
    }
}
