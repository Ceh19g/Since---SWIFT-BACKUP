import Foundation

struct StreakSegment: Identifiable, Equatable {
    var id: Date { startedAt }
    let startedAt: Date
    let endedAt: Date?
    let endReason: HabitEventKind?

    func elapsed(at now: Date = .now) -> ElapsedTime {
        ElapsedTime(from: startedAt, to: endedAt ?? now)
    }
}

enum StreakCalculator {
    static func segments(for habit: Habit) -> [StreakSegment] {
        let restartEvents = habit.events
            .filter {
                ($0.kind == .reset || ($0.kind == .slip && $0.restartsStreak))
                    && $0.occurredAt >= habit.startAt
            }
            .sorted { $0.occurredAt < $1.occurredAt }

        var segments: [StreakSegment] = []
        var segmentStart = habit.startAt

        for event in restartEvents {
            segments.append(
                StreakSegment(
                    startedAt: segmentStart,
                    endedAt: event.occurredAt,
                    endReason: event.kind
                )
            )
            segmentStart = event.occurredAt
        }

        segments.append(
            StreakSegment(startedAt: segmentStart, endedAt: nil, endReason: nil)
        )
        return segments
    }

    static func personalBest(for habit: Habit, now: Date = .now) -> ElapsedTime {
        segments(for: habit)
            .map { $0.elapsed(at: now) }
            .max { $0.totalSeconds < $1.totalSeconds }
            ?? ElapsedTime(from: habit.startAt, to: now)
    }
}
