import SwiftUI

struct SettingsScreen: View {

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var notifications: NotificationService
    @EnvironmentObject private var data: StreetDataStore
    @EnvironmentObject private var engine: CollectionEngine

    @State private var showResetConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Permissions") {
                    permissionRow

                    if location.accuracyAuthorization == .reducedAccuracy {
                        Button("Enable precise location") {
                            location.requestFullAccuracy()
                        }
                        Text("Street matching needs precise location. With it off, the app can't tell which street you're on.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Toggle("Notifications", isOn: Binding(
                        get: { notifications.isAuthorized },
                        set: { enabled in
                            if enabled { notifications.requestAuthorization() }
                        }
                    ))
                    .disabled(notifications.isAuthorized)
                }

                Section("Map") {
                    Picker("Style", selection: $settings.mapStyle) {
                        ForEach(MapStyleOption.allCases) { Text($0.displayName).tag($0) }
                    }
                    Toggle("Fog of war", isOn: $settings.fogOfWar)
                    Toggle("Show uncollected streets", isOn: $settings.showUncollectedStreets)
                }

                Section("Collecting") {
                    Toggle("Keep screen awake during trips", isOn: $settings.keepScreenAwake)
                    Toggle("Haptics", isOn: $settings.hapticsOnCollect)
                    if notifications.isAuthorized {
                        Toggle("Notify on street collected", isOn: $notifications.notifyOnStreetCollected)
                        Toggle("Notify on badge unlocked", isOn: $notifications.notifyOnAchievement)
                        Toggle("Trip summaries", isOn: $notifications.notifyOnTripSummary)
                    }
                }

                Section("Street data") {
                    LabeledContent("Loaded tiles", value: "\(data.loadedTiles.count)")
                    LabeledContent("Segments in memory", value: "\(data.segmentCount)")
                    LabeledContent("Cache on disk", value: byteLabel)
                    if let error = data.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Button("Clear downloaded street data") {
                        data.clearCache()
                    }
                    Text("Street geometry comes from OpenStreetMap contributors, via the Overpass API. Clearing the cache keeps your collection — only the maps are refetched.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button("Reset all progress", role: .destructive) {
                        showResetConfirmation = true
                    }
                } footer: {
                    Text("Deletes every collected street, trip and badge. There is no undo and nothing is backed up off-device.")
                }

                Section("About") {
                    LabeledContent("Version", value: "1.0")
                    Link("OpenStreetMap copyright", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                }
            }
            .scrollContentBackground(.hidden)
            .cityBackground()
            .tint(Theme.accent)
            .navigationTitle("Settings")
            .confirmationDialog(
                "Reset everything?",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete all progress", role: .destructive) {
                    engine.resetEverything()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var permissionRow: some View {
        HStack {
            Text("Location")
            Spacer()
            switch location.authorizationStatus {
            case .authorizedAlways:
                Text("Always").foregroundStyle(.secondary)
            case .authorizedWhenInUse:
                Button("Upgrade to Always") { location.requestAlways() }
            case .denied, .restricted:
                Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
            default:
                Button("Allow") { location.requestWhenInUse() }
            }
        }
    }

    private var byteLabel: String {
        ByteCountFormatter.string(fromByteCount: data.cacheSizeOnDisk, countStyle: .file)
    }
}
