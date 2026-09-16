import Foundation
import SwiftUI

/// Single composition root. Everything that needs wiring is built here once and
/// handed down the view tree.
@MainActor
final class AppEnvironment: ObservableObject {

    let location = LocationService()
    let data = StreetDataStore()
    let coverage = CoverageStore()
    let game = GameEngine()
    let trips = TripStore()
    let notifications = NotificationService()
    let settings = AppSettings()
    let engine: CollectionEngine

    init() {
        engine = CollectionEngine(
            location: location,
            data: data,
            coverage: coverage,
            game: game,
            trips: trips,
            notifications: notifications
        )
        game.refreshStreak()
        notifications.refreshAuthorization()
    }

    func applicationDidEnterBackground() {
        coverage.flush()
        game.flush()
    }

    func applicationWillEnterForeground() {
        game.refreshStreak()
        notifications.refreshAuthorization()
    }
}

/// User-facing preferences, persisted to `UserDefaults`.
///
/// `@AppStorage` is tempting here, but it only drives view updates when it
/// lives on a `View`. On an `ObservableObject` it silently stops republishing,
/// so preferences are `@Published` with an explicit write-through instead.
@MainActor
final class AppSettings: ObservableObject {

    private let defaults: UserDefaults

    @Published var hasOnboarded: Bool { didSet { defaults.set(hasOnboarded, forKey: "hasOnboarded") } }
    @Published var showUncollectedStreets: Bool { didSet { defaults.set(showUncollectedStreets, forKey: "showUncollectedStreets") } }
    @Published var fogOfWar: Bool { didSet { defaults.set(fogOfWar, forKey: "fogOfWar") } }
    @Published var keepScreenAwake: Bool { didSet { defaults.set(keepScreenAwake, forKey: "keepScreenAwake") } }
    @Published var hapticsOnCollect: Bool { didSet { defaults.set(hapticsOnCollect, forKey: "hapticsOnCollect") } }
    @Published var mapStyle: MapStyleOption { didSet { defaults.set(mapStyle.rawValue, forKey: "mapStyle") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "showUncollectedStreets": true,
            "fogOfWar": true,
            "hapticsOnCollect": true,
        ])
        hasOnboarded = defaults.bool(forKey: "hasOnboarded")
        showUncollectedStreets = defaults.bool(forKey: "showUncollectedStreets")
        fogOfWar = defaults.bool(forKey: "fogOfWar")
        keepScreenAwake = defaults.bool(forKey: "keepScreenAwake")
        hapticsOnCollect = defaults.bool(forKey: "hapticsOnCollect")
        mapStyle = MapStyleOption(rawValue: defaults.string(forKey: "mapStyle") ?? "") ?? .standard
    }
}

enum MapStyleOption: String, CaseIterable, Identifiable {
    case standard
    case muted
    case satellite
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .muted: return "Muted"
        case .satellite: return "Satellite"
        case .dark: return "Night"
        }
    }
}
