import Foundation

enum InsightPeriod: String, CaseIterable, Identifiable {
    case sevenDays
    case thirtyDays
    case ninetyDays
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sevenDays: "7D"
        case .thirtyDays: "30D"
        case .ninetyDays: "90D"
        case .allTime: "All"
        }
    }

    var dayCount: Int? {
        switch self {
        case .sevenDays: 7
        case .thirtyDays: 30
        case .ninetyDays: 90
        case .allTime: nil
        }
    }
}

struct InsightsDateRange: Equatable {
    let start: Date
    let endExclusive: Date

    func contains(_ date: Date) -> Bool {
        date >= start && date < endExclusive
    }
}

struct HabitInsightSnapshot: Identifiable, Equatable {
    let id: UUID
    let name: String
    let type: HabitType
    let currentDays: Int?
    let remainingDays: Int?
    let bestDays: Int?
    let eligibleDays: Int
    let completedDays: Int
    let slipCount: Int
    let restartingSlipCount: Int
    let occurrenceCount: Int
    let averageIntervalDays: Double?
    let medianSegmentDays: Double?
    let averageSteps: Int?
    let recordedStepDays: Int
    let highestSteps: Int?
    let measurementStatistics: HabitMeasurementStatistics?

    var completionRate: Double? {
        guard eligibleDays > 0 else { return nil }
        return Double(completedDays) / Double(eligibleDays)
    }
}

struct PlannerInsightSnapshot: Equatable {
    let completedTasks: Int
    let scheduledTasks: Int
    let linkedTasks: Int

    var completionRate: Double? {
        guard scheduledTasks > 0 else { return nil }
        return Double(completedTasks) / Double(scheduledTasks)
    }
}

struct InsightActivityPoint: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let habitLogs: Int
    let slips: Int
    let completedTasks: Int
    let scheduledTasks: Int
}

struct InsightFinding: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let symbolName: String
}

struct InsightsSnapshot: Equatable {
    let range: InsightsDateRange
    let habitSnapshots: [HabitInsightSnapshot]
    let planner: PlannerInsightSnapshot
    let activity: [InsightActivityPoint]
    let comparisons: [InsightFinding]
    let patterns: [InsightFinding]
    let eligibleHabitDays: Int
    let completedHabitDays: Int
    let slipCount: Int
    let occurrenceCount: Int

    var habitCompletionRate: Double? {
        guard eligibleHabitDays > 0 else { return nil }
        return Double(completedHabitDays) / Double(eligibleHabitDays)
    }
}

enum InsightsEngine {
    static let minimumHabitDays = 7
    static let minimumPlannerTasks = 5
    static let minimumSlipEvents = 3

