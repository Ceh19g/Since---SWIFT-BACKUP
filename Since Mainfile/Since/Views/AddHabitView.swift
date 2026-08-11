import SwiftData
import SwiftUI

struct AddHabitView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @Query private var storedHabits: [Habit]

    @State private var name = ""
    @State private var habitDescription = ""
    @State private var type: HabitType = .abstinence
    @State private var startAt = Date()
    @State private var tint: HabitTint = .indigo
    @State private var symbolName = "leaf.fill"
    @State private var usesCustomMilestone = false
    @State private var customMilestoneDays = 30
    @State private var isHealthSteps = false
    @State private var stepGoal = 8_000
    @State private var healthWeekdays = HealthGoalManager.everyDay
    @State private var measurementDraft = HabitMeasurementDraft()
    @State private var showsCustomization = false
    @State private var persistenceIssue: PersistenceIssue?
    @FocusState private var isTextInputFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("What are you tracking?") {
                    TextField("Habit name", text: $name)
                        .focused($isTextInputFocused)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .onSubmit { isTextInputFocused = false }
                        .accessibilityIdentifier("habit-name-field")
                    TextField("A private intention (optional)", text: $habitDescription, axis: .vertical)
                        .focused($isTextInputFocused)
                        .lineLimit(2...4)
                }

                Section {
                    Button {
                        selectHealthSteps()
                    } label: {
                        HealthTrackingStyleChoiceRow(isSelected: isHealthSteps)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tracking-style-health-steps")
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Steps are read automatically from Apple Health. Since never writes or changes your Health data.")
                }

                Section {
                    ForEach(HabitType.supportedCases) { option in
                        Button {
                            selectType(option)
                        } label: {
                            TrackingStyleChoiceRow(
                                type: option,
                                isSelected: !isHealthSteps && type == option
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("tracking-style-\(option.rawValue)")
                    }
                } header: {
                    Text("Manual tracking")
                } footer: {
                    Text("Every option shown here is fully functional. You can create another tracker later to try a different style.")
                }

                Section(isHealthSteps ? "Begin tracking" : type.dateSectionTitle) {
                    DatePicker(
                        "Date and time",
                        selection: $startAt,
                        in: allowedDateRange
                    )
                }

                if isHealthSteps {
                    Section {
                        Stepper(value: $stepGoal, in: 1_000...100_000, step: 500) {
                            HStack {
                                Text("Daily goal")
                                Spacer()
                                Text("\(stepGoal.formatted()) steps")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("health-step-goal-stepper")

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Active days")
                                .font(.subheadline)
                            WeekdaySelector(selection: $healthWeekdays)
                        }
                    } header: {
                        Text("Step goal")
                    } footer: {
                        Text("A scheduled day is complete when Apple Health reports at least this many steps.")
                    }
                }

                Section {
                    Button(action: toggleCustomization) {
                        HStack {
                            Label(
                                showsCustomization ? "Hide options" : "More options",
                                systemImage: "slider.horizontal.3"
                            )
                            Spacer()
                            Image(systemName: showsCustomization ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("habit-more-options-button")
                } footer: {
                    Text("Measurement, appearance, and personal milestones are optional.")
                }

                if showsCustomization {
                    if supportsManualMeasurement {
                        MeasurementSetupSection(
                            draft: $measurementDraft,
                            habitType: type,
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
                                 ? "This goal replaces the standard milestone schedule for this tracker."
                                 : "Since will use its standard milestone schedule.")
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createHabit()
                    }
                    .accessibilityIdentifier("create-habit-button")
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || (supportsManualMeasurement && !measurementDraft.isValid)
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
        type == .countdown
            ? Date.now...Date.distantFuture
            : Date.distantPast...Date.now
    }

    private var supportsMilestones: Bool {
        type == .abstinence || type == .sinceDate
    }

    private var supportsManualMeasurement: Bool {
        !isHealthSteps && type != .sinceDate && type != .countdown
    }

    private var savedMeasurementDefinitions: [HabitMeasurementDefinition] {
        HabitMeasurementManager.customDefinitions(from: storedHabits)
    }

    private func toggleCustomization() {
        if reduceMotion {
            showsCustomization.toggle()
        } else {
            withAnimation(SinceMotion.standard(reduceMotion: false)) {
                showsCustomization.toggle()
            }
        }
    }

    private func selectType(_ newType: HabitType) {
        isHealthSteps = false
        type = newType
        usesCustomMilestone = false

        if newType == .countdown, startAt < .now {
            startAt = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        } else if newType != .countdown, startAt > .now {
            startAt = .now
        }
    }

    private func selectHealthSteps() {
        isHealthSteps = true
        type = .positiveStreak
        usesCustomMilestone = false
        startAt = min(startAt, .now)
        symbolName = "figure.walk"
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = "Daily Steps"
        }
    }

    private func createHabit() {
        do {
            let existingHabits = try modelContext.fetch(FetchDescriptor<Habit>())
            let habit = Habit(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                habitDescription: habitDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                type: type,
                tint: tint,
                symbolName: symbolName,
                startAt: startAt,
                customMilestoneDays: supportsMilestones && usesCustomMilestone ? customMilestoneDays : nil,
                healthMetric: isHealthSteps ? .steps : nil,
                healthGoalValue: isHealthSteps ? Double(stepGoal) : nil,
                healthGoalWeekdays: healthWeekdays,
                isPinned: existingHabits.allSatisfy(\.isArchived)
            )
            let startEvent = HabitEvent(kind: .started, occurredAt: startAt, habit: habit)
            measurementDraft.apply(to: habit)
            habit.events.append(startEvent)
            modelContext.insert(habit)
            try modelContext.save()
            if isHealthSteps {
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
            persistenceIssue = PersistenceIssue(title: "Habit Could Not Be Created", error: error)
        }
    }
}

private struct HealthTrackingStyleChoiceRow: View {
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.walk")
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
                .frame(width: 38, height: 38)
                .background(
                    Color.accentColor.opacity(isSelected ? 0.20 : 0.12),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("Daily step goal")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Track steps recorded by your iPhone or Apple Watch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct TrackingStyleChoiceRow: View {
    let type: HabitType
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.symbolName)
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
                .frame(width: 38, height: 38)
                .background(
                    Color.accentColor.opacity(isSelected ? 0.20 : 0.12),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(type.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(type.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
