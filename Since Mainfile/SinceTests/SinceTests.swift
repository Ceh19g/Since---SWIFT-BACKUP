//
//  SinceTests.swift
//  SinceTests
//
//  Created by Charlie Hardgrove on 7/30/26.
//

import Foundation
import SwiftData
import Testing
@testable import Since

@MainActor
struct SinceTests {
    @Test func elapsedTimeBreaksDownExactSeconds() {
        let start = Date(timeIntervalSince1970: 0)
        let interval: TimeInterval = 273_906 // 3 days, 4 hours, 5 minutes, 6 seconds
        let end = start.addingTimeInterval(interval)
        let elapsed = ElapsedTime(from: start, to: end)

        #expect(elapsed.days == 3)
        #expect(elapsed.hours == 4)
        #expect(elapsed.minutes == 5)
        #expect(elapsed.seconds == 6)
    }

    @Test func elapsedTimeNeverBecomesNegative() {
        let start = Date(timeIntervalSince1970: 100)
        let end = Date(timeIntervalSince1970: 0)

        #expect(ElapsedTime(from: start, to: end).totalSeconds == 0)
    }

    @Test func restartingPreservesThePreviousSegment() throws {
        let originalStart = Date(timeIntervalSince1970: 1_000)
        let restart = originalStart.addingTimeInterval(10 * 86_400)
        let habit = Habit(name: "No alcohol", startAt: originalStart)
        let slip = HabitEvent(
            kind: .slip,
            occurredAt: restart,
            restartsStreak: true,
            habit: habit
        )
        habit.events.append(slip)

        let segments = StreakCalculator.segments(for: habit)

        #expect(segments.count == 2)
        #expect(segments[0].startedAt == originalStart)
        #expect(segments[0].endedAt == restart)
        #expect(segments[0].endReason == .slip)
        #expect(segments[1].startedAt == restart)
        #expect(segments[1].endedAt == nil)
    }

    @Test func nonRestartingSlipKeepsTheOriginalStart() {
        let originalStart = Date(timeIntervalSince1970: 1_000)
        let habit = Habit(name: "No alcohol", startAt: originalStart)
        let slip = HabitEvent(
            kind: .slip,
            occurredAt: originalStart.addingTimeInterval(10 * 86_400),
            restartsStreak: false,
            habit: habit
        )
        habit.events.append(slip)

        #expect(ElapsedTimeCalculator.currentStart(for: habit) == originalStart)
        #expect(StreakCalculator.segments(for: habit).count == 1)
    }

    @Test func milestoneProgressFindsTheNextThreshold() throws {
        let start = Date(timeIntervalSince1970: 0)
        let elapsed = ElapsedTime(from: start, to: start.addingTimeInterval(8 * 86_400))
        let progress = MilestoneCalculator.progress(for: elapsed)

        #expect(progress.nextDay == 14)
        #expect(progress.remainingSeconds == 6 * 86_400)
        #expect(progress.fractionComplete > 0)
        #expect(progress.fractionComplete < 1)
        #expect(!progress.isComplete)
    }

    @Test func customMilestoneUsesThePersonalTarget() {
        let start = Date(timeIntervalSince1970: 0)
        let elapsed = ElapsedTime(from: start, to: start.addingTimeInterval(10 * 86_400))
        let progress = MilestoneCalculator.progress(for: elapsed, customDay: 30)

        #expect(progress.nextDay == 30)
        #expect(progress.remainingSeconds == 20 * 86_400)
        #expect(progress.fractionComplete > 0.33)
        #expect(progress.fractionComplete < 0.34)
        #expect(!progress.isComplete)
    }

    @Test func completedCustomMilestoneIsRecognized() {
        let start = Date(timeIntervalSince1970: 0)
        let elapsed = ElapsedTime(from: start, to: start.addingTimeInterval(31 * 86_400))
        let progress = MilestoneCalculator.progress(for: elapsed, customDay: 30)

        #expect(progress.nextDay == 30)
        #expect(progress.remainingSeconds == 0)
        #expect(progress.fractionComplete == 1)
        #expect(progress.isComplete)
    }

    @Test func archivingThePrimaryHabitPromotesAnotherHabit() {
        let first = Habit(
            name: "No alcohol",
            startAt: .now,
            isPinned: true,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let second = Habit(
            name: "No smoking",
            startAt: .now,
            isPinned: false,
            createdAt: Date(timeIntervalSince1970: 2)
        )

        HabitManager.archive(first, among: [first, second])

        #expect(first.isArchived)
        #expect(!first.isPinned)
        #expect(second.isPinned)
    }

    @Test func restoringTheOnlyActiveHabitMakesItPrimary() {
        let habit = Habit(
            name: "No alcohol",
            startAt: .now,
            isPinned: false,
            isArchived: true
        )

        HabitManager.restore(habit, among: [habit])

        #expect(!habit.isArchived)
        #expect(habit.isPinned)
    }

    @Test func activeHabitOrderAlwaysStartsWithPriority() {
        let older = Habit(
            name: "Older",
            startAt: .now,
            isPinned: false,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let priority = Habit(
            name: "Priority",
            startAt: .now,
            isPinned: true,
            createdAt: Date(timeIntervalSince1970: 3)
        )
        let archived = Habit(
            name: "Archived",
            startAt: .now,
            isPinned: false,
            isArchived: true,
            createdAt: Date(timeIntervalSince1970: 0)
        )

        #expect(HabitManager.orderedActive([older, archived, priority]).map(\.name) == ["Priority", "Older"])
    }

    @Test func removingARestartingSlipRejoinsTheStreak() {
        let originalStart = Date(timeIntervalSince1970: 1_000)
        let habit = Habit(name: "No alcohol", startAt: originalStart)
        let slip = HabitEvent(
            kind: .slip,
            occurredAt: originalStart.addingTimeInterval(10 * 86_400),
            restartsStreak: true,
            habit: habit
        )
        habit.events.append(slip)

        #expect(StreakCalculator.segments(for: habit).count == 2)

        habit.events.removeAll { $0.id == slip.id }

        #expect(StreakCalculator.segments(for: habit).count == 1)
        #expect(ElapsedTimeCalculator.currentStart(for: habit) == originalStart)
    }

    @Test func plannerGroupsTasksByLocalCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let firstDay = calendar.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 23, minute: 30))!
        let secondDay = calendar.date(from: DateComponents(year: 2026, month: 7, day: 31, hour: 0, minute: 30))!
        let firstTask = PlannerTask(title: "Late task", scheduledDay: firstDay)
        let secondTask = PlannerTask(title: "Early task", scheduledDay: secondDay)