    static func makeSnapshot(
        habits: [Habit],
        tasks: [PlannerTask],
        period: InsightPeriod,
        selectedHabitID: UUID? = nil,
        healthStepTotals: [Date: Int] = [:],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> InsightsSnapshot {
        let activeHabits = habits.filter { !$0.isArchived }
        let scopedHabits: [Habit]
        if let selectedHabitID {
            scopedHabits = activeHabits.filter { $0.id == selectedHabitID }
        } else {
            scopedHabits = activeHabits
        }

        let scopedTasks = tasks.filter { task in
            guard let selectedHabitID else { return true }
            return task.habitID == selectedHabitID
        }
        let range = dateRange(
            for: period,
            habits: scopedHabits,
            tasks: scopedTasks,
            now: now,
            calendar: calendar
        )
        let priorRange = previousRange(for: period, current: range, calendar: calendar)
        let habitSnapshots = scopedHabits.map {
            habitSnapshot(
                for: $0,
                range: range,
                healthStepTotals: healthStepTotals,
                now: now,
                calendar: calendar
            )
        }
        let positiveTotals = completionTotals(
            habits: scopedHabits,
            range: range,
            healthStepTotals: healthStepTotals,
            now: now,
            calendar: calendar
        )
        let planner = plannerSnapshot(
            tasks: scopedTasks,
            range: range,
            now: now,
            calendar: calendar,
            selectedHabitID: selectedHabitID
        )
        let slipEvents = events(
            kinds: [.slip],
            habits: scopedHabits,
            range: range
        )
        let occurrenceEvents = events(
            kinds: [.completed],
            habits: scopedHabits.filter { $0.type == .event },
            range: range
        )

        return InsightsSnapshot(
            range: range,
            habitSnapshots: habitSnapshots,
            planner: planner,
            activity: activityPoints(
                habits: scopedHabits,
                tasks: scopedTasks,
                range: range,
                healthStepTotals: healthStepTotals,
                calendar: calendar
            ),
            comparisons: comparisonFindings(
                habits: scopedHabits,
                tasks: scopedTasks,
                currentRange: range,
                priorRange: priorRange,
                healthStepTotals: healthStepTotals,
                now: now,
                calendar: calendar,
                selectedHabitID: selectedHabitID
            ),
            patterns: patternFindings(
                habits: scopedHabits,
                tasks: scopedTasks,
                range: range,
                healthStepTotals: healthStepTotals,
                now: now,
                calendar: calendar,
                selectedHabitID: selectedHabitID
            ),
            eligibleHabitDays: positiveTotals.eligible,
            completedHabitDays: positiveTotals.completed,
            slipCount: slipEvents.count,
            occurrenceCount: occurrenceEvents.count
        )
    }

    static func dateRange(
        for period: InsightPeriod,
        habits: [Habit],
        tasks: [PlannerTask],
        now: Date,
        calendar: Calendar
    ) -> InsightsDateRange {
        let today = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now

        if let dayCount = period.dayCount {
            let start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) ?? today
            return InsightsDateRange(start: start, endExclusive: end)
        }

        let habitDates = habits.flatMap { habit in
            [habit.startAt, habit.createdAt] + habit.events.map(\.occurredAt)
        }
        let taskDates = tasks.flatMap { task in
            [task.scheduledDay, task.createdAt] + [task.completedAt].compactMap { $0 }
        }
        let earliest = (habitDates + taskDates).min() ?? today
        return InsightsDateRange(
            start: min(calendar.startOfDay(for: earliest), today),
            endExclusive: end
        )
    }

    static func previousRange(
        for period: InsightPeriod,
        current: InsightsDateRange,
        calendar: Calendar
    ) -> InsightsDateRange? {
        guard let dayCount = period.dayCount else { return nil }
        let start = calendar.date(byAdding: .day, value: -dayCount, to: current.start) ?? current.start
        return InsightsDateRange(start: start, endExclusive: current.start)
    }

