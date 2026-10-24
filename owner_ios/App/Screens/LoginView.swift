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
                    Image("logo-cream").resizable().scaledToFit().frame(height: 72).padding(.top, 70)
                    Text("الداش بورد").font(.largeTitle.bold()).foregroundStyle(Color.cream).padding(.top, 18)
                    Text("سجّل دخول بحساب صاحب المحل").foregroundStyle(Color.lilac)

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
