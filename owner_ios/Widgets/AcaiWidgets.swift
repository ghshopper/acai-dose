import WidgetKit
import SwiftUI
import ActivityKit

private let purple = Color(red: 0x47 / 255, green: 0x0D / 255, blue: 0x43 / 255)
private let purple2 = Color(red: 0x5E / 255, green: 0x1A / 255, blue: 0x55 / 255)
private let cream = Color(red: 0xFA / 255, green: 0xF3 / 255, blue: 0xE0 / 255)
private let orange = Color(red: 0xE3 / 255, green: 0x9A / 255, blue: 0x2E / 255)
private let lilac = Color(red: 0xD9 / 255, green: 0xBC / 255, blue: 0xDB / 255)

@main
struct AcaiWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        OrdersLiveActivity()
    }
}

// MARK: - Home / Lock Screen widget

struct TodayEntry: TimelineEntry {
    let date: Date
    let g: Glance?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { TodayEntry(date: .now, g: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        if context.isPreview { completion(TodayEntry(date: .now, g: .sample)); return }
        Task { completion(TodayEntry(date: .now, g: await Glance.fetch() ?? Glance.cached)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        Task {
            let g = await Glance.fetch() ?? Glance.cached
            completion(Timeline(entries: [TodayEntry(date: .now, g: g)], policy: .after(Date.now.addingTimeInterval(15 * 60))))
        }
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AcaiToday", provider: TodayProvider()) { e in
            TodayView(e: e)
                .containerBackground(for: .widget) { LinearGradient(colors: [purple, purple2], startPoint: .topTrailing, endPoint: .bottomLeading) }
                .environment(\.layoutDirection, .rightToLeft)
        }
        .configurationDisplayName("أساي دوز اليوم")
        .description("مبيعات وطلبات اليوم")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct TodayView: View {
    let e: TodayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let g = e.g {
            switch family {
            case .accessoryInline:
                Text("أساي دوز \(g.salesText) · \(g.orders) طلب")
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Text("\(g.orders)").font(.title2.bold())
                    Text("طلب").font(.caption2)
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("أساي دوز · اليوم").font(.caption2.bold())
                    Text("\(g.salesText) ر.ع").font(.headline).monospacedDigit()
                    Text("\(g.orders) طلب\(g.pending > 0 ? " · \(g.pending) ينتظر" : "")").font(.caption2)
                }
            case .systemMedium:
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("مبيعات اليوم").font(.caption.bold()).foregroundStyle(lilac)
                        Text(g.salesText).font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(cream)
                            .minimumScaleFactor(0.6).lineLimit(1)
                        Text("ر.ع · آخر تحديث \(g.at)").font(.caption2).foregroundStyle(lilac)
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 8) {
                        pill("\(g.orders)", "طلب", cream, purple)
                        pill("\(g.pending)", "ينتظر", g.pending > 0 ? orange : cream.opacity(0.2), g.pending > 0 ? purple : cream)
                    }
                }
            default:
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("اليوم").font(.caption.bold()).foregroundStyle(lilac)
                        Spacer()
                        if g.pending > 0 {
                            Text("\(g.pending)").font(.caption.bold()).foregroundStyle(purple)
                                .frame(minWidth: 20, minHeight: 20).background(orange, in: Circle())
                        }
                    }
                    Spacer(minLength: 0)
                    Text(g.salesText).font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(cream)
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text("ر.ع · \(g.orders) طلب").font(.caption.weight(.semibold)).foregroundStyle(lilac)
                }
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "lock.fill").foregroundStyle(lilac)
                Text("افتح تطبيق أساي دوز وسجّل دخول").font(.caption.weight(.semibold)).foregroundStyle(cream).multilineTextAlignment(.center)
            }
        }
    }

    private func pill(_ v: String, _ l: String, _ bg: Color, _ fg: Color) -> some View {
        VStack(spacing: 0) {
            Text(v).font(.title3.bold()).monospacedDigit()
            Text(l).font(.caption2.weight(.semibold))
        }
        .foregroundStyle(fg)
        .frame(width: 70, height: 50)
        .background(bg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Live Activity (Lock Screen + Dynamic Island)

struct OrdersLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OrdersActivityAttributes.self) { ctx in
            let s = ctx.state
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("أساي دوز · اليوم").font(.caption.bold()).foregroundStyle(lilac)
                    Text(String(format: "%.3f", s.sales)).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(cream)
                    Text("ر.ع · \(s.orders) طلب\(s.lastRef.isEmpty ? "" : " · آخر طلب #\(s.lastRef)")").font(.caption2).foregroundStyle(lilac)
                }
                Spacer()
                VStack(spacing: 0) {
                    Text("\(s.pending)").font(.title.bold()).monospacedDigit()
                    Text("ينتظر").font(.caption2.bold())
                }
                .foregroundStyle(s.pending > 0 ? purple : cream)
                .frame(width: 66, height: 66)
                .background(s.pending > 0 ? orange : cream.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(16)
            .environment(\.layoutDirection, .rightToLeft)
            .activityBackgroundTint(purple)
            .activitySystemActionForegroundColor(cream)
        } dynamicIsland: { ctx in
            let s = ctx.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("المبيعات").font(.caption2).foregroundStyle(lilac)
                        Text(String(format: "%.3f", s.sales)).font(.title3.bold()).monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("ينتظر").font(.caption2).foregroundStyle(lilac)
                        Text("\(s.pending)").font(.title3.bold()).foregroundStyle(s.pending > 0 ? orange : .white)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("\(s.orders) طلب اليوم\(s.lastRef.isEmpty ? "" : " · آخر طلب #\(s.lastRef)") · \(s.at)")
                        .font(.caption).foregroundStyle(lilac)
                }
            } compactLeading: {
                Image(systemName: "cup.and.saucer.fill").foregroundStyle(orange)
            } compactTrailing: {
                Text(s.pending > 0 ? "\(s.pending)" : "\(s.orders)").font(.caption.bold()).monospacedDigit()
                    .foregroundStyle(s.pending > 0 ? orange : .white)
            } minimal: {
                Text("\(s.pending > 0 ? s.pending : s.orders)").font(.caption2.bold()).foregroundStyle(orange)
            }
            .keylineTint(orange)
        }
    }
}