    private static func habitSnapshot(
        for habit: Habit,
        range: InsightsDateRange,
        healthStepTotals: [Date: Int],
        now: Date,
        calendar: Calendar
    ) -> HabitInsightSnapshot {
        let slips = habit.events.filter { $0.kind == .slip && range.contains($0.occurredAt) }
        let occurrences = habit.events
            .filter { $0.kind == .completed && range.contains($0.occurredAt) }
            .sorted { $0.occurredAt < $1.occurredAt }
        let totals = completionTotals(
            habits: [habit],
            range: range,
            healthStepTotals: healthStepTotals,
            now: now,
            calendar: calendar
        )

        let currentDays: Int?
        let remainingDays: Int?
        let bestDays: Int?

        if habit.isHealthPowered {
            let streak = HealthGoalManager.streak(
                for: habit,
                totals: healthStepTotals,
                now: now,
                calendar: calendar
            )
            currentDays = streak.current
            remainingDays = nil
            bestDays = streak.best
        } else {
            switch habit.type {
        case .abstinence, .frequency, .count, .duration:
            currentDays = ElapsedTimeCalculator.elapsed(for: habit, now: now).days
            remainingDays = nil
            bestDays = StreakCalculator.personalBest(for: habit, now: now).days
        case .positiveStreak:
            let streak = HabitTrackingManager.dailyStreak(for: habit, now: now, calendar: calendar)
            currentDays = streak.current
            remainingDays = nil
            bestDays = streak.best
        case .event:
            currentDays = ElapsedTime(from: HabitTrackingManager.latestOccurrence(for: habit), to: now).days
            remainingDays = nil
            bestDays = nil
        case .sinceDate:
            currentDays = ElapsedTime(from: habit.startAt, to: now).days
            remainingDays = nil
            bestDays = nil
        case .countdown:
            currentDays = nil
            remainingDays = now >= habit.startAt ? 0 : ElapsedTime(from: now, to: habit.startAt).days
            bestDays = nil
            }
        }

        let segments = StreakCalculator.segments(for: habit).map {
            Double($0.elapsed(at: now).totalSeconds) / 86_400
        }

        let stepValues = healthStepTotals.compactMap { date, value -> Int? in
            let day = calendar.startOfDay(for: date)
            guard habit.isHealthPowered,
                  range.contains(day),
                  day >= calendar.startOfDay(for: habit.startAt) else { return nil }
            return value
        }
        let measurementStatistics = HabitMeasurementManager.statistics(
            for: habit,
            from: range.start,
            to: range.endExclusive
        )

        return HabitInsightSnapshot(
            id: habit.id,
            name: habit.name,
            type: habit.type,
            currentDays: currentDays,
            remainingDays: remainingDays,
            bestDays: bestDays,
            eligibleDays: totals.eligible,
            completedDays: totals.completed,
            slipCount: slips.count,
            restartingSlipCount: slips.filter(\.restartsStreak).count,
            occurrenceCount: occurrences.count,
            averageIntervalDays: averageIntervalDays(for: occurrences.map(\.occurredAt)),
            medianSegmentDays: median(segments),
            averageSteps: stepValues.isEmpty
                ? nil
                : Int((Double(stepValues.reduce(0, +)) / Double(stepValues.count)).rounded()),
            recordedStepDays: stepValues.count,
            highestSteps: stepValues.max(),
            measurementStatistics: measurementStatistics
        )
    }

    private static func completionTotals(
        habits: [Habit],
        range: InsightsDateRange,
        healthStepTotals: [Date: Int] = [:],
        now: Date,
        calendar: Calendar
    ) -> (eligible: Int, completed: Int) {
        let today = calendar.startOfDay(for: now)
        let historicalEnd = min(range.endExclusive, today)
        var eligible = 0
        var completed = 0

        for habit in habits where habit.type == .positiveStreak {
            let habitStart = max(calendar.startOfDay(for: habit.startAt), range.start)
            guard habitStart < historicalEnd else { continue }
            let eligibleDays = historicalEligibleDays(
                for: habit,
                from: habitStart,
                to: historicalEnd,
                calendar: calendar
            )
            let completedDays = historicalCompletedDays(
                for: habit,
                from: habitStart,
                to: historicalEnd,
                healthStepTotals: healthStepTotals,
                calendar: calendar
            )
            eligible += eligibleDays.count
            completed += completedDays.count
        }

        return (eligible, completed)
    }

    private static func plannerSnapshot(
        tasks: [PlannerTask],
        range: InsightsDateRange,
        now: Date,
        calendar: Calendar,
        selectedHabitID: UUID?
    ) -> PlannerInsightSnapshot {
        let included = historicalTaskEntries(tasks, range: range, now: now, calendar: calendar)
        return PlannerInsightSnapshot(
            completedTasks: included.filter(\.isCompleted).count,
            scheduledTasks: included.count,
            linkedTasks: selectedHabitID.map { id in
                included.filter { $0.task.habitID == id }.count
            } ?? 0
        )
    }

    private static func historicalTaskEntries(
        _ tasks: [PlannerTask],
        range: InsightsDateRange,
        now: Date,
        calendar: Calendar
    ) -> [PlannerDayTask] {
        let historicalEnd = min(range.endExclusive, calendar.startOfDay(for: now))
        return daySequence(from: range.start, to: historicalEnd, calendar: calendar).flatMap { day in
            PlannerTaskManager.dayTasks(on: day, from: tasks, calendar: calendar)
                .filter { $0.isPlanned || $0.isDue }
        }
    }

