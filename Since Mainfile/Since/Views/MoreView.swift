import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct MoreView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var plannerTasks: [PlannerTask]

    @AppStorage("lastSuccessfulBackup") private var lastSuccessfulBackup = 0.0
    @AppStorage(SinceAppearance.storageKey) private var appearanceRawValue = SinceAppearance.system.rawValue
    @State private var backupDocument: SinceBackupDocument?
    @State private var pendingRestore: SinceBackupArchive?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var statusTitle = ""
    @State private var statusMessage = ""
    @State private var isShowingStatus = false

    var body: some View {
        List {
            Section {
                NavigationLink {
                    InsightsView()
                } label: {
                    Label("Insights", systemImage: "chart.xyaxis.line")
                }
                .accessibilityIdentifier("open-insights-button")
            } footer: {
                Text("Private summaries calculated from your habit history and planner activity.")
            }

            Section("Connections") {
                NavigationLink {
                    HealthConnectionView()
                } label: {
                    Label("Apple Health", systemImage: "heart.fill")
                }
                .accessibilityIdentifier("open-apple-health-button")
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")

                    Picker("Appearance", selection: $appearanceRawValue) {
                        ForEach(SinceAppearance.allCases) { appearance in
                            Text(appearance.title)
                                .tag(appearance.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("appearance-picker")
                    .accessibilityLabel("App appearance")
                    .accessibilityHint("Choose System, Light, or Dark appearance")
                }
                .padding(.vertical, 4)
            } header: {
                Text("Display")
            } footer: {
                Text("System automatically follows your iPhone's appearance setting.")
            }

            Section {
                HStack {
                    Label("Storage", systemImage: "iphone")
                    Spacer()
                    Text("On this iPhone")
                        .foregroundStyle(.secondary)
                }

                Button {
                    prepareBackup()
                } label: {
                    Label("Export Backup", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("export-backup-button")

                Button {
                    isImporting = true
                } label: {
                    Label("Restore Backup", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("restore-backup-button")

                if lastSuccessfulBackup > 0 {
                    HStack {
                        Text("Last backup")
                        Spacer()
                        Text(Date(timeIntervalSince1970: lastSuccessfulBackup).formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack {
                        Text("Last backup")
                        Spacer()
                        Text("Not yet")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Data & Safety")
            } footer: {
                Text("Your data is stored privately on this iPhone. Deleting the app deletes its local data, so save backups somewhere safe such as iCloud Drive.")
            }

            Section("App") {
                HStack {
                    Label("Backup format", systemImage: "doc.badge.gearshape")
                    Spacer()
                    Text("Version \(SinceBackupArchive.currentVersion)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("More")
        .fileExporter(
            isPresented: $isExporting,
            document: backupDocument,
            contentType: .json,
            defaultFilename: backupFilename
        ) { result in
            switch result {
            case .success:
                lastSuccessfulBackup = Date.now.timeIntervalSince1970
                showStatus(
                    title: "Backup Saved",
                    message: "Your habits, streak history, and planner tasks were exported successfully."
                )
            case let .failure(error):
                showStatus(title: "Backup Not Saved", message: error.localizedDescription)
            }
            backupDocument = nil
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            loadBackup(result)
        }
        .confirmationDialog(
            "Restore this backup?",
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Restore Backup") {
                restorePendingBackup()
            }
            Button("Cancel", role: .cancel) {
                pendingRestore = nil
            }
        } message: {
            if let pendingRestore {
                Text(
                    "This backup contains \(pendingRestore.habits.count) habits and \(pendingRestore.plannerTasks.count) planner tasks. Matching records will be updated; other current records will be kept."
                )
            }
        }
        .alert(statusTitle, isPresented: $isShowingStatus) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(statusMessage)
        }
    }

    private var backupFilename: String {
        "Since Backup \(Date.now.formatted(.dateTime.year().month().day()))"
    }

    private func prepareBackup() {
        backupDocument = SinceBackupDocument(
            archive: SinceBackupService.makeArchive(
                habits: habits,
                plannerTasks: plannerTasks
            )
        )
        isExporting = true
    }

    private func loadBackup(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else {
                throw SinceBackupError.unreadableFile
            }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let archive = try SinceBackupCoding.decoder.decode(SinceBackupArchive.self, from: data)
            try SinceBackupService.validate(archive)
            pendingRestore = archive
        } catch {
            showStatus(title: "Backup Cannot Be Restored", message: error.localizedDescription)
        }
    }

    private func restorePendingBackup() {
        guard let pendingRestore else { return }

        do {
            let summary = try SinceBackupService.restore(
                pendingRestore,
                currentHabits: habits,
                currentTasks: plannerTasks,
                in: modelContext
            )
            self.pendingRestore = nil
            showStatus(title: "Backup Restored", message: summary.message)
        } catch {
            self.pendingRestore = nil
            showStatus(title: "Restore Failed", message: error.localizedDescription)
        }
    }

    private func showStatus(title: String, message: String) {
        statusTitle = title
        statusMessage = message
        isShowingStatus = true
    }
}
