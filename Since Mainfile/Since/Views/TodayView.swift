import SwiftData
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var plannerTasks: [PlannerTask]

    @Binding var isPresentingNewHabit: Bool
    @State private var selectedDay = PlannerTaskManager.startOfDay(.now)
    @State private var slipHabit: Habit?
    @State private var measurementEntryRequest: HabitMeasurementEntryRequest?
    @State private var editingTask: PlannerTask?
    @State private var isPresentingNewTask = false
    @State private var taskPendingDeletion: PlannerTask?
    @State private var recentlyDeletedTask: PlannerTaskSnapshot?
    @State private var persistenceErrorMessage = ""
    @State private var isShowingPersistenceError = false
    @State private var selectedHabitID: UUID?
    @State private var detailHabit: Habit?
    @State private var isShowingCompletedTasks = false
    @State private var isPresentingDayView = false

    private var orderedActiveHabits: [Habit] {
        HabitManager.orderedActive(habits)
    }

    private var primaryHabit: Habit? {
        orderedActiveHabits.first
    }

    private var selectedHabit: Habit? {
        orderedActiveHabits.first(where: { $0.id == selectedHabitID }) ?? primaryHabit
    }

    private var selectedTasks: [PlannerTask] {
        PlannerTaskManager.tasks(on: selectedDay, from: plannerTasks)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if primaryHabit != nil {
                    habitCarousel
                } else {
                    habitEmptyCard
                }

                plannerSection

                if !orderedActiveHabits.isEmpty {
                    RecentActivityView(habits: orderedActiveHabits)
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        isPresentingNewTask = true
                    } label: {
                        Label("New task", systemImage: "checkmark.circle")
                    }

                    Button {
                        isPresentingNewHabit = true
                    } label: {
                        Label("New habit", systemImage: "hourglass")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("today-add-menu")
                .accessibilityLabel("Add")
            }
        }
        .sheet(item: $slipHabit) { habit in
            SlipResetView(habit: habit)
        }
        .sheet(item: $measurementEntryRequest) { request in
            HabitMeasurementEntryView(request: request) { value in
                saveMeasuredHabitEntry(request, value: value)
            }
        }
        .sheet(isPresented: $isPresentingNewTask) {
            PlannerTaskEditorView(scheduledDay: selectedDay)
        }
        .sheet(item: $editingTask) { task in
            PlannerTaskEditorView(task: task, scheduledDay: task.scheduledDay)
        }
        .sheet(isPresented: $isPresentingDayView) {
            CalendarDayDetailView(initialDate: selectedDay, habitIDs: nil)
        }
        .navigationDestination(
            isPresented: Binding(
                get: { detailHabit != nil },
                set: { if !$0 { detailHabit = nil } }
            )
        ) {
            if let detailHabit {
                HabitDetailView(habit: detailHabit)
            }
        }
        .confirmationDialog(
            "Delete this task?",
            isPresented: Binding(
                get: { taskPendingDeletion != nil },
                set: { if !$0 { taskPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Task", role: .destructive) {
                deletePendingTask()
            }
            .accessibilityIdentifier("confirm-delete-planner-task-button")
            Button("Cancel", role: .cancel) {
                taskPendingDeletion = nil
            }
        } message: {
            Text("This removes the task from your plan. It will not affect any habit streak.")
        }
        .safeAreaInset(edge: .bottom) {
            if recentlyDeletedTask != nil {
                HStack {
                    Text("Task deleted")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Undo") {
                        undoTaskDeletion()
                    }
                    .font(.subheadline.weight(.bold))
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
                .background(.regularMaterial, in: Capsule())
                .padding(.horizontal)
                .padding(.bottom, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .alert("Changes Could Not Be Saved", isPresented: $isShowingPersistenceError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(persistenceErrorMessage)
        }
        .onAppear {
            selectedDay = PlannerTaskManager.startOfDay(.now)
            selectPriorityHabitIfNeeded()
        }
        .onChange(of: orderedActiveHabits.map(\.id)) {
            selectPriorityHabitIfNeeded()
        }
        .task {
            await refreshHealthDataIfNeeded()
        }
        .refreshable {
            await refreshHealthDataIfNeeded(forceAuthorization: false)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            selectedDay = PlannerTaskManager.startOfDay(.now)
            Task { await refreshHealthDataIfNeeded() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            selectedDay = PlannerTaskManager.startOfDay(.now)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            selectedDay = PlannerTaskManager.startOfDay(.now)
        }
    }

    private var habitCarousel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if let primaryHabit, selectedHabitID == primaryHabit.id {
                    Label("Priority habit", systemImage: "pin.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(primaryHabit.tint.color)
                } else {
                    Text("Active habit")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if orderedActiveHabits.count > 1,
                   let selectedHabitID,
                   let index = orderedActiveHabits.firstIndex(where: { $0.id == selectedHabitID }) {
                    Text("\(index + 1) of \(orderedActiveHabits.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(orderedActiveHabits) { habit in
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            HabitHeroCard(
                                habit: habit,
                                now: context.date,
                                healthStepTotals: healthKitManager.stepTotals,
                                healthAccessState: healthKitManager.accessState,
                                healthLastUpdated: healthKitManager.lastUpdated,
                                openDetails: { detailHabit = habit },
                                performPrimaryAction: {
                                    if habit.isHealthPowered {
                                        Task { await handleHealthAction() }
                                    } else {
                                        performPrimaryHabitAction(habit)
                                    }
                                }
                            )
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 1)
                        .containerRelativeFrame(.horizontal)
                        .id(habit.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selectedHabitID)

            if orderedActiveHabits.count > 1 {
                if orderedActiveHabits.count <= 6 {
                    habitPageDots
                } else {
                    compactHabitPager
                }
            }
        }
    }

    private var habitPageDots: some View {
        HStack(spacing: 8) {
            ForEach(orderedActiveHabits) { habit in
                Button {
                    selectHabit(habit)
                } label: {
                    Circle()
                        .fill(selectedHabitID == habit.id ? habit.tint.color : Color.secondary.opacity(0.25))
                        .frame(width: selectedHabitID == habit.id ? 9 : 7, height: selectedHabitID == habit.id ? 9 : 7)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(habit.name)")
                .accessibilityAddTraits(selectedHabitID == habit.id ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var compactHabitPager: some View {
        let index = orderedActiveHabits.firstIndex { $0.id == selectedHabitID } ?? 0

        return HStack(spacing: 12) {
            Button {
                selectHabit(orderedActiveHabits[max(0, index - 1)])
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(index == 0)
            .accessibilityLabel("Previous habit")

            Text("\(index + 1) of \(orderedActiveHabits.count)")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 62)

            Button {
                selectHabit(orderedActiveHabits[min(orderedActiveHabits.count - 1, index + 1)])
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(index == orderedActiveHabits.count - 1)
            .accessibilityLabel("Next habit")
        }
        .frame(maxWidth: .infinity)
    }

    private func selectHabit(_ habit: Habit) {
        withAnimation(SinceMotion.standard(reduceMotion: reduceMotion)) {
            selectedHabitID = habit.id
        }
    }

    private var habitEmptyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Start your first timeline", systemImage: "hourglass")
                .font(.headline)
            Text("Track exact time since something changed. Your planner works with or without a habit.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Create a habit") {
                isPresentingNewHabit = true
            }
            .accessibilityIdentifier("empty-create-habit-button")
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sinceCardSurface(radius: 20)
    }

    private var plannerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(planSectionTitle)
                        .font(.headline)
                    plannerProgressLabel
                }

                Spacer()

                Button {
                    isPresentingDayView = true
                } label: {
                    Image(systemName: "calendar.day.timeline.left")
                        .frame(width: 44, height: 44)
                        .background(.indigo.opacity(0.10), in: Circle())
                }
                .accessibilityLabel("Open today in calendar")

                Button {
                    isPresentingNewTask = true
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 44, height: 44)
                        .background(.indigo.opacity(0.12), in: Circle())
                }
                .accessibilityIdentifier("add-planner-task-button")
                .accessibilityLabel("Add a task")
            }

            if selectedTasks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Plan something kind and manageable.")
                        .font(.subheadline.weight(.semibold))
                    Text("Tasks can stand alone or support one of your habits.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Add your first task") {
                        isPresentingNewTask = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.indigo)
                    .padding(.top, 4)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .sinceCardSurface()
            } else {
                PlannerTaskGroup(
                    title: "Focus",
                    symbolName: "scope",
                    tasks: focusTasks,
                    date: selectedDay,
                    habits: habits,
                    onToggle: toggleCompletion,
                    onEdit: { editingTask = $0 },
                    onMove: moveTask,
                    onDelete: { taskPendingDeletion = $0 }
                )

                PlannerTaskGroup(
                    title: "Anytime",
                    symbolName: "circle.dotted",
                    tasks: tasks(in: nil, from: regularIncompleteTasks),
                    date: selectedDay,
                    habits: habits,
                    onToggle: toggleCompletion,
                    onEdit: { editingTask = $0 },
                    onMove: moveTask,
                    onDelete: { taskPendingDeletion = $0 }
                )

                ForEach(PlannerDaySection.allCases) { section in
                    PlannerTaskGroup(
                        title: section.title,
                        symbolName: section.symbolName,
                        tasks: tasks(in: section, from: regularIncompleteTasks),
                        date: selectedDay,
                        habits: habits,
                        onToggle: toggleCompletion,
                        onEdit: { editingTask = $0 },
                        onMove: moveTask,
                        onDelete: { taskPendingDeletion = $0 }
                    )
                }

                if !completedTasks.isEmpty {
                    DisclosureGroup(isExpanded: $isShowingCompletedTasks) {
                        PlannerTaskGroup(
                            title: "Done",
                            symbolName: "checkmark.circle.fill",
                            tasks: completedTasks,
                            date: selectedDay,
                            habits: habits,
                            onToggle: toggleCompletion,
                            onEdit: { editingTask = $0 },
                            onMove: moveTask,
                            onDelete: { taskPendingDeletion = $0 }
                        )
                        .padding(.top, 8)
                    } label: {
                        Label("Completed \(completedTasks.count)", systemImage: "checkmark.circle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var plannerProgressLabel: some View {
        let progress = PlannerTaskManager.progress(
            for: PlannerTaskManager.dayTasks(on: selectedDay, from: plannerTasks)
        )
        if progress.total > 0 {
            Text("\(progress.completed) of \(progress.total) completed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("planner-progress-label")
        }
    }

    private var planSectionTitle: String {
        "Today’s plan"
    }

    private var focusTasks: [PlannerTask] {
        selectedTasks.filter {
            !PlannerTaskManager.isCompleted($0, on: selectedDay)
                && ($0.status == .inProgress || $0.priority == .important)
        }
    }

    private var regularIncompleteTasks: [PlannerTask] {
        selectedTasks.filter { task in
            !PlannerTaskManager.isCompleted(task, on: selectedDay)
                && !focusTasks.contains(where: { $0.id == task.id })
        }
    }

    private var completedTasks: [PlannerTask] {
        selectedTasks.filter { PlannerTaskManager.isCompleted($0, on: selectedDay) }
    }

    private func tasks(in section: PlannerDaySection?, from source: [PlannerTask]) -> [PlannerTask] {
        source.filter { task in
            let session = PlannerTaskManager.session(for: task, on: selectedDay)
            if let section {
                return session?.timeMode == .daySection && session?.daySection == section
            }
            return session?.timeMode != .daySection
        }
    }

    private func toggleCompletion(_ task: PlannerTask) {
        withAnimation(SinceMotion.standard(reduceMotion: reduceMotion)) {
            PlannerTaskManager.setCompletion(
                !PlannerTaskManager.isCompleted(task, on: selectedDay),
                for: task,
                on: selectedDay
            )
        }
        if saveChanges() { playSuccessFeedback() }
    }

    private func selectPriorityHabitIfNeeded() {
        guard let primaryHabit else {
            selectedHabitID = nil
            return
        }

        if selectedHabitID == nil
            || !orderedActiveHabits.contains(where: { $0.id == selectedHabitID }) {
            selectedHabitID = primaryHabit.id
        }
    }

    private func performPrimaryHabitAction(_ habit: Habit) {
        guard !habit.isHealthPowered else { return }
        switch habit.type {
        case .abstinence:
            slipHabit = habit
            return
        case .positiveStreak:
            let todayEvents = HabitTrackingManager.completionEvents(for: habit, on: .now)
            if todayEvents.isEmpty {
                if habit.measurementDefinition != nil {
                    measurementEntryRequest = HabitMeasurementEntryRequest(
                        habit: habit,
                        purpose: .completion
                    )
                    return
                }
                addCompletionEvent(to: habit)
            } else {
                todayEvents.forEach(modelContext.delete)
            }
        case .event:
            if habit.measurementDefinition != nil {
                measurementEntryRequest = HabitMeasurementEntryRequest(
                    habit: habit,
                    purpose: .occurrence
                )
                return
            }
            addCompletionEvent(to: habit)
        case .sinceDate, .countdown:
            return
        case .frequency, .count, .duration:
            slipHabit = habit
            return
        }

        habit.updatedAt = .now
        if saveChanges() { playSuccessFeedback() }
    }

    private func saveMeasuredHabitEntry(
        _ request: HabitMeasurementEntryRequest,
        value: Double
    ) {
        addCompletionEvent(to: request.habit, measurementValue: value)
        request.habit.updatedAt = .now
        if saveChanges() { playSuccessFeedback() }
    }

    private func addCompletionEvent(to habit: Habit, measurementValue: Double? = nil) {
        let event = HabitEvent(kind: .completed, occurredAt: .now, habit: habit)
        HabitMeasurementManager.apply(
            value: measurementValue,
            definition: habit.measurementDefinition,
            to: event
        )
        habit.events.append(event)
        modelContext.insert(event)
    }

    private func handleHealthAction() async {
        if !healthKitManager.hasRequestedAccess {
            await healthKitManager.requestStepAccess()
        }
        await healthKitManager.refreshRecentDays()
    }

    private func refreshHealthDataIfNeeded(forceAuthorization: Bool = false) async {
        guard orderedActiveHabits.contains(where: \.isHealthPowered) else { return }
        if forceAuthorization && !healthKitManager.hasRequestedAccess {
            await healthKitManager.requestStepAccess()
        }
        await healthKitManager.refreshRecentDays()
    }

    private func moveTask(_ task: PlannerTask, _ offset: Int) {
        let peers = selectedTasks.filter { candidate in
            let taskSession = PlannerTaskManager.session(for: task, on: selectedDay)
            let candidateSession = PlannerTaskManager.session(for: candidate, on: selectedDay)
            if taskSession?.timeMode == .daySection {
                return candidateSession?.timeMode == .daySection
                    && candidateSession?.daySection == taskSession?.daySection
            }
            return candidateSession?.timeMode != .daySection
        }
        PlannerTaskManager.move(task, by: offset, among: peers)
        saveChanges()
    }

    private func deletePendingTask() {
        guard let taskPendingDeletion else { return }
        let snapshot = PlannerTaskSnapshot(task: taskPendingDeletion)
        modelContext.delete(taskPendingDeletion)
        self.taskPendingDeletion = nil

        do {
            try modelContext.save()
            withAnimation(SinceMotion.standard(reduceMotion: reduceMotion)) {
                recentlyDeletedTask = snapshot
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                guard recentlyDeletedTask?.id == snapshot.id else { return }
                withAnimation(SinceMotion.standard(reduceMotion: reduceMotion)) {
                    recentlyDeletedTask = nil
                }
            }
        } catch {
            modelContext.rollback()
            showPersistenceError(error)
        }
    }

    private func undoTaskDeletion() {
        guard let snapshot = recentlyDeletedTask else { return }
        let restoredTask = snapshot.makeTask()
        modelContext.insert(restoredTask)

        do {
            try modelContext.save()
            withAnimation(SinceMotion.standard(reduceMotion: reduceMotion)) {
                recentlyDeletedTask = nil
            }
        } catch {
            modelContext.rollback()
            showPersistenceError(error)
        }
    }

    @discardableResult
    private func saveChanges() -> Bool {
        do {
            try modelContext.save()
            return true
        } catch {
            modelContext.rollback()
            showPersistenceError(error)
            return false
        }
    }

    private func playSuccessFeedback() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    private func showPersistenceError(_ error: Error) {
        persistenceErrorMessage = error.localizedDescription
        isShowingPersistenceError = true
    }
}

private struct PlannerTaskGroup: View {
    let title: String
    let symbolName: String
    let tasks: [PlannerTask]
    let date: Date
    let habits: [Habit]
    let onToggle: (PlannerTask) -> Void
    let onEdit: (PlannerTask) -> Void
    let onMove: (PlannerTask, Int) -> Void
    let onDelete: (PlannerTask) -> Void

    var body: some View {
        if !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Label(title, systemImage: symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 6)

                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    PlannerTaskRow(
                        task: task,
                        date: date,
                        habit: habits.first(where: { $0.id == task.habitID }),
                        canMoveEarlier: PlannerTaskManager.session(for: task, on: date)?.timeMode != .exactTime && index > 0,
                        canMoveLater: PlannerTaskManager.session(for: task, on: date)?.timeMode != .exactTime && index < tasks.count - 1,
                        onToggle: { onToggle(task) },
                        onEdit: { onEdit(task) },
                        onMoveEarlier: { onMove(task, -1) },
                        onMoveLater: { onMove(task, 1) },
                        onDelete: { onDelete(task) }
                    )
                    .contextMenu {
                        Button {
                            onEdit(task)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

                        Button {
                            onMove(task, -1)
                        } label: {
                            Label("Move earlier", systemImage: "arrow.up")
                        }
                        .disabled(index == 0 || PlannerTaskManager.session(for: task, on: date)?.timeMode == .exactTime)

                        Button {
                            onMove(task, 1)
                        } label: {
                            Label("Move later", systemImage: "arrow.down")
                        }
                        .disabled(index == tasks.count - 1 || PlannerTaskManager.session(for: task, on: date)?.timeMode == .exactTime)

                        Button(role: .destructive) {
                            onDelete(task)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }

                    if index < tasks.count - 1 {
                        Divider()
                            .padding(.leading, 58)
                    }
                }
            }
            .sinceCardSurface()
        }
    }
}

private struct PlannerTaskRow: View {
    let task: PlannerTask
    let date: Date
    let habit: Habit?
    let canMoveEarlier: Bool
    let canMoveLater: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onMoveEarlier: () -> Void
    let onMoveLater: () -> Void
    let onDelete: () -> Void

    private var isCompleted: Bool {
        PlannerTaskManager.isCompleted(task, on: date)
    }

    private var session: PlannerWorkSession? {
        PlannerTaskManager.session(for: task, on: date)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isCompleted ? .teal : .secondary)
                    .frame(width: 44, height: 44)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("planner-task-toggle-\(task.id)")
            .accessibilityLabel(isCompleted ? "Mark \(task.title) incomplete" : "Complete \(task.title)")

            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(task.title)
                            .font(.body.weight(task.priority == .important ? .semibold : .regular))
                            .strikethrough(isCompleted)
                            .foregroundStyle(isCompleted ? .secondary : .primary)
                            .lineLimit(2)

                        if task.priority == .important {
                            Image(systemName: "flag.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .accessibilityLabel("Important")
                        }
                    }

                    AdaptiveFlowLayout(horizontalSpacing: 8, verticalSpacing: 4) {
                        if session?.timeMode == .exactTime, let time = session?.startTime {
                            Label(timeDescription(time), systemImage: "clock")
                        }

                        if task.status == .inProgress {
                            Label("In progress", systemImage: task.status.symbolName)
                                .foregroundStyle(.orange)
                        }

                        if task.priority != .normal {
                            Label(task.priority.title, systemImage: task.priority.symbolName)
                                .foregroundStyle(task.priority == .important ? .red : .orange)
                        }

                        if let dueDate = task.dueDate {
                            Label(
                                "Due \(dueDate.formatted(.dateTime.month(.abbreviated).day()))",
                                systemImage: "flag"
                            )
                        }

                        if let habit {
                            Label(habit.name, systemImage: habit.symbolName)
                                .foregroundStyle(habit.tint.color)
                        } else if task.habitID != nil {
                            Label("Habit removed", systemImage: "link.badge.plus")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if !task.taskNotes.isEmpty {
                        Text(task.taskNotes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.title)
            .accessibilityHint("Opens task details")

            Spacer(minLength: 0)

            Menu {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                Button(action: onMoveEarlier) {
                    Label("Move earlier", systemImage: "arrow.up")
                }
                .disabled(!canMoveEarlier)
                Button(action: onMoveLater) {
                    Label("Move later", systemImage: "arrow.down")
                }
                .disabled(!canMoveLater)
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Options for \(task.title)")
        }
        .padding(.horizontal, 8)
        .accessibilityAction(named: isCompleted ? "Mark incomplete" : "Complete") {
            onToggle()
        }
        .accessibilityAction(named: "Edit") {
            onEdit()
        }
        .accessibilityAction(named: "Move earlier") {
            if canMoveEarlier { onMoveEarlier() }
        }
        .accessibilityAction(named: "Move later") {
            if canMoveLater { onMoveLater() }
        }
        .accessibilityAction(named: "Delete") {
            onDelete()
        }
    }

    private func timeDescription(_ start: Date) -> String {
        guard let duration = session?.durationMinutes,
              let end = Calendar.current.date(byAdding: .minute, value: duration, to: start) else {
            return start.formatted(date: .omitted, time: .shortened)
        }
        return "\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
    }
}

private struct PlannerTaskSnapshot {
    let id: UUID
    let title: String
    let taskNotes: String
    let scheduledDay: Date
    let dueDate: Date?
    let dueTime: Date?
    let timeMode: PlannerTimeMode
    let scheduledTime: Date?
    let daySection: PlannerDaySection?
    let scheduleKind: PlannerScheduleKind
    let scheduleEndDate: Date?
    let scheduleWeekdays: Set<Int>
    let plannedDurationMinutes: Int?
    let customWorkSessionsData: Data?
    let repeatFrequency: PlannerRepeatFrequency
    let repeatInterval: Int
    let repeatEndMode: PlannerRepeatEndMode
    let repeatEndDate: Date?
    let repeatCount: Int?
    let completedOccurrenceDaysData: Data?
    let excludedOccurrenceDaysData: Data?
    let isCompleted: Bool
    let completedAt: Date?
    let position: Int
    let priority: PlannerTaskPriority
    let status: PlannerTaskStatus
    let habitID: UUID?
    let createdAt: Date
    let updatedAt: Date

    init(task: PlannerTask) {
        id = task.id
        title = task.title
        taskNotes = task.taskNotes
        scheduledDay = task.scheduledDay
        dueDate = task.dueDate
        dueTime = task.dueTime
        timeMode = task.timeMode
        scheduledTime = task.scheduledTime
        daySection = task.daySection
        scheduleKind = task.scheduleKind
        scheduleEndDate = task.scheduleEndDate
        scheduleWeekdays = PlannerTaskManager.decodedWeekdays(task.scheduleWeekdaysRawValue)
        plannedDurationMinutes = task.plannedDurationMinutes
        customWorkSessionsData = task.customWorkSessionsData
        repeatFrequency = task.repeatFrequency
        repeatInterval = task.repeatInterval ?? 1
        repeatEndMode = task.repeatEndMode
        repeatEndDate = task.repeatEndDate
        repeatCount = task.repeatCount
        completedOccurrenceDaysData = task.completedOccurrenceDaysData
        excludedOccurrenceDaysData = task.excludedOccurrenceDaysData
        isCompleted = task.isCompleted
        completedAt = task.completedAt
        position = task.position
        priority = task.priority
        status = task.status
        habitID = task.habitID
        createdAt = task.createdAt
        updatedAt = task.updatedAt
    }

    func makeTask() -> PlannerTask {
        PlannerTask(
            id: id,
            title: title,
            taskNotes: taskNotes,
            scheduledDay: scheduledDay,
            dueDate: dueDate,
            dueTime: dueTime,
            timeMode: timeMode,
            scheduledTime: scheduledTime,
            daySection: daySection,
            scheduleKind: scheduleKind,
            scheduleEndDate: scheduleEndDate,
            scheduleWeekdays: scheduleWeekdays,
            plannedDurationMinutes: plannedDurationMinutes,
            customWorkSessionsData: customWorkSessionsData,
            repeatFrequency: repeatFrequency,
            repeatInterval: repeatInterval,
            repeatEndMode: repeatEndMode,
            repeatEndDate: repeatEndDate,
            repeatCount: repeatCount,
            completedOccurrenceDaysData: completedOccurrenceDaysData,
            excludedOccurrenceDaysData: excludedOccurrenceDaysData,
            isCompleted: isCompleted,
            completedAt: completedAt,
            position: position,
            priority: priority,
            status: status,
            habitID: habitID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private struct HabitSummaryRow: View {
    let habit: Habit

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: habit.symbolName)
                .frame(width: 42, height: 42)
                .background(habit.tint.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(habit.tint.color)

            VStack(alignment: .leading, spacing: 3) {
                Text(habit.name)
                    .font(.headline)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .sinceCardSurface(radius: 16)
    }

    private var summary: String {
        HabitTrackingManager.summary(for: habit)
    }
}

private struct RecentActivityView: View {
    let habits: [Habit]

    private var recentEvents: [HabitEvent] {
        habits
            .flatMap(\.events)
            .sorted { $0.occurredAt > $1.occurredAt }
            .prefix(4)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent activity")
                .font(.headline)

            if recentEvents.isEmpty {
                Text("Your notes, slips, and restarts will appear here without replacing your earlier progress.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .sinceCardSurface(radius: 16)
            } else {
                ForEach(recentEvents) { event in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: event.kind == .slip ? "arrow.counterclockwise" : "circle.fill")
                            .font(.caption)
                            .foregroundStyle(event.kind == .slip ? .orange : .secondary)
                            .frame(width: 28, height: 28)
                            .background(.quaternary, in: Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(HabitTrackingManager.activityTitle(for: event))
                                .font(.subheadline.weight(.semibold))
                            Text(event.occurredAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !event.note.isEmpty {
                                Text(event.note)
                                    .font(.subheadline)
                                    .padding(.top, 2)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}
