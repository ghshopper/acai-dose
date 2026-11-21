import SwiftUI

struct NameAmount: Identifiable { let id: String; let v: Double }

/// Fixed costs: what repeats every month (rent, salaries, the monthly entries, past monthly totals).
func isFixedExpense(_ r: J) -> Bool {
    let cat = r["category"].string, note = r["note"].string
    return note.hasPrefix("شهري") || ["مصاريف ثابتة", "إيجار", "رواتب", "راتب"].contains(cat) || note.contains("المصاريف الثابتة")
}

struct ExpensesView: View {
    @Environment(Period.self) private var period
    @Environment(Toaster.self) private var toaster
    @State private var exps: [J] = []
    @State private var loading = false
    @State private var adding = false
    @State private var toDelete: J?
    @State private var editing: J?

    var body: some View {
        let total = exps.reduce(0) { $0 + $1["amount"].double }
        let fixed = exps.filter(isFixedExpense), other = exps.filter { !isFixedExpense($0) }
        let fixedT = fixed.reduce(0) { $0 + $1["amount"].double }, otherT = total - fixedT
        let byCat = Dictionary(grouping: exps, by: { $0["category"].string }).mapValues { $0.reduce(0) { $0 + $1["amount"].double } }
            .sorted { $0.value > $1.value }.map { NameAmount(id: $0.key, v: $0.value) }
        List {
            Section {
                PeriodBar().listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                VStack(alignment: .leading, spacing: 8) {
                    Text("مصاريف الفترة").font(.subheadline.weight(.semibold)).foregroundStyle(Color.lilac)
                    Text(money(total)).font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Color.cream)
                    HStack(spacing: 10) {
                        split("ثابتة", fixedT, total)
                        split("متغيرة", otherT, total)
                    }
                    .padding(.bottom, 4)
                    ForEach(byCat) { c in
                        VStack(spacing: 4) {
                            HStack {
                                Text(c.id).font(.footnote).foregroundStyle(Color.cream)
                                Spacer()
                                Text(money(c.v)).font(.footnote.bold()).monospacedDigit().foregroundStyle(Color.cream)
                            }
                            ThinBar(value: total > 0 ? c.v / total : 0, track: Color.brand2, height: 5)
                        }
                    }
                }
                .padding(18)
                .background(Color.brand, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
            }
            if exps.isEmpty && !loading {
                Section { EmptyNote(text: "ما فيه مصاريف في هالفترة", icon: "creditcard").listRowBackground(Color.clear) }
            }
            if !fixed.isEmpty {
                Section {
                    ForEach(fixed.indices, id: \.self) { i in row(fixed[i]) }
                } header: { secHeader("المصاريف الثابتة", fixedT) }
            }
            if !other.isEmpty {
                Section {
                    ForEach(other.indices, id: \.self) { i in row(other[i]) }
                } header: { secHeader("المصاريف الثانية", otherT) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("المصاريف")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { if loading { ProgressView() } }
            ToolbarItem(placement: .topBarTrailing) { Button { adding = true } label: { Image(systemName: "plus.circle.fill").font(.title3) } }
        }
        .refreshable { await load() }
        .task(id: period.version) { await load() }
        .sheet(isPresented: $adding) { AddExpenseSheet { toaster.show("انحفظ المصروف"); Task { await load() } } }
        .sheet(item: Binding(get: { editing.map { EditBox(j: $0) } }, set: { editing = $0?.j })) { b in
            AddExpenseSheet(existing: b.j) { toaster.show("انعدّل المصروف"); Task { await load() } }
        }
        .confirmationDialog("تحذف هذا المصروف؟", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button("احذف", role: .destructive) { if let r = toDelete { Task { await delete(r) } } }
            Button("إلغاء", role: .cancel) {}
        }
    }

    private func split(_ label: String, _ v: Double, _ total: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label + (total > 0 ? " · \(Int((v / total * 100).rounded()))%" : "")).font(.caption2.weight(.semibold)).foregroundStyle(Color.lilac)
            Text(money(v)).font(.subheadline.bold()).monospacedDigit().foregroundStyle(Color.cream)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func secHeader(_ t: String, _ v: Double) -> some View {
        HStack {
            Text(t).font(.subheadline.weight(.bold))
            Spacer()
            Text(money(v)).font(.subheadline.bold()).monospacedDigit()
        }
        .foregroundStyle(Color.ink)
        .textCase(nil)
    }

    private func row(_ r: J) -> some View {
        Button { editing = r } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r["category"].string).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                    Text(r["expense_date"].string + (r["paid_from"].string == "cash" ? " · كاش" : r["paid_from"].string == "custody" ? " · من العهدة" : " · تحويل") + (r["note"].string.isEmpty ? "" : " · \(r["note"].string)")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(money(r["amount"])).font(.headline).monospacedDigit().foregroundStyle(Color.primary)
                Image(systemName: "chevron.left").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .swipeActions {
            Button(role: .destructive) { toDelete = r } label: { Label("احذف", systemImage: "trash") }
            Button { editing = r } label: { Label("عدّل", systemImage: "pencil") }.tint(.accent2)
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        if let r = try? await API.shared.get("range", ["from": period.fromStr, "to": period.toStr]) { exps = r["exps"].array }
    }

    private func delete(_ r: J) async {
        do {
            try await API.shared.post("delete", ["type": "expense", "id": r["id"].int])
            toaster.show("انحذف المصروف")
        } catch { toaster.show(errText(error), ok: false) }
        await load()
    }
}

/// Wraps a row so a sheet can be opened for it.
struct EditBox: Identifiable { let j: J; var id: Int { j["id"].int } }
