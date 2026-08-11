import SwiftData
import SwiftUI

struct SlipResetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let habit: Habit
    @State private var occurredAt = Date()
    @State private var note = ""
    @State private var restartsStreak = true
    @State private var measurementValue: Double?
    @State private var persistenceIssue: PersistenceIssue?
    @FocusState private var isTextInputFocused: Bool

    init(habit: Habit) {
        self.habit = habit
        _measurementValue = State(initialValue: HabitMeasurementManager.initialEntryValue(for: habit))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("A slip is information, not erased progress.")
                        .font(.headline)
                    Text("Your current chapter will always remain in your history.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("When did it happen?") {
                    DatePicker(
                        "Date and time",
                        selection: $occurredAt,
                        in: habit.startAt...Date.now
                    )
                }

                Section("What should happen next?") {
                    Toggle("Start a new streak", isOn: $restartsStreak)
                    Text(restartsStreak
                         ? "The current streak will close at this time and a new one will begin."
                         : "The slip will be recorded, but your current start time will stay unchanged.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let definition = habit.measurementDefinition {
                    MeasurementInputSection(
                        definition: definition,
                        value: $measurementValue,
                        textInputFocus: $isTextInputFocused,
                        isRequired: true
                    )
                }

                Section("Private note") {
                    TextField("What was happening? (optional)", text: $note, axis: .vertical)
                        .focused($isTextInputFocused)
                        .lineLimit(3...6)
                }

                if restartsStreak {
                    Section("Preview") {
                        let currentStart = ElapsedTimeCalculator.currentStart(for: habit)
                        let elapsed = ElapsedTime(from: currentStart, to: occurredAt)

                        Text("Your \(elapsed.days)-day chapter will be preserved. A new streak will begin \(occurredAt.formatted(date: .abbreviated, time: .shortened)).")
                            .font(.subheadline)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Record a slip")
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
                    .disabled(!hasValidMeasurement)
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

    private var hasValidMeasurement: Bool {
        guard habit.measurementDefinition != nil else { return true }
        return measurementValue.map { $0 > 0 } ?? false
    }

    private func save() {
        let event = HabitEvent(
            kind: .slip,
            occurredAt: occurredAt,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            restartsStreak: restartsStreak,
            habit: habit
        )
        HabitMeasurementManager.apply(
            value: measurementValue,
            definition: habit.measurementDefinition,
            to: event
        )
        habit.events.append(event)
        habit.updatedAt = .now
        modelContext.insert(event)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            persistenceIssue = PersistenceIssue(title: "Slip Could Not Be Saved", error: error)
        }
    }
}
