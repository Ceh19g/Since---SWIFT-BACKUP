import SwiftData
import SwiftUI

struct EditHabitView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @Query private var storedHabits: [Habit]

    let habit: Habit

    @State private var name: String
    @State private var habitDescription: String
    @State private var startAt: Date
    @State private var tint: HabitTint
    @State private var symbolName: String
    @State private var usesCustomMilestone: Bool
    @State private var customMilestoneDays: Int
    @State private var healthGoal: Int
    @State private var healthWeekdays: Set<Int>
    @State private var measurementDraft: HabitMeasurementDraft
    @State private var persistenceIssue: PersistenceIssue?
    @FocusState private var isTextInputFocused: Bool

    init(habit: Habit) {
        self.habit = habit
        _name = State(initialValue: habit.name)
        _habitDescription = State(initialValue: habit.habitDescription)
        _startAt = State(initialValue: habit.startAt)
        _tint = State(initialValue: habit.tint)
        _symbolName = State(initialValue: habit.symbolName)
        _usesCustomMilestone = State(initialValue: habit.customMilestoneDays != nil)
        _customMilestoneDays = State(initialValue: habit.customMilestoneDays ?? 30)
        _healthGoal = State(initialValue: Int((habit.healthGoalValue ?? 8_000).rounded()))
        _healthWeekdays = State(
            initialValue: HealthGoalManager.decodedWeekdays(habit.healthGoalWeekdaysRawValue)
        )
        _measurementDraft = State(initialValue: HabitMeasurementDraft(habit: habit))
    }

    private var latestAllowedStart: Date {
        habit.events
            .filter { $0.kind != .started }
            .map(\.occurredAt)
            .min()
            .map { min($0, Date.now) } ?? Date.now
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What are you tracking?") {
                    TextField("Habit name", text: $name)
                        .focused($isTextInputFocused)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .onSubmit { isTextInputFocused = false }
                        .accessibilityIdentifier("edit-habit-name-field")

                    TextField("A private intention (optional)", text: $habitDescription, axis: .vertical)
                        .focused($isTextInputFocused)
                        .lineLimit(2...4)
                }

                Section {
                    Label(habit.trackingTitle, systemImage: habit.isHealthPowered ? "heart.fill" : habit.type.symbolName)
                    Text(
                        habit.isHealthPowered
                            ? "Progress is read automatically from Apple Health."
                            : habit.type.explanation
                    )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Tracking style")
                } footer: {
                    Text("The tracking style stays fixed so existing history keeps its original meaning.")
                }

                Section {
                    DatePicker(
                        "Date and time",
                        selection: $startAt,
                        in: allowedDateRange
                    )
                } header: {
                    Text(habit.type.dateSectionTitle)
                } footer: {
                    Text(dateExplanation)
                }

                if habit.isHealthPowered {
                    Section {
                        Stepper(value: $healthGoal, in: 1_000...100_000, step: 500) {
                            HStack {
                                Text("Daily goal")
                                Spacer()
                                Text("\(healthGoal.formatted()) steps")
                                    .foregroundStyle(.secondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Active days")
                                .font(.subheadline)
                            WeekdaySelector(selection: $healthWeekdays)
                        }
                    } header: {
                        Text("Step goal")
                    } footer: {
                        Text("Changes begin today. Earlier dates keep the goal that applied at the time.")
                    }
                }

                if habit.supportsManualMeasurement {
                    MeasurementSetupSection(
                        draft: $measurementDraft,
                        habitType: habit.type,
                        savedDefinitions: savedMeasurementDefinitions,
                        textInputFocus: $isTextInputFocused
                    )
                }

                Section("Appearance") {
                    Picker("Color", selection: $tint) {
                        ForEach(HabitTint.allCases) { option in
                            Label(option.rawValue.capitalized, systemImage: "circle.fill")
                                .foregroundStyle(option.color)
                                .tag(option)
                        }
                    }

                    Picker("Symbol", selection: $symbolName) {
                        ForEach(HabitAppearanceOptions.symbols, id: \.self) { symbol in
                            Label(symbol.replacingOccurrences(of: ".fill", with: "").capitalized, systemImage: symbol)
                                .tag(symbol)
                        }
                    }
                }

                if supportsMilestones {
                    Section {
                        Toggle("Set a custom milestone", isOn: $usesCustomMilestone)

                        if usesCustomMilestone {
                            Stepper(
                                "\(customMilestoneDays) \(customMilestoneDays == 1 ? "day" : "days")",
                                value: $customMilestoneDays,
                                in: 1...3_650
                            )
                        }
                    } header: {
                        Text("Personal milestone")
                    } footer: {
                        Text(usesCustomMilestone
                             ? "Progress will focus on this personal goal."
                             : "Since will use its standard milestone schedule.")
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .accessibilityIdentifier("save-habit-button")
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || (habit.supportsManualMeasurement && !measurementDraft.isValid)
                    )
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isTextInputFocused = false
                    }
                }
            }
        }
        .persistenceIssueAlert($persistenceIssue)
    }

    private var allowedDateRange: ClosedRange<Date> {
        habit.type == .countdown
            ? Date.distantPast...Date.distantFuture
            : Date.distantPast...latestAllowedStart
    }

    private var supportsMilestones: Bool {
        habit.type == .abstinence
            || habit.type == .sinceDate
    }

    private var savedMeasurementDefinitions: [HabitMeasurementDefinition] {
        HabitMeasurementManager.customDefinitions(from: storedHabits.filter { $0.id != habit.id })
    }

    private var dateExplanation: String {
        if habit.isHealthPowered {
            return "Apple Health progress is shown from this date forward."
        }
        return switch habit.type {
        case .abstinence:
            "Changing this updates the beginning of your original chapter. Later slips and restarts stay in your history."
        case .positiveStreak:
            "Daily completions before this date will not count toward streaks."
        case .event:
            "This is used when no newer occurrences have been logged."
        case .sinceDate:
            "The exact counter begins from this meaningful moment."
        case .countdown:
            "Choose the moment the countdown is working toward."
        case .frequency, .count, .duration:
            "Changing this updates the original tracking date."
        }
    }

    private func save() {
        habit.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        habit.habitDescription = habitDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        habit.startAt = startAt
        habit.tint = tint
        habit.symbolName = symbolName
        habit.customMilestoneDays = supportsMilestones && usesCustomMilestone ? customMilestoneDays : nil
        measurementDraft.apply(to: habit)
        if habit.isHealthPowered {
            let currentWeekdays = HealthGoalManager.decodedWeekdays(habit.healthGoalWeekdaysRawValue)
            if Int((habit.healthGoalValue ?? 0).rounded()) != healthGoal
                || currentWeekdays != healthWeekdays {
                HealthGoalManager.recordGoal(
                    for: habit,
                    target: Double(healthGoal),
                    activeWeekdays: healthWeekdays,
                    effectiveAt: .now
                )
            }
        }
        habit.updatedAt = .now

        if let startEvent = habit.events.first(where: { $0.kind == .started }) {
            startEvent.occurredAt = startAt
        } else {
            let startEvent = HabitEvent(kind: .started, occurredAt: startAt, habit: habit)
            habit.events.append(startEvent)
            modelContext.insert(startEvent)
        }

        do {
            try modelContext.save()
            if habit.isHealthPowered {
                Task {
                    if !healthKitManager.hasRequestedAccess {
                        await healthKitManager.requestStepAccess()
                    }
                    await healthKitManager.refreshRecentDays()
                }
            }
            dismiss()
        } catch {
            modelContext.rollback()
            persistenceIssue = PersistenceIssue(title: "Habit Could Not Be Saved", error: error)
        }
    }
}
