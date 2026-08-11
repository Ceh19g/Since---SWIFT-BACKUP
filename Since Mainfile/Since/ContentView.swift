//
//  ContentView.swift
//  Since
//
//  Created by Charlie Hardgrove on 7/30/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var storedPlannerTasks: [PlannerTask]
    @State private var selection: AppTab = .today
    @State private var isPresentingNewHabit = false
    @State private var isShowingLaunch = !CommandLine.arguments.contains("--ui-testing-reset")

    var body: some View {
        ZStack {
            TabView(selection: $selection) {
                NavigationStack {
                    TodayView(isPresentingNewHabit: $isPresentingNewHabit)
                }
                .tabItem {
                    Label("Today", systemImage: "sun.max")
                }
                .tag(AppTab.today)

                NavigationStack {
                    PlannerView()
                }
                .tabItem {
                    Label("Planner", systemImage: "checklist")
                }
                .tag(AppTab.planner)

                NavigationStack {
                    HabitCalendarView()
                }
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
                .tag(AppTab.calendar)

                NavigationStack {
                    HabitsView(isPresentingNewHabit: $isPresentingNewHabit)
                }
                .tabItem {
                    Label("Habits", systemImage: "square.grid.2x2")
                }
                .tag(AppTab.habits)

                NavigationStack {
                    MoreView()
                }
                .tabItem {
                    Label("More", systemImage: "ellipsis")
                }
                .tag(AppTab.more)
            }
            .tint(.indigo)

            if isShowingLaunch {
                SinceLaunchView()
                    .transition(.opacity.animation(SinceMotion.quick(reduceMotion: reduceMotion)))
                    .zIndex(1)
            }
        }
        .sheet(isPresented: $isPresentingNewHabit) {
            AddHabitView()
        }
        .task {
            if CommandLine.arguments.contains("--ui-testing-reset") {
                try? modelContext.delete(model: PlannerTask.self)
                try? modelContext.delete(model: HabitEvent.self)
                try? modelContext.delete(model: Habit.self)
                try? modelContext.save()
                return
            }

            if PlannerTaskManager.normalizeLegacyState(storedPlannerTasks) {
                try? modelContext.save()
            }

            if reduceMotion {
                isShowingLaunch = false
                return
            }

            // Keep the branded handoff brief and nonblocking. The system launch
            // screen remains the primary launch experience.
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            withAnimation(SinceMotion.quick(reduceMotion: false)) {
                isShowingLaunch = false
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
        .environmentObject(HealthKitManager())
}