        let tasks = PlannerTaskManager.tasks(
            on: firstDay,
            from: [firstTask, secondTask],
            calendar: calendar
        )

        #expect(tasks.map(\.title) == ["Late task"])
    }

    @Test func plannerProgressCountsCompletedTasks() {
        let first = PlannerTask(title: "Walk", scheduledDay: .now, isCompleted: true)
        let second = PlannerTask(title: "Read", scheduledDay: .now)
        let progress = PlannerTaskManager.progress(for: [first, second])

        #expect(progress.completed == 1)
        #expect(progress.total == 2)
        #expect(progress.fraction == 0.5)
        #expect(PlannerTaskManager.progress(for: [PlannerTask]()).fraction == 0)
    }

    @Test func plannerTasksCanBeReordered() {
        let first = PlannerTask(title: "First", scheduledDay: .now, position: 0)
        let second = PlannerTask(title: "Second", scheduledDay: .now, position: 1)
        let third = PlannerTask(title: "Third", scheduledDay: .now, position: 2)

        PlannerTaskManager.move(third, by: -1, among: [first, second, third])
        let ordered = [first, second, third].sorted(by: PlannerTaskManager.comesBefore)

        #expect(ordered.map(\.title) == ["First", "Third", "Second"])
    }

    @Test func plannerCompletionCanBeReopenedWithoutChangingItsDay() {
        let day = PlannerTaskManager.startOfDay(.now)
        let task = PlannerTask(title: "Journal", scheduledDay: day)

        PlannerTaskManager.setStatus(.completed, for: task)
        #expect(task.isCompleted)
        #expect(task.status == .completed)
        #expect(task.completedAt != nil)
        #expect(task.scheduledDay == day)

        PlannerTaskManager.setStatus(.planned, for: task)
        #expect(!task.isCompleted)
        #expect(task.status == .planned)
        #expect(task.completedAt == nil)
        #expect(task.scheduledDay == day)
    }

    @Test func inboxAndWaitingTasksStayOffTheCalendar() {
        let day = PlannerTaskManager.startOfDay(.now)
        let inbox = PlannerTask(title: "Unsorted", scheduledDay: day, status: .inbox)
        let waiting = PlannerTask(title: "Waiting", scheduledDay: day, status: .waiting)
        let planned = PlannerTask(title: "Planned", scheduledDay: day, status: .planned)

        #expect(PlannerTaskManager.tasks(on: day, from: [inbox, waiting, planned]).map(\.title) == ["Planned"])
        #expect(PlannerTaskManager.inbox(from: [inbox, waiting, planned]).map(\.title) == ["Unsorted"])
        #expect(PlannerTaskManager.waiting(from: [inbox, waiting, planned]).map(\.title) == ["Waiting"])
    }

    @Test func anUnplannedInboxTaskAppearsOnItsDeadline() throws {
        let calendar = Calendar(identifier: .gregorian)
        let dueDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 12)))
        let task = PlannerTask(
            title: "File paperwork",
            scheduledDay: dueDay,
            dueDate: dueDay,
            scheduleKind: PlannerScheduleKind.none,
            status: .inbox
        )

        let entry = try #require(PlannerTaskManager.dayTask(task, on: dueDay, calendar: calendar))
        #expect(entry.isDue)
        #expect(!entry.isPlanned)
        #expect(entry.session == nil)
    }

    @Test func overdueUsesDeadlineWhileUnfinishedUsesPastWorkPlan() throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 12)))
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: today))
        let overdue = PlannerTask(
            title: "Overdue",
            scheduledDay: tomorrow,
            dueDate: yesterday,
            scheduleKind: .once
        )
        let unfinished = PlannerTask(
            title: "Unfinished",
            scheduledDay: yesterday,
            dueDate: tomorrow,
            scheduleKind: .once
        )

        #expect(PlannerTaskManager.overdue(before: today, from: [overdue, unfinished], calendar: calendar).map(\.title) == ["Overdue"])
        #expect(PlannerTaskManager.unfinished(before: today, from: [overdue, unfinished], calendar: calendar).map(\.title) == ["Unfinished"])
    }

    @Test func deadlineTimeCanBecomeOverdueDuringTheDueDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 12)))
        let dueTime = try #require(calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day))
        let before = try #require(calendar.date(bySettingHour: 9, minute: 59, second: 0, of: day))
        let after = try #require(calendar.date(bySettingHour: 10, minute: 1, second: 0, of: day))
        let task = PlannerTask(
            title: "Timed deadline",
            scheduledDay: day,
            dueDate: day,
            dueTime: dueTime,
            scheduleKind: PlannerScheduleKind.none,
            status: .inbox
        )

        #expect(PlannerTaskManager.overdue(before: before, from: [task], calendar: calendar).isEmpty)
        #expect(PlannerTaskManager.overdue(before: after, from: [task], calendar: calendar).map(\.title) == ["Timed deadline"])
    }

    @Test func multiDayTaskUsesIndependentWorkSessionTimes() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let firstDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 10)))
        let secondDay = try #require(calendar.date(byAdding: .day, value: 1, to: firstDay))
        let firstStart = try #require(calendar.date(bySettingHour: 9, minute: 0, second: 0, of: firstDay))
        let secondStart = try #require(calendar.date(bySettingHour: 14, minute: 30, second: 0, of: secondDay))
        let sessions = [
            PlannerWorkSession(day: firstDay, timeMode: .exactTime, startTime: firstStart, durationMinutes: 60, calendar: calendar),
            PlannerWorkSession(day: secondDay, timeMode: .exactTime, startTime: secondStart, durationMinutes: 90, calendar: calendar)
        ]
        let task = PlannerTask(
            title: "Prepare report",
            scheduledDay: firstDay,
            timeMode: .exactTime,
            scheduledTime: firstStart,
            scheduleKind: .multipleDays,
            scheduleEndDate: secondDay,
            customWorkSessionsData: PlannerTaskManager.encodedSessions(sessions)
        )

        let first = try #require(PlannerTaskManager.session(for: task, on: firstDay, calendar: calendar))
        let second = try #require(PlannerTaskManager.session(for: task, on: secondDay, calendar: calendar))
        #expect(calendar.component(.hour, from: try #require(first.startTime)) == 9)
        #expect(first.durationMinutes == 60)
        #expect(calendar.component(.hour, from: try #require(second.startTime)) == 14)
        #expect(calendar.component(.minute, from: try #require(second.startTime)) == 30)
        #expect(second.durationMinutes == 90)
    }

    @Test func customRepeatingTaskOnlyAppearsOnSelectedWeekdays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 10)))
        let tuesday = try #require(calendar.date(byAdding: .day, value: 1, to: monday))
        let wednesday = try #require(calendar.date(byAdding: .day, value: 2, to: monday))
        let task = PlannerTask(
            title: "Training",
            scheduledDay: monday,
            scheduleKind: .repeating,
            scheduleWeekdays: [2, 4],
            repeatFrequency: .custom
        )

        #expect(PlannerTaskManager.session(for: task, on: monday, calendar: calendar) != nil)
        #expect(PlannerTaskManager.session(for: task, on: tuesday, calendar: calendar) == nil)
        #expect(PlannerTaskManager.session(for: task, on: wednesday, calendar: calendar) != nil)
    }

    @Test func repeatingOccurrencesCompleteIndependently() throws {
        let calendar = Calendar(identifier: .gregorian)
        let firstDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 10)))
        let secondDay = try #require(calendar.date(byAdding: .day, value: 1, to: firstDay))
        let task = PlannerTask(
            title: "Daily review",
            scheduledDay: firstDay,
            scheduleKind: .repeating,
            repeatFrequency: .daily
        )

        PlannerTaskManager.setCompletion(true, for: task, on: firstDay, calendar: calendar)

        #expect(PlannerTaskManager.isCompleted(task, on: firstDay, calendar: calendar))
        #expect(!PlannerTaskManager.isCompleted(task, on: secondDay, calendar: calendar))
        #expect(task.status != .completed)
    }

    @Test func completingAnEntireRepeatingTaskStopsFutureOccurrences() throws {
        let calendar = Calendar(identifier: .gregorian)
        let firstDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 10)))
        let secondDay = try #require(calendar.date(byAdding: .day, value: 1, to: firstDay))
        let task = PlannerTask(
            title: "Daily review",
            scheduledDay: firstDay,
            scheduleKind: .repeating,
            repeatFrequency: .daily
        )

        PlannerTaskManager.setStatus(.completed, for: task, now: firstDay.addingTimeInterval(12 * 3_600))

        #expect(PlannerTaskManager.session(for: task, on: firstDay, calendar: calendar) != nil)
        #expect(PlannerTaskManager.session(for: task, on: secondDay, calendar: calendar) == nil)
    }

    @Test func exhaustedOccurrenceCountDoesNotAppearInUpcomingTasks() throws {
        let calendar = Calendar(identifier: .gregorian)
        let firstDay = try #require(calendar.date(from: DateComponents(year: 2020, month: 1, day: 1)))
        let finalDay = try #require(calendar.date(byAdding: .day, value: 2, to: firstDay))
        let task = PlannerTask(
            title: "Three-day reset",
            scheduledDay: firstDay,
            scheduleKind: .repeating,
            repeatFrequency: .daily,
            repeatEndMode: .afterCount,
            repeatCount: 3
        )

        #expect(
            PlannerTaskManager.nextRelevantDate(
                for: task,
                onOrAfter: finalDay,
                calendar: calendar
            ) == finalDay
        )
        #expect(PlannerTaskManager.upcoming(after: finalDay, from: [task], calendar: calendar).isEmpty)
    }

    @Test func repeatingTaskStopsAfterItsEndDate() throws {
        let calendar = Calendar(identifier: .gregorian)
        let firstDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 10)))
        let endDay = try #require(calendar.date(byAdding: .day, value: 2, to: firstDay))
        let dayAfterEnd = try #require(calendar.date(byAdding: .day, value: 1, to: endDay))
        let task = PlannerTask(
            title: "Short routine",
            scheduledDay: firstDay,
            scheduleKind: .repeating,
            repeatFrequency: .daily,
            repeatEndMode: .onDate,
            repeatEndDate: endDay
        )

        #expect(
            PlannerTaskManager.nextRelevantDate(
                for: task,
                onOrAfter: endDay,
                calendar: calendar
            ) == endDay
        )
        #expect(
            PlannerTaskManager.nextRelevantDate(
                for: task,
                onOrAfter: dayAfterEnd,
                calendar: calendar
            ) == nil
        )
    }

    @Test func upcomingMonthlyRepeatSkipsMonthsWithoutItsCalendarDay() throws {
        let calendar = Calendar(identifier: .gregorian)
        let january31 = try #require(calendar.date(from: DateComponents(year: 2026, month: 1, day: 31)))
        let february1 = try #require(calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)))
        let march31 = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 31)))
        let task = PlannerTask(
            title: "Month-end review",
            scheduledDay: january31,
            scheduleKind: .repeating,
            repeatFrequency: .monthly
        )

        #expect(
            PlannerTaskManager.nextRelevantDate(
                for: task,
                onOrAfter: february1,
                calendar: calendar
            ) == march31
        )
    }

    @Test func upcomingCustomRepeatKeepsItsWeekInterval() throws {
        let calendar = Calendar(identifier: .gregorian)
        let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 10)))
        let thursday = try #require(calendar.date(byAdding: .day, value: 3, to: monday))
        let nextActiveMonday = try #require(calendar.date(byAdding: .day, value: 14, to: monday))
        let task = PlannerTask(
            title: "Training",
            scheduledDay: monday,
            scheduleKind: .repeating,
            scheduleWeekdays: [2, 4],
            repeatFrequency: .custom,
            repeatInterval: 2
        )

        #expect(
            PlannerTaskManager.nextRelevantDate(
                for: task,
                onOrAfter: thursday,
                calendar: calendar
            ) == nextActiveMonday
        )
    }

    @Test func missingOccurrenceLimitPreservesLegacyUnlimitedSchedule() throws {
        let calendar = Calendar(identifier: .gregorian)
        let firstDay = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 10)))
        let secondDay = try #require(calendar.date(byAdding: .day, value: 1, to: firstDay))
        let task = PlannerTask(
            title: "Legacy repeat",
            scheduledDay: firstDay,
            scheduleKind: .repeating,
            repeatFrequency: .daily,
            repeatEndMode: .afterCount,
            repeatCount: nil
        )

        #expect(PlannerTaskManager.session(for: task, on: firstDay, calendar: calendar) != nil)
        #expect(PlannerTaskManager.session(for: task, on: secondDay, calendar: calendar) != nil)
        #expect(
            PlannerTaskManager.nextRelevantDate(
                for: task,
                onOrAfter: secondDay,
                calendar: calendar
            ) == secondDay
        )
    }

    @Test func plannedAndDueOnSameDayProduceOneCalendarEntry() throws {
        let calendar = Calendar(identifier: .gregorian)
        let day = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 12)))
        let task = PlannerTask(title: "Submit report", scheduledDay: day, dueDate: day)

        let entries = PlannerTaskManager.dayTasks(on: day, from: [task], calendar: calendar)
        let entry = try #require(entries.first)
        #expect(entries.count == 1)
        #expect(entry.isPlanned)
        #expect(entry.isDue)
    }

    @Test func plannerNormalizesLegacyCompletionState() {
        let task = PlannerTask(title: "Legacy", scheduledDay: .now)
        task.isCompleted = true
        task.statusRawValue = PlannerTaskStatus.planned.rawValue

        #expect(PlannerTaskManager.normalizeLegacyState([task]))
        #expect(task.statusRawValue == PlannerTaskStatus.completed.rawValue)
        #expect(task.status == .completed)
    }

    @Test func removingAHabitConnectionDoesNotRemoveThePlannerTask() {
        let habit = Habit(name: "Exercise", startAt: .now)
        let task = PlannerTask(title: "Take a walk", scheduledDay: .now, habitID: habit.id)

        #expect(task.habitID == habit.id)
        task.habitID = nil

        #expect(task.title == "Take a walk")
        #expect(task.habitID == nil)
    }

    @Test func exactTimePlannerTasksSortChronologically() {
        let day = PlannerTaskManager.startOfDay(.now)
        let afternoon = PlannerTask(
            title: "Afternoon",
            scheduledDay: day,
            timeMode: .exactTime,
            scheduledTime: day.addingTimeInterval(15 * 3_600),
            position: 0
        )
        let morning = PlannerTask(
            title: "Morning",
            scheduledDay: day,
            timeMode: .exactTime,
            scheduledTime: day.addingTimeInterval(9 * 3_600),
            position: 10
        )

        let ordered = PlannerTaskManager.tasks(on: day, from: [afternoon, morning])
        #expect(ordered.map(\.title) == ["Morning", "Afternoon"])
    }

    @Test func deletingAHabitClearsPlannerLinksWithoutDeletingTasks() {
        let habit = Habit(name: "Exercise", startAt: .now)
        let linked = PlannerTask(title: "Walk", scheduledDay: .now, habitID: habit.id)
        let unrelated = PlannerTask(title: "Read", scheduledDay: .now)

        PlannerTaskManager.clearHabitConnection(habit.id, from: [linked, unrelated])

        #expect(linked.habitID == nil)
        #expect(linked.title == "Walk")
        #expect(unrelated.habitID == nil)
    }

    @Test func measurementAddsDetailWithoutMultiplyingSlipCount() throws {
        let habit = Habit(
            name: "No alcohol",
            startAt: Date(timeIntervalSince1970: 1_000),
            measurementTemplateRawValue: HabitMeasurementTemplate.drinks.rawValue,
            measurementDefaultValue: 2
        )
        let slip = HabitEvent(
            kind: .slip,
            occurredAt: Date(timeIntervalSince1970: 2_000),
            habit: habit
        )
        HabitMeasurementManager.applyDefaultMeasurement(to: slip, for: habit)
        habit.events.append(slip)

        let statistics = try #require(HabitMeasurementManager.statistics(for: habit))
        #expect(habit.events.filter { $0.kind == .slip }.count == 1)
        #expect(slip.formattedMeasurement == "2 drinks")
        #expect(statistics.total == 2)
        #expect(statistics.measuredCount == 1)
    }

    @Test func measurementStatisticsExcludeMissingAmountsInsteadOfTreatingThemAsZero() throws {
        let habit = Habit(
            name: "Read",
            type: .positiveStreak,
            startAt: Date(timeIntervalSince1970: 1_000),
            measurementTemplateRawValue: HabitMeasurementTemplate.pages.rawValue
        )
        for value in [12.0, nil, 8.0] as [Double?] {
            let event = HabitEvent(kind: .completed, occurredAt: .now, habit: habit)
            HabitMeasurementManager.apply(value: value, definition: habit.measurementDefinition, to: event)
            habit.events.append(event)
        }

        let statistics = try #require(HabitMeasurementManager.statistics(for: habit))
        #expect(statistics.total == 20)
        #expect(statistics.average == 10)
        #expect(statistics.measuredCount == 2)
        #expect(statistics.missingCount == 1)
    }

    @Test func measuredHabitWithoutDefaultStillRequiresASuggestedEntryValue() {
        let habit = Habit(
            name: "Read",
            type: .positiveStreak,
            startAt: .now,
            measurementTemplateRawValue: HabitMeasurementTemplate.pages.rawValue
        )

        #expect(HabitMeasurementManager.initialEntryValue(for: habit) == 1)
    }

    @Test func measuredHabitEntryStartsWithItsChosenDefault() {
        let habit = Habit(
            name: "Water",
            type: .positiveStreak,
            startAt: .now,
            measurementTemplateRawValue: HabitMeasurementTemplate.glasses.rawValue,
            measurementDefaultValue: 8
        )

        #expect(HabitMeasurementManager.initialEntryValue(for: habit) == 8)
    }

    @Test func builtInMeasurementsUseSingularUnitsForOne() {
        #expect(HabitMeasurementTemplate.pages.definition.formatted(1) == "1 page")
        #expect(HabitMeasurementTemplate.glasses.definition.formatted(1) == "1 glass")
        #expect(HabitMeasurementTemplate.minutes.definition.formatted(1) == "1 minute")
        #expect(HabitMeasurementTemplate.pages.definition.formatted(2) == "2 pages")
    }

    @Test func customMeasurementsCanBeReusedAcrossHabits() throws {
        let source = Habit(
            name: "Practice",
            type: .positiveStreak,
            startAt: .now,
            measurementTemplateRawValue: HabitMeasurementManager.customSourceID,
            measurementCustomName: "Songs",
            measurementCustomUnit: "songs",
            measurementCustomValueKindRawValue: HabitMeasurementValueKind.wholeNumber.rawValue
        )
        let definition = try #require(HabitMeasurementManager.customDefinitions(from: [source]).first)

        #expect(definition.name == "Songs")
        #expect(definition.unit == "songs")
        #expect(definition.valueKind == .wholeNumber)
    }

    @Test func backupEncodingPreservesHabitHistoryAndPlannerTasks() throws {
        let habit = Habit(
            name: "No alcohol",
            habitDescription: "Clear mornings",
            type: .event,
            tint: .teal,
            symbolName: "drop.fill",
            startAt: Date(timeIntervalSince1970: 1_000),
            measurementTemplateRawValue: HabitMeasurementTemplate.rating.rawValue,
            measurementDefaultValue: 4
        )
        let slip = HabitEvent(
            kind: .slip,
            occurredAt: Date(timeIntervalSince1970: 2_000),
            note: "Dinner",
            restartsStreak: true,
            habit: habit
        )
        habit.events.append(slip)
        HabitMeasurementManager.apply(
            value: 4,
            definition: habit.measurementDefinition,
            to: slip
        )
        let task = PlannerTask(
            title: "Buy sparkling water",
            scheduledDay: Date(timeIntervalSince1970: 3_000),
            dueDate: Date(timeIntervalSince1970: 90_000),
            dueTime: Date(timeIntervalSince1970: 93_600),
            timeMode: .exactTime,
            scheduledTime: Date(timeIntervalSince1970: 32_400),
            scheduleKind: .repeating,
            scheduleWeekdays: [2, 4, 6],
            plannedDurationMinutes: 45,
            repeatFrequency: .custom,
            repeatInterval: 2,
            repeatEndMode: .afterCount,
            repeatCount: 8,
            priority: .important,
            status: .inProgress,
            habitID: habit.id
        )

        let archive = SinceBackupService.makeArchive(
            habits: [habit],
            plannerTasks: [task],
            now: Date(timeIntervalSince1970: 4_000)
        )
        let data = try SinceBackupCoding.encoder.encode(archive)
        let decoded = try SinceBackupCoding.decoder.decode(SinceBackupArchive.self, from: data)

        #expect(decoded.version == SinceBackupArchive.currentVersion)
        #expect(decoded.habits.count == 1)
        #expect(decoded.habits[0].typeRawValue == HabitType.event.rawValue)
        #expect(decoded.habits[0].events.count == 1)
        #expect(decoded.habits[0].events[0].note == "Dinner")
        #expect(decoded.habits[0].measurementTemplateRawValue == HabitMeasurementTemplate.rating.rawValue)
        #expect(decoded.habits[0].measurementDefaultValue == 4)
        #expect(decoded.habits[0].events[0].measurementValue == 4)
        #expect(decoded.habits[0].events[0].measurementName == "Rating")
        #expect(decoded.plannerTasks.count == 1)
        #expect(decoded.plannerTasks[0].habitID == habit.id)
        #expect(decoded.plannerTasks[0].dueDate == PlannerTaskManager.startOfDay(Date(timeIntervalSince1970: 90_000)))
        #expect(decoded.plannerTasks[0].dueTime == Date(timeIntervalSince1970: 93_600))
        #expect(decoded.plannerTasks[0].scheduleKindRawValue == PlannerScheduleKind.repeating.rawValue)
        #expect(decoded.plannerTasks[0].scheduleWeekdaysRawValue == "2,4,6")
        #expect(decoded.plannerTasks[0].plannedDurationMinutes == 45)
        #expect(decoded.plannerTasks[0].repeatFrequencyRawValue == PlannerRepeatFrequency.custom.rawValue)
        #expect(decoded.plannerTasks[0].repeatInterval == 2)
        #expect(decoded.plannerTasks[0].repeatEndModeRawValue == PlannerRepeatEndMode.afterCount.rawValue)
        #expect(decoded.plannerTasks[0].repeatCount == 8)
        #expect(decoded.plannerTasks[0].priorityRawValue == PlannerTaskPriority.important.rawValue)
        #expect(decoded.plannerTasks[0].statusRawValue == PlannerTaskStatus.inProgress.rawValue)
    }

    @Test func backupRestoreInsertsRecordsIntoAnEmptyStore() throws {
        let schema = Schema([Habit.self, HabitEvent.self, PlannerTask.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let habitID = UUID()
        let archive = SinceBackupArchive(
            version: SinceBackupArchive.currentVersion,
            exportedAt: .now,
            habits: [
                HabitBackupRecord(
                    id: habitID,
                    name: "Meditation",
                    habitDescription: "",
                    typeRawValue: HabitType.countdown.rawValue,
                    tintRawValue: HabitTint.indigo.rawValue,
                    symbolName: "brain.head.profile.fill",
                    startAt: .now,
                    customMilestoneDays: nil,
                    isPinned: true,
                    isArchived: false,
                    createdAt: .now,
                    updatedAt: .now,
                    events: []
                )
            ],
            plannerTasks: [
                PlannerTaskBackupRecord(
                    id: UUID(),
                    title: "Sit quietly",
                    taskNotes: "",
                    scheduledDay: .now,
                    dueDate: .now,
                    timeModeRawValue: PlannerTimeMode.anytime.rawValue,
                    scheduledTime: nil,
                    daySectionRawValue: nil,
                    isCompleted: false,
                    completedAt: nil,
                    position: 0,
                    priorityRawValue: PlannerTaskPriority.medium.rawValue,
                    statusRawValue: PlannerTaskStatus.waiting.rawValue,
                    habitID: habitID,
                    createdAt: .now,
                    updatedAt: .now
                )
            ]
        )

        let summary = try SinceBackupService.restore(
            archive,
            currentHabits: [],
            currentTasks: [],
            in: container.mainContext
        )
        let restoredHabits = try container.mainContext.fetch(FetchDescriptor<Habit>())
        let restoredTasks = try container.mainContext.fetch(FetchDescriptor<PlannerTask>())

        #expect(summary.habitsInserted == 1)
        #expect(summary.tasksInserted == 1)
        #expect(restoredHabits.first?.name == "Meditation")
        #expect(restoredHabits.first?.type == .countdown)
        #expect(restoredTasks.first?.habitID == habitID)
        #expect(restoredTasks.first?.priority == .medium)
        #expect(restoredTasks.first?.status == .waiting)
        #expect(restoredTasks.first?.dueDate != nil)
    }

    @Test func versionOneBackupRestoresTasksAsPlannedOrCompleted() throws {
        let schema = Schema([Habit.self, HabitEvent.self, PlannerTask.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let record = PlannerTaskBackupRecord(
            id: UUID(),
            title: "Old task",
            taskNotes: "",
            scheduledDay: .now,
            dueDate: nil,
            timeModeRawValue: PlannerTimeMode.anytime.rawValue,
            scheduledTime: nil,
            daySectionRawValue: nil,
            isCompleted: false,
            completedAt: nil,
            position: 0,
            priorityRawValue: PlannerTaskPriority.normal.rawValue,
            statusRawValue: nil,
            habitID: nil,
            createdAt: .now,
            updatedAt: .now
        )
        let archive = SinceBackupArchive(
            version: 1,
            exportedAt: .now,
            habits: [],
            plannerTasks: [record]
        )

        _ = try SinceBackupService.restore(
            archive,
            currentHabits: [],
            currentTasks: [],
            in: container.mainContext
        )
        let restoredTasks = try container.mainContext.fetch(FetchDescriptor<PlannerTask>())

        #expect(restoredTasks.first?.status == .planned)
    }

    @Test func calendarSummaryCombinesTaskProgressAndHabitActivity() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 12))!
        let habit = Habit(
            name: "No alcohol",
            startAt: calendar.date(byAdding: .day, value: -10, to: day)!
        )
        habit.events.append(
            HabitEvent(
                kind: .slip,
                occurredAt: calendar.date(bySettingHour: 19, minute: 30, second: 0, of: day)!,
                habit: habit
            )
        )
        let complete = PlannerTask(title: "Walk", scheduledDay: day, isCompleted: true)
        let incomplete = PlannerTask(title: "Read", scheduledDay: day)

        let summary = CalendarActivityManager.summary(
            on: day,
            tasks: [complete, incomplete],
            habits: [habit],
            now: day,
            calendar: calendar
        )

        #expect(summary.completedTaskCount == 1)
        #expect(summary.totalTaskCount == 2)
        #expect(summary.incompleteTaskCount == 1)
        #expect(!summary.areAllTasksComplete)
        #expect(summary.trackedHabitCount == 1)
        #expect(summary.slipCount == 1)
    }

    @Test func calendarSummaryRecognizesAnAllCompleteTaskDay() {
        let day = PlannerTaskManager.startOfDay(.now)
        let tasks = [
            PlannerTask(title: "Walk", scheduledDay: day, isCompleted: true),
            PlannerTask(title: "Read", scheduledDay: day, isCompleted: true)
        ]

        let summary = CalendarActivityManager.summary(
            on: day,
            tasks: tasks,
            habits: []
        )

        #expect(summary.areAllTasksComplete)
        #expect(summary.incompleteTaskCount == 0)
    }

    @Test func calendarDoesNotMarkHabitsBeforeTheirStartOrInTheFuture() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 12))!
        let habit = Habit(
            name: "No alcohol",
            startAt: calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 9))!
        )
        let beforeStart = calendar.date(from: DateComponents(year: 2026, month: 7, day: 19, hour: 12))!
        let future = calendar.date(from: DateComponents(year: 2026, month: 7, day: 31, hour: 12))!

        #expect(!CalendarActivityManager.isHabit(habit, trackedOn: beforeStart, now: now, calendar: calendar))
        #expect(!CalendarActivityManager.isHabit(habit, trackedOn: future, now: now, calendar: calendar))
        #expect(CalendarActivityManager.isHabit(habit, trackedOn: now, now: now, calendar: calendar))
    }

    @Test func trackingStylePickerOnlyOffersFullySupportedStyles() {
        #expect(
            HabitType.supportedCases == [
                .abstinence,
                .positiveStreak,
                .event,
                .sinceDate,
                .countdown
            ]
        )
        #expect(!HabitType.supportedCases.contains(.frequency))
        #expect(!HabitType.supportedCases.contains(.count))
        #expect(!HabitType.supportedCases.contains(.duration))
    }

    @Test func dailyHabitStreakCountsCurrentBestAndUniqueDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 12))!
        let habit = Habit(name: "Read", type: .positiveStreak, startAt: start)

        for day in [20, 21, 27, 28, 29, 30, 30] {
            let occurredAt = calendar.date(
                from: DateComponents(year: 2026, month: 7, day: day, hour: day == 30 ? 9 : 12)
            )!
            habit.events.append(
                HabitEvent(kind: .completed, occurredAt: occurredAt, habit: habit)
            )
        }

        let streak = HabitTrackingManager.dailyStreak(
            for: habit,
            now: now,
            calendar: calendar
        )

        #expect(streak.current == 4)
        #expect(streak.best == 4)
        #expect(streak.totalCompletions == 6)
    }

    @Test func dailyHabitCurrentStreakContinuesThroughYesterday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 12))!
        let habit = Habit(name: "Journal", type: .positiveStreak, startAt: start)

        for day in [28, 29] {
            let occurredAt = calendar.date(
                from: DateComponents(year: 2026, month: 7, day: day, hour: 8)
            )!
            habit.events.append(
                HabitEvent(kind: .completed, occurredAt: occurredAt, habit: habit)
            )
        }

        let streak = HabitTrackingManager.dailyStreak(
            for: habit,
            now: now,
            calendar: calendar
        )

        #expect(streak.current == 2)
        #expect(streak.best == 2)
    }

    @Test func lastTimeTrackingUsesTheNewestLoggedOccurrence() {
        let start = Date(timeIntervalSince1970: 1_000)
        let habit = Habit(name: "Called home", type: .event, startAt: start)
        habit.events.append(
            HabitEvent(kind: .completed, occurredAt: Date(timeIntervalSince1970: 3_000), habit: habit)
        )
        habit.events.append(
            HabitEvent(kind: .slip, occurredAt: Date(timeIntervalSince1970: 5_000), habit: habit)
        )
        habit.events.append(
            HabitEvent(kind: .completed, occurredAt: Date(timeIntervalSince1970: 4_000), habit: habit)
        )

        #expect(HabitTrackingManager.latestOccurrence(for: habit) == Date(timeIntervalSince1970: 4_000))
    }

    @Test func calendarUsesTheMeaningOfEachTrackingStyle() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 12))!
        let tomorrow = calendar.date(from: DateComponents(year: 2026, month: 7, day: 31, hour: 12))!
        let yesterday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 29, hour: 12))!

        let daily = Habit(name: "Read", type: .positiveStreak, startAt: yesterday)
        daily.events.append(HabitEvent(kind: .completed, occurredAt: yesterday, habit: daily))

        let occurrence = Habit(name: "Water plants", type: .event, startAt: yesterday)
        occurrence.events.append(HabitEvent(kind: .started, occurredAt: yesterday, habit: occurrence))
        occurrence.events.append(HabitEvent(kind: .completed, occurredAt: today, habit: occurrence))

        let countdown = Habit(name: "Vacation", type: .countdown, startAt: tomorrow)

        #expect(CalendarActivityManager.isHabit(daily, trackedOn: yesterday, now: today, calendar: calendar))
        #expect(!CalendarActivityManager.isHabit(daily, trackedOn: today, now: today, calendar: calendar))
        #expect(CalendarActivityManager.isHabit(occurrence, trackedOn: today, now: today, calendar: calendar))
        #expect(CalendarActivityManager.isHabit(countdown, trackedOn: tomorrow, now: today, calendar: calendar))
        #expect(!CalendarActivityManager.isHabit(countdown, trackedOn: today, now: today, calendar: calendar))
    }

    @Test func insightsDeduplicatesDailyCompletionsAndExcludesTodayFromRate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 12))!
        let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 8))!
        let habit = Habit(name: "Read", type: .positiveStreak, startAt: start)

        for day in [24, 24, 26, 30] {
            let completion = calendar.date(
                from: DateComponents(year: 2026, month: 7, day: day, hour: 9)
            )!
            habit.events.append(HabitEvent(kind: .completed, occurredAt: completion, habit: habit))
        }

        let snapshot = InsightsEngine.makeSnapshot(
            habits: [habit],
            tasks: [],
            period: .sevenDays,
            now: now,
            calendar: calendar
        )

        #expect(snapshot.eligibleHabitDays == 6)
        #expect(snapshot.completedHabitDays == 2)
        #expect(snapshot.habitCompletionRate == Double(2) / Double(6))
        #expect(snapshot.activity.last?.habitLogs == 1)
    }

    @Test func insightsRequireThreeSlipsBeforeShowingTimingPatterns() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 31, hour: 12))!
        let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        let habit = Habit(name: "No alcohol", startAt: start)

        for day in [10, 17] {
            let occurredAt = calendar.date(
                from: DateComponents(year: 2026, month: 7, day: day, hour: 19)
            )!
            habit.events.append(
                HabitEvent(kind: .slip, occurredAt: occurredAt, restartsStreak: true, habit: habit)
            )
        }

        let belowThreshold = InsightsEngine.makeSnapshot(
            habits: [habit],
            tasks: [],
            period: .thirtyDays,
            now: now,
            calendar: calendar
        )
        #expect(!belowThreshold.patterns.contains { $0.id == "slip-weekday" })
        #expect(!belowThreshold.patterns.contains { $0.id == "slip-time" })

        let thirdSlip = calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 24, hour: 19)
        )!
        habit.events.append(
            HabitEvent(kind: .slip, occurredAt: thirdSlip, restartsStreak: true, habit: habit)
        )

        let qualified = InsightsEngine.makeSnapshot(
            habits: [habit],
            tasks: [],
            period: .thirtyDays,
            now: now,
            calendar: calendar
        )
        #expect(qualified.patterns.contains { $0.id == "slip-weekday" && $0.detail.contains("Friday") })
        #expect(qualified.patterns.contains { $0.id == "slip-time" && $0.detail.contains("Evening") })
    }

    @Test func insightsPlannerRateExcludesTodayInboxWaitingAndFutureTasks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 12))!
        let yesterday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 29))!
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        let tasks = [
            PlannerTask(title: "Done", scheduledDay: yesterday, status: .completed),
            PlannerTask(title: "Open", scheduledDay: yesterday, status: .planned),
            PlannerTask(title: "Today", scheduledDay: today, status: .completed),
            PlannerTask(title: "Inbox", scheduledDay: yesterday, status: .inbox),
            PlannerTask(title: "Waiting", scheduledDay: yesterday, status: .waiting),
            PlannerTask(title: "Future", scheduledDay: tomorrow, status: .planned)
        ]

        let snapshot = InsightsEngine.makeSnapshot(
            habits: [],
            tasks: tasks,
            period: .sevenDays,
            now: now,
            calendar: calendar
        )

        #expect(snapshot.planner.scheduledTasks == 2)
        #expect(snapshot.planner.completedTasks == 1)
        #expect(snapshot.planner.completionRate == 0.5)
    }

    @Test func insightsCountRepeatingOccurrencesAsSeparateWorkSessions() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 12)))
        let start = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 2)))
        let secondCompletion = try #require(calendar.date(byAdding: .day, value: 2, to: start))
        let task = PlannerTask(
            title: "Daily review",
            scheduledDay: start,
            scheduleKind: .repeating,
            repeatFrequency: .daily
        )
        PlannerTaskManager.setCompletion(true, for: task, on: start, calendar: calendar)
        PlannerTaskManager.setCompletion(true, for: task, on: secondCompletion, calendar: calendar)

        let snapshot = InsightsEngine.makeSnapshot(
            habits: [],
            tasks: [task],
            period: .sevenDays,
            now: now,
            calendar: calendar
        )

        #expect(snapshot.planner.scheduledTasks == 3)
        #expect(snapshot.planner.completedTasks == 2)
        #expect(snapshot.planner.completionRate == Double(2) / Double(3))
    }

    @Test func insightsHabitFilterScopesEventsAndLinkedTasks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 12))!
        let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 18))!
        let first = Habit(name: "First", startAt: start)
        let second = Habit(name: "Second", startAt: start)
        first.events.append(HabitEvent(kind: .slip, occurredAt: eventDate, habit: first))
        second.events.append(HabitEvent(kind: .slip, occurredAt: eventDate, habit: second))

        let linked = PlannerTask(
            title: "Linked",
            scheduledDay: eventDate,
            status: .completed,
            habitID: first.id
        )
        let unrelated = PlannerTask(
            title: "Unrelated",
            scheduledDay: eventDate,
            status: .completed,
            habitID: second.id
        )

        let snapshot = InsightsEngine.makeSnapshot(
            habits: [first, second],
            tasks: [linked, unrelated],
            period: .thirtyDays,
            selectedHabitID: first.id,
            now: now,
            calendar: calendar
        )

        #expect(snapshot.habitSnapshots.count == 1)
        #expect(snapshot.habitSnapshots.first?.id == first.id)
        #expect(snapshot.slipCount == 1)
        #expect(snapshot.planner.scheduledTasks == 1)
        #expect(snapshot.planner.linkedTasks == 1)
    }

    @Test func allTimeInsightsDoNotInventPeriodComparisons() {
        let now = Date(timeIntervalSince1970: 100_000)
        let habit = Habit(name: "No alcohol", startAt: Date(timeIntervalSince1970: 1_000))
        let snapshot = InsightsEngine.makeSnapshot(
            habits: [habit],
            tasks: [],
            period: .allTime,
            now: now
        )

        #expect(snapshot.comparisons.isEmpty)
        #expect(snapshot.range.start <= habit.startAt)
    }

    @Test func healthGoalChangesKeepHistoricalTargets() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1, hour: 12))!
        let changeDay = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 12))!
        let habit = Habit(
            name: "Daily Steps",
            type: .positiveStreak,
            startAt: start,
            healthMetric: .steps,
            healthGoalValue: 8_000
        )

        HealthGoalManager.recordGoal(
            for: habit,
            target: 10_000,
            activeWeekdays: HealthGoalManager.everyDay,
            effectiveAt: changeDay,
            calendar: calendar
        )

        let beforeChange = calendar.date(from: DateComponents(year: 2026, month: 7, day: 10, hour: 12))!
        let afterChange = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 12))!

        #expect(HealthGoalManager.progress(for: habit, on: beforeChange, stepCount: 8_000, calendar: calendar)?.target == 8_000)
        #expect(HealthGoalManager.progress(for: habit, on: beforeChange, stepCount: 8_000, calendar: calendar)?.isReached == true)
        #expect(HealthGoalManager.progress(for: habit, on: afterChange, stepCount: 8_000, calendar: calendar)?.target == 10_000)
        #expect(HealthGoalManager.progress(for: habit, on: afterChange, stepCount: 8_000, calendar: calendar)?.isReached == false)
    }

    @Test func healthStreakSkipsUnscheduledWeekendDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 27, hour: 9))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 12))!
        let habit = Habit(
            name: "Workday Steps",
            type: .positiveStreak,
            startAt: start,
            healthMetric: .steps,
            healthGoalValue: 8_000,
            healthGoalWeekdays: [2, 3, 4, 5, 6]
        )
        var totals: [Date: Int] = [:]
        for day in 27...31 {
            let date = calendar.date(from: DateComponents(year: 2026, month: 7, day: day))!
            totals[date] = 9_000
        }

        let streak = HealthGoalManager.streak(
            for: habit,
            totals: totals,
            now: now,
            calendar: calendar
        )

        #expect(streak.current == 5)
        #expect(streak.best == 5)
        #expect(streak.totalCompletions == 5)
    }

    @Test func healthInsightsUseStepTotalsWithoutCreatingHabitEvents() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 30, hour: 12))!
        let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 20, hour: 9))!
        let habit = Habit(
            name: "Daily Steps",
            type: .positiveStreak,
            startAt: start,
            healthMetric: .steps,
            healthGoalValue: 8_000
        )
        let values = [24: 9_000, 25: 5_000, 26: 10_000, 27: 8_000, 29: 12_000, 30: 7_000]
        let totals = Dictionary(uniqueKeysWithValues: values.map { day, steps in
            (calendar.date(from: DateComponents(year: 2026, month: 7, day: day))!, steps)
        })

        let snapshot = InsightsEngine.makeSnapshot(
            habits: [habit],
            tasks: [],
            period: .sevenDays,
            selectedHabitID: habit.id,
            healthStepTotals: totals,
            now: now,
            calendar: calendar
        )
        let healthSnapshot = snapshot.habitSnapshots.first

        #expect(habit.events.isEmpty)
        #expect(snapshot.eligibleHabitDays == 6)
        #expect(snapshot.completedHabitDays == 4)
        #expect(healthSnapshot?.averageSteps == 8_500)
        #expect(healthSnapshot?.recordedStepDays == 6)
        #expect(healthSnapshot?.highestSteps == 12_000)
    }

    @Test func healthCalendarOnlyMarksScheduledDaysWithRecordedData() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 27))!
        let friday = calendar.date(from: DateComponents(year: 2026, month: 7, day: 31, hour: 12))!
        let saturday = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 12))!
        let habit = Habit(
            name: "Workday Steps",
            type: .positiveStreak,
            startAt: start,
            healthMetric: .steps,
            healthGoalValue: 8_000,
            healthGoalWeekdays: [2, 3, 4, 5, 6]
        )

        #expect(!CalendarActivityManager.isHabit(habit, trackedOn: friday, healthStepCount: nil, now: friday, calendar: calendar))
        #expect(CalendarActivityManager.isHabit(habit, trackedOn: friday, healthStepCount: 5_000, now: friday, calendar: calendar))
        #expect(!CalendarActivityManager.isHabit(habit, trackedOn: saturday, healthStepCount: 9_000, now: saturday, calendar: calendar))
    }

    @Test func backupPreservesHealthGoalConfigurationAndOlderFilesRemainReadable() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let habit = Habit(
            name: "Daily Steps",
            type: .positiveStreak,
            startAt: start,
            healthMetric: .steps,
            healthGoalValue: 9_000,
            healthGoalWeekdays: [2, 3, 4, 5, 6]
        )
        let archive = SinceBackupService.makeArchive(habits: [habit], plannerTasks: [])
        let data = try SinceBackupCoding.encoder.encode(archive)
        let decoded = try SinceBackupCoding.decoder.decode(SinceBackupArchive.self, from: data)

        #expect(decoded.habits.first?.healthMetricRawValue == HealthMetric.steps.rawValue)
        #expect(decoded.habits.first?.healthGoalValue == 9_000)
        #expect(decoded.habits.first?.healthGoalWeekdaysRawValue == "2,3,4,5,6")
        #expect(decoded.habits.first?.healthGoalHistoryData != nil)

        let legacyRecord = HabitBackupRecord(
            id: UUID(),
            name: "Legacy habit",
            habitDescription: "",
            typeRawValue: HabitType.abstinence.rawValue,
            tintRawValue: HabitTint.indigo.rawValue,
            symbolName: "leaf.fill",
            startAt: start,
            customMilestoneDays: nil,
            isPinned: true,
            isArchived: false,
            createdAt: start,
            updatedAt: start,
            events: []
        )
        let legacyArchive = SinceBackupArchive(
            version: 2,
            exportedAt: start,
            habits: [legacyRecord],
            plannerTasks: []
        )
        let legacyData = try SinceBackupCoding.encoder.encode(legacyArchive)
        let decodedLegacy = try SinceBackupCoding.decoder.decode(SinceBackupArchive.self, from: legacyData)

        #expect(decodedLegacy.habits.first?.healthMetricRawValue == nil)
        #expect(decodedLegacy.habits.first?.healthGoalValue == nil)
    }
}
