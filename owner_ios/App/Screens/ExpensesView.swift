import SwiftUI

struct NameAmount: Identifiable { let id: String; let v: Double }

struct ExpensesView: View {
    @Environment(Period.self) private var period
    @Environment(Toaster.self) private var toaster
    @State private var exps: [J] = []
    @State private var loading = false
    @State private var adding = false
    @State private var toDelete: J?

    var body: some View {
        let total = exps.reduce(0) { $0 + $1["amount"].double }
        let byCat = Dictionary(grouping: exps, by: { $0["category"].string }).mapValues { $0.reduce(0) { $0 + $1["amount"].double } }
            .sorted { $0.value > $1.value }.map { NameAmount(id: $0.key, v: $0.value) }
        List {
            Section {
                PeriodBar().listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                VStack(alignment: .leading, spacing: 8) {
                    Text("مصاريف الفترة").font(.subheadline.weight(.semibold)).foregroundStyle(Color.lilac)
                    Text(money(total)).font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Color.cream)
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
            Section {
                if exps.isEmpty && !loading { EmptyNote(text: "ما فيه مصاريف في هالفترة", icon: "creditcard").listRowBackground(Color.clear) }
                ForEach(exps.indices, id: \.self) { i in
                    let r = exps[i]
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r["category"].string).font(.subheadline.weight(.semibold))
                            Text(r["expense_date"].string + (r["note"].string.isEmpty ? "" : " · \(r["note"].string)")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(money(r["amount"])).font(.headline).monospacedDigit()
                    }
                    .swipeActions { Button(role: .destructive) { toDelete = r } label: { Label("احذف", systemImage: "trash") } }
                }
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
        .confirmationDialog("تحذف هذا المصروف؟", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button("احذف", role: .destructive) { if let r = toDelete { Task { await delete(r) } } }
            Button("إلغاء", role: .cancel) {}
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
