import Foundation
import SwiftData

@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let schema = Schema([Habit.self, HabitEvent.self, PlannerTask.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [configuration])

        let start = Calendar.current.date(byAdding: .day, value: -42, to: .now)!
        let habit = Habit(
            name: "No alcohol",
            habitDescription: "Choosing clearer mornings.",
            tint: .indigo,
            symbolName: "drop.fill",
            startAt: start
        )
        container.mainContext.insert(habit)
        container.mainContext.insert(
            PlannerTask(
                title: "Take a short walk",
                scheduledDay: .now,
                timeMode: .daySection,
                daySection: .morning,
                habitID: habit.id
            )
        )
        return container
    }()
}