    private static func activityPoints(
        habits: [Habit],
        tasks: [PlannerTask],
        range: InsightsDateRange,
        healthStepTotals: [Date: Int],
        calendar: Calendar
    ) -> [InsightActivityPoint] {
        daySequence(from: range.start, to: range.endExclusive, calendar: calendar).map { day in
            let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let manualHabitEvents = habits.filter { !$0.isHealthPowered }.flatMap(\.events).filter {
                $0.occurredAt >= day && $0.occurredAt < nextDay
            }
            let healthCompletions = habits.filter(\.isHealthPowered).filter { habit in
                let steps = healthStepTotals[calendar.startOfDay(for: day)]
                return HealthGoalManager.progress(
                    for: habit,
                    on: day,
                    stepCount: steps,
                    calendar: calendar
                )?.isReached == true
            }.count
            let dayTasks = PlannerTaskManager.dayTasks(on: day, from: tasks, calendar: calendar)
                .filter { $0.isPlanned || $0.isDue }
            return InsightActivityPoint(
                date: day,
                habitLogs: manualHabitEvents.filter { $0.kind == .completed }.count + healthCompletions,
                slips: manualHabitEvents.filter { $0.kind == .slip }.count,
                completedTasks: dayTasks.filter(\.isCompleted).count,
                scheduledTasks: dayTasks.count
            )
        }
    }

    private static func comparisonFindings(
        habits: [Habit],
        tasks: [PlannerTask],
        currentRange: InsightsDateRange,
        priorRange: InsightsDateRange?,
        healthStepTotals: [Date: Int],
        now: Date,
        calendar: Calendar,
        selectedHabitID: UUID?
    ) -> [InsightFinding] {
        guard let priorRange else { return [] }
        var findings: [InsightFinding] = []

        let currentHabit = completionTotals(
            habits: habits,
            range: currentRange,
            healthStepTotals: healthStepTotals,
            now: now,
            calendar: calendar
        )
        let priorHabit = completionTotals(
            habits: habits,
            range: priorRange,
            healthStepTotals: healthStepTotals,
            now: priorRange.endExclusive,
            calendar: calendar
        )
        if currentHabit.eligible >= minimumHabitDays, priorHabit.eligible >= minimumHabitDays {
            let currentRate = Double(currentHabit.completed) / Double(currentHabit.eligible)
            let priorRate = Double(priorHabit.completed) / Double(priorHabit.eligible)
            findings.append(
                comparisonFinding(
                    id: "habit-rate",
                    title: "Habit consistency",
                    current: currentRate,
                    prior: priorRate,
                    currentCount: currentHabit.completed,
                    currentTotal: currentHabit.eligible
                )
            )
        }

        let currentPlanner = plannerSnapshot(
            tasks: tasks,
            range: currentRange,
            now: now,
            calendar: calendar,
            selectedHabitID: selectedHabitID
        )
        let priorPlanner = plannerSnapshot(
            tasks: tasks,
            range: priorRange,
            now: priorRange.endExclusive,
            calendar: calendar,
            selectedHabitID: selectedHabitID
        )
        if currentPlanner.scheduledTasks >= minimumPlannerTasks,
           priorPlanner.scheduledTasks >= minimumPlannerTasks,
           let currentRate = currentPlanner.completionRate,
           let priorRate = priorPlanner.completionRate {
            findings.append(
                comparisonFinding(
                    id: "planner-rate",
                    title: "Planner completion",
                    current: currentRate,
                    prior: priorRate,
                    currentCount: currentPlanner.completedTasks,
                    currentTotal: currentPlanner.scheduledTasks
                )
            )
        }

        let currentSlips = events(kinds: [.slip], habits: habits, range: currentRange).count
        let priorSlips = events(kinds: [.slip], habits: habits, range: priorRange).count
        if currentSlips + priorSlips >= minimumSlipEvents {
            findings.append(
                InsightFinding(
                    id: "slip-change",
                    title: "Recorded slips",
                    detail: "\(currentSlips) in this period; \(priorSlips) in the previous period.",
                    symbolName: currentSlips > priorSlips ? "arrow.up.right" : "arrow.down.right"
                )
            )
        }

        return findings
    }

