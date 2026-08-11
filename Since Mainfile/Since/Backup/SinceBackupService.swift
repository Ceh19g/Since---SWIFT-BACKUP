import Foundation
import SwiftData

struct BackupRestoreSummary {
    let habitsInserted: Int
    let habitsUpdated: Int
    let tasksInserted: Int
    let tasksUpdated: Int

    var message: String {
        "Restored \(habitsInserted + habitsUpdated) habits and \(tasksInserted + tasksUpdated) planner tasks."
    }
}

@MainActor
enum SinceBackupService {
    static func makeArchive(
        habits: [Habit],
        plannerTasks: [PlannerTask],
        now: Date = .now
    ) -> SinceBackupArchive {
        let habitIDs = Set(habits.map(\.id))
        return SinceBackupArchive(
            version: SinceBackupArchive.currentVersion,
            exportedAt: now,
            habits: habits.map { habit in
                HabitBackupRecord(
                    id: habit.id,
                    name: habit.name,
                    habitDescription: habit.habitDescription,
                    typeRawValue: habit.typeRawValue,
                    tintRawValue: habit.tintRawValue,
                    symbolName: habit.symbolName,
                    startAt: habit.startAt,
                    customMilestoneDays: habit.customMilestoneDays,
                    healthMetricRawValue: habit.healthMetricRawValue,
                    healthGoalValue: habit.healthGoalValue,
                    healthGoalWeekdaysRawValue: habit.healthGoalWeekdaysRawValue,
                    healthGoalHistoryData: habit.healthGoalHistoryData,
                    measurementTemplateRawValue: habit.measurementTemplateRawValue,
                    measurementCustomName: habit.measurementCustomName,
                    measurementCustomUnit: habit.measurementCustomUnit,
                    measurementCustomValueKindRawValue: habit.measurementCustomValueKindRawValue,
                    measurementDefaultValue: habit.measurementDefaultValue,
                    isPinned: habit.isPinned,
                    isArchived: habit.isArchived,
                    createdAt: habit.createdAt,
                    updatedAt: habit.updatedAt,
                    events: habit.events.map {
                        HabitEventBackupRecord(
                            id: $0.id,
                            kindRawValue: $0.kindRawValue,
                            occurredAt: $0.occurredAt,
                            endedAt: $0.endedAt,
                            note: $0.note,
                            restartsStreak: $0.restartsStreak,
                            timezoneIdentifier: $0.timezoneIdentifier,
                            createdAt: $0.createdAt,
                            measurementValue: $0.measurementValue,
                            measurementSourceID: $0.measurementSourceID,
                            measurementName: $0.measurementName,
                            measurementUnit: $0.measurementUnit,
                            measurementValueKindRawValue: $0.measurementValueKindRawValue
                        )
                    }
                )
            },
            plannerTasks: plannerTasks.map {
                PlannerTaskBackupRecord(
                    id: $0.id,
                    title: $0.title,
                    taskNotes: $0.taskNotes,
                    scheduledDay: $0.scheduledDay,
                    dueDate: $0.dueDate,
                    dueTime: $0.dueTime,
                    timeModeRawValue: $0.timeModeRawValue,
                    scheduledTime: $0.scheduledTime,
                    daySectionRawValue: $0.daySectionRawValue,
                    scheduleKindRawValue: $0.scheduleKindRawValue,
                    scheduleEndDate: $0.scheduleEndDate,
                    scheduleWeekdaysRawValue: $0.scheduleWeekdaysRawValue,
                    plannedDurationMinutes: $0.plannedDurationMinutes,
                    customWorkSessionsData: $0.customWorkSessionsData,
                    repeatFrequencyRawValue: $0.repeatFrequencyRawValue,
                    repeatInterval: $0.repeatInterval,
                    repeatEndModeRawValue: $0.repeatEndModeRawValue,
                    repeatEndDate: $0.repeatEndDate,
                    repeatCount: $0.repeatCount,
                    completedOccurrenceDaysData: $0.completedOccurrenceDaysData,
                    excludedOccurrenceDaysData: $0.excludedOccurrenceDaysData,
                    isCompleted: $0.isCompleted,
                    completedAt: $0.completedAt,
                    position: $0.position,
                    priorityRawValue: $0.priorityRawValue,
                    statusRawValue: $0.statusRawValue,
                    habitID: $0.habitID.flatMap { habitIDs.contains($0) ? $0 : nil },
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            }
        )
    }

    static func validate(_ archive: SinceBackupArchive) throws {
        guard
            archive.version >= SinceBackupArchive.oldestSupportedVersion,
            archive.version <= SinceBackupArchive.currentVersion
        else {
            throw SinceBackupError.unsupportedVersion(archive.version)
        }

        let habitIDs = Set(archive.habits.map(\.id))
        let eventIDs = archive.habits.flatMap(\.events).map(\.id)
        let taskIDs = archive.plannerTasks.map(\.id)

        guard
            habitIDs.count == archive.habits.count,
            Set(eventIDs).count == eventIDs.count,
            Set(taskIDs).count == taskIDs.count
        else {
            throw SinceBackupError.unreadableFile
        }

        for task in archive.plannerTasks {
            if let habitID = task.habitID, !habitIDs.contains(habitID) {
                throw SinceBackupError.invalidReference
            }
        }
    }

    static func restore(
        _ archive: SinceBackupArchive,
        currentHabits: [Habit],
        currentTasks: [PlannerTask],
        in modelContext: ModelContext
    ) throws -> BackupRestoreSummary {
        try validate(archive)

        var habitsByID = Dictionary(uniqueKeysWithValues: currentHabits.map { ($0.id, $0) })
        var tasksByID = Dictionary(uniqueKeysWithValues: currentTasks.map { ($0.id, $0) })
        var habitsInserted = 0
        var habitsUpdated = 0
        var tasksInserted = 0
        var tasksUpdated = 0

        for record in archive.habits {
            let habit: Habit
            if let existing = habitsByID[record.id] {
                habit = existing
                habitsUpdated += 1
            } else {
                habit = Habit(
                    id: record.id,
                    name: record.name,
                    habitDescription: record.habitDescription,
                    type: HabitType(rawValue: record.typeRawValue) ?? .abstinence,
                    tint: HabitTint(rawValue: record.tintRawValue) ?? .indigo,
                    symbolName: record.symbolName,
                    startAt: record.startAt,
                    customMilestoneDays: record.customMilestoneDays,
                    healthMetric: record.healthMetricRawValue.flatMap(HealthMetric.init(rawValue:)),
                    healthGoalValue: record.healthGoalValue,
                    healthGoalWeekdays: HealthGoalManager.decodedWeekdays(record.healthGoalWeekdaysRawValue),
                    healthGoalHistoryData: record.healthGoalHistoryData,
                    measurementTemplateRawValue: record.measurementTemplateRawValue,
                    measurementCustomName: record.measurementCustomName,
                    measurementCustomUnit: record.measurementCustomUnit,
                    measurementCustomValueKindRawValue: record.measurementCustomValueKindRawValue,
                    measurementDefaultValue: record.measurementDefaultValue,
                    isPinned: record.isPinned,
                    isArchived: record.isArchived,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt
                )
                modelContext.insert(habit)
                habitsByID[record.id] = habit
                habitsInserted += 1
            }

            update(habit, from: record)
            var eventsByID = Dictionary(uniqueKeysWithValues: habit.events.map { ($0.id, $0) })
            for eventRecord in record.events {
                if let event = eventsByID[eventRecord.id] {
                    update(event, from: eventRecord)
                } else {
                    let event = HabitEvent(
                        id: eventRecord.id,
                        kind: HabitEventKind(rawValue: eventRecord.kindRawValue) ?? .note,
                        occurredAt: eventRecord.occurredAt,
                        endedAt: eventRecord.endedAt,
                        note: eventRecord.note,
                        restartsStreak: eventRecord.restartsStreak,
                        measurementValue: eventRecord.measurementValue,
                        measurementSourceID: eventRecord.measurementSourceID,
                        measurementName: eventRecord.measurementName,
                        measurementUnit: eventRecord.measurementUnit,
                        measurementValueKindRawValue: eventRecord.measurementValueKindRawValue,
                        timezoneIdentifier: eventRecord.timezoneIdentifier,
                        createdAt: eventRecord.createdAt,
                        habit: habit
                    )
                    habit.events.append(event)
                    modelContext.insert(event)
                    eventsByID[event.id] = event
                }
            }
        }

        for record in archive.plannerTasks {
            if let task = tasksByID[record.id] {
                update(task, from: record)
                tasksUpdated += 1
            } else {
                let task = PlannerTask(
                    id: record.id,
                    title: record.title,
                    taskNotes: record.taskNotes,
                    scheduledDay: record.scheduledDay,
                    dueDate: record.dueDate,
                    dueTime: record.dueTime,
                    timeMode: PlannerTimeMode(rawValue: record.timeModeRawValue) ?? .anytime,
                    scheduledTime: record.scheduledTime,
                    daySection: record.daySectionRawValue.flatMap(PlannerDaySection.init(rawValue:)),
                    scheduleKind: record.scheduleKindRawValue.flatMap(PlannerScheduleKind.init(rawValue:)),
                    scheduleEndDate: record.scheduleEndDate,
                    scheduleWeekdays: PlannerTaskManager.decodedWeekdays(record.scheduleWeekdaysRawValue),
                    plannedDurationMinutes: record.plannedDurationMinutes,
                    customWorkSessionsData: record.customWorkSessionsData,
                    repeatFrequency: record.repeatFrequencyRawValue
                        .flatMap(PlannerRepeatFrequency.init(rawValue:)) ?? .weekly,
                    repeatInterval: record.repeatInterval ?? 1,
                    repeatEndMode: record.repeatEndModeRawValue
                        .flatMap(PlannerRepeatEndMode.init(rawValue:)) ?? .never,
                    repeatEndDate: record.repeatEndDate,
                    repeatCount: record.repeatCount,
                    completedOccurrenceDaysData: record.completedOccurrenceDaysData,
                    excludedOccurrenceDaysData: record.excludedOccurrenceDaysData,
                    isCompleted: record.isCompleted,
                    completedAt: record.completedAt,
                    position: record.position,
                    priority: PlannerTaskPriority(rawValue: record.priorityRawValue) ?? .normal,
                    status: record.statusRawValue
                        .flatMap(PlannerTaskStatus.init(rawValue:))
                        ?? (record.isCompleted ? .completed : .planned),
                    habitID: record.habitID,
                    createdAt: record.createdAt,
                    updatedAt: record.updatedAt
                )
                modelContext.insert(task)
                tasksByID[record.id] = task
                tasksInserted += 1
            }
        }

        HabitManager.ensureOnePrimary(among: Array(habitsByID.values))
        try modelContext.save()

        return BackupRestoreSummary(
            habitsInserted: habitsInserted,
            habitsUpdated: habitsUpdated,
            tasksInserted: tasksInserted,
            tasksUpdated: tasksUpdated
        )
    }

    private static func update(_ habit: Habit, from record: HabitBackupRecord) {
        habit.name = record.name
        habit.habitDescription = record.habitDescription
        habit.typeRawValue = record.typeRawValue
        habit.tintRawValue = record.tintRawValue
        habit.symbolName = record.symbolName
        habit.startAt = record.startAt
        habit.customMilestoneDays = record.customMilestoneDays
        habit.healthMetricRawValue = record.healthMetricRawValue
        habit.healthGoalValue = record.healthGoalValue
        habit.healthGoalWeekdaysRawValue = record.healthGoalWeekdaysRawValue
        habit.healthGoalHistoryData = record.healthGoalHistoryData
        habit.measurementTemplateRawValue = record.measurementTemplateRawValue
        habit.measurementCustomName = record.measurementCustomName
        habit.measurementCustomUnit = record.measurementCustomUnit
        habit.measurementCustomValueKindRawValue = record.measurementCustomValueKindRawValue
        habit.measurementDefaultValue = record.measurementDefaultValue
        habit.isPinned = record.isPinned
        habit.isArchived = record.isArchived
        habit.createdAt = record.createdAt
        habit.updatedAt = record.updatedAt
    }

    private static func update(_ event: HabitEvent, from record: HabitEventBackupRecord) {
        event.kindRawValue = record.kindRawValue
        event.occurredAt = record.occurredAt
        event.endedAt = record.endedAt
        event.note = record.note
        event.restartsStreak = record.restartsStreak
        event.timezoneIdentifier = record.timezoneIdentifier
        event.createdAt = record.createdAt
        event.measurementValue = record.measurementValue
        event.measurementSourceID = record.measurementSourceID
        event.measurementName = record.measurementName
        event.measurementUnit = record.measurementUnit
        event.measurementValueKindRawValue = record.measurementValueKindRawValue
    }

    private static func update(_ task: PlannerTask, from record: PlannerTaskBackupRecord) {
        task.title = record.title
        task.taskNotes = record.taskNotes
        task.scheduledDay = record.scheduledDay
        task.dueDate = record.dueDate
        task.dueTime = record.dueTime
        task.timeModeRawValue = record.timeModeRawValue
        task.scheduledTime = record.scheduledTime
        task.daySectionRawValue = record.daySectionRawValue
        task.scheduleKindRawValue = record.scheduleKindRawValue
        task.scheduleEndDate = record.scheduleEndDate
        task.scheduleWeekdaysRawValue = record.scheduleWeekdaysRawValue
        task.plannedDurationMinutes = record.plannedDurationMinutes
        task.customWorkSessionsData = record.customWorkSessionsData
        task.repeatFrequencyRawValue = record.repeatFrequencyRawValue
        task.repeatInterval = record.repeatInterval
        task.repeatEndModeRawValue = record.repeatEndModeRawValue
        task.repeatEndDate = record.repeatEndDate
        task.repeatCount = record.repeatCount
        task.completedOccurrenceDaysData = record.completedOccurrenceDaysData
        task.excludedOccurrenceDaysData = record.excludedOccurrenceDaysData
        let restoredStatus = record.statusRawValue
            .flatMap(PlannerTaskStatus.init(rawValue:))
            ?? (record.isCompleted ? .completed : .planned)
        task.statusRawValue = restoredStatus.rawValue
        task.isCompleted = restoredStatus == .completed
        task.completedAt = restoredStatus == .completed
            ? (record.completedAt ?? record.updatedAt)
            : nil
        task.position = record.position
        task.priorityRawValue = record.priorityRawValue
        task.habitID = record.habitID
        task.createdAt = record.createdAt
        task.updatedAt = record.updatedAt
    }
}
