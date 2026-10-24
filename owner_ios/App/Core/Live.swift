import SwiftUI
import ActivityKit
import WidgetKit
import BackgroundTasks

/// Keeps the widget and the Live Activity fed with today's numbers.
@Observable
final class Live {
    static let shared = Live()
    static let refreshTask = "com.acaidose.owner.refresh"

    var glance: Glance? = Glance.cached
    var activityOn = false
    var enabledByUser: Bool {
        get { UserDefaults.standard.bool(forKey: "live_on") }
        set { UserDefaults.standard.set(newValue, forKey: "live_on") }
    }

    private init() {
        activityOn = !Activity<OrdersActivityAttributes>.activities.isEmpty
    }

    /// After login: get a read-only key for the widget (once per device).
    func ensureKey() async {
        // The widget shows Açaí Dose; a key is only made while signed in to it
        if SharedStore.widgetKey != nil || BizStore.shared.current != .acai { return }
        if let r = try? await API.shared.post("widget_token"), !r["token"].string.isEmpty {
            SharedStore.widgetKey = r["token"].string
        }
    }

    func signOut() async {
        SharedStore.widgetKey = nil
        Glance.cached = nil
        glance = nil
        WidgetCenter.shared.reloadAllTimelines()
        await stop()
    }

    /// Fetch today's numbers, update the widget and the Live Activity.
    @MainActor
    func refresh() async {
        await ensureKey()
        guard let g = await Glance.fetch() else { return }
        let changed = g != glance
        glance = g
        if changed { WidgetCenter.shared.reloadAllTimelines() }
        let state = OrdersActivityAttributes.ContentState(g)
        for a in Activity<OrdersActivityAttributes>.activities {
            await a.update(ActivityContent(state: state, staleDate: Date.now.addingTimeInterval(30 * 60)))
        }
        if enabledByUser && Activity<OrdersActivityAttributes>.activities.isEmpty { start() }
    }

    var canUseActivities: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    @MainActor
    func start() {
        guard canUseActivities, Activity<OrdersActivityAttributes>.activities.isEmpty else { activityOn = !Activity<OrdersActivityAttributes>.activities.isEmpty; return }
        let g = glance ?? Glance(day: "", sales: 0, orders: 0, pending: 0, new: 0, expenses: 0, lastRef: nil, at: "")
        do {
            _ = try Activity.request(attributes: OrdersActivityAttributes(shop: "Açaí Dose"),
                                     content: ActivityContent(state: .init(g), staleDate: Date.now.addingTimeInterval(30 * 60)))
            activityOn = true
            enabledByUser = true
        } catch {
            activityOn = false
        }
    }

    @MainActor
    func stop() async {
        enabledByUser = false
        for a in Activity<OrdersActivityAttributes>.activities {
            await a.end(nil, dismissalPolicy: .immediate)
        }
        activityOn = false
    }

    // MARK: background refresh (iOS decides when; roughly every 15 minutes at best)

    private static var registered = false

    static func register() {
        if registered { return }   // registering the same task twice crashes
        registered = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTask, using: nil) { task in
            schedule()
            let work = Task { @MainActor in
                await Live.shared.refresh()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() {
        let req = BGAppRefreshTaskRequest(identifier: refreshTask)
        req.earliestBeginDate = Date.now.addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }
}
