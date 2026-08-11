import Foundation

struct MilestoneProgress {
    let nextDay: Int?
    let remainingSeconds: Int
    let fractionComplete: Double
    let isComplete: Bool
}

enum MilestoneCalculator {
    static let standardDays = [1, 3, 7, 14, 30, 60, 90, 180, 365, 730, 1_825]

    static func progress(for elapsed: ElapsedTime) -> MilestoneProgress {
        guard let next = standardDays.first(where: { $0 * 86_400 > elapsed.totalSeconds }) else {
            return MilestoneProgress(nextDay: nil, remainingSeconds: 0, fractionComplete: 1, isComplete: true)
        }

        let previous = standardDays.last(where: { $0 * 86_400 <= elapsed.totalSeconds }) ?? 0
        let previousSeconds = previous * 86_400
        let nextSeconds = next * 86_400
        let interval = max(1, nextSeconds - previousSeconds)
        let completed = elapsed.totalSeconds - previousSeconds

        return MilestoneProgress(
            nextDay: next,
            remainingSeconds: max(0, nextSeconds - elapsed.totalSeconds),
            fractionComplete: min(1, max(0, Double(completed) / Double(interval))),
            isComplete: false
        )
    }

    static func progress(for elapsed: ElapsedTime, customDay: Int?) -> MilestoneProgress {
        guard let customDay else {
            return progress(for: elapsed)
        }

        let day = max(1, customDay)
        let targetSeconds = day * 86_400
        let completed = elapsed.totalSeconds >= targetSeconds

        return MilestoneProgress(
            nextDay: day,
            remainingSeconds: max(0, targetSeconds - elapsed.totalSeconds),
            fractionComplete: min(1, max(0, Double(elapsed.totalSeconds) / Double(targetSeconds))),
            isComplete: completed
        )
    }
}
