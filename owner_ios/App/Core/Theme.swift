import SwiftUI
import UIKit

extension Color {
    /// Karak Dose is charcoal and white (its logo); Açaí Dose is purple, cream and orange. Follows the shop picked in the app.
    private static var karak: Bool { BizStore.shared.current == .karak }
    private static func rgb(_ v: Int) -> Color { Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255) }
    static var brand: Color { rgb(karak ? 0x393939 : 0x470D43) }
    static var brand2: Color { rgb(karak ? 0x4A4A4A : 0x5E1A55) }
    static var cream: Color { rgb(karak ? 0xFFFFFF : 0xFAF3E0) }
    static var cream2: Color { rgb(karak ? 0xF2F2F2 : 0xF1E9DA) }
    static var accent2: Color { rgb(karak ? 0x7A7A7A : 0xE39A2E) }
    static var lilac: Color { rgb(karak ? 0xBDBDBD : 0xD9BCDB) }
    static let good = Color(red: 0x24 / 255, green: 0x8A / 255, blue: 0x3D / 255)
    static let bad = Color(red: 0xE5 / 255, green: 0x34 / 255, blue: 0x2B / 255)
    /// Brand colour for text and icons: deep in light mode, soft in dark mode so it stays readable.
    static var ink: Color {
        let k = karak
        return Color(uiColor: UIColor { t in
            if k { return t.userInterfaceStyle == .dark ? UIColor(white: 0.88, alpha: 1) : UIColor(red: 0x39 / 255, green: 0x39 / 255, blue: 0x39 / 255, alpha: 1) }
            return t.userInterfaceStyle == .dark ? UIColor(red: 0.86, green: 0.68, blue: 0.86, alpha: 1) : UIColor(red: 0x47 / 255, green: 0x0D / 255, blue: 0x43 / 255, alpha: 1)
        })
    }
    /// One colour for light mode and one for dark mode.
    private static func dyn(_ light: Int, _ dark: Int) -> Color {
        Color(uiColor: UIColor { t in
            let v = t.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        })
    }
    static let yellow = Color(red: 1, green: 0xC2 / 255, blue: 0x29 / 255)
    /// Page: cream (light) or deep purple (dark); Karak Dose light grey or near black.
    static var pageBG: Color { karak ? dyn(0xF2F2F2, 0x111111) : dyn(0xFAF3E0, 0x170515) }
    static var cardBG: Color { karak ? dyn(0xFFFFFF, 0x1F1F1F) : dyn(0xFFFFFF, 0x28102A) }
    /// A step up from a card (icon wells, chips inside cards).
    static var wellBG: Color { karak ? dyn(0xEDEDED, 0x2B2B2B) : dyn(0xF1E9DA, 0x341636) }
    /// The big card on top: purple with cream text (light), yellow with purple text (dark). Karak: charcoal / white.
    static var heroBG: Color { karak ? dyn(0x393939, 0xF2F2F2) : dyn(0x470D43, 0xFFC229) }
    static var heroBG2: Color { karak ? dyn(0x4A4A4A, 0xDDDDDD) : dyn(0x5E1A55, 0xF2B21C) }
    static var heroFG: Color { karak ? dyn(0xFFFFFF, 0x222222) : dyn(0xFAF3E0, 0x470D43) }
    /// Highlight on the hero colour (badges, the chosen tab): yellow on purple, purple on yellow.
    static var pop: Color { karak ? dyn(0xFFFFFF, 0x393939) : dyn(0xFFC229, 0x470D43) }
    static var popFG: Color { karak ? dyn(0x393939, 0xFFFFFF) : dyn(0x470D43, 0xFFC229) }
    /// The floating tab bar.
    static var barBG: Color { karak ? dyn(0x393939, 0x2A2A2A) : dyn(0x470D43, 0x2E1430) }
    static var barOn: Color { karak ? dyn(0xFFFFFF, 0xFFFFFF) : dyn(0xFFC229, 0xFFC229) }
    static var barOnFG: Color { karak ? dyn(0x393939, 0x222222) : dyn(0x470D43, 0x470D43) }
}

/// White rounded group like an iOS inset-grouped section.
struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardBG, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

extension View {
    func card(_ padding: CGFloat = 16) -> some View { modifier(CardStyle(padding: padding)) }
}

