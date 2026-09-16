import CoreLocation
import Foundation
import os

/// Wraps `CLLocationManager` for continuous, background-capable tracking.
///
/// The settings here are the difference between an app that fills in streets
/// and one that eats your battery: full accuracy while a trip is running,
/// significant-location-change monitoring when it isn't, and automatic pausing
/// so standing still costs nothing.
@MainActor
final class LocationService: NSObject, ObservableObject {

    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var latestLocation: CLLocation?
    @Published private(set) var isTracking = false
    @Published private(set) var accuracyAuthorization: CLAccuracyAuthorization = .reducedAccuracy

    /// Called on every accepted fix. Set by the collection engine.
    var onLocation: ((CLLocation) -> Void)?

    private let manager = CLLocationManager()
    private let logger = Logger(subsystem: "com.example.StreetCollector", category: "Location")

    /// Fixes closer together than this add nothing at walking speed and cost
    /// battery at driving speed. 8 m is under a car length.
    private let distanceFilter: CLLocationDistance = 8

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = distanceFilter
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = true
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
    }

    var hasAnyPermission: Bool {
        authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse
    }

    var hasBackgroundPermission: Bool {
        authorizationStatus == .authorizedAlways
    }

    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    /// Only meaningful once when-in-use has been granted; iOS ignores it
    /// otherwise.
    func requestAlways() {
        manager.requestAlwaysAuthorization()
    }

    func requestFullAccuracy() {
        guard accuracyAuthorization == .reducedAccuracy else { return }
        manager.requestTemporaryFullAccuracyAuthorization(
            withPurposeKey: "StreetCollectionAccuracy"
        ) { [weak self] error in
            if let error {
                self?.logger.error("Full accuracy request failed: \(error.localizedDescription, privacy: .public)")
            }
            Task { @MainActor in
                self?.accuracyAuthorization = self?.manager.accuracyAuthorization ?? .reducedAccuracy
            }
        }
    }

    func startTracking() {
        guard hasAnyPermission else {
            requestWhenInUse()
            return
        }
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = distanceFilter

        if hasBackgroundPermission {
            // Required for updates to continue with the app suspended, and it
            // throws if "Always" hasn't been granted.
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
        }

        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        isTracking = true
        logger.info("Tracking started")
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        manager.allowsBackgroundLocationUpdates = false
        isTracking = false
        logger.info("Tracking stopped")
    }

    /// Cheap always-on monitoring used between trips. Wakes the app when the
    /// user moves a meaningful distance so a trip can auto-start.
    func startMonitoringSignificantChanges() {
        guard hasBackgroundPermission,
              CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        manager.startMonitoringSignificantLocationChanges()
    }

    func stopMonitoringSignificantChanges() {
        manager.stopMonitoringSignificantLocationChanges()
    }

    func requestOneShotLocation() {
        guard hasAnyPermission else { return }
        manager.requestLocation()
    }
}

extension LocationService: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let accepted = locations.filter { location in
            // Cached fixes from before the app woke up are worse than useless:
            // they can draw a straight line across town.
            location.timestamp.timeIntervalSinceNow > -30
                && location.horizontalAccuracy > 0
        }
        guard !accepted.isEmpty else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            for location in accepted {
                self.latestLocation = location
                self.onLocation?(location)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.logger.error("Location failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorizationStatus = manager.authorizationStatus
            self.accuracyAuthorization = manager.accuracyAuthorization
            if self.isTracking && self.hasAnyPermission {
                self.startTracking()
            }
        }
    }

    nonisolated func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            self?.logger.info("Location updates paused by the system")
        }
    }
}
