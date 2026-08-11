//
//  SinceApp.swift
//  Since
//
//  Created by Charlie Hardgrove on 7/30/26.
//

import SwiftUI
import SwiftData

@main
struct SinceApp: App {
    @StateObject private var healthKitManager = HealthKitManager()
    @AppStorage(SinceAppearance.storageKey) private var appearanceRawValue = SinceAppearance.system.rawValue

    private let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Habit.self,
            HabitEvent.self,
            PlannerTask.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(healthKitManager)
                .preferredColorScheme(
                    SinceAppearance(rawValue: appearanceRawValue)?.colorScheme
                )
        }
        .modelContainer(sharedModelContainer)
    }
}
