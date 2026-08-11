import Charts
import SwiftData
import SwiftUI

struct HabitDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @Query private var plannerTasks: [PlannerTask]
    @ScaledMetric(relativeTo: .largeTitle) private var streakFontSize: CGFloat = 64

    @Bindable var habit: Habit
    @State private var isPresentingSlip = false
    @State private var isPresentingEdit = false
    @State private var isConfirmingDelete = false
    @State private var slipBeingEdited: HabitEvent?
    @State private var measurementEventBeingEdited: HabitEvent?
    @State private var measurementEntryRequest: HabitMeasurementEntryRequest?
    @State private var eventPendingDeletion: HabitEvent?
    @State private var persistenceIssue: PersistenceIssue?
    @State private var showsAllHistory = false

    private let initialHistoryLimit = 30

    private var segments: [StreakSegment] {
        Array(StreakCalculator.segments(for: habit).reversed())
    }

    private var slips: [HabitEvent] {
        habit.events
            .filter { $0.kind == .slip }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    private var completionEvents: [HabitEvent] {
        habit.events
            .filter { $0.kind == .completed }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    private var occurrenceEvents: [HabitEvent] {
        habit.events
            .filter { $0.kind == .started || $0.kind == .completed }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                trackingOverview
                    .padding(20)
                    .background(.background, in: RoundedRectangle(cornerRadius: 22))

                if habit.measurementDefinition != nil {
                    measurementSummarySection
                }

                styleHistory

                if habit.isHealthPowered {
                    healthDataSourceSection
                }

                if !habit.habitDescription.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your intention")
                            .font(.headline)
                        Text(habit.habitDescription)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(habit.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPresentingSlip) {
            SlipResetView(habit: habit)
        }
        .sheet(isPresented: $isPresentingEdit) {
            EditHabitView(habit: habit)
        }
        .sheet(item: $slipBeingEdited) { event in
            EditSlipView(event: event, habit: habit)
        }
        .sheet(item: $measurementEventBeingEdited) { event in
            EventMeasurementEditorView(event: event, habit: habit)
        }
        .sheet(item: $measurementEntryRequest) { request in
            HabitMeasurementEntryView(request: request) { value in
                saveMeasuredHabitEntry(request, value: value)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                habitOptionsMenu
            }
        }
        .confirmationDialog(
            "Remove this history entry?",
            isPresented: Binding(
                get: { eventPendingDeletion != nil },
                set: { if !$0 { eventPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Entry", role: .destructive) {
                removePendingEvent()
            }
            Button("Cancel", role: .cancel) {
                eventPendingDeletion = nil
            }
        } message: {
            Text("Streaks and last-time calculations will update immediately.")
        }
        .alert("Delete \(habit.name)?", isPresented: $isConfirmingDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Habit", role: .destructive) {
                deleteHabit()
            }
            .accessibilityIdentifier("confirm-delete-habit-button")
        } message: {
            Text("This permanently removes the habit and its complete history. This cannot be undone.")
        }
        .persistenceIssueAlert($persistenceIssue)
        .task(id: habit.id) {
            showsAllHistory = false
            guard habit.isHealthPowered else { return }
            await healthKitManager.refreshRecentDays()
        }
    }

    @ViewBuilder
    private var trackingOverview: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            if habit.isHealthPowered {
                healthStepsOverview(now: context.date)
            } else {
                switch habit.type {
                case .abstinence:
                    abstinenceOverview(now: context.date)
                case .positiveStreak:
                    positiveStreakOverview(now: context.date)
                case .event:
                    lastOccurrenceOverview
                case .sinceDate:
                    sinceDateOverview(now: context.date)
                case .countdown:
                    countdownOverview
                case .frequency, .count, .duration:
                    abstinenceOverview(now: context.date)
                }
            }
        }
    }

    private func healthStepsOverview(now: Date) -> some View {
        let steps = healthKitManager.steps(on: now)
        let progress = HealthGoalManager.progress(for: habit, on: now, stepCount: steps)
        let streak = HealthGoalManager.streak(
            for: habit,
            totals: healthKitManager.stepTotals,
            now: now
        )

        return VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(steps?.formatted() ?? "—")
                    .font(.system(size: min(streakFontSize, 84), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("of \((progress?.target ?? Int(habit.healthGoalValue ?? 8_000)).formatted()) steps")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            if let progress {
                ProgressView(value: progress.fraction)
                    .tint(progress.isReached ? .teal : habit.tint.color)

                Text(healthProgressDescription(progress))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(progress.isReached ? Color.teal : Color.secondary)
            }

            HStack(spacing: 12) {
                metric(title: "Current", value: "\(streak.current) days")
                metric(title: "Best", value: "\(streak.best) days")
            }

            if healthKitManager.accessState == .notRequested {
                Button {
                    Task {
                        await healthKitManager.requestStepAccess()
                        await healthKitManager.refreshRecentDays()
                    }
                } label: {
                    Label("Connect Apple Health", systemImage: "heart.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(habit.tint.color)
            } else if steps == nil {
                Button {
                    Task { await healthKitManager.refreshRecentDays() }
                } label: {
                    Label(
                        healthKitManager.isRefreshing ? "Refreshing Steps" : "Refresh Steps",
                        systemImage: "arrow.clockwise"
                    )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(habit.tint.color)
                .disabled(healthKitManager.isRefreshing)
                .accessibilityHint("Updates recent daily step totals from Apple Health")
            }
        }
        .accessibilityIdentifier("health-steps-detail-overview")
    }

    private func abstinenceOverview(now: Date) -> some View {
        VStack(spacing: 16) {
            ExactTimeCounter(startAt: ElapsedTimeCalculator.currentStart(for: habit))

            Text("Since \(ElapsedTimeCalculator.currentStart(for: habit).formatted(date: .long, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                isPresentingSlip = true
            } label: {
                Label("Record a slip", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(habit.tint.color)

            HStack(spacing: 12) {
                metric(
                    title: "Current",
                    value: "\(ElapsedTimeCalculator.elapsed(for: habit, now: now).days) days"
                )
                metric(
                    title: "Best",
                    value: "\(StreakCalculator.personalBest(for: habit, now: now).days) days"
                )
            }
        }
    }

    private func positiveStreakOverview(now: Date) -> some View {
        let streak = HabitTrackingManager.dailyStreak(for: habit, now: now)
        let completedToday = HabitTrackingManager.isCompleted(habit, on: now)

        return VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("\(streak.current)")
                    .font(.system(size: min(streakFontSize, 84), weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text("day streak")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Button {
                toggleTodayCompletion()
            } label: {
                Label(
                    completedToday ? "Completed today" : "Mark today complete",
                    systemImage: completedToday ? "checkmark.circle.fill" : "circle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(completedToday ? .teal : habit.tint.color)
            .accessibilityHint(completedToday ? "Double tap to undo today’s completion" : "")

            HStack(spacing: 12) {
                metric(title: "Best", value: "\(streak.best) days")
                metric(title: "Total", value: "\(streak.totalCompletions)")
            }
        }
    }

    private var lastOccurrenceOverview: some View {
        let lastOccurrence = HabitTrackingManager.latestOccurrence(for: habit)

        return VStack(spacing: 16) {
            ExactTimeCounter(startAt: lastOccurrence)

            Text("Since \(lastOccurrence.formatted(date: .long, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                logOccurrenceNow()
            } label: {
                Label("Log it happened now", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(habit.tint.color)
        }
    }

    private func sinceDateOverview(now: Date) -> some View {
        VStack(spacing: 16) {
            ExactTimeCounter(startAt: habit.startAt)
            Text("Since \(habit.startAt.formatted(date: .long, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            metric(
                title: "Total elapsed",
                value: "\(ElapsedTime(from: habit.startAt, to: now).days) days"
            )
        }
    }

    private var countdownOverview: some View {
        VStack(spacing: 16) {
            ExactCountdownCounter(targetAt: habit.startAt)
            Text("Until \(habit.startAt.formatted(date: .long, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var styleHistory: some View {
        if habit.isHealthPowered {
            healthStepsHistory
        } else {
            switch habit.type {
            case .abstinence, .frequency, .count, .duration:
                abstinenceHistory
            case .positiveStreak:
                eventHistorySection(
                    title: "Completion history",
                    emptyMessage: "Completed days will appear here.",
                    events: completionEvents,
                    initialEventLabel: ""
                )
            case .event:
                eventHistorySection(
                    title: "Occurrence history",
                    emptyMessage: "Logged occurrences will appear here.",
                    events: occurrenceEvents,
                    initialEventLabel: "Initial occurrence"
                )
            case .sinceDate:
                staticDateSection(
                    title: "Meaningful moment",
                    symbol: "heart.fill",
                    date: habit.startAt
                )
            case .countdown:
                staticDateSection(
                    title: habit.startAt > .now ? "Looking forward to" : "Date reached",
                    symbol: "calendar.badge.clock",
                    date: habit.startAt
                )
            }
        }
    }

    private var healthStepsHistory: some View {
        let days = healthHistoryDays

        return VStack(alignment: .leading, spacing: 14) {
            Text("Last 7 days")
                .font(.headline)

            Chart(days, id: \.date) { item in
                BarMark(
                    x: .value("Day", item.date, unit: .day),
                    y: .value("Steps", item.steps)
                )
                .foregroundStyle(item.reached ? habit.tint.color : habit.tint.color.opacity(0.35))

                if item.target > 0 {
                    RuleMark(y: .value("Goal", item.target))
                        .foregroundStyle(.secondary.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .frame(height: 170)
            .accessibilityIdentifier("health-steps-seven-day-chart")
            .accessibilityLabel("Step history for the last seven days")
            .accessibilityValue(
                "\(days.filter(\.reached).count) of \(days.count) daily goals reached"
            )

            ForEach(days, id: \.date) { item in
                HStack {
                    Text(item.date.formatted(.dateTime.weekday(.abbreviated)))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(item.hasData ? "\(item.steps.formatted())" : "—")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                    Image(systemName: item.reached ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.reached ? habit.tint.color : Color.secondary)
                }
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var healthHistoryDays: [(date: Date, steps: Int, target: Int, reached: Bool, hasData: Bool)] {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: .now)
        return (0..<7).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let steps = healthKitManager.steps(on: date)
            let progress = HealthGoalManager.progress(for: habit, on: date, stepCount: steps, calendar: calendar)
            return (date, steps ?? 0, progress?.target ?? 0, progress?.isReached == true, steps != nil)
        }
    }

    private var healthDataSourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Data source")
                .font(.headline)
            Label("Apple Health", systemImage: "heart.fill")
                .foregroundStyle(habit.tint.color)
            Text("Since reads daily totals. Your individual step samples stay in Apple Health.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func healthProgressDescription(_ progress: HealthGoalProgress) -> String {
        if !progress.isScheduled { return "Rest day" }
        if progress.isReached { return "Goal reached" }
        if progress.value == nil { return "No step data available" }
        return "\(progress.remaining.formatted()) remaining"
    }

    private var abstinenceHistory: some View {
        let allSegments = segments
        let allSlips = slips
        let visibleSegments = showsAllHistory
            ? allSegments
            : Array(allSegments.prefix(initialHistoryLimit))
        let visibleSlips = showsAllHistory
            ? allSlips
            : Array(allSlips.prefix(initialHistoryLimit))
        let hasMoreHistory = allSegments.count > initialHistoryLimit
            || allSlips.count > initialHistoryLimit

        return VStack(spacing: 22) {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text("Streak history")
                    .font(.headline)

                ForEach(visibleSegments) { segment in
                    StreakSegmentRow(segment: segment, tint: habit.tint.color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !allSlips.isEmpty {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text("Recorded slips")
                        .font(.headline)

                    ForEach(visibleSlips) { event in
                        Button {
                            slipBeingEdited = event
                        } label: {
                            SlipHistoryRow(event: event)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens this slip for editing")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if hasMoreHistory {
                historyExpansionButton
            }
        }
    }

    private func eventHistorySection(
        title: String,
        emptyMessage: String,
        events: [HabitEvent],
        initialEventLabel: String
    ) -> some View {
        let visibleEvents = showsAllHistory
            ? events
            : Array(events.prefix(initialHistoryLimit))

        return LazyVStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            if events.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 16))
            } else {
                ForEach(visibleEvents) { event in
                    TrackingHistoryRow(
                        event: event,
                        title: event.kind == .started
                            ? initialEventLabel
                            : HabitTrackingManager.activityTitle(for: event),
                        tint: habit.tint.color,
                        canDelete: event.kind != .started,
                        onEdit: event.kind != .started && (event.measurementDefinition != nil || habit.measurementDefinition != nil)
                            ? { measurementEventBeingEdited = event }
                            : nil,
                        onDelete: { eventPendingDeletion = event }
                    )
                }

                if events.count > initialHistoryLimit {
                    historyExpansionButton
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var historyExpansionButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                showsAllHistory.toggle()
            }
        } label: {
            Label(
                showsAllHistory ? "Show Less" : "Show All History",
                systemImage: showsAllHistory ? "chevron.up" : "chevron.down"
            )
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("habit-history-toggle")
        .accessibilityHint(
            showsAllHistory
                ? "Shows only the 30 most recent entries"
                : "Shows the complete history"
        )
    }

    private func staticDateSection(title: String, symbol: String, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Label(date.formatted(date: .complete, time: .shortened), systemImage: symbol)
                .foregroundStyle(habit.tint.color)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background, in: RoundedRectangle(cornerRadius: 16))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var habitOptionsMenu: some View {
        Menu {
            Button {
                isPresentingEdit = true
            } label: {
                Label("Edit Habit", systemImage: "pencil")
            }
            .accessibilityIdentifier("edit-habit-menu-button")

            if !habit.isPinned && !habit.isArchived {
                Button {
                    makePrimary()
                } label: {
                    Label("Make Primary", systemImage: "pin.fill")
                }
            }

            Button {
                toggleArchive()
            } label: {
                Label(
                    habit.isArchived ? "Restore Habit" : "Archive Habit",
                    systemImage: habit.isArchived ? "arrow.uturn.backward" : "archivebox"
                )
            }

            Divider()

            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Delete Habit", systemImage: "trash")
            }
            .accessibilityIdentifier("delete-habit-menu-button")
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Habit options")
    }

    private var measurementSummarySection: some View {
        let definition = habit.measurementDefinition
        let statistics = HabitMeasurementManager.statistics(for: habit)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: definition?.symbolName ?? "number.circle")
                    .foregroundStyle(habit.tint.color)
                    .frame(width: 34, height: 34)
                    .background(habit.tint.color.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(definition?.name ?? "Measurement")
                        .font(.headline)
                    Text("Measured entries stay separate from your streak count")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let statistics {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 10
                ) {
                    metric(title: "Total", value: statistics.definition.compactFormatted(statistics.total))
                    metric(title: "Average", value: statistics.definition.compactFormatted(statistics.average))
                    metric(title: "Largest", value: statistics.definition.compactFormatted(statistics.maximum))
                    metric(title: "Recorded", value: "\(statistics.measuredCount) entries")
                }

                if statistics.missingCount > 0 {
                    Text("\(statistics.missingCount) older \(statistics.missingCount == 1 ? "entry has" : "entries have") no amount and is excluded from totals.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No measured entries yet. New entries can include an optional amount.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("habit-measurement-summary")
    }

    private func metric(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }

    private func toggleTodayCompletion() {
        guard !habit.isHealthPowered else { return }
        let events = HabitTrackingManager.completionEvents(for: habit, on: .now)
        if events.isEmpty {
            if habit.measurementDefinition != nil {
                measurementEntryRequest = HabitMeasurementEntryRequest(
                    habit: habit,
                    purpose: .completion
                )
                return
            }
            addCompletionEvent(measurementValue: nil)
        } else {
            events.forEach(modelContext.delete)
        }
        habit.updatedAt = .now
        saveChanges(title: "Completion Could Not Be Saved")
    }

    private func logOccurrenceNow() {
        if habit.measurementDefinition != nil {
            measurementEntryRequest = HabitMeasurementEntryRequest(
                habit: habit,
                purpose: .occurrence
            )
            return
        }
        addCompletionEvent(measurementValue: nil)
        habit.updatedAt = .now
        saveChanges(title: "Occurrence Could Not Be Saved")
    }

    private func saveMeasuredHabitEntry(
        _ request: HabitMeasurementEntryRequest,
        value: Double
    ) {
        addCompletionEvent(measurementValue: value)
        habit.updatedAt = .now
        saveChanges(
            title: request.purpose == .completion
                ? "Completion Could Not Be Saved"
                : "Occurrence Could Not Be Saved"
        )
    }

    private func addCompletionEvent(measurementValue: Double?) {
        let event = HabitEvent(kind: .completed, occurredAt: .now, habit: habit)
        HabitMeasurementManager.apply(
            value: measurementValue,
            definition: habit.measurementDefinition,
            to: event
        )
        habit.events.append(event)
        modelContext.insert(event)
    }

    private func removePendingEvent() {
        guard let event = eventPendingDeletion, event.kind != .started else { return }
        modelContext.delete(event)
        eventPendingDeletion = nil
        habit.updatedAt = .now
        saveChanges(title: "History Entry Could Not Be Removed")
    }

    private func saveChanges(title: String) {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            persistenceIssue = PersistenceIssue(title: title, error: error)
        }
    }

    private func makePrimary() {
        do {
            let habits = try modelContext.fetch(FetchDescriptor<Habit>())
            HabitManager.makePrimary(habit, among: habits)
            habit.updatedAt = .now
            try modelContext.save()
        } catch {
            modelContext.rollback()
            persistenceIssue = PersistenceIssue(error: error)
        }
    }

    private func toggleArchive() {
        do {
            let habits = try modelContext.fetch(FetchDescriptor<Habit>())
            if habit.isArchived {
                HabitManager.restore(habit, among: habits)
            } else {
                HabitManager.archive(habit, among: habits)
            }
            habit.updatedAt = .now
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            persistenceIssue = PersistenceIssue(error: error)
        }
    }

    private func deleteHabit() {
        do {
            let habits = try modelContext.fetch(FetchDescriptor<Habit>())
            HabitManager.prepareForDeletion(habit, among: habits)
            PlannerTaskManager.clearHabitConnection(habit.id, from: plannerTasks)
            modelContext.delete(habit)
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            persistenceIssue = PersistenceIssue(title: "Habit Could Not Be Deleted", error: error)
        }
    }
}

private struct TrackingHistoryRow: View {
    let event: HabitEvent
    let title: String
    let tint: Color
    let canDelete: Bool
    let onEdit: (() -> Void)?
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.kind == .started ? "flag.fill" : "checkmark.circle.fill")
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let measurement = event.formattedMeasurement {
                    Text(measurement)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                }
            }

            Spacer()

            if canDelete {
                Menu {
                    Button(role: .destructive, action: onDelete) {
                        Label("Remove Entry", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Options for \(title)")
            }

            if onEdit != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture { onEdit?() }
        .accessibilityAction(named: "Edit entry") { onEdit?() }
    }
}

private struct SlipHistoryRow: View {
    let event: HabitEvent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.counterclockwise")
                .foregroundStyle(.orange)
                .frame(width: 34, height: 34)
                .background(.orange.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline.weight(.semibold))
                Text(event.restartsStreak ? "Started a new streak" : "History only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let measurement = event.formattedMeasurement {
                    Text(measurement)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                if !event.note.isEmpty {
                    Text(event.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var details = [
            "Slip recorded",
            event.occurredAt.formatted(date: .abbreviated, time: .shortened),
            event.restartsStreak ? "Started a new streak" : "History only"
        ]
        if let measurement = event.formattedMeasurement {
            details.append(measurement)
        }
        if !event.note.isEmpty {
            details.append(event.note)
        }
        return details.joined(separator: ", ")
    }
}

private struct StreakSegmentRow: View {
    let segment: StreakSegment
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Capsule()
                .fill(segment.endedAt == nil ? tint : Color.secondary.opacity(0.25))
                .frame(width: 5, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(segment.endedAt == nil ? "Current chapter" : "\(segment.elapsed().days) days")
                    .font(.subheadline.weight(.semibold))
                Text(dateRange)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let endReason = segment.endReason {
                Text(endReason == .slip ? "Slip" : "Restart")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dateRange: String {
        let start = segment.startedAt.formatted(date: .abbreviated, time: .omitted)
        if let endedAt = segment.endedAt {
            return "\(start) – \(endedAt.formatted(date: .abbreviated, time: .omitted))"
        }
        return "\(start) – Present"
    }
}
