import Foundation

/// Delivery apps of the shop on screen (from the server), in order.
var kChannels: [(String, String)] { BizStore.shared.channels }
/// Every delivery app either shop uses, to tell app orders from shop sales.
let kChannelNames: [String: String] = ["talabat": "طلبات", "tmdone": "تم دن", "snoonu": "سنونو", "khedmah": "خدمة"]
var kCats: [String] {
    BizStore.shared.current == .karak
        ? ["مواد خام", "خبز ومعجنات", "أكواب وتغليف", "رواتب", "إيجار", "كهرباء وماء وغاز", "تسويق وإعلانات", "صيانة", "معدات وأجهزة (مرة وحدة)", "أخرى"]
        : ["مواد خام (آساي وفواكه)", "أكواب وتغليف", "رواتب", "إيجار", "كهرباء وماء", "تسويق وإعلانات", "صيانة", "معدات وأجهزة (مرة وحدة)", "أخرى"]
}
let kStatusNames = ["new": "جديد", "preparing": "يتحضر", "ready": "جاهز", "done": "مستلم", "cancelled": "ملغي"]
let kPayNames = ["cash": "نقد", "card": "بطاقة", "talabat": "طلبات", "tmdone": "تم دن", "snoonu": "سنونو", "khedmah": "خدمة"]

struct NameCount: Identifiable { let id: String; let n: Int }
struct DayValue: Identifiable { let id: Date; let v: Double }

struct PayMethod: Identifiable {
    let id: String
    let name: String
    let isApp: Bool
    let gross: Double
    let comm: Double
    let n: Int
    var net: Double { gross - comm }
}

/// Same sums as the web dashboard's summary.
struct Stats {
    var site = 0.0, shop = 0.0, appGross = 0.0, comm = 0.0, exp = 0.0, sales = 0.0, net = 0.0, unpaidTotal = 0.0
    var siteOrders = 0, siteCups = 0, shopOrders = 0, shopCups = 0, unpaidCount = 0, expCount = 0, orderCount = 0
    var methods: [PayMethod] = []
    var products: [NameCount] = []
    var daily: [DayValue] = []

    var avg: Double { orderCount > 0 ? sales / Double(orderCount) : 0 }
    func pct(_ v: Double) -> Int { sales > 0 ? min(100, max(0, Int((v / sales * 100).rounded()))) : 0 }

    init(_ data: J, days: [Date]) {
        let orders = data["orders"].array
        let apps = data["apps"].array
        let exps = data["exps"].array
        let valid = orders.filter { $0["status"].string != "cancelled" }
        func isApp(_ o: J) -> Bool { o["source"].string == "pos" && kChannelNames[o["payment"].string] != nil }
        let web = valid.filter { $0["source"].string == "web" }   // car orders taken outside count as shop sales
        let shopO = valid.filter { $0["source"].string != "web" && kChannelNames[$0["payment"].string] == nil }
        let appO = valid.filter(isApp)

        func sumT(_ l: [J]) -> Double { l.reduce(0) { $0 + $1["total"].double } }
        func cnt(_ l: [J]) -> Int { l.reduce(0) { $0 + ($1["n_orders"].isNull ? 1 : $1["n_orders"].int) } }
        func cups(_ l: [J]) -> Int { l.reduce(0) { s, o in s + o["items"].array.reduce(0) { $0 + $1["qty"].int } } }

        site = sumT(web); shop = sumT(shopO)
        siteOrders = cnt(web); siteCups = cups(web)
        shopOrders = cnt(shopO); shopCups = cups(shopO)

        func mk(_ k: String, _ name: String, _ list: [J], _ manual: [J], _ app: Bool) -> PayMethod {
            let gross = sumT(list) + manual.reduce(0) { $0 + $1["gross"].double }
            let comm = list.reduce(0) { $0 + $1["commission"].double } + manual.reduce(0) { $0 + $1["commission"].double }
            let n = cnt(list) + manual.reduce(0) { $0 + $1["orders_count"].int }
            return PayMethod(id: k, name: name, isApp: app, gross: gross, comm: comm, n: n)
        }
        methods = [mk("cash", "نقد", valid.filter { $0["payment"].string == "cash" }, [], false),
                   mk("card", "بطاقة", valid.filter { $0["payment"].string == "card" }, [], false)]
            + kChannels.map { k, name in mk(k, name, appO.filter { $0["payment"].string == k }, apps.filter { $0["channel"].string == k }, true) }

        let unpaid = web.filter { $0["payment"].string.isEmpty }
        unpaidTotal = sumT(unpaid); unpaidCount = unpaid.count
        appGross = methods.filter(\.isApp).reduce(0) { $0 + $1.gross }
        comm = methods.reduce(0) { $0 + $1.comm }
        exp = exps.reduce(0) { $0 + $1["amount"].double }
        expCount = exps.count
        sales = sumT(valid) + apps.reduce(0) { $0 + $1["gross"].double }
        net = sales - comm - exp
        orderCount = cnt(valid) + apps.reduce(0) { $0 + $1["orders_count"].int }

        var prod: [String: Int] = [:]
        for o in valid {
            for i in o["items"].array {
                let full = i["name_ar"].string.isEmpty ? i["name_en"].string : i["name_ar"].string
                let name = full.components(separatedBy: " (").first ?? full   // built bowls count together
                prod[name, default: 0] += i["qty"].int
            }
        }
        products = prod.sorted { $0.value > $1.value }.map { NameCount(id: $0.key, n: $0.value) }

        daily = days.map { d in
            let k = ymd(d)
            let v = valid.filter { $0["created_at"].string.hasPrefix(k) }.reduce(0) { $0 + $1["total"].double }
                + apps.filter { $0["sale_date"].string == k }.reduce(0) { $0 + $1["gross"].double }
            return DayValue(id: d, v: v)
        }
    }
}
