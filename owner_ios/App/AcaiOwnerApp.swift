import SwiftUI

@main
struct AcaiOwnerApp: App {
    @State private var toaster = Toaster()
    @State private var period = Period()
    @Environment(\.scenePhase) private var phase

    init() {
        Live.register()
    }

    var body: some Scene {
        WindowGroup {
            // .toasts() reads the Toaster from the environment, so it must sit inside .environment(toaster)
            RootView()
                .toasts()
                .environment(toaster)
                .environment(period)
                .environment(Live.shared)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar_OM"))
        }
        .onChange(of: phase) { _, p in
            if p == .background { Live.schedule() }
            if p == .active { Task { @MainActor in await DailyReport.check(); DailyReport.scheduleFallback() } }
        }
    }
}

/// Login gate: checks the saved session, then shows the tabs or the login screen.
struct RootView: View {
    enum Gate: Equatable { case loading, signedOut, signedIn, offline(String) }
    @State private var gate: Gate = .loading

    var body: some View {
        Group {
            switch gate {
            case .loading:
                ZStack { Color.brand.ignoresSafeArea(); ProgressView().tint(.cream).controlSize(.large) }
            case .offline(let msg):
                ZStack {
                    Color.brand.ignoresSafeArea()
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.slash").font(.largeTitle).foregroundStyle(Color.cream)
                        Text(msg).font(.title3.weight(.semibold)).foregroundStyle(Color.cream)
                        Button("حاول مرة ثانية") { Task { await check() } }
                            .buttonStyle(.borderedProminent).tint(.accent2).foregroundStyle(Color.brand)
                    }
                }
            case .signedOut:
                LoginView { gate = .signedIn }
            case .signedIn:
                MainTabs { Task { await logout() } }
            }
        }
        // Switching shop starts over: its own login, numbers and settings
        .id(BizStore.shared.current)
        .tint(.ink)   // follows the shop: purple for Açaí Dose, charcoal for Karak Dose
        .task(id: BizStore.shared.current) { await check() }
    }

    private func check() async {
        gate = .loading
        do {
            let r = try await API.shared.get("me")
            gate = r["role"].string == "owner" ? .signedIn : .signedOut
        } catch let e as APIError where e.code == "network" {
            gate = .offline(errText(e))
        } catch {
            gate = .signedOut
        }
    }

    private func logout() async {
        _ = try? await API.shared.post("logout")
        API.shared.clearSession()
        if BizStore.shared.current == .acai { await Live.shared.signOut() }
        gate = .signedOut
    }
}

struct MainTabs: View {
    let onLogout: () -> Void
    @State private var tab = 0
    /// Tabs opened so far: each is built the first time it is opened, then kept (its scroll and data stay).
    @State private var opened: Set<Int> = [0]
    @Namespace private var tabNS
    @Environment(\.scenePhase) private var phase
    @Environment(Live.self) private var live

    static let tabs: [(String, String)] = [("الملخص", "house.fill"), ("الطلبات", "doc.text.fill"), ("العملاء", "person.2.fill"), ("المصاريف", "creditcard.fill"), ("المزيد", "ellipsis")]

    var body: some View {
        ZStack {
            ForEach(Array(opened).sorted(), id: \.self) { i in
                page(i)
                    .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 78) }
                    .opacity(tab == i ? 1 : 0)
                    .allowsHitTesting(tab == i)
                    .accessibilityHidden(tab != i)
            }
        }
        .overlay(alignment: .bottom) { bar }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task {
            // Keep the widget and Live Activity fresh while the app is open
            while !Task.isCancelled {
                if phase == .active { await live.refresh() }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    @ViewBuilder private func page(_ i: Int) -> some View {
        switch i {
        case 0: NavigationStack { SummaryView() }
        case 1: NavigationStack { OrdersView() }
        case 2: NavigationStack { CustomersView() }
        case 3: NavigationStack { ExpensesView() }
        default: NavigationStack { MoreView(onLogout: onLogout) }
        }
    }

    /// Floating capsule of icons; the open tab sits on a yellow (or white) pill.
    private var bar: some View {
        HStack(spacing: 0) {
            ForEach(Self.tabs.indices, id: \.self) { i in
                let on = tab == i
                Button {
                    guard tab != i else { return }
                    Haptics.tap()
                    opened.insert(i)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { tab = i }
                } label: {
                    Image(systemName: Self.tabs[i].1)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(on ? Color.barOnFG : Color.white.opacity(0.7))
                        .frame(width: 58, height: 46)
                        .background {
                            if on { Capsule().fill(Color.barOn).matchedGeometryEffect(id: "tab", in: tabNS) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(Pressable(scale: 0.88))
                .accessibilityLabel(Self.tabs[i].0)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(6)
        .background(Color.barBG, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }
}

/// Picks which shop the app shows (Açaí Dose or Karak Dose).
struct BizSwitcher: View {
    var body: some View {
        Menu {
            Picker("المحل", selection: Binding(get: { BizStore.shared.current }, set: { b in Haptics.tap(); BizStore.shared.current = b })) {
                ForEach(Biz.allCases) { b in Text(b.name).tag(b) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(BizStore.shared.current.name).font(.subheadline.weight(.bold))
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.ink.opacity(0.12), in: Capsule())
        }
    }
}
