import SwiftUI

/// Four pages: the pitch, then permissions.
///
/// The permission ask comes last and explains itself, because "Always" is a big
/// thing to ask for on page one. Each page animates a little illustration built
/// out of the same neon vocabulary as the map, so the app has shown you what it
/// looks like before it asks for anything.
struct OnboardingView: View {

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var notifications: NotificationService

    @State private var page = 0

    private let pages: [Page] = [
        Page(
            symbol: "map.fill",
            tint: Theme.accent,
            title: "Collect your city",
            body: "Every street you go down lights up and stays lit. The rest stays dark. The goal is simple and slightly unhinged: all of them."
        ),
        Page(
            symbol: "figure.walk.motion",
            tint: Theme.hot,
            title: "It runs in your pocket",
            body: "Start a trip and put the phone away. Walking, cycling, driving — it matches you to real streets and scores whatever's new."
        ),
        Page(
            symbol: "rosette",
            tint: Theme.violet,
            title: "Levels, streaks, badges",
            body: "Backstreets pay more than motorway. Finish a street end to end for the bonus. Come back tomorrow to keep the streak alive."
        ),
    ]

    private struct Page {
        let symbol: String
        let tint: Color
        let title: String
        let body: String
    }

    var body: some View {
        ZStack {
            Theme.ink.ignoresSafeArea()
            aurora

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        pageView(item)
                            .tag(index)
                    }
                    permissionsPage
                        .tag(pages.count)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                dots
                    .padding(.bottom, 26)
            }
        }
    }

    /// Slow-drifting colour wash behind everything. Cheap, and it stops the
    /// first screen the user ever sees from being flat black.
    private var aurora: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                RadialGradient(
                    colors: [currentTint.opacity(0.35), .clear],
                    center: UnitPoint(x: 0.5 + 0.22 * cos(t / 7), y: 0.28 + 0.12 * sin(t / 5)),
                    startRadius: 10,
                    endRadius: 420
                )
                RadialGradient(
                    colors: [Theme.violet.opacity(0.22), .clear],
                    center: UnitPoint(x: 0.3 + 0.2 * sin(t / 9), y: 0.75 + 0.1 * cos(t / 6)),
                    startRadius: 10,
                    endRadius: 380
                )
            }
            .blur(radius: 30)
            .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.8), value: page)
    }

    private var currentTint: Color {
        page < pages.count ? pages[page].tint : Theme.accent
    }

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(0...pages.count, id: \.self) { index in
                Capsule()
                    .fill(index == page ? AnyShapeStyle(Theme.primaryGradient) : AnyShapeStyle(Color.white.opacity(0.18)))
                    .frame(width: index == page ? 22 : 7, height: 7)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: page)
            }
        }
    }

    private func pageView(_ item: Page) -> some View {
        VStack(spacing: 26) {
            Spacer()

            ZStack {
                Circle()
                    .fill(item.tint.opacity(0.16))
                    .frame(width: 190, height: 190)
                    .blur(radius: 20)
                Circle()
                    .strokeBorder(item.tint.opacity(0.3), lineWidth: 1)
                    .frame(width: 150, height: 150)
                Circle()
                    .strokeBorder(item.tint.opacity(0.15), lineWidth: 1)
                    .frame(width: 190, height: 190)
                Image(systemName: item.symbol)
                    .font(.system(size: 66, weight: .bold, design: .rounded))
                    .foregroundStyle(item.tint)
                    .shadow(color: item.tint.opacity(0.6), radius: 24)
            }

            VStack(spacing: 14) {
                Text(item.title)
                    .font(Theme.display)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(item.body)
                    .font(Theme.body)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 34)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("Next") {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { page += 1 }
            }
            .buttonStyle(NeonButtonStyle())
            .padding(.bottom, 40)
        }
    }

    private var permissionsPage: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "location.fill.viewfinder")
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accent)
                .shadow(color: Theme.accent.opacity(0.5), radius: 20)

            Text("Two permissions")
                .font(Theme.display)
                .foregroundStyle(.white)

            VStack(spacing: 12) {
                permissionExplainer(
                    symbol: "location.fill",
                    tint: Theme.accent,
                    title: "Location, Always",
                    detail: "\"While using\" only collects with the app open on screen. \"Always\" is what lets it fill streets in from your pocket.",
                    granted: location.hasBackgroundPermission
                )
                permissionExplainer(
                    symbol: "bell.fill",
                    tint: Theme.partial,
                    title: "Notifications",
                    detail: "Optional. Milestones and trip summaries, capped at one street alert every ten minutes.",
                    granted: notifications.isAuthorized
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                if !location.hasAnyPermission {
                    Button("Allow location") { location.requestWhenInUse() }
                        .buttonStyle(NeonButtonStyle())
                } else if location.authorizationStatus == .authorizedWhenInUse {
                    Button("Upgrade to Always") { location.requestAlways() }
                        .buttonStyle(NeonButtonStyle())
                }

                if !notifications.isAuthorized {
                    Button("Enable notifications") { notifications.requestAuthorization() }
                        .font(Theme.font(14, .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Button {
                    withAnimation { settings.hasOnboarded = true }
                } label: {
                    HStack(spacing: 6) {
                        Text(location.hasAnyPermission ? "Start collecting" : "Skip for now")
                        Image(systemName: "arrow.right")
                    }
                }
                .buttonStyle(
                    location.hasAnyPermission
                        ? NeonButtonStyle(gradient: Theme.legendaryGradient, glowColor: Theme.violet)
                        : NeonButtonStyle(gradient: Theme.primaryGradient, glowColor: .clear)
                )
                .opacity(location.hasAnyPermission ? 1 : 0.5)
            }
            .padding(.bottom, 40)
        }
    }

    private func permissionExplainer(
        symbol: String,
        tint: Color,
        title: String,
        detail: String,
        granted: Bool
    ) -> some View {
        GlassPanel(tint: tint, glow: granted) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: granted ? "checkmark.circle.fill" : symbol)
                    .font(Theme.font(16, .bold))
                    .foregroundStyle(granted ? tint : tint.opacity(0.7))
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(Theme.font(14, .bold))
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(Theme.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
