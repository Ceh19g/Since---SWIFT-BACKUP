import Foundation

struct DailyHabitStreak: Equatable {
    let current: Int
    let best: Int
    let totalCompletions: Int
}

enum HabitTrackingManager {
    static func completionEvents(
        for habit: Habit,
        on date: Date,
        calendar: Calendar = .current
    ) -> [HabitEvent] {
        habit.events
            .filter { $0.kind == .completed && calendar.isDate($0.occurredAt, inSameDayAs: date) }
            .sorted { $0.occurredAt < $1.occurredAt }
    }

    static func isCompleted(
        _ habit: Habit,
        on date: Date,
        calendar: Calendar = .current
    ) -> Bool {
        !completionEvents(for: habit, on: date, calendar: calendar).isEmpty
    }

    static func dailyStreak(
        for habit: Habit,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> DailyHabitStreak {
        let completedDays = Set(
            habit.events
                .filter { $0.kind == .completed && $0.occurredAt >= habit.startAt }
                .map { calendar.startOfDay(for: $0.occurredAt) }
        )

        guard !completedDays.isEmpty else {
            return DailyHabitStreak(current: 0, best: 0, totalCompletions: 0)
        }

        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var cursor = completedDays.contains(today) ? today : yesterday
        var current = 0

        while completedDays.contains(cursor) {
            current += 1
            guard let priorDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = priorDay
        }

        let orderedDays = completedDays.sorted()
        var best = 0
        var run = 0
        var previous: Date?

        for day in orderedDays {
            if let previous,
               let expected = calendar.date(byAdding: .day, value: 1, to: previous),
               calendar.isDate(day, inSameDayAs: expected) {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }

        return DailyHabitStreak(
            current: current,
            best: best,
            totalCompletions: completedDays.count
        )
    }

    static func latestOccurrence(for habit: Habit) -> Date {
        habit.events
            .filter { $0.kind == .completed }
            .map(\.occurredAt)
            .max() ?? habit.startAt
    }

    static func occurrenceEvents(
        for habit: Habit,
        on date: Date,
        calendar: Calendar = .current
    ) -> [HabitEvent] {
        let logged = completionEvents(for: habit, on: date, calendar: calendar)
        if logged.isEmpty && calendar.isDate(habit.startAt, inSameDayAs: date) {
            return habit.events.filter {
                $0.kind == .started && calendar.isDate($0.occurredAt, inSameDayAs: date)
            }
        }
        return logged
    }

    static func hasCalendarActivity(
        _ habit: Habit,
        on date: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        switch habit.type {
        case .abstinence, .sinceDate:
            return isTrackedDay(habit, date: date, now: now, calendar: calendar)
        case .positiveStreak:
            return isCompleted(habit, on: date, calendar: calendar)
        case .event:
            return !occurrenceEvents(for: habit, on: date, calendar: calendar).isEmpty
        case .countdown:
            return calendar.isDate(habit.startAt, inSameDayAs: date)
        case .frequency, .count, .duration:
            return isTrackedDay(habit, date: date, now: now, calendar: calendar)
        }
    }

    static func isTrackedDay(
        _ habit: Habit,
        date: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        let dayStart = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? date
        let today = calendar.startOfDay(for: now)
        return nextDay > habit.startAt && dayStart <= today
    }

    static func summary(
        for habit: Habit,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        switch habit.type {
        case .abstinence:
            return daysDescription(ElapsedTimeCalculator.elapsed(for: habit, now: now).days)
        case .positiveStreak:
            let streak = dailyStreak(for: habit, now: now, calendar: calendar)
            return "\(streak.current)-day streak"
        case .event:
            let elapsed = ElapsedTime(from: latestOccurrence(for: habit), to: now)
            return "\(daysDescription(elapsed.days)) since last time"
        case .sinceDate:
            let elapsed = ElapsedTime(from: habit.startAt, to: now)
            return "\(daysDescription(elapsed.days)) since"
        case .countdown:
            if now >= habit.startAt {
                return "Date reached"
            }
            let remaining = ElapsedTime(from: now, to: habit.startAt)
            return "\(daysDescription(remaining.days)) remaining"
        case .frequency, .count, .duration:
            return daysDescription(ElapsedTimeCalculator.elapsed(for: habit, now: now).days)
        }
    }

    static func activityTitle(for event: HabitEvent) -> String {
        guard event.kind == .completed, let habit = event.habit else {
            return event.kind.title
        }

        switch habit.type {
        case .positiveStreak: return "Daily habit completed"
        case .event: return "Occurrence logged"
        default: return event.kind.title
        }
    }

    private static func daysDescription(_ days: Int) -> String {
        "\(days) \(days == 1 ? "day" : "days")"
    }
}
