import SwiftUI

/// Three pages, then permissions. The permission ask comes last and explains
/// itself, because "Always" is a big thing to ask for on page one.
struct OnboardingView: View {

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var notifications: NotificationService

    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                pageView(
                    symbol: "map.fill",
                    title: "Collect your city",
                    body: "Every street you go down fills in. The rest stays dark. The goal is simple and slightly unhinged: all of them."
                )
                .tag(0)

                pageView(
                    symbol: "sparkles",
                    title: "It runs in your pocket",
                    body: "Start a trip and put your phone away. Walking, cycling, driving — it matches you to real streets and scores what's new."
                )
                .tag(1)

                pageView(
                    symbol: "rosette",
                    title: "Levels, streaks, badges",
                    body: "Backstreets are worth more than motorway. Finish a street end to end for the bonus. Come back tomorrow to keep the streak."
                )
                .tag(2)

                permissionsPage
                    .tag(3)
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
        .background(
            LinearGradient(
                colors: [Theme.accent.opacity(0.18), .clear],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        )
    }

    private func pageView(symbol: String, title: String, body: String) -> some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 72))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button("Next") { withAnimation { page += 1 } }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .padding(.bottom, 60)
        }
    }

    private var permissionsPage: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "location.fill.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(Theme.accent)
            Text("Two permissions")
                .font(.title.weight(.bold))

            VStack(alignment: .leading, spacing: 14) {
                permissionExplainer(
                    symbol: "location.fill",
                    title: "Location, Always",
                    detail: "\"While using\" only collects with the app open on screen. \"Always\" is what lets it fill streets in from your pocket."
                )
                permissionExplainer(
                    symbol: "bell.fill",
                    title: "Notifications",
                    detail: "Optional. Milestones and trip summaries only, capped at one street alert per ten minutes."
                )
            }
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 10) {
                Button {
                    location.requestWhenInUse()
                } label: {
                    Text(location.hasAnyPermission ? "Location granted" : "Allow location")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(location.hasAnyPermission)

                if location.authorizationStatus == .authorizedWhenInUse {
                    Button("Upgrade to Always") { location.requestAlways() }
                }

                Button("Enable notifications") { notifications.requestAuthorization() }
                    .disabled(notifications.isAuthorized)

                Button("Start collecting") {
                    settings.hasOnboarded = true
                }
                .font(.headline)
                .padding(.top, 6)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 60)
        }
    }

    private func permissionExplainer(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
