import Foundation
import UserNotifications
import os

/// Local notifications for collection milestones.
///
/// Rate-limited hard: the whole point is that the app runs in your pocket, and
/// an app that buzzes once per side street gets deleted.
@MainActor
final class NotificationService: ObservableObject {

    @Published var isAuthorized = false
    @Published var notifyOnStreetCollected = true
    @Published var notifyOnAchievement = true
    @Published var notifyOnTripSummary = true

    private let centre = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "com.example.StreetCollector", category: "Notifications")
    private var lastStreetNotification = Date.distantPast
    private let streetNotificationCooldown: TimeInterval = 600

    func requestAuthorization() {
        centre.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            if let error {
                self?.logger.error("Notification auth failed: \(error.localizedDescription, privacy: .public)")
            }
            Task { @MainActor in
                self?.isAuthorized = granted
            }
        }
    }

    func refreshAuthorization() {
        centre.getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                self?.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    func postStreetCollected(_ segment: StreetSegment, xp: Int) {
        guard isAuthorized, notifyOnStreetCollected else { return }
        guard Date().timeIntervalSince(lastStreetNotification) > streetNotificationCooldown else { return }
        lastStreetNotification = Date()
        post(
            title: "Street collected",
            body: "\(segment.displayName) is yours. +\(xp) XP.",
            identifier: "street.\(segment.id)"
        )
    }

    func postAchievement(_ achievement: Achievement) {
        guard isAuthorized, notifyOnAchievement else { return }
        post(
            title: "\(achievement.tier.displayName) unlocked",
            body: "\(achievement.title) — \(achievement.detail)",
            identifier: "achievement.\(achievement.id)"
        )
    }

    func postTripSummary(_ trip: Trip) {
        guard isAuthorized, notifyOnTripSummary else { return }
        let km = trip.newStreetMetres / 1_000
        post(
            title: "Trip logged",
            body: String(
                format: "%.1f km of new streets, %d collected, +%d XP.",
                km,
                trip.completedSegmentIDs.count,
                trip.xpEarned
            ),
            identifier: "trip.\(trip.id.uuidString)"
        )
    }

    private func post(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        centre.add(request) { [logger] error in
            if let error {
                logger.error("Notification post failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
