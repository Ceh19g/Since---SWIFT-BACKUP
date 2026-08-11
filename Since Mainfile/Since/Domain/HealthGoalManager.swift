import Foundation

enum HealthMetric: String, Codable, Identifiable {
    case steps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps: "Daily steps"
        }
    }

    var unitTitle: String {
        switch self {
        case .steps: "steps"
        }
    }

    var symbolName: String {
        switch self {
        case .steps: "figure.walk"
        }
    }
}

struct HealthGoalRevision: Codable, Equatable, Identifiable {
    let id: UUID
    let effectiveAt: Date
    let targetValue: Double
    let activeWeekdays: [Int]

    init(
        id: UUID = UUID(),
        effectiveAt: Date,
        targetValue: Double,
        activeWeekdays: Set<Int>
    ) {
        self.id = id
        self.effectiveAt = effectiveAt
        self.targetValue = targetValue
        self.activeWeekdays = activeWeekdays.sorted()
    }
}

struct HealthGoalProgress: Equatable {
    let value: Int?
    let target: Int
    let isScheduled: Bool

    var fraction: Double {
        guard let value, target > 0 else { return 0 }
        return min(1, Double(value) / Double(target))
    }

    var isReached: Bool {
        guard let value else { return false }
        return isScheduled && value >= target
    }

    var remaining: Int {
        max(0, target - (value ?? 0))
    }
}

enum HealthGoalManager {
    static let everyDay = Set(1...7)

    static func revisions(for habit: Habit) -> [HealthGoalRevision] {
        if let data = habit.healthGoalHistoryData,
           let revisions = try? JSONDecoder().decode([HealthGoalRevision].self, from: data),
           !revisions.isEmpty {
            return revisions.sorted { $0.effectiveAt < $1.effectiveAt }
        }

        guard let target = habit.healthGoalValue else { return [] }
        return [
            HealthGoalRevision(
                effectiveAt: habit.startAt,
                targetValue: target,
                activeWeekdays: decodedWeekdays(habit.healthGoalWeekdaysRawValue)
            )
        ]
    }

    static func recordGoal(
        for habit: Habit,
        target: Double,
        activeWeekdays: Set<Int>,
        effectiveAt: Date,
        calendar: Calendar = .current
    ) {
        let normalizedTarget = max(1, target)
        let normalizedWeekdays = activeWeekdays.isEmpty ? everyDay : activeWeekdays
        var history = revisions(for: habit)
        let effectiveDay = calendar.startOfDay(for: effectiveAt)

        history.removeAll { calendar.isDate($0.effectiveAt, inSameDayAs: effectiveDay) }
        history.append(
            HealthGoalRevision(
                effectiveAt: effectiveDay,
                targetValue: normalizedTarget,
                activeWeekdays: normalizedWeekdays
            )
        )
        history.sort { $0.effectiveAt < $1.effectiveAt }

        habit.healthGoalValue = normalizedTarget
        habit.healthGoalWeekdaysRawValue = encodedWeekdays(normalizedWeekdays)
        habit.healthGoalHistoryData = try? JSONEncoder().encode(history)
    }

    static func goal(
        for habit: Habit,
        on date: Date,
        calendar: Calendar = .current
    ) -> HealthGoalRevision? {
        let endOfDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: date)
        ) ?? date
        return revisions(for: habit).last { $0.effectiveAt < endOfDay }
    }

    static func progress(
        for habit: Habit,
        on date: Date,
        stepCount: Int?,
        calendar: Calendar = .current
    ) -> HealthGoalProgress? {
        guard habit.healthMetric == .steps,
              let revision = goal(for: habit, on: date, calendar: calendar) else {
            return nil
        }
        let weekday = calendar.component(.weekday, from: date)
        return HealthGoalProgress(
            value: stepCount,
            target: Int(revision.targetValue.rounded()),
            isScheduled: revision.activeWeekdays.contains(weekday)
        )
    }

    static func isScheduled(
        _ habit: Habit,
        on date: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard let goal = goal(for: habit, on: date, calendar: calendar) else { return false }
        return goal.activeWeekdays.contains(calendar.component(.weekday, from: date))
    }

    static func completedDays(
        for habit: Habit,
        totals: [Date: Int],
        in range: Range<Date>? = nil,
        calendar: Calendar = .current
    ) -> Set<Date> {
        Set(totals.compactMap { date, value in
            let day = calendar.startOfDay(for: date)
            if let range, !range.contains(day) { return nil }
            guard let progress = progress(
                for: habit,
                on: day,
                stepCount: value,
                calendar: calendar
            ), progress.isReached else { return nil }
            return day
        })
    }

    static func streak(
        for habit: Habit,
        totals: [Date: Int],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> DailyHabitStreak {
        let completed = completedDays(for: habit, totals: totals, calendar: calendar)
        let today = calendar.startOfDay(for: now)

        var best = 0
        var running = 0
        var cursor = calendar.startOfDay(for: habit.startAt)
        while cursor <= today {
            if isScheduled(habit, on: cursor, calendar: calendar) {
                if completed.contains(cursor) {
                    running += 1
                    best = max(best, running)
                } else {
                    running = 0
                }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        var current = 0
        cursor = today
        if isScheduled(habit, on: today, calendar: calendar), !completed.contains(today) {
            cursor = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        }
        while cursor >= calendar.startOfDay(for: habit.startAt) {
            if isScheduled(habit, on: cursor, calendar: calendar) {
                guard completed.contains(cursor) else { break }
                current += 1
            }
            guard let prior = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prior
        }

        return DailyHabitStreak(
            current: current,
            best: best,
            totalCompletions: completed.count
        )
    }

    static func encodedWeekdays(_ weekdays: Set<Int>) -> String {
        weekdays.sorted().map(String.init).joined(separator: ",")
    }

    static func decodedWeekdays(_ value: String?) -> Set<Int> {
        guard let value, !value.isEmpty else { return everyDay }
        let result = Set(value.split(separator: ",").compactMap { Int($0) })
        return result.isEmpty ? everyDay : result
    }
}
