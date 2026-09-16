import SwiftUI

@main
struct StreetCollectorApp: App {

    @StateObject private var environment = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .environmentObject(environment.engine)
                .environmentObject(environment.coverage)
                .environmentObject(environment.data)
                .environmentObject(environment.game)
                .environmentObject(environment.trips)
                .environmentObject(environment.location)
                .environmentObject(environment.notifications)
                .environmentObject(environment.settings)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                environment.applicationDidEnterBackground()
            case .active:
                environment.applicationWillEnterForeground()
            default:
                break
            }
        }
    }
}
