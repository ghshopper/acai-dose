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
            RootView()
                .environment(toaster)
                .environment(period)
                .environment(Live.shared)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar_OM"))
                .tint(.brand)
                .toasts()
        }
        .onChange(of: phase) { _, p in
            if p == .background { Live.schedule() }
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
        .task { await check() }
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
        await Live.shared.signOut()
        gate = .signedOut
    }
}

struct MainTabs: View {
    let onLogout: () -> Void
    @State private var tab = 0
    @Environment(\.scenePhase) private var phase
    @Environment(Live.self) private var live

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { SummaryView() }
                .tabItem { Label("الملخص", systemImage: "chart.pie.fill") }.tag(0)
            NavigationStack { OrdersView() }
                .tabItem { Label("الطلبات", systemImage: "doc.text.fill") }.tag(1)
            NavigationStack { CustomersView() }
                .tabItem { Label("العملاء", systemImage: "person.2.fill") }.tag(2)
            NavigationStack { ExpensesView() }
                .tabItem { Label("المصاريف", systemImage: "creditcard.fill") }.tag(3)
            NavigationStack { MoreView(onLogout: onLogout) }
                .tabItem { Label("المزيد", systemImage: "ellipsis.circle.fill") }.tag(4)
        }
        .onChange(of: tab) { _, _ in Haptics.tap() }
        .task {
            // Keep the widget and Live Activity fresh while the app is open
            while !Task.isCancelled {
                if phase == .active { await live.refresh() }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}
