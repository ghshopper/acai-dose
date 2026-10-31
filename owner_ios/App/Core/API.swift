import Foundation

/// A loosely typed JSON value. The API returns numbers as numbers or strings depending on the database,
/// so reading through this keeps every screen tolerant (same idea as the Flutter app's dynamic maps).
struct J: Hashable {
    let raw: Any?

    init(_ raw: Any?) { self.raw = (raw is NSNull) ? nil : raw }

    subscript(_ key: String) -> J { J((raw as? [String: Any])?[key]) }

    var array: [J] { (raw as? [Any])?.map { J($0) } ?? [] }
    var dict: [String: J] { ((raw as? [String: Any]) ?? [:]).mapValues { J($0) } }
    var isNull: Bool { raw == nil }

    var double: Double {
        if let n = raw as? NSNumber { return n.doubleValue }
        if let s = raw as? String { return Double(s.trimmingCharacters(in: .whitespaces)) ?? 0 }
        return 0
    }
    var int: Int { Int(double.rounded()) }
    var string: String {
        if let s = raw as? String { return s }
        if let n = raw as? NSNumber { return n.stringValue }
        return ""
    }
    var bool: Bool {
        if let b = raw as? Bool { return b }
        return int == 1
    }

    static func == (a: J, b: J) -> Bool {
        guard let x = a.raw, let y = b.raw else { return a.raw == nil && b.raw == nil }
        return NSDictionary(dictionary: ["v": x]).isEqual(to: ["v": y])
    }
    func hash(into h: inout Hasher) { h.combine(string) }
}

struct APIError: Error, LocalizedError {
    let code: String
    var errorDescription: String? { errText(code) }
}

let kErrors: [String: String] = [
    "bad_login": "اسم المستخدم أو كلمة السر غلط",
    "too_many": "محاولات كثيرة، انتظر شوي وجرب",
    "network": "ما فيه اتصال بالإنترنت",
    "login_required": "لازم تسجل دخول",
    "forbidden": "هذا الحساب مب حساب صاحب المحل",
    "invalid_phone": "رقم الجوال غلط",
    "customer_exists": "هذا الرقم مسجل من قبل",
    "bad_name": "اكتب الاسم",
    "not_found": "ما لقيته، حدّث الصفحة",
    "invalid_items": "فيه شي غلط في البيانات",
    "need_price": "حط السعر قبل لا تشغل الصنف",
    "no_stamps": "ما يمدي تنقص أكثر، الأختام صفر",
    "bad_delta": "عدد الأختام غلط",
    "bad_amount": "المبلغ غلط",
    "bad_pct": "النسبة لازم بين 0 و 100",
    "bad_need": "عدد الأختام لازم بين 2 و 30",
    "bad_username": "اسم المستخدم إنجليزي بدون مسافات (٣ حروف أو أكثر)",
    "short_password": "كلمة السر ٦ حروف أو أكثر",
    "username_taken": "اسم المستخدم مأخوذ",
    "cannot_change_self": "ما تقدر تغير حسابك من هنا",
    "server_error": "مشكلة في السيرفر، جرب بعد شوي",
    "bad_size": "الحجم غلط",
    "sold_out": "الصنف خالص",
    "bad_channel": "اختار التطبيق",
    "account_used": "الحساب فيه حركات، احذفها أو انقلها أول",
]

func errText(_ code: String) -> String { kErrors[code] ?? "صار خطأ، جرب مرة ثانية" }
func errText(_ e: Error) -> String { (e as? APIError).map { errText($0.code) } ?? errText("") }

/// Client for api/api.php that keeps the login session cookie (like the web pages).
final class API {
    static let shared = API()
    /// The shop on screen decides the address and which saved login is used.
    private var base: URL { URL(string: "\(BizStore.shared.current.site)/api/api.php")! }
    private var biz: Biz { BizStore.shared.current }
    private let session: URLSession

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.httpShouldSetCookies = false
        cfg.httpCookieAcceptPolicy = .never
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = 15
        session = URLSession(configuration: cfg)
    }

    private(set) var cookie: String? {
        get { UserDefaults.standard.string(forKey: biz.cookieKey) }
        set { UserDefaults.standard.set(newValue, forKey: biz.cookieKey) }
    }

    /// Reads from a given shop whatever shop is on screen (the partners' report reads both).
    func get(_ action: String, _ query: [String: String] = [:], biz b: Biz) async throws -> J {
        try await send(action, body: nil, query: query, biz: b)
    }

    func clearSession() { cookie = nil }

    func get(_ action: String, _ query: [String: String] = [:]) async throws -> J {
        try await send(action, body: nil, query: query)
    }

    @discardableResult
    func post(_ action: String, _ body: [String: Any] = [:]) async throws -> J {
        try await send(action, body: body, query: [:])
    }

    private func send(_ action: String, body: [String: Any]?, query: [String: String], biz forBiz: Biz? = nil) async throws -> J {
        let b = forBiz ?? biz
        var comps = URLComponents(url: URL(string: "\(b.site)/api/api.php")!, resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "a", value: action)] + query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: comps.url!)
        req.setValue("AcaiDoseOwner/2.0 (iOS)", forHTTPHeaderField: "User-Agent")
        if let c = UserDefaults.standard.string(forKey: b.cookieKey) { req.setValue(c, forHTTPHeaderField: "Cookie") }
        if let body {
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: req) } catch { throw APIError(code: "network") }
        let http = resp as? HTTPURLResponse
        if b == biz { keepCookie(http) }
        let json = J(try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
        let status = http?.statusCode ?? 0
        if status >= 400 {
            let code = json["error"].string
            throw APIError(code: code.isEmpty ? "http_\(status)" : code)
        }
        return json
    }

    private func keepCookie(_ r: HTTPURLResponse?) {
        guard let sc = r?.value(forHTTPHeaderField: "Set-Cookie"),
              let range = sc.range(of: "\(biz.cookieName)=([^;,]*)", options: .regularExpression) else { return }
        let v = String(sc[range]).replacingOccurrences(of: "\(biz.cookieName)=", with: "")
        cookie = (v.isEmpty || v == "deleted") ? nil : "\(biz.cookieName)=\(v)"
    }
}

// MARK: - Small formatters

func money(_ v: Double) -> String { String(format: "%.3f", v) }
func money(_ v: J) -> String { money(v.double) }

func ymd(_ d: Date) -> String {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "Asia/Muscat")
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: d)
}

var muscat: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Muscat") ?? .current
    return c
}

/// "2026-10-24 14:05:11" → Date (shop time)
func parseStamp(_ s: String) -> Date? {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "Asia/Muscat")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f.date(from: s)
}

func shortNumber(_ v: Double) -> String {
    v == v.rounded() ? String(Int(v)) : String(v)
}
