import SwiftUI

struct RootView: View {

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var engine: CollectionEngine
    @State private var selectedTab = Tab.map

    enum Tab: Hashable {
        case map, streets, stats, achievements, settings
    }

    var body: some View {
        Group {
            if settings.hasOnboarded {
                tabs
            } else {
                OnboardingView()
            }
        }
        .task {
            // Keep the screen awake only while a trip is running, and only if
            // the user asked for it.
            UIApplication.shared.isIdleTimerDisabled = settings.keepScreenAwake && engine.isRunning
        }
        .onChange(of: engine.isRunning) { _, running in
            UIApplication.shared.isIdleTimerDisabled = settings.keepScreenAwake && running
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            MapScreen()
                .tabItem { Label("Map", systemImage: "map.fill") }
                .tag(Tab.map)

            StreetsScreen()
                .tabItem { Label("Streets", systemImage: "list.bullet.rectangle") }
                .tag(Tab.streets)

            StatsScreen()
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }
                .tag(Tab.stats)

            AchievementsScreen()
                .tabItem { Label("Badges", systemImage: "rosette") }
                .tag(Tab.achievements)

            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .tint(Theme.accent)
    }
}
