import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct HealthConnectionView: View {
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @Environment(\.openURL) private var openURL
    @Query(sort: \Habit.createdAt) private var habits: [Habit]

    private var stepHabits: [Habit] {
        habits.filter { !$0.isArchived && $0.healthMetric == .steps }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                        .frame(width: 38, height: 38)
                        .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Apple Health")
                            .font(.headline)
                        Text(statusTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Circle()
                        .fill(statusColor)
                        .frame(width: 9, height: 9)
                        .accessibilityHidden(true)
                }
            } footer: {
                Text("Since requests read-only access to steps. It cannot add, edit, or delete Health data.")
            }

            Section("Reading") {
                HStack {
                    Label("Steps", systemImage: "figure.walk")
                    Spacer()
                    Text(stepHabits.isEmpty ? "No tracker" : "Enabled")
                        .foregroundStyle(.secondary)
                }

                if let lastUpdated = healthKitManager.lastUpdated {
                    HStack {
                        Text("Last refreshed")
                        Spacer()
                        Text(lastUpdated.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                if healthKitManager.accessState == .notRequested {
                    Button {
                        Task {
                            await healthKitManager.requestStepAccess()
                            await healthKitManager.refreshRecentDays()
                        }
                    } label: {
                        Label("Connect Apple Health", systemImage: "heart.fill")
                    }
                    .accessibilityIdentifier("connect-apple-health-button")
                } else {
                    Button {
                        Task { await healthKitManager.refreshRecentDays() }
                    } label: {
                        Label(
                            healthKitManager.isRefreshing ? "Refreshing…" : "Refresh Step Data",
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .disabled(healthKitManager.isRefreshing)

                    #if os(iOS)
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        Label("Open Since Settings", systemImage: "gear")
                    }
                    #endif
                }
            } footer: {
                Text("Health access is controlled by iOS. If no steps appear, check Settings → Privacy & Security → Health → Since.")
            }

            Section("Privacy") {
                Label("Daily totals are displayed only inside Since", systemImage: "lock.fill")
                Label("Raw step samples remain in Apple Health", systemImage: "heart.text.square")
                Label("No Health information is included in Since backups", systemImage: "externaldrive")
            }
            .font(.footnote)
        }
        .navigationTitle("Apple Health")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !stepHabits.isEmpty else { return }
            await healthKitManager.refreshRecentDays()
        }
    }

    private var statusTitle: String {
        switch healthKitManager.accessState {
        case .unavailable: "Unavailable on this device"
        case .notRequested: "Not connected"
        case .ready: "Ready for step data"
        case .failed: "Needs attention"
        }
    }

    private var statusColor: Color {
        switch healthKitManager.accessState {
        case .ready: .green
        case .failed: .orange
        case .notRequested, .unavailable: .secondary
        }
    }
}
