import SwiftData
import SwiftUI

struct EditSlipView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let event: HabitEvent
    let habit: Habit

    @State private var occurredAt: Date
    @State private var note: String
    @State private var restartsStreak: Bool
    @State private var measurementValue: Double?
    @State private var isConfirmingDelete = false
    @State private var persistenceIssue: PersistenceIssue?
    @FocusState private var isTextInputFocused: Bool

    init(event: HabitEvent, habit: Habit) {
        self.event = event
        self.habit = habit
        _occurredAt = State(initialValue: event.occurredAt)
        _note = State(initialValue: event.note)
        _restartsStreak = State(initialValue: event.restartsStreak)
        _measurementValue = State(initialValue: event.measurementValue)
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

                Section {
                    Toggle("Started a new streak", isOn: $restartsStreak)
                } header: {
                    Text("Effect on the streak")
                } footer: {
                    Text(restartsStreak
                         ? "The previous chapter closes at this time and a new one begins."
                         : "The slip stays in your history without changing the streak start.")
                }

                if let definition = event.measurementDefinition ?? habit.measurementDefinition {
                    MeasurementInputSection(
                        definition: definition,
                        value: $measurementValue,
                        textInputFocus: $isTextInputFocused
                    )
                }

                Section("Private note") {
                    TextField("What was happening? (optional)", text: $note, axis: .vertical)
                        .focused($isTextInputFocused)
                        .lineLimit(3...6)
                }

                Section {
                    Button("Delete this slip", role: .destructive) {
                        isConfirmingDelete = true
                    }
                    .frame(maxWidth: .infinity)
                } footer: {
                    Text("Removing a restarting slip will join the chapters on either side.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit slip")
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
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isTextInputFocused = false
                    }
                }
            }
            .alert("Delete this slip?", isPresented: $isConfirmingDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Slip", role: .destructive) {
                    deleteSlip()
                }
            } message: {
                Text("This removes the slip and recalculates the streak history. The habit itself will remain.")
            }
        }
        .persistenceIssueAlert($persistenceIssue)
    }

    private func save() {
        event.occurredAt = occurredAt
        event.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        event.restartsStreak = restartsStreak
        HabitMeasurementManager.apply(
            value: measurementValue,
            definition: event.measurementDefinition ?? habit.measurementDefinition,
            to: event
        )
        habit.updatedAt = .now
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            persistenceIssue = PersistenceIssue(title: "Slip Could Not Be Saved", error: error)
        }
    }

    private func deleteSlip() {
        habit.events.removeAll { $0.id == event.id }
        modelContext.delete(event)
        habit.updatedAt = .now
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            persistenceIssue = PersistenceIssue(title: "Slip Could Not Be Deleted", error: error)
        }
    }
}
