import SwiftUI

/// Link to the management system: an API key it reads sales and expenses with, and a webhook it receives every change on.
struct IntegrationView: View {
    @Environment(Toaster.self) private var toaster
    @State private var c: J?
    @State private var err: String?
    @State private var url = ""
    @State private var shown: (title: String, value: String)?
    @State private var askNewKey = false
    @State private var askOff = false
    @State private var testing = false
    @State private var askOld = false

    var body: some View {
        Group {
            if let c {
                Form {
                    Section {
                        LabeledContent("الحالة") {
                            Tag(text: c["on"].bool ? "شغال" : "مطفي", bg: (c["on"].bool ? Color.good : Color.gray).opacity(0.15), fg: c["on"].bool ? .good : .secondary)
                        }
                        copyRow("رابط الـ API", c["base_url"].string)
                        LabeledContent("المحل") { Text(c["shop"].string).monospaced() }
                    } footer: { Text("كل محل له مفتاح ورابط بروحه. بدّل المحل من «المزيد» عشان تضبط الثاني.") }

                    Section {
                        if c["has_key"].bool {
                            LabeledContent("المفتاح") { Text("dose_••••\(c["key_hint"].string)").monospaced().foregroundStyle(.secondary) }
                            Button { askNewKey = true } label: { Label("مفتاح جديد", systemImage: "key.fill") }
                        } else {
                            Button { Task { await newKey() } } label: { Label("سوّ مفتاح", systemImage: "key.fill") }.bold()
                        }
                    } header: { Text("المفتاح (نظام الإدارة يسحب البيانات)") } footer: { Text("يطلع مرة وحدة بس، انسخه وعطه المبرمج. المفتاح الجديد يوقف القديم.") }

                    Section {
                        TextField("https://...", text: $url)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .environment(\.layoutDirection, .leftToRight)
                        Button("احفظ الرابط") { Task { await saveHook(newSecret: false) } }
                        if !c["hook_url"].string.isEmpty {
                            Button { Task { await test() } } label: { Label(testing ? "قاعد يجرب…" : "جرّب الإرسال", systemImage: "paperplane.fill") }.disabled(testing)
                            Button { Task { await saveHook(newSecret: true) } } label: { Label("سر توقيع جديد", systemImage: "lock.rotation") }
                            LabeledContent("ينتظر الإرسال") { Text("\(c["pending"].int)").monospacedDigit() }
                            if c["failed"].int > 0 { LabeledContent("ما وصل") { Text("\(c["failed"].int)").monospacedDigit().foregroundStyle(Color.bad) } }
                            if !c["last_ok"].string.isEmpty { LabeledContent("آخر إرسال ناجح") { Text(c["last_ok"].string).font(.caption).monospacedDigit() } }
                            if !c["last_error"].string.isEmpty { LabeledContent("آخر خطأ") { Text(c["last_error"].string).font(.caption).foregroundStyle(Color.bad) } }
                        }
                    } header: { Text("رابط الاستقبال (نرسل له كل حركة)") } footer: { Text("كل بيع وإلغاء ومصروف، وملخص كل يوم بعد نص الليل، يوصل لنظام الإدارة على طول. لو ما رد، نعيد المحاولة.") }

                    if c["on"].bool {
                        Section {
                            Button { askOld = true } label: { Label("أرسل القديم", systemImage: "clock.arrow.circlepath") }
                        } footer: { Text("يرسل كل الطلبات ومبيعات التطبيقات والمصاريف وملخص كل يوم من قبل ما تشغّل الربط. لو انرسل مرتين ما يتكرر عندهم.") }
                        Section { Button("طفّي الربط", role: .destructive) { askOff = true } }
                    }
                }
            } else if let err {
                EmptyNote(text: err, icon: "wifi.exclamationmark")
            } else {
                ProgressView()
            }
        }
        .navigationTitle("ربط نظام الإدارة")
        .refreshable { await load() }
        .task { await load() }
        .alert(shown?.title ?? "", isPresented: Binding(get: { shown != nil }, set: { if !$0 { shown = nil } })) {
            Button("انسخ") { UIPasteboard.general.string = shown?.value; toaster.show("انتسخ") ; shown = nil }
            Button("تم", role: .cancel) { shown = nil }
        } message: { Text((shown?.value ?? "") + "\n\nيطلع مرة وحدة بس، انسخه الحين.") }
        .confirmationDialog("المفتاح القديم بيوقف، ونظام الإدارة يحتاج الجديد", isPresented: $askNewKey, titleVisibility: .visible) {
            Button("سوّ مفتاح جديد", role: .destructive) { Task { await newKey() } }
            Button("إلغاء", role: .cancel) {}
        }
        .confirmationDialog("أرسل كل البيانات القديمة لنظام الإدارة؟", isPresented: $askOld, titleVisibility: .visible) {
            Button("أرسل") { Task { await sendOld() } }
            Button("إلغاء", role: .cancel) {}
        }
        .confirmationDialog("نظام الإدارة بيوقف يستلم ويسحب من هالمحل", isPresented: $askOff, titleVisibility: .visible) {
            Button("طفّي", role: .destructive) { Task { await call("ext_off", [:], "انطفى الربط") } }
            Button("إلغاء", role: .cancel) {}
        }
    }

    private func copyRow(_ title: String, _ value: String) -> some View {
        Button { UIPasteboard.general.string = value; toaster.show("انتسخ") } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(value).font(.footnote).monospaced().lineLimit(1).truncationMode(.middle).foregroundStyle(Color.primary)
                    Spacer()
                    Image(systemName: "doc.on.doc").foregroundStyle(.tertiary)
                }
                .environment(\.layoutDirection, .leftToRight)
            }
        }
    }

    private func load() async {
        do { let r = try await API.shared.get("ext_config"); c = r; err = nil; url = r["hook_url"].string }
        catch { err = errText(error) }
    }

    private func newKey() async {
        do {
            let r = try await API.shared.post("ext_key_new")
            shown = ("مفتاح نظام الإدارة", r["key"].string)
            await load()
        } catch { toaster.show(errText(error), ok: false) }
    }

    private func saveHook(newSecret: Bool) async {
        do {
            let r = try await API.shared.post("ext_hook_save", ["url": url.trimmingCharacters(in: .whitespaces), "new_secret": newSecret])
            if !r["secret"].string.isEmpty { shown = ("سر التوقيع", r["secret"].string) } else { toaster.show(url.isEmpty ? "انشال الرابط" : "انحفظ الرابط") }
            await load()
        } catch { toaster.show(errText(error), ok: false) }
    }

    private func test() async {
        testing = true; defer { testing = false }
        do {
            let r = try await API.shared.post("ext_hook_test")
            if r["ok"].bool { toaster.show("وصل ✓ (\(r["code"].int))") }
            else { toaster.show(r["code"].int > 0 ? "رد بخطأ \(r["code"].int)" : "ما رد: \(r["error"].string)", ok: false) }
        } catch { toaster.show(errText(error), ok: false) }
    }

    private func sendOld() async {
        do {
            let r = try await API.shared.post("ext_backfill")
            toaster.show("تجهز: \(r["orders"].int) طلب، \(r["expenses"].int) مصروف، \(r["days"].int) يوم. قاعد ينرسل")
            await load()
        } catch { toaster.show(errText(error), ok: false) }
    }

    private func call(_ a: String, _ body: [String: Any], _ done: String) async {
        do { try await API.shared.post(a, body); toaster.show(done); await load() }
        catch { toaster.show(errText(error), ok: false) }
    }
}