    private static func comparisonFinding(
        id: String,
        title: String,
        current: Double,
        prior: Double,
        currentCount: Int,
        currentTotal: Int
    ) -> InsightFinding {
        let change = Int(((current - prior) * 100).rounded())
        let direction: String
        if change == 0 {
            direction = "unchanged"
        } else {
            direction = "\(abs(change)) points \(change > 0 ? "higher" : "lower")"
        }
        return InsightFinding(
            id: id,
            title: title,
            detail: "\(Int((current * 100).rounded()))% (\(currentCount) of \(currentTotal)); \(direction) than the previous period.",
            symbolName: change > 0 ? "arrow.up.right" : (change < 0 ? "arrow.down.right" : "equal")
        )
    }

    private static func patternFindings(
        habits: [Habit],
        tasks: [PlannerTask],
        range: InsightsDateRange,
        healthStepTotals: [Date: Int],
        now: Date,
        calendar: Calendar,
        selectedHabitID: UUID?
    ) -> [InsightFinding] {
        var findings: [InsightFinding] = []
        let slipEvents = events(kinds: [.slip], habits: habits, range: range)

        if slipEvents.count >= minimumSlipEvents,
           let weekday = mostCommonWeekday(for: slipEvents.map(\.occurredAt), calendar: calendar) {
            findings.append(
                InsightFinding(
                    id: "slip-weekday",
                    title: "Slip timing",
                    detail: "\(weekday.name) contains \(weekday.count) of \(slipEvents.count) recorded slips.",
                    symbolName: "calendar"
                )
            )
        }

        if slipEvents.count >= minimumSlipEvents,
           let block = mostCommonTimeBlock(for: slipEvents.map(\.occurredAt), calendar: calendar) {
            findings.append(
                InsightFinding(
                    id: "slip-time",
                    title: "Most common time block",
                    detail: "\(block.name) contains \(block.count) of \(slipEvents.count) recorded slips.",
                    symbolName: "clock"
                )
            )
        }

        if let completionPattern = completionWeekdayPattern(
            habits: habits,
            range: range,
            healthStepTotals: healthStepTotals,
            now: now,
            calendar: calendar
        ) {
            findings.append(completionPattern)
        }

        let includedTasks = historicalTaskEntries(tasks, range: range, now: now, calendar: calendar)
        let sectionTasks = includedTasks.filter { $0.session?.daySection != nil }
        if sectionTasks.count >= minimumPlannerTasks,
           let bestSection = bestTaskSection(sectionTasks) {
            findings.append(
                InsightFinding(
                    id: "task-section",
                    title: "Strongest task window",
                    detail: "\(bestSection.name): \(bestSection.completed) of \(bestSection.total) scheduled tasks completed.",
                    symbolName: bestSection.symbolName
                )
            )
        }

        let importantTasks = includedTasks.filter { $0.task.priority == .important }
        if importantTasks.count >= minimumPlannerTasks {
            let completed = importantTasks.filter(\.isCompleted).count
            findings.append(
                InsightFinding(
                    id: "important-tasks",
                    title: "High-priority tasks",
                    detail: "\(completed) of \(importantTasks.count) completed in the selected period.",
                    symbolName: "exclamationmark.circle"
                )
            )
        }

        if let selectedHabitID {
            let linkedTasks = includedTasks.filter { $0.task.habitID == selectedHabitID }
            if linkedTasks.count >= minimumPlannerTasks {
                findings.append(
                    InsightFinding(
                        id: "linked-tasks",
                        title: "Linked planner work",
                        detail: "\(linkedTasks.filter(\.isCompleted).count) of \(linkedTasks.count) habit-linked tasks completed.",
                        symbolName: "link"
                    )
                )
            }

            if let habit = habits.first(where: { $0.id == selectedHabitID }),
               habit.type == .abstinence,
               StreakCalculator.segments(for: habit).count > 1 {
                let longest = StreakCalculator.segments(for: habit)
                    .map { $0.elapsed(at: now).days }
                    .max() ?? 0
                findings.append(
                    InsightFinding(
                        id: "longest-segment",
                        title: "Longest stable period",
                        detail: "\(longest) \(longest == 1 ? "day" : "days") across recorded streak segments.",
                        symbolName: "point.topleft.down.to.point.bottomright.curvepath"
                    )
                )
            }

            if let healthHabit = habits.first(where: { $0.id == selectedHabitID && $0.isHealthPowered }),
               let stepPattern = stepWeekdayPattern(
                    habit: healthHabit,
                    totals: healthStepTotals,
                    range: range,
                    calendar: calendar
               ) {
                findings.append(stepPattern)
            }
        }

        return findings
    }

