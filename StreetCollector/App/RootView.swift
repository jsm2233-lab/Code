import SwiftUI

struct RootView: View {

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var engine: CollectionEngine
    @State private var selectedTab = Tab.map

    enum Tab: Hashable {
        case map, streets, stats, achievements, settings
    }

    init() {
        // The tab bar sits over a dark map; the default translucent light one
        // fights it. Set once, here, rather than per-screen.
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = UIColor(red: 0.078, green: 0.110, blue: 0.149, alpha: 0.92)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance

        let navigation = UINavigationBarAppearance()
        navigation.configureWithTransparentBackground()
        navigation.titleTextAttributes = [.foregroundColor: UIColor.white]
        navigation.largeTitleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 34, weight: .heavy),
        ]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
    }

    var body: some View {
        ZStack {
            if settings.hasOnboarded {
                tabs
            } else {
                OnboardingView()
            }

            CelebrationOverlay()
        }
        .preferredColorScheme(.dark)
        .task {
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
                .tabItem { Label("Streets", systemImage: "list.bullet.rectangle.fill") }
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
