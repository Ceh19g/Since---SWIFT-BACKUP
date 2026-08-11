import Foundation

struct ElapsedTime: Equatable {
    let totalSeconds: Int
    let days: Int
    let hours: Int
    let minutes: Int
    let seconds: Int

    init(from start: Date, to end: Date) {
        totalSeconds = max(0, Int(end.timeIntervalSince(start)))
        days = totalSeconds / 86_400
        hours = (totalSeconds % 86_400) / 3_600
        minutes = (totalSeconds % 3_600) / 60
        seconds = totalSeconds % 60
    }
}

enum ElapsedTimeCalculator {
    static func currentStart(for habit: Habit) -> Date {
        habit.events
            .filter {
                ($0.kind == .reset || ($0.kind == .slip && $0.restartsStreak))
                    && $0.occurredAt >= habit.startAt
            }
            .map(\.occurredAt)
            .max() ?? habit.startAt
    }

    static func elapsed(for habit: Habit, now: Date = .now) -> ElapsedTime {
        ElapsedTime(from: currentStart(for: habit), to: now)
    }
}
