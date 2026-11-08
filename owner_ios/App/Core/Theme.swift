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
    static let pageBG = Color(uiColor: .systemGroupedBackground)
    static let cardBG = Color(uiColor: .secondarySystemGroupedBackground)
}

/// White rounded group like an iOS inset-grouped section.
struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardBG, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
