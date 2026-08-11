import SwiftData
import SwiftUI

struct HabitsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var plannerTasks: [PlannerTask]
    @Binding var isPresentingNewHabit: Bool
    @State private var habitPendingDeletion: Habit?
    @State private var persistenceIssue: PersistenceIssue?

    private var activeHabits: [Habit] {
        habits.filter { !$0.isArchived }
    }

    private var archivedHabits: [Habit] {
        habits.filter(\.isArchived)
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding(
            get: { habitPendingDeletion != nil },
            set: { if !$0 { habitPendingDeletion = nil } }
        )
    }

    var body: some View {
        Group {
            if habits.isEmpty {
                ContentUnavailableView(
                    "No habits yet",
                    systemImage: "square.grid.2x2",
                    description: Text("Create a private timeline to begin.")
                )
            } else {
                List {
                    if !activeHabits.isEmpty {
                        Section("Active") {
                            ForEach(activeHabits) { habit in
                                NavigationLink {
                                    HabitDetailView(habit: habit)
                                } label: {
                                    HabitListRow(habit: habit, healthStepTotals: healthKitManager.stepTotals)
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    if !habit.isPinned {
                                        Button {
                                            makePrimary(habit)
                                        } label: {
                                            Label("Primary", systemImage: "pin.fill")
                                        }
                                        .tint(.indigo)
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        archive(habit)
                                    } label: {
                                        Label("Archive", systemImage: "archivebox")
                                    }
                                    .tint(.orange)

                                    Button(role: .destructive) {
                                        habitPendingDeletion = habit
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }

                    if !archivedHabits.isEmpty {
                        Section("Archived") {
                            ForEach(archivedHabits) { habit in
                                NavigationLink {
                                    HabitDetailView(habit: habit)
                                } label: {
                                    HabitListRow(habit: habit, healthStepTotals: healthKitManager.stepTotals)
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        restore(habit)
                                    } label: {
                                        Label("Restore", systemImage: "arrow.uturn.backward")
                                    }
                                    .tint(.green)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        habitPendingDeletion = habit
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Habits")
        .toolbar {
            Button {
                isPresentingNewHabit = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Create a habit")
        }
        .alert(
            "Delete \(habitPendingDeletion?.name ?? "habit")?",
            isPresented: isConfirmingDeletion
        ) {
            Button("Cancel", role: .cancel) {
                habitPendingDeletion = nil
            }
            Button("Delete Habit", role: .destructive) {
                deletePendingHabit()
            }
        } message: {
            Text("This permanently removes the habit and its complete history. This cannot be undone.")
        }
        .persistenceIssueAlert($persistenceIssue)
        .task {
            guard activeHabits.contains(where: \.isHealthPowered) else { return }
            await healthKitManager.refreshRecentDays()
        }
    }

    private func makePrimary(_ habit: Habit) {
        HabitManager.makePrimary(habit, among: habits)
        habit.updatedAt = .now
        saveChanges()
    }

    private func archive(_ habit: Habit) {
        HabitManager.archive(habit, among: habits)
        habit.updatedAt = .now
        saveChanges()
    }

    private func restore(_ habit: Habit) {
        HabitManager.restore(habit, among: habits)
        habit.updatedAt = .now
        saveChanges()
    }

    private func deletePendingHabit() {
        guard let habit = habitPendingDeletion else { return }
        HabitManager.prepareForDeletion(habit, among: habits)
        PlannerTaskManager.clearHabitConnection(habit.id, from: plannerTasks)
        modelContext.delete(habit)
        do {
            try modelContext.save()
            habitPendingDeletion = nil
        } catch {
            modelContext.rollback()
            persistenceIssue = PersistenceIssue(title: "Habit Could Not Be Deleted", error: error)
        }
    }

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            persistenceIssue = PersistenceIssue(error: error)
        }
    }
}

private struct HabitListRow: View {
    let habit: Habit
    let healthStepTotals: [Date: Int]

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: habit.symbolName)
                .font(.headline)
                .frame(width: 42, height: 42)
                .foregroundStyle(habit.tint.color)
                .background(habit.tint.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(habit.name)
                        .font(.headline)

                    if habit.isPinned && !habit.isArchived {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(habit.tint.color)
                            .accessibilityLabel("Primary habit")
                    }
                }

                Text(rowSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var rowSummary: String {
        if habit.isArchived {
            return "Archived · \(habit.trackingTitle)"
        }
        if habit.isHealthPowered {
            let today = Calendar.autoupdatingCurrent.startOfDay(for: .now)
            let value = healthStepTotals[today]
            let target = Int((habit.healthGoalValue ?? 8_000).rounded())
            return value.map { "\($0.formatted()) of \(target.formatted()) steps" }
                ?? "No step data available"
        }
        return HabitTrackingManager.summary(for: habit)
    }
}
