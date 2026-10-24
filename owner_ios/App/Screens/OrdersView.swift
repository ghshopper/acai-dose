import SwiftUI

struct OrderItem: Identifiable, Hashable {
    let id: Int
    let j: J
}

struct OrdersView: View {
    @Environment(Period.self) private var period
    @Environment(Toaster.self) private var toaster
    @State private var orders: [J] = []
    @State private var loading = false
    @State private var filter = "all"
    @State private var open: OrderItem?

    private var list: [J] {
        orders.filter {
            switch filter {
            case "web": return $0["source"].string != "pos"
            case "shop": return $0["source"].string == "pos"
            default: return true
            }
        }
    }

    var body: some View {
        let valid = list.filter { $0["status"].string != "cancelled" }
        let sum = valid.reduce(0) { $0 + $1["total"].double }
        List {
            Section {
                PeriodBar().listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                Picker("", selection: $filter) {
                    Text("الكل").tag("all"); Text("الموقع").tag("web"); Text("المحل").tag("shop")
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                HStack {
                    Text("\(valid.count) طلب").font(.headline)
                    Spacer()
                    Text("\(money(sum)) ر.ع").font(.headline).monospacedDigit()
                }
                .foregroundStyle(Color.ink)
                .listRowBackground(Color.clear)
            }
            Section {
                if list.isEmpty && !loading {
                    EmptyNote(text: "ما فيه طلبات في هالفترة", icon: "doc.text").listRowBackground(Color.clear)
                }
                ForEach(list.indices, id: \.self) { i in
                    let o = list[i]
                    Button { open = OrderItem(id: o["id"].int, j: o) } label: { OrderRow(o: o) }
                        .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("الطلبات")
        .toolbar { ToolbarItem(placement: .topBarLeading) { if loading { ProgressView() } } }
        .refreshable { await load() }
        .task(id: period.version) { await load() }
        .sheet(item: $open) { o in
            OrderDetail(order: o.j) { toaster.show("انلغى الطلب"); Task { await load() } }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        if let r = try? await API.shared.get("range", ["from": period.fromStr, "to": period.toStr]) {
            orders = r["orders"].array
        }
    }
}

struct OrderRow: View {
    let o: J
    var body: some View {
        let cancelled = o["status"].string == "cancelled"
        let web = o["source"].string != "pos"
        let items = o["items"].array.map { "\($0["qty"].int)× \($0["name_ar"].string.isEmpty ? $0["name_en"].string : $0["name_ar"].string)" }.joined(separator: "، ")
        let when = o["created_at"].string
        let plate = o["car_plate"].string
        let who = web ? o["customer_name"].string + (plate.isEmpty ? "" : " · \(plate)") : (o["customer_name"].string == "Imported" ? "مبيعات مستوردة" : "المحل")
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("#\(o["ref"].string)").font(.headline).foregroundStyle(Color.ink).environment(\.layoutDirection, .leftToRight)
                Tag(text: web ? "الموقع" : "المحل", bg: web ? Color.accent2.opacity(0.18) : Color.brand.opacity(0.08))
                Tag(text: kStatusNames[o["status"].string] ?? o["status"].string,
                    bg: o["status"].string == "done" ? Color.good.opacity(0.14) : cancelled ? Color.bad.opacity(0.14) : Color.ink.opacity(0.14),
                    fg: o["status"].string == "done" ? .good : cancelled ? .bad : .brand)
                Spacer()
                Text(money(o["total"])).font(.headline).monospacedDigit().strikethrough(cancelled)
            }
            Text(items).font(.subheadline)
            HStack {
                Text(who).font(.caption).foregroundStyle(.secondary)
                Spacer()
                let pay = kPayNames[o["payment"].string] ?? (web ? "ما انستلم" : "")
                let comm = o["commission"].double > 0 ? " · عمولة \(money(o["commission"]))" : ""
                Text("\(pay)\(comm)  \(when.count >= 16 ? String(when.dropFirst(5).prefix(11)) : "")").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .opacity(cancelled ? 0.5 : 1)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// One order in full, with a cancel button.
struct OrderDetail: View {
    let order: J
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(Toaster.self) private var toaster
    @State private var busy = false
    @State private var asking = false

    var body: some View {
        let o = order
        let web = o["source"].string != "pos"
        let cancelled = o["status"].string == "cancelled"
        let imported = o["customer_name"].string == "Imported"
        let phone = o["phone"].string
        let when = o["created_at"].string
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 6) {
                        Tag(text: web ? "الموقع" : (imported ? "مستورد" : "المحل"))
                        Tag(text: kStatusNames[o["status"].string] ?? o["status"].string)
                        if when.count >= 16 { Tag(text: String(when.prefix(16)), icon: "clock") }
                    }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
                if web || !phone.isEmpty {
                    Section("العميل") {
                        LabeledContent("الاسم", value: o["customer_name"].string.isEmpty ? "عميل" : o["customer_name"].string)
                        if !phone.isEmpty {
                            LabeledContent("الجوال") { Text(phone).environment(\.layoutDirection, .leftToRight) }
                            HStack(spacing: 12) {
                                Button { openURL(waLink(phone)) } label: { Label("واتساب", systemImage: "message.fill") }
                                    .buttonStyle(.bordered).tint(.good)
                                Button { openURL("tel:\(phone)") } label: { Label("اتصال", systemImage: "phone.fill") }
                                    .buttonStyle(.bordered)
                            }
                        }
                        if !o["car_plate"].string.isEmpty { LabeledContent("السيارة", value: o["car_plate"].string) }
                    }
                }
                Section("الأصناف") {
                    ForEach(o["items"].array.indices, id: \.self) { i in
                        let it = o["items"].array[i]
                        HStack(spacing: 10) {
                            Text("\(it["qty"].int)").font(.subheadline.bold()).foregroundStyle(Color.ink)
                                .frame(width: 30, height: 30).background(Color.ink.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                            Text(it["name_ar"].string.isEmpty ? it["name_en"].string : it["name_ar"].string).font(.subheadline.weight(.semibold))
                            Spacer()
                            if !it["price"].isNull { Text(money(it["price"].double * Double(max(it["qty"].int, 1)))).foregroundStyle(.secondary).monospacedDigit() }
                        }
                    }
                    if o["discount"].double > 0 { LabeledContent("كوب مجاني (ولاء)", value: "-\(money(o["discount"]))") }
                    if o["commission"].double > 0 { LabeledContent("عمولة التطبيق", value: "-\(money(o["commission"]))") }
                    HStack {
                        Text("الإجمالي").font(.headline)
                        Spacer()
                        Text("\(money(o["total"])) ر.ع").font(.title3.bold()).foregroundStyle(Color.ink).strikethrough(cancelled)
                    }
                    Text(o["payment"].string.isEmpty ? "ما انستلم للحين" : "الدفع: \(kPayNames[o["payment"].string] ?? o["payment"].string)")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if !cancelled && !imported {
                    Section {
                        Button(role: .destructive) { asking = true } label: {
                            HStack { Spacer(); if busy { ProgressView() } else { Label("إلغاء الطلب", systemImage: "xmark.circle") }; Spacer() }
                        }
                        .disabled(busy)
                    }
                }
            }
            .navigationTitle("طلب #\(o["ref"].string)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } } }
            .confirmationDialog("تلغي الطلب #\(o["ref"].string)؟", isPresented: $asking, titleVisibility: .visible) {
                Button("ألغِ الطلب", role: .destructive) { Task { await cancel() } }
                Button("لا", role: .cancel) {}
            } message: { Text("ينشال من المبيعات، وإذا كان له رقم تنشال أختامه.") }
        }
        .presentationDragIndicator(.visible)
    }

    private func cancel() async {
        busy = true
        do {
            try await API.shared.post("order_status", ["id": order["id"].int, "status": "cancelled"])
            Haptics.notify(.success)
            onChanged(); dismiss()
        } catch {
            toaster.show(errText(error), ok: false); busy = false
        }
    }
}
