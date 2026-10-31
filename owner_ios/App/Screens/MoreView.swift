import SwiftUI

struct MoreView: View {
    let onLogout: () -> Void
    @Environment(Toaster.self) private var toaster
    @Environment(Live.self) private var live
    @State private var sale = false
    @State private var askLogout = false

    var body: some View {
        List {
            Section {
                HStack {
                    row("building.2.fill", .brand, "المحل", "بدّل بين أساي دوز وكرك دوز")
                    Spacer()
                    BizSwitcher()
                }
            }
            Section {
                NavigationLink { SettingsView() } label: { row("gearshape.fill", .gray, "الإعدادات", "الأسعار، الولاء، العمولات، حسابات العمال") }
                NavigationLink { ReportView() } label: { row("doc.text.magnifyingglass", .brand, "تقرير الشركاء", "المحلين مع بعض، وترسله واتساب بضغطة") }
                NavigationLink { AccountsView() } label: { row("banknote.fill", .accent2, "الحسابات والتحويلات", "كم باقي على التطبيقات، ورصيد حساب الشركة") }
                NavigationLink { CostView() } label: { row("shippingbox.fill", .good, "التكلفة والمخزون", "تكلفة كل كوب، الجرد، المشتريات") }
                Button { sale = true } label: { row("bag.fill", .accent2, "مبيعات التطبيقات", "أدخل مبيعات " + kChannels.map(\.1).joined(separator: " و")) }
            }
            if BizStore.shared.current == .acai {
            Section {
                Toggle(isOn: Binding(get: { live.activityOn }, set: { on in Task { @MainActor in if on { live.start() } else { await live.stop() } } })) {
                    row("bolt.fill", .brand, "تابع الطلبات على شاشة القفل", live.canUseActivities ? "مبيعات وطلبات اليوم في الجزيرة الديناميكية" : "شغّل Live Activities من إعدادات الآيفون")
                }
                .disabled(!live.canUseActivities)
                if let g = live.glance {
                    LabeledContent("اليوم") {
                        Text("\(g.salesText) ر.ع · \(g.orders) طلب").monospacedDigit()
                    }
                }
            } header: { Text("شاشة القفل والويدجت") } footer: {
                Text("أضف ويدجت «أساي دوز» من الشاشة الرئيسية: اضغط مطوّل على الشاشة ← + ← أساي دوز.")
            }
            }
            Section("على الموقع") {
                let site = BizStore.shared.current.site
                if BizStore.shared.current == .acai {
                    link("creditcard.fill", .black, "المحفظة والموقع", "Apple و Google Wallet وموقع المحل", "\(site)/dashboard")
                }
                link("square.and.arrow.down.fill", .blue, "استيراد وتصفير", "المبيعات القديمة من إكسل", "\(site)/dashboard")
                link("link", .brand, "صفحة الطلب", site.replacingOccurrences(of: "https://", with: ""), "\(site)/")
                if BizStore.shared.current == .acai {
                    link("eye.fill", .indigo, "معاينة المنيو", "المنيو مع الباول قبل لا تطلقه", "\(site)/index.html?preview=1")
                }
            }
            Section {
                Button(role: .destructive) { askLogout = true } label: { row("rectangle.portrait.and.arrow.right", .bad, "خروج", "تسجيل الخروج من التطبيق", destructive: true) }
            }
            Section {
                VStack(spacing: 6) {
                    Image("logo-purple").resizable().scaledToFit().frame(height: 30).opacity(0.35)
                    Text("\(BizStore.shared.current == .karak ? "Karak Dose" : "Açaí Dose") · Owner \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("المزيد")
        .sheet(isPresented: $sale) { AppSaleSheet { toaster.show("انحفظت المبيعات") } }
        .confirmationDialog("تبي تطلع؟", isPresented: $askLogout, titleVisibility: .visible) {
            Button("خروج", role: .destructive, action: onLogout)
            Button("إلغاء", role: .cancel) {}
        }
    }

    private func row(_ icon: String, _ tint: Color, _ title: String, _ sub: String, destructive: Bool = false) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.body.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 32, height: 32).background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(destructive ? Color.bad : Color.primary)
                Text(sub).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func link(_ icon: String, _ tint: Color, _ title: String, _ sub: String, _ url: String) -> some View {
        Button { openURL(url) } label: {
            HStack {
                row(icon, tint, title, sub)
                Spacer()
                Image(systemName: "arrow.up.forward.square").foregroundStyle(.tertiary)
            }
        }
    }
}
