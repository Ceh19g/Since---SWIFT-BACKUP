import Foundation

struct CalendarDaySummary: Equatable {
    let completedTaskCount: Int
    let totalTaskCount: Int
    let trackedHabitCount: Int
    let slipCount: Int

    var incompleteTaskCount: Int {
        max(0, totalTaskCount - completedTaskCount)
    }

    var areAllTasksComplete: Bool {
        totalTaskCount > 0 && completedTaskCount == totalTaskCount
    }
}

enum CalendarActivityManager {
    static func summary(
        on date: Date,
        tasks: [PlannerTask],
        habits: [Habit],
        healthStepTotals: [Date: Int] = [:],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> CalendarDaySummary {
        let dayTasks = PlannerTaskManager.dayTasks(on: date, from: tasks, calendar: calendar)
        let trackedHabits = habits.filter {
            isHabit(
                $0,
                trackedOn: date,
                healthStepCount: healthStepTotals[calendar.startOfDay(for: date)],
                now: now,
                calendar: calendar
            )
        }
        let slips = trackedHabits.reduce(into: 0) { count, habit in
            count += slipEvents(for: habit, on: date, calendar: calendar).count
        }

        return CalendarDaySummary(
            completedTaskCount: dayTasks.filter(\.isCompleted).count,
            totalTaskCount: dayTasks.count,
            trackedHabitCount: trackedHabits.count,
            slipCount: slips
        )
    }

    static func isHabit(
        _ habit: Habit,
        trackedOn date: Date,
        healthStepCount: Int? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        if habit.isHealthPowered {
            return HabitTrackingManager.isTrackedDay(habit, date: date, now: now, calendar: calendar)
                && HealthGoalManager.isScheduled(habit, on: date, calendar: calendar)
                && healthStepCount != nil
        }
        return HabitTrackingManager.hasCalendarActivity(
            habit,
            on: date,
            now: now,
            calendar: calendar
        )
    }

    static func slipEvents(
        for habit: Habit,
        on date: Date,
        calendar: Calendar = .current
    ) -> [HabitEvent] {
        habit.events
            .filter { $0.kind == .slip && calendar.isDate($0.occurredAt, inSameDayAs: date) }
            .sorted { $0.occurredAt < $1.occurredAt }
    }
}
