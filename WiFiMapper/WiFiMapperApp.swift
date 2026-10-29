import Observation
import SwiftData
import SwiftUI

@main
struct WiFiMapperApp: App {
    @State private var location = LocationService()
    @State private var path: NetworkPathService
    @State private var monitor: SignalMonitor
    @State private var router = Router()
    @State private var ads = AdsManager()
    @State private var store = PurchaseStore()

    init() {
        let path = NetworkPathService()
        _path = State(initialValue: path)
        _monitor = State(initialValue: SignalMonitor(path: path))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(location)
                .environment(path)
                .environment(monitor)
                .environment(router)
                .environment(ads)
                .environment(store)
        }
        .modelContainer(for: [WiFiMap.self, SignalSample.self])
    }
}

enum Route: Hashable {
    case map(WiFiMap)
    case record(RecordingTarget)
    case checkHere
    case compare(WiFiMap)
    case settings
}

@MainActor
@Observable
final class Router {
    var path = NavigationPath()

    func show(_ route: Route) {
        path.append(route)
    }
}

/// Owns navigation and starts/stops sensing with the app's lifecycle. Measuring keeps
/// going in the background only while a recording is subscribed to the monitor.
struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(LocationService.self) private var location
    @Environment(SignalMonitor.self) private var monitor
    @Environment(Router.self) private var router
    @Environment(AdsManager.self) private var ads
    @Environment(PurchaseStore.self) private var store
    #if DEBUG
    @Environment(\.modelContext) private var context
    #endif

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .map(let map): MapDetailView(map: map)
                    case .record(let target): RecordingView(target: target)
                    case .checkHere: CheckHereView()
                    case .compare(let map): CompareModesView(map: map)
                    case .settings: SettingsView()
                    }
                }
        }
        .tint(Brand.blue)
        .task { await store.load() }
        .onChange(of: store.adsRemoved, initial: true) { _, removed in
            ads.adsRemoved = removed
        }
        // Ask for ad consent only after the location prompt is answered, so prompts don't stack.
        .task(id: location.authorization) {
            if location.authorization != .notDetermined {
                await ads.startIfNeeded()
            }
        }
        #if DEBUG
        .task {
            DemoData.seedIfRequested(context)
            if let route = DemoData.requestedRoute(context) { router.show(route) }
        }
        #endif
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active:
                location.requestAccess()
                monitor.start()
            case .background where !monitor.hasSubscriber:
                monitor.stop()
                location.stop()
            default:
                break
            }
        }
    }
}
