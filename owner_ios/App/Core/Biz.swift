import SwiftUI

/// The two shops this app runs. Karak Dose lives under /karak on the same site with its own menu, staff, sales and login.
enum Biz: String, CaseIterable, Identifiable {
    case acai, karak
    var id: String { rawValue }
    var name: String { self == .karak ? "كرك دوز" : "أساي دوز" }
    var site: String { SharedStore.site + (self == .karak ? "/karak" : "") }
    var cookieName: String { self == .karak ? "kd_sid" : "acai_sid" }
    var cookieKey: String { self == .karak ? "cookie_karak" : "cookie" }
    var defaultChannels: [(String, String)] {
        self == .karak
            ? [("talabat", "طلبات"), ("tmdone", "تم دن"), ("snoonu", "سنونو"), ("khedmah", "خدمة")]
            : [("talabat", "طلبات"), ("snoonu", "سنونو"), ("khedmah", "خدمة")]
    }
}

/// Which shop the app is showing, plus what the server says about it (delivery apps, menu sections).
@Observable
final class BizStore {
    static let shared = BizStore()

    var current: Biz {
        didSet {
            UserDefaults.standard.set(current.rawValue, forKey: "biz")
            channels = current.defaultChannels
            cats = []
        }
    }
    var channels: [(String, String)]
    var cats: [J] = []

    private init() {
        let b = Biz(rawValue: UserDefaults.standard.string(forKey: "biz") ?? "") ?? .acai
        current = b
        channels = b.defaultChannels
    }

    /// Takes the shop's delivery apps and menu sections from a settings or range reply.
    func absorb(_ r: J) {
        let ch = r["channels"].array.map { ($0["k"].string, $0["ar"].string) }.filter { !$0.0.isEmpty }
        if !ch.isEmpty { channels = ch }
        if !r["cats"].array.isEmpty { cats = r["cats"].array }
    }
}

/// Size labels for Karak Dose items.
let kSizeNames = ["small": "صغير", "large": "كبير", "meal": "وجبة", "regular": "عادي",
                  "cola": "كولا", "cola_diet": "كولا دايت", "lemon": "ليمون", "lemon_diet": "ليمون دايت", "citrus": "حمضيات",
                  "berry": "توت", "orange": "برتقال", "mango": "مانجو", "mixed": "مشكل"]

/// "كرك (صغير)" for an item with a size, else just the name.
func itemName(_ p: J) -> String {
    let s = kSizeNames[p["size"].string] ?? ""
    return s.isEmpty ? p["name_ar"].string : "\(p["name_ar"].string) (\(s))"
}
