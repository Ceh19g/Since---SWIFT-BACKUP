import Foundation

enum HabitManager {
    static func orderedActive(_ habits: [Habit]) -> [Habit] {
        habits
            .filter { !$0.isArchived }
            .sorted {
                if $0.isPinned != $1.isPinned {
                    return $0.isPinned
                }
                return $0.createdAt < $1.createdAt
            }
    }

    static func makePrimary(_ habit: Habit, among habits: [Habit]) {
        guard !habit.isArchived else { return }
        habits.forEach { $0.isPinned = $0.id == habit.id }
    }

    static func archive(_ habit: Habit, among habits: [Habit]) {
        let wasPrimary = habit.isPinned
        habit.isArchived = true
        habit.isPinned = false

        if wasPrimary {
            ensureOnePrimary(among: habits, excluding: habit.id)
        }
    }

    static func restore(_ habit: Habit, among habits: [Habit]) {
        habit.isArchived = false
        ensureOnePrimary(among: habits)
    }

    static func prepareForDeletion(_ habit: Habit, among habits: [Habit]) {
        let wasPrimary = habit.isPinned
        habit.isPinned = false

        if wasPrimary {
            ensureOnePrimary(among: habits, excluding: habit.id)
        }
    }

    static func ensureOnePrimary(among habits: [Habit], excluding excludedID: UUID? = nil) {
        let active = habits
            .filter { !$0.isArchived && $0.id != excludedID }
            .sorted { $0.createdAt < $1.createdAt }

        guard let preferred = active.first(where: \.isPinned) ?? active.first else {
            return
        }

        habits.forEach { candidate in
            candidate.isPinned = candidate.id == preferred.id
        }
    }
}
