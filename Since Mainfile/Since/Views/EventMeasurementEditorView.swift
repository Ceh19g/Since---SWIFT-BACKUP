import SwiftData
import SwiftUI

struct EventMeasurementEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let event: HabitEvent
    let habit: Habit

    @State private var occurredAt: Date
    @State private var note: String
    @State private var measurementValue: Double?
    @State private var persistenceIssue: PersistenceIssue?
    @FocusState private var isTextInputFocused: Bool

    init(event: HabitEvent, habit: Habit) {
        self.event = event
        self.habit = habit
        _occurredAt = State(initialValue: event.occurredAt)
        _note = State(initialValue: event.note)
        _measurementValue = State(initialValue: event.measurementValue)
    }

    private var definition: HabitMeasurementDefinition? {
        event.measurementDefinition ?? habit.measurementDefinition
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("When did it happen?") {
                    DatePicker(
                        "Date and time",
                        selection: $occurredAt,
                        in: habit.startAt...Date.now
                    )
                }

                if let definition {
                    MeasurementInputSection(
                        definition: definition,
                        value: $measurementValue,
                        textInputFocus: $isTextInputFocused
                    )
                }

                Section("Private note") {
                    TextField("Add context (optional)", text: $note, axis: .vertical)
                        .focused($isTextInputFocused)
                        .lineLimit(3...6)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isTextInputFocused = false }
                }
            }
        }
        .persistenceIssueAlert($persistenceIssue)
    }

    private func save() {
        event.occurredAt = occurredAt
        event.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        HabitMeasurementManager.apply(
            value: measurementValue,
            definition: definition,
            to: event
        )
        habit.updatedAt = .now

        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            persistenceIssue = PersistenceIssue(title: "Entry Could Not Be Saved", error: error)
        }
    }
}
