import Foundation

struct PlannerProgress: Equatable {
    let completed: Int
    let total: Int

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}

enum PlannerTaskManager {
    static let everyDay = Set(1...7)
    static let weekdays = Set(2...6)

    static func startOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    nonisolated static func encodedWeekdays(_ weekdays: Set<Int>) -> String {
        weekdays.sorted().map(String.init).joined(separator: ",")
    }

    static func decodedWeekdays(_ rawValue: String?) -> Set<Int> {
        guard let rawValue else { return everyDay }
        let decoded = Set(rawValue.split(separator: ",").compactMap { Int($0) })
        return decoded.isEmpty ? everyDay : decoded
    }

    static func encodedSessions(_ sessions: [PlannerWorkSession]) -> Data? {
        try? JSONEncoder().encode(sessions)
    }

    static func decodedSessions(_ data: Data?) -> [PlannerWorkSession] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([PlannerWorkSession].self, from: data)) ?? []
    }

    static func encodedDays(_ days: Set<Date>, calendar: Calendar = .current) -> Data? {
        let normalized = days.map { calendar.startOfDay(for: $0) }.sorted()
        return try? JSONEncoder().encode(normalized)
    }

    static func decodedDays(_ data: Data?, calendar: Calendar = .current) -> Set<Date> {
        guard let data,
              let decoded = try? JSONDecoder().decode([Date].self, from: data) else {
            return []
        }
        return Set(decoded.map { calendar.startOfDay(for: $0) })
    }

    static func session(
        for task: PlannerTask,
        on date: Date,
        calendar: Calendar = .current
    ) -> PlannerWorkSession? {
        let day = calendar.startOfDay(for: date)
        guard !isFutureSessionSuppressed(task, on: day, calendar: calendar) else { return nil }

        switch task.scheduleKind {
        case .none:
            return nil
        case .once:
            guard calendar.isDate(task.scheduledDay, inSameDayAs: day) else { return nil }
            return baseSession(for: task, on: day, calendar: calendar)
        case .multipleDays:
            let stored = decodedSessions(task.customWorkSessionsData)
            if !stored.isEmpty {
                return stored.first { calendar.isDate($0.day, inSameDayAs: day) }
            }
            let end = task.scheduleEndDate ?? task.scheduledDay
            let selectedDays = decodedWeekdays(task.scheduleWeekdaysRawValue)
            guard day >= calendar.startOfDay(for: task.scheduledDay),
                  day <= calendar.startOfDay(for: end),
                  selectedDays.contains(calendar.component(.weekday, from: day)) else {
                return nil
            }
            return baseSession(for: task, on: day, calendar: calendar)
        case .repeating:
            guard isRepeatingTask(task, scheduledOn: day, calendar: calendar),
                  !decodedDays(task.excludedOccurrenceDaysData, calendar: calendar).contains(day) else {
                return nil
            }
            return baseSession(for: task, on: day, calendar: calendar)
        }
    }

    static func dayTask(
        _ task: PlannerTask,
        on date: Date,
        calendar: Calendar = .current
    ) -> PlannerDayTask? {
        let day = calendar.startOfDay(for: date)
        let plannedSession = session(for: task, on: day, calendar: calendar)
        let isDue = task.dueDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let completedOnDate = task.completedAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let occurrenceCompleted = task.scheduleKind == .repeating
            && decodedDays(task.completedOccurrenceDaysData, calendar: calendar).contains(day)

        var reasons = Set<PlannerCalendarReason>()
        if plannedSession != nil { reasons.insert(.planned) }
        if isDue { reasons.insert(.due) }
        if completedOnDate || occurrenceCompleted { reasons.insert(.completed) }
        guard !reasons.isEmpty else { return nil }

        return PlannerDayTask(
            task: task,
            date: day,
            reasons: reasons,
            session: plannedSession,
            isCompleted: isCompleted(task, on: day, calendar: calendar)
        )
    }

    static func dayTasks(
        on date: Date,
        from tasks: [PlannerTask],
        calendar: Calendar = .current
    ) -> [PlannerDayTask] {
        tasks.compactMap { dayTask($0, on: date, calendar: calendar) }
            .sorted { dayTaskComesBefore($0, $1) }
    }

    static func isTask(
        _ task: PlannerTask,
        scheduledFor date: Date,
        calendar: Calendar = .current
    ) -> Bool {
        dayTask(task, on: date, calendar: calendar) != nil
    }

    static func tasks(
        on date: Date,
        from tasks: [PlannerTask],
        calendar: Calendar = .current
    ) -> [PlannerTask] {
        dayTasks(on: date, from: tasks, calendar: calendar).map(\.task)
    }

    static func progress(for tasks: [PlannerTask]) -> PlannerProgress {
        PlannerProgress(
            completed: tasks.filter(\.isCompleted).count,
            total: tasks.count
        )
    }

    static func progress(for tasks: [PlannerDayTask]) -> PlannerProgress {
        PlannerProgress(
            completed: tasks.filter(\.isCompleted).count,
            total: tasks.count
        )
    }

    static func inbox(from tasks: [PlannerTask]) -> [PlannerTask] {
        tasks.filter { $0.status == .inbox }.sorted(by: comesBefore)
    }

    static func waiting(from tasks: [PlannerTask]) -> [PlannerTask] {
        tasks.filter { $0.status == .waiting }.sorted(by: comesBefore)
    }

    static func completed(from tasks: [PlannerTask]) -> [PlannerTask] {
        tasks.filter { $0.status == .completed }.sorted {
            ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt)
        }
    }

    static func upcoming(
        after date: Date,
        from tasks: [PlannerTask],
        calendar: Calendar = .current
    ) -> [PlannerTask] {
        let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        let datedTasks = tasks.compactMap { task -> (task: PlannerTask, date: Date)? in
            guard task.status != .completed,
                  let relevantDate = nextRelevantDate(for: task, onOrAfter: nextDay, calendar: calendar) else {
                return nil
            }
            return (task, relevantDate)
        }
        return datedTasks.sorted {
            $0.date == $1.date ? comesBefore($0.task, $1.task) : $0.date < $1.date
        }.map(\.task)
    }

    static func overdue(
        before date: Date,
        from tasks: [PlannerTask],
        calendar: Calendar = .current
    ) -> [PlannerTask] {
        return tasks.filter {
            $0.status != .completed
                && isOverdue($0, before: date, calendar: calendar)
        }.sorted {
            ($0.dueTime ?? $0.dueDate ?? .distantFuture)
                < ($1.dueTime ?? $1.dueDate ?? .distantFuture)
        }
    }

    static func unfinished(
        before date: Date,
        from tasks: [PlannerTask],
        calendar: Calendar = .current
    ) -> [PlannerTask] {
        let dayStart = calendar.startOfDay(for: date)
        return tasks.filter { task in
            guard task.status != .completed,
                  task.scheduleKind != .none,
                  task.scheduleKind != .repeating,
                  !isOverdue(task, before: date, calendar: calendar) else {
                return false
            }
            return lastPlannedDate(for: task, calendar: calendar).map { $0 < dayStart } ?? false
        }.sorted {
            (lastPlannedDate(for: $0, calendar: calendar) ?? .distantPast)
                < (lastPlannedDate(for: $1, calendar: calendar) ?? .distantPast)
        }
    }

    static func setStatus(
        _ status: PlannerTaskStatus,
        for task: PlannerTask,
        now: Date = .now
    ) {
        task.statusRawValue = status.rawValue
        task.isCompleted = status == .completed
        task.completedAt = status == .completed ? (task.completedAt ?? now) : nil
        task.updatedAt = now
    }

    static func setCompletion(
        _ completed: Bool,
        for task: PlannerTask,
        on date: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        if task.scheduleKind == .repeating && task.status != .completed {
            let day = calendar.startOfDay(for: date)
            var completedDays = decodedDays(task.completedOccurrenceDaysData, calendar: calendar)
            if completed {
                completedDays.insert(day)
            } else {
                completedDays.remove(day)
            }
            task.completedOccurrenceDaysData = encodedDays(completedDays, calendar: calendar)
            task.updatedAt = now
        } else {
            setStatus(completed ? .completed : .planned, for: task, now: now)
        }
    }

    static func isCompleted(
        _ task: PlannerTask,
        on date: Date,
        calendar: Calendar = .current
    ) -> Bool {
        if task.isCompleted { return true }
        guard task.scheduleKind == .repeating else { return false }
        return decodedDays(task.completedOccurrenceDaysData, calendar: calendar)
            .contains(calendar.startOfDay(for: date))
    }

    @discardableResult
    static func normalizeLegacyState(_ tasks: [PlannerTask]) -> Bool {
        var changed = false
        for task in tasks {
            let storedStatus = PlannerTaskStatus(rawValue: task.statusRawValue)
            if task.isCompleted {
                if storedStatus != .completed {
                    task.statusRawValue = PlannerTaskStatus.completed.rawValue
                    changed = true
                }
            } else if storedStatus == nil || storedStatus == .completed {
                task.statusRawValue = PlannerTaskStatus.planned.rawValue
                changed = true
            }

            if task.scheduleKindRawValue == nil {
                let status = PlannerTaskStatus(rawValue: task.statusRawValue) ?? .planned
                task.scheduleKindRawValue = (status == .inbox || status == .waiting)
                    ? PlannerScheduleKind.none.rawValue
                    : PlannerScheduleKind.once.rawValue
                changed = true
            }
        }
        return changed
    }

    static func nextPosition(for tasks: [PlannerTask], on date: Date) -> Int {
        let positions = tasks.filter { isTask($0, scheduledFor: date) }.map(\.position)
        return (positions.max() ?? -1) + 1
    }

    static func normalizePositions(_ tasks: [PlannerTask]) {
        for (index, task) in tasks.sorted(by: comesBefore).enumerated() {
            task.position = index
            task.updatedAt = .now
        }
    }

    static func move(_ task: PlannerTask, by offset: Int, among tasks: [PlannerTask]) {
        var ordered = tasks.sorted(by: comesBefore)
        guard let source = ordered.firstIndex(where: { $0.id == task.id }), !ordered.isEmpty else { return }
        let destination = min(max(source + offset, 0), ordered.count - 1)
        guard source != destination else { return }
        ordered.swapAt(source, destination)
        for (index, item) in ordered.enumerated() {
            item.position = index
            item.updatedAt = .now
        }
    }

    nonisolated static func comesBefore(_ lhs: PlannerTask, _ rhs: PlannerTask) -> Bool {
        let lhsHasExactTime = lhs.timeMode == .exactTime && lhs.scheduledTime != nil
        let rhsHasExactTime = rhs.timeMode == .exactTime && rhs.scheduledTime != nil
        if lhsHasExactTime != rhsHasExactTime { return !lhsHasExactTime }
        if lhsHasExactTime, rhsHasExactTime,
           let lhsTime = lhs.scheduledTime, let rhsTime = rhs.scheduledTime,
           lhsTime != rhsTime {
            return lhsTime < rhsTime
        }
        if lhs.position != rhs.position { return lhs.position < rhs.position }
        return lhs.createdAt < rhs.createdAt
    }

    static func clearHabitConnection(_ habitID: UUID, from tasks: [PlannerTask]) {
        for task in tasks where task.habitID == habitID {
            task.habitID = nil
            task.updatedAt = .now
        }
    }

    static func nextRelevantDate(
        for task: PlannerTask,
        onOrAfter date: Date,
        calendar: Calendar = .current
    ) -> Date? {
        let day = calendar.startOfDay(for: date)
        var candidates: [Date] = []
        if let due = task.dueDate, calendar.startOfDay(for: due) >= day {
            candidates.append(calendar.startOfDay(for: due))
        }
        if let planned = nextPlannedDate(for: task, onOrAfter: day, calendar: calendar) {
            candidates.append(planned)
        }
        return candidates.min()
    }

    static func scheduleSummary(for task: PlannerTask, calendar: Calendar = .current) -> String {
        switch task.scheduleKind {
        case .none:
            return "Not planned"
        case .once:
            return task.scheduledDay.formatted(.dateTime.month(.abbreviated).day())
        case .multipleDays:
            let end = task.scheduleEndDate ?? task.scheduledDay
            return "\(task.scheduledDay.formatted(.dateTime.month(.abbreviated).day()))–\(end.formatted(.dateTime.month(.abbreviated).day()))"
        case .repeating:
            switch task.repeatFrequency {
            case .daily: return "Repeats daily"
            case .weekdays: return "Repeats weekdays"
            case .weekly: return "Repeats weekly"
            case .monthly: return "Repeats monthly"
            case .custom: return "Repeats on selected days"
            }
        }
    }

    private static func baseSession(
        for task: PlannerTask,
        on day: Date,
        calendar: Calendar
    ) -> PlannerWorkSession {
        let startTime: Date?
        if task.timeMode == .exactTime, let stored = task.scheduledTime {
            let components = calendar.dateComponents([.hour, .minute], from: stored)
            startTime = calendar.date(
                bySettingHour: components.hour ?? 0,
                minute: components.minute ?? 0,
                second: 0,
                of: day
            )
        } else {
            startTime = nil
        }
        return PlannerWorkSession(
            day: day,
            timeMode: task.timeMode,
            startTime: startTime,
            daySection: task.daySection,
            durationMinutes: task.plannedDurationMinutes,
            calendar: calendar
        )
    }

    private static func isFutureSessionSuppressed(
        _ task: PlannerTask,
        on day: Date,
        calendar: Calendar
    ) -> Bool {
        guard task.isCompleted,
              let completedAt = task.completedAt else { return false }
        return day > calendar.startOfDay(for: completedAt)
    }

    private static func isRepeatingTask(
        _ task: PlannerTask,
        scheduledOn day: Date,
        calendar: Calendar
    ) -> Bool {
        let start = calendar.startOfDay(for: task.scheduledDay)
        guard day >= start else { return false }
        if task.repeatEndMode == .onDate,
           let end = task.repeatEndDate,
           day > calendar.startOfDay(for: end) { return false }

        guard matchesRepeatingPattern(task, on: day, calendar: calendar) else { return false }

        if task.repeatEndMode == .afterCount, let repeatCount = task.repeatCount {
            let limit = max(1, repeatCount)
            return repeatingOccurrenceNumber(for: task, on: day, calendar: calendar) <= limit
        }
        return true
    }

    private static func repeatingOccurrenceNumber(
        for task: PlannerTask,
        on day: Date,
        calendar: Calendar
    ) -> Int {
        var count = 0
        var cursor = calendar.startOfDay(for: task.scheduledDay)
        let target = calendar.startOfDay(for: day)
        let countCeiling = task.repeatEndMode == .afterCount
            ? task.repeatCount.map { max(1, $0) + 1 } ?? Int.max
            : Int.max
        while count < countCeiling,
              let occurrence = nextRepeatingPatternDate(for: task, onOrAfter: cursor, calendar: calendar),
              occurrence <= target {
            count += 1
            guard let next = calendar.date(byAdding: .day, value: 1, to: occurrence) else { break }
            cursor = next
        }
        return count
    }

    private static func matchesRepeatingPattern(
        _ task: PlannerTask,
        on day: Date,
        calendar: Calendar
    ) -> Bool {
        let start = calendar.startOfDay(for: task.scheduledDay)
        guard day >= start else { return false }
        let interval = max(1, task.repeatInterval ?? 1)
        let dayDifference = calendar.dateComponents([.day], from: start, to: day).day ?? 0
        let selectedWeekdays = decodedWeekdays(task.scheduleWeekdaysRawValue)
        switch task.repeatFrequency {
        case .daily:
            return dayDifference.isMultiple(of: interval)
        case .weekdays:
            return weekdays.contains(calendar.component(.weekday, from: day))
        case .weekly:
            let weekDifference = calendar.dateComponents([.weekOfYear], from: start, to: day).weekOfYear ?? 0
            return weekDifference.isMultiple(of: interval)
                && calendar.component(.weekday, from: day) == calendar.component(.weekday, from: start)
        case .monthly:
            let monthDifference = calendar.dateComponents([.month], from: start, to: day).month ?? 0
            return monthDifference.isMultiple(of: interval)
                && calendar.component(.day, from: day) == calendar.component(.day, from: start)
        case .custom:
            let weekDifference = calendar.dateComponents([.weekOfYear], from: start, to: day).weekOfYear ?? 0
            return weekDifference.isMultiple(of: interval)
                && selectedWeekdays.contains(calendar.component(.weekday, from: day))
        }
    }

    private static func nextPlannedDate(
        for task: PlannerTask,
        onOrAfter day: Date,
        calendar: Calendar
    ) -> Date? {
        switch task.scheduleKind {
        case .none:
            return nil
        case .once:
            let planned = calendar.startOfDay(for: task.scheduledDay)
            return planned >= day && !isFutureSessionSuppressed(task, on: planned, calendar: calendar) ? planned : nil
        case .multipleDays:
            let stored = decodedSessions(task.customWorkSessionsData)
            if !stored.isEmpty {
                return stored.map { calendar.startOfDay(for: $0.day) }.filter { $0 >= day }.min()
            }
            let end = calendar.startOfDay(for: task.scheduleEndDate ?? task.scheduledDay)
            var cursor = max(day, calendar.startOfDay(for: task.scheduledDay))
            while cursor <= end {
                if session(for: task, on: cursor, calendar: calendar) != nil { return cursor }
                guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
            }
            return nil
        case .repeating:
            return nextRepeatingDate(for: task, onOrAfter: day, calendar: calendar)
        }
    }

    private static func nextRepeatingDate(
        for task: PlannerTask,
        onOrAfter day: Date,
        calendar: Calendar
    ) -> Date? {
        let start = calendar.startOfDay(for: task.scheduledDay)
        let searchStart = max(calendar.startOfDay(for: day), start)
        let excludedDays = decodedDays(task.excludedOccurrenceDaysData, calendar: calendar)
        let completionDate = task.isCompleted
            ? task.completedAt.map { calendar.startOfDay(for: $0) }
            : nil

        let endDate: Date?
        switch task.repeatEndMode {
        case .never:
            endDate = nil
        case .onDate:
            endDate = task.repeatEndDate.map { calendar.startOfDay(for: $0) }
        case .afterCount:
            if let repeatCount = task.repeatCount {
                let limit = max(1, repeatCount)
                var occurrenceStart = start
                for _ in 0..<limit {
                    guard let occurrence = nextRepeatingPatternDate(
                        for: task,
                        onOrAfter: occurrenceStart,
                        calendar: calendar
                    ) else {
                        return nil
                    }
                    if let completionDate, occurrence > completionDate { return nil }
                    if occurrence >= searchStart, !excludedDays.contains(occurrence) {
                        return occurrence
                    }
                    guard let next = calendar.date(byAdding: .day, value: 1, to: occurrence) else {
                        return nil
                    }
                    occurrenceStart = next
                }
                return nil
            }
            // Preserve legacy behavior: a missing count meant the schedule had no limit.
            endDate = nil
        }

        let lastAllowedDate = [endDate, completionDate].compactMap { $0 }.min()
        if let lastAllowedDate, searchStart > lastAllowedDate { return nil }

        var occurrenceStart = searchStart
        while let occurrence = nextRepeatingPatternDate(
            for: task,
            onOrAfter: occurrenceStart,
            calendar: calendar
        ) {
            if let lastAllowedDate, occurrence > lastAllowedDate { return nil }
            if !excludedDays.contains(occurrence) { return occurrence }
            guard let next = calendar.date(byAdding: .day, value: 1, to: occurrence) else {
                return nil
            }
            occurrenceStart = next
        }
        return nil
    }

    private static func nextRepeatingPatternDate(
        for task: PlannerTask,
        onOrAfter day: Date,
        calendar: Calendar
    ) -> Date? {
        let start = calendar.startOfDay(for: task.scheduledDay)
        let target = max(calendar.startOfDay(for: day), start)
        let interval = max(1, task.repeatInterval ?? 1)

        switch task.repeatFrequency {
        case .daily:
            let difference = max(0, calendar.dateComponents([.day], from: start, to: target).day ?? 0)
            let intervalsToAdd = (difference + interval - 1) / interval
            return calendar.date(byAdding: .day, value: intervalsToAdd * interval, to: start)

        case .weekdays:
            var candidate = target
            for _ in 0..<7 {
                if weekdays.contains(calendar.component(.weekday, from: candidate)) { return candidate }
                guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
                candidate = next
            }
            return nil

        case .weekly, .custom:
            var candidate = target
            let maximumDaysToSearch = (7 * interval) + 7
            for _ in 0...maximumDaysToSearch {
                if matchesRepeatingPattern(task, on: candidate, calendar: calendar) { return candidate }
                guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
                candidate = next
            }
            return nil

        case .monthly:
            let startComponents = calendar.dateComponents([.era, .year, .month, .day], from: start)
            guard let startDay = startComponents.day,
                  let startMonth = calendar.date(from: DateComponents(
                    era: startComponents.era,
                    year: startComponents.year,
                    month: startComponents.month,
                    day: 1
                  )) else {
                return nil
            }
            let targetComponents = calendar.dateComponents([.era, .year, .month], from: target)
            guard let targetMonth = calendar.date(from: DateComponents(
                era: targetComponents.era,
                year: targetComponents.year,
                month: targetComponents.month,
                day: 1
            )) else {
                return nil
            }
            let monthDifference = max(
                0,
                calendar.dateComponents([.month], from: startMonth, to: targetMonth).month ?? 0
            )
            var monthOffset = (monthDifference / interval) * interval

            // Within 12 aligned recurrence months, the starting calendar month repeats
            // and therefore guarantees a valid day even for dates such as the 31st.
            for _ in 0..<12 {
                guard let month = calendar.date(byAdding: .month, value: monthOffset, to: startMonth) else {
                    return nil
                }
                var components = calendar.dateComponents([.era, .year, .month], from: month)
                components.day = startDay
                if let expectedMonth = components.month,
                   let candidate = calendar.date(from: components),
                   calendar.component(.day, from: candidate) == startDay,
                   calendar.component(.month, from: candidate) == expectedMonth,
                   candidate >= target,
                   matchesRepeatingPattern(task, on: candidate, calendar: calendar) {
                    return candidate
                }
                monthOffset += interval
            }
            return nil
        }
    }

    private static func lastPlannedDate(
        for task: PlannerTask,
        calendar: Calendar
    ) -> Date? {
        switch task.scheduleKind {
        case .none: return nil
        case .once: return calendar.startOfDay(for: task.scheduledDay)
        case .multipleDays:
            let stored = decodedSessions(task.customWorkSessionsData)
            return stored.map { calendar.startOfDay(for: $0.day) }.max()
                ?? calendar.startOfDay(for: task.scheduleEndDate ?? task.scheduledDay)
        case .repeating: return nil
        }
    }

    private static func dayTaskComesBefore(_ lhs: PlannerDayTask, _ rhs: PlannerDayTask) -> Bool {
        if lhs.isDue != rhs.isDue, lhs.session == nil || rhs.session == nil {
            return lhs.isDue && lhs.session == nil
        }
        let lhsRank = sessionRank(lhs.session)
        let rhsRank = sessionRank(rhs.session)
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        if let lhsTime = lhs.session?.startTime, let rhsTime = rhs.session?.startTime, lhsTime != rhsTime {
            return lhsTime < rhsTime
        }
        return comesBefore(lhs.task, rhs.task)
    }

    private static func isOverdue(
        _ task: PlannerTask,
        before date: Date,
        calendar: Calendar
    ) -> Bool {
        if let dueTime = task.dueTime {
            return dueTime < date
        }
        guard let dueDate = task.dueDate else { return false }
        return calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: date)
    }

    private static func sessionRank(_ session: PlannerWorkSession?) -> Int {
        guard let session else { return -1 }
        switch session.timeMode {
        case .anytime: return 0
        case .daySection:
            switch session.daySection {
            case .morning: return 1
            case .afternoon: return 3
            case .evening: return 4
            case nil: return 0
            }
        case .exactTime: return 2
        }
    }
}
