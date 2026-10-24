import SwiftUI

struct LoginView: View {
    let onLogin: () -> Void
    @State private var user = ""
    @State private var pass = ""
    @State private var busy = false
    @State private var err = ""
    @FocusState private var focus: Int?

    var body: some View {
        ZStack {
            Color.brand.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 10) {
                    Picker("المحل", selection: Binding(get: { BizStore.shared.current }, set: { BizStore.shared.current = $0 })) {
                        ForEach(Biz.allCases) { b in Text(b.name).tag(b) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.top, 24)
                    if BizStore.shared.current == .karak {
                        Image("karak-white").resizable().scaledToFit().frame(height: 80).padding(.top, 40)
                    } else {
                        Image("logo-cream").resizable().scaledToFit().frame(height: 72).padding(.top, 40)
                    }
                    Text("الداش بورد").font(.largeTitle.bold()).foregroundStyle(Color.cream).padding(.top, 18)
                    Text(BizStore.shared.current == .karak ? "نفس اسم المستخدم وكلمة السر حق أساي دوز" : "سجّل دخول بحساب صاحب المحل").foregroundStyle(Color.lilac)

                    VStack(spacing: 0) {
                        TextField("اسم المستخدم", text: $user)
                            .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .environment(\.layoutDirection, .leftToRight)
                            .multilineTextAlignment(.leading)
                            .focused($focus, equals: 0).submitLabel(.next).onSubmit { focus = 1 }
                            .padding(16)
                        Divider().padding(.leading, 16)
                        SecureField("كلمة السر", text: $pass)
                            .textContentType(.password)
                            .focused($focus, equals: 1).submitLabel(.go).onSubmit { Task { await go() } }
                            .padding(16)
                    }
                    .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 22)

                    if !err.isEmpty {
                        Text(err).font(.subheadline.weight(.semibold)).foregroundStyle(Color(red: 1, green: 0.7, blue: 0.7)).padding(.top, 6)
                    }

                    Button { Task { await go() } } label: {
                        Group { if busy { ProgressView().tint(.brand) } else { Text("دخول").font(.headline) } }
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accent2)
                    .foregroundStyle(Color.brand)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .disabled(busy || user.isEmpty || pass.isEmpty)
                    .padding(.top, 14)
                }
                .padding(.horizontal, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func go() async {
        busy = true; err = ""
        defer { busy = false }
        do {
            let r = try await API.shared.post("login", ["username": user.trimmingCharacters(in: .whitespaces), "password": pass])
            if r["role"].string == "owner" {
                Haptics.notify(.success)
                await Live.shared.ensureKey()
                onLogin()
            } else {
                _ = try? await API.shared.post("logout")
                API.shared.clearSession()
                err = errText("forbidden")
            }
        } catch {
            err = errText(error)
            Haptics.notify(.error)
        }
    }
}