    private static func completionWeekdayPattern(
        habits: [Habit],
        range: InsightsDateRange,
        healthStepTotals: [Date: Int],
        now: Date,
        calendar: Calendar
    ) -> InsightFinding? {
        let positiveHabits = habits.filter { $0.type == .positiveStreak }
        let totals = completionTotals(
            habits: positiveHabits,
            range: range,
            healthStepTotals: healthStepTotals,
            now: now,
            calendar: calendar
        )
        guard totals.eligible >= minimumHabitDays else { return nil }

        let historicalEnd = min(range.endExclusive, calendar.startOfDay(for: now))
        var eligibleByWeekday: [Int: Int] = [:]
        var completedByWeekday: [Int: Int] = [:]

        for habit in positiveHabits {
            let start = max(calendar.startOfDay(for: habit.startAt), range.start)
            for day in historicalEligibleDays(for: habit, from: start, to: historicalEnd, calendar: calendar) {
                eligibleByWeekday[calendar.component(.weekday, from: day), default: 0] += 1
            }
            let completedDays = historicalCompletedDays(
                for: habit,
                from: start,
                to: historicalEnd,
                healthStepTotals: healthStepTotals,
                calendar: calendar
            )
            for day in completedDays {
                completedByWeekday[calendar.component(.weekday, from: day), default: 0] += 1
            }
        }

        let candidates = eligibleByWeekday.compactMap { weekday, eligible -> (Int, Int, Int, Double)? in
            guard eligible >= 2 else { return nil }
            let completed = completedByWeekday[weekday, default: 0]
            return (weekday, completed, eligible, Double(completed) / Double(eligible))
        }
        guard let best = candidates.max(by: { $0.3 < $1.3 }), best.1 > 0 else { return nil }
        let name = calendar.weekdaySymbols[best.0 - 1]
        return InsightFinding(
            id: "completion-weekday",
            title: "Strongest completion day",
            detail: "\(name): \(best.1) of \(best.2) eligible days completed (\(Int((best.3 * 100).rounded()))%).",
            symbolName: "checkmark.circle"
        )
    }

    private static func historicalEligibleDays(
        for habit: Habit,
        from start: Date,
        to end: Date,
        calendar: Calendar
    ) -> [Date] {
        daySequence(from: start, to: end, calendar: calendar).filter { day in
            !habit.isHealthPowered || HealthGoalManager.isScheduled(habit, on: day, calendar: calendar)
        }
    }

    private static func historicalCompletedDays(
        for habit: Habit,
        from start: Date,
        to end: Date,
        healthStepTotals: [Date: Int],
        calendar: Calendar
    ) -> Set<Date> {
        if habit.isHealthPowered {
            return HealthGoalManager.completedDays(
                for: habit,
                totals: healthStepTotals,
                in: start..<end,
                calendar: calendar
            )
        }

        return Set(
            habit.events
                .filter { $0.kind == .completed && $0.occurredAt >= start && $0.occurredAt < end }
                .map { calendar.startOfDay(for: $0.occurredAt) }
        )
    }