/// Section header above a group of cards.
struct SectionHeader: View {
    let title: String
    var note: String = ""
    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title).font(.title3.bold())
            Spacer()
            if !note.isEmpty { Text(note).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
        }
        .padding(.horizontal, 4)
        .padding(.top, 18)
    }
}

/// Small rounded label.
struct Tag: View {
    let text: String
    var bg: Color = Color.ink.opacity(0.14)
    var fg: Color = .ink
    var icon: String? = nil
    var body: some View {
        HStack(spacing: 3) {
            if let icon { Image(systemName: icon).font(.caption2.bold()) }
            Text(text).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .foregroundStyle(fg)
        .background(bg, in: Capsule())
    }
}

/// Green or red "↑ 12%" against the previous period.
struct DeltaBadge: View {
    let now: Double
    let before: Double
    var onDark = false
    var lowerIsBetter = false
    var body: some View {
        if before <= 0 && now <= 0 { EmptyView() } else {
            let pct = before <= 0 ? 100 : (now - before) / before * 100
            let up = pct >= 0
            let good = lowerIsBetter ? !up : up
            let fg: Color = onDark ? (good ? Color(red: 0.66, green: 0.9, blue: 0.72) : Color(red: 1, green: 0.7, blue: 0.7)) : (good ? .good : .bad)
            HStack(spacing: 2) {
                Image(systemName: up ? "arrow.up" : "arrow.down").font(.caption2.bold())
                Text("\(Int(abs(pct).rounded()))%").font(.caption.bold()).monospacedDigit()
            }
            .environment(\.layoutDirection, .leftToRight)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(fg)
            .background(onDark ? Color.white.opacity(0.12) : fg.opacity(0.12), in: Capsule())
        }
    }
}

/// Thin rounded progress bar.
struct ThinBar: View {
    let value: Double
    var color: Color = .accent2
    var track: Color = Color.ink.opacity(0.14)
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(color).frame(width: max(0, min(1, value.isNaN ? 0 : value)) * g.size.width)
            }
        }
        .frame(height: height)
    }
}

/// Grey message for empty lists.
struct EmptyNote: View {
    let text: String
    var icon = "tray"
    var body: some View {
        ContentUnavailableView(text, systemImage: icon)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
    }
}

/// Row of loyalty cups: [filled] of [need].
struct StampRow: View {
    let filled: Int
    let need: Int
    var size: CGFloat = 30
    var body: some View {
        let cols = [GridItem(.adaptive(minimum: size + 4), spacing: 6)]
        LazyVGrid(columns: cols, spacing: 6) {
            ForEach(0..<max(need, 0), id: \.self) { i in
                Image(i < filled ? "stamp-on" : "stamp-off")
                    .resizable().scaledToFit()
                    .frame(width: size, height: size * 1.36)
                    .scaleEffect(i < filled ? 1 : 0.86)
                    .animation(.spring(duration: 0.3), value: filled)
            }
        }
    }
}

// MARK: - Toast

@Observable
final class Toaster {
    var message: String?
    var ok = true
    private var task: Task<Void, Never>?

    func show(_ text: String, ok: Bool = true) {
        Haptics.notify(ok ? .success : .error)
        withAnimation(.spring(duration: 0.35)) { message = text; self.ok = ok }
        task?.cancel()
        task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            if Task.isCancelled { return }
            withAnimation(.easeIn(duration: 0.25)) { self.message = nil }
        }
    }
}

struct ToastOverlay: ViewModifier {
    @Environment(Toaster.self) private var toaster
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let m = toaster.message {
                HStack(spacing: 8) {
                    Image(systemName: toaster.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(toaster.ok ? Color.good : Color.bad)
                    Text(m).font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func toasts() -> some View { modifier(ToastOverlay()) }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func notify(_ t: UINotificationFeedbackGenerator.FeedbackType) { UINotificationFeedbackGenerator().notificationOccurred(t) }
}

/// Opens a link outside the app (WhatsApp, phone, maps, the web dashboard).
func openURL(_ s: String) {
    guard let u = URL(string: s) else { return }
    UIApplication.shared.open(u)
}

func waLink(_ phone: String, text: String? = nil) -> String {
    let n = phone.filter(\.isNumber)
    if let text, let q = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) { return "https://wa.me/\(n)?text=\(q)" }
    return "https://wa.me/\(n)"
}


/// Buttons that visibly react: shrink a little and dim while pressed.
struct Pressable: ButtonStyle {
    var scale: CGFloat = 0.95
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
