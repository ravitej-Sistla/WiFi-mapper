import Observation
import SwiftData
import SwiftUI

@main
struct WiFiMapperApp: App {
    @State private var location = LocationService()
    @State private var path: NetworkPathService
    @State private var monitor: SignalMonitor
    @State private var router = Router()

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