    private static func stepWeekdayPattern(
        habit: Habit,
        totals: [Date: Int],
        range: InsightsDateRange,
        calendar: Calendar
    ) -> InsightFinding? {
        let included = totals.compactMap { date, value -> (Int, Int)? in
            let day = calendar.startOfDay(for: date)
            guard range.contains(day), day >= calendar.startOfDay(for: habit.startAt) else { return nil }
            return (calendar.component(.weekday, from: day), value)
        }
        guard included.count >= minimumHabitDays else { return nil }

        let grouped = Dictionary(grouping: included, by: { $0.0 })
        let averages = grouped.compactMap { weekday, values -> (Int, Int)? in
            guard values.count >= 2 else { return nil }
            return (weekday, Int((Double(values.map(\.1).reduce(0, +)) / Double(values.count)).rounded()))
        }
        guard let best = averages.max(by: { $0.1 < $1.1 }) else { return nil }
        let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        guard weekdayNames.indices.contains(best.0 - 1) else { return nil }
        return InsightFinding(
            id: "health-step-weekday",
            title: "Highest step average",
            detail: "\(weekdayNames[best.0 - 1]) averages \(best.1.formatted()) recorded steps in this period.",
            symbolName: "figure.walk"
        )
    }

    private static func bestTaskSection(
        _ tasks: [PlannerDayTask]
    ) -> (name: String, completed: Int, total: Int, symbolName: String)? {
        let grouped = Dictionary(grouping: tasks) { $0.session?.daySection }
        return grouped.compactMap { section, tasks -> (String, Int, Int, String, Double)? in
            guard let section, tasks.count >= 2 else { return nil }
            let completed = tasks.filter(\.isCompleted).count
            return (
                section.title,
                completed,
                tasks.count,
                section.symbolName,
                Double(completed) / Double(tasks.count)
            )
        }
        .max(by: { $0.4 < $1.4 })
        .map { ($0.0, $0.1, $0.2, $0.3) }
    }

    private static func events(
        kinds: [HabitEventKind],
        habits: [Habit],
        range: InsightsDateRange
    ) -> [HabitEvent] {
        habits
            .flatMap(\.events)
            .filter { kinds.contains($0.kind) && range.contains($0.occurredAt) }
            .sorted { $0.occurredAt < $1.occurredAt }
    }

    private static func mostCommonWeekday(
        for dates: [Date],
        calendar: Calendar
    ) -> (name: String, count: Int)? {
        let counts = dates.reduce(into: [Int: Int]()) { result, date in
            result[calendar.component(.weekday, from: date), default: 0] += 1
        }
        guard let top = counts.max(by: { $0.value < $1.value }) else { return nil }
        let weekdayNames = [
            "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
        ]
        guard weekdayNames.indices.contains(top.key - 1) else { return nil }
        return (weekdayNames[top.key - 1], top.value)
    }

    private static func mostCommonTimeBlock(
        for dates: [Date],
        calendar: Calendar
    ) -> (name: String, count: Int)? {
        let counts = dates.reduce(into: [String: Int]()) { result, date in
            let hour = calendar.component(.hour, from: date)
            let block: String
            switch hour {
            case 5..<12: block = "Morning"
            case 12..<17: block = "Afternoon"
            case 17..<22: block = "Evening"
            default: block = "Night"
            }
            result[block, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value }).map { ($0.key, $0.value) }
    }

    private static func averageIntervalDays(for dates: [Date]) -> Double? {
        guard dates.count >= 2 else { return nil }
        let intervals = zip(dates.dropFirst(), dates).map { newer, older in
            newer.timeIntervalSince(older) / 86_400
        }
        return intervals.reduce(0, +) / Double(intervals.count)
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func daySequence(
        from start: Date,
        to endExclusive: Date,
        calendar: Calendar
    ) -> [Date] {
        guard start < endExclusive else { return [] }
        var days: [Date] = []
        var cursor = calendar.startOfDay(for: start)
        while cursor < endExclusive {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else {
                break
            }
            cursor = next
        }
        return days
    }
}
