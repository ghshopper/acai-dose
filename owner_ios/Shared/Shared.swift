import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Things both the app and the widget extension use.
enum SharedStore {
    static let group = "group.com.acaidose.owner"
    static let site = "https://order.acaiee.com"
    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    /// Read-only key the widget uses to fetch today's numbers (made by the app after login).
    static var widgetKey: String? {
        get { defaults.string(forKey: "wkey") }
        set { defaults.set(newValue, forKey: "wkey") }
    }
}

/// Today's numbers for the widget and the Live Activity.
struct Glance: Codable, Hashable {
    var day: String
    var sales: Double
    var orders: Int
    var pending: Int
    var new: Int
    var expenses: Double
    var lastRef: String?
    var at: String

    enum CodingKeys: String, CodingKey {
        case day, sales, orders, pending, new, expenses, at
        case lastRef = "last_ref"
    }

    static let sample = Glance(day: "", sales: 48.6, orders: 15, pending: 2, new: 1, expenses: 6.5, lastRef: "2410-15", at: "14:05")

    static var cached: Glance? {
        get {
            guard let d = SharedStore.defaults.data(forKey: "glance") else { return nil }
            return try? JSONDecoder().decode(Glance.self, from: d)
        }
        set {
            if let v = newValue, let d = try? JSONEncoder().encode(v) { SharedStore.defaults.set(d, forKey: "glance") }
            else { SharedStore.defaults.removeObject(forKey: "glance") }
        }
    }

    /// Fetches today's numbers with the widget key; nil when there is no key yet.
    static func fetch() async -> Glance? {
        guard let key = SharedStore.widgetKey,
              let url = URL(string: "\(SharedStore.site)/api/api.php?a=glance&k=\(key)") else { return nil }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 12
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let g = try? JSONDecoder().decode(Glance.self, from: data) else { return nil }
        cached = g
        return g
    }

    var salesText: String { String(format: "%.3f", sales) }
}

#if canImport(ActivityKit)
/// Live Activity: today's orders on the Lock Screen and in the Dynamic Island.
struct OrdersActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var sales: Double
        var orders: Int
        var pending: Int
        var newCount: Int
        var lastRef: String
        var at: String
    }
    var shop: String
}

extension OrdersActivityAttributes.ContentState {
    init(_ g: Glance) {
        self.init(sales: g.sales, orders: g.orders, pending: g.pending, newCount: g.new, lastRef: g.lastRef ?? "", at: g.at)
    }
}
#endif
