import SwiftUI

struct HabitMeasurementDraft: Equatable {
    static let noneID = "none"
    static let customID = "custom"

    var selectionID: String = noneID
    var customName = ""
    var customUnit = ""
    var customValueKind: HabitMeasurementValueKind = .wholeNumber
    var defaultValue: Double?

    init() {}

    init(habit: Habit) {
        if let rawValue = habit.measurementTemplateRawValue {
            selectionID = HabitMeasurementTemplate(rawValue: rawValue) == nil
                ? Self.customID
                : "template:\(rawValue)"
        }
        customName = habit.measurementCustomName ?? ""
        customUnit = habit.measurementCustomUnit ?? ""
        customValueKind = habit.measurementCustomValueKindRawValue
            .flatMap(HabitMeasurementValueKind.init(rawValue:)) ?? .wholeNumber
        defaultValue = habit.measurementDefaultValue
    }

    var definition: HabitMeasurementDefinition? {
        if selectionID.hasPrefix("template:"),
           let rawValue = selectionID.split(separator: ":", maxSplits: 1).last,
           let template = HabitMeasurementTemplate(rawValue: String(rawValue)) {
            return template.definition
        }
        guard selectionID == Self.customID else { return nil }
        let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = customUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !unit.isEmpty else { return nil }
        return HabitMeasurementDefinition(
            sourceID: HabitMeasurementManager.customSourceID,
            name: name,
            unit: unit,
            valueKind: customValueKind,
            symbolName: customValueKind.symbolName
        )
    }

    var isValid: Bool {
        if selectionID == Self.noneID { return true }
        guard let definition else { return false }
        guard let defaultValue else { return true }
        return defaultValue > 0 && defaultValue <= definition.valueKind.maximumValue
    }

    mutating func select(_ selection: String, savedDefinitions: [HabitMeasurementDefinition]) {
        if selection.hasPrefix("saved:"),
           let saved = savedDefinitions.first(where: { "saved:\($0.identityKey)" == selection }) {
            customName = saved.name
            customUnit = saved.unit
            customValueKind = saved.valueKind
            selectionID = Self.customID
            return
        }
        selectionID = selection
        if selection == Self.noneID {
            defaultValue = nil
        }
    }

    func apply(to habit: Habit) {
        guard habit.supportsManualMeasurement, let definition else {
            habit.measurementTemplateRawValue = nil
            habit.measurementCustomName = nil
            habit.measurementCustomUnit = nil
            habit.measurementCustomValueKindRawValue = nil
            habit.measurementDefaultValue = nil
            return
        }

        if selectionID.hasPrefix("template:") {
            habit.measurementTemplateRawValue = definition.sourceID
            habit.measurementCustomName = nil
            habit.measurementCustomUnit = nil
            habit.measurementCustomValueKindRawValue = nil
        } else {
            habit.measurementTemplateRawValue = HabitMeasurementManager.customSourceID
            habit.measurementCustomName = definition.name
            habit.measurementCustomUnit = definition.unit
            habit.measurementCustomValueKindRawValue = definition.valueKind.rawValue
        }
        habit.measurementDefaultValue = defaultValue
    }
}

struct MeasurementSetupSection: View {
    @Binding var draft: HabitMeasurementDraft
    let habitType: HabitType
    let savedDefinitions: [HabitMeasurementDefinition]
    let textInputFocus: FocusState<Bool>.Binding

    private var recommended: [HabitMeasurementTemplate] {
        HabitMeasurementTemplate.recommended(for: habitType)
    }

    private var remaining: [HabitMeasurementTemplate] {
        HabitMeasurementTemplate.allCases.filter { !recommended.contains($0) }
    }

    var body: some View {
        Section {
            Picker("Measurement", selection: $draft.selectionID) {
                Text("None").tag(HabitMeasurementDraft.noneID)

                Section("Recommended") {
                    ForEach(recommended) { template in
                        Label(template.title, systemImage: template.symbolName)
                            .tag("template:\(template.rawValue)")
                    }
                }

                if !savedDefinitions.isEmpty {
                    Section("My Measurements") {
                        ForEach(savedDefinitions) { definition in
                            Label(definition.name, systemImage: definition.symbolName)
                                .tag("saved:\(definition.identityKey)")
                        }
                    }
                }

                Section("More") {
                    ForEach(remaining) { template in
                        Label(template.title, systemImage: template.symbolName)
                            .tag("template:\(template.rawValue)")
                    }
                    Label("Custom…", systemImage: "slider.horizontal.3")
                        .tag(HabitMeasurementDraft.customID)
                }
            }
            .onChange(of: draft.selectionID) { _, newValue in
                draft.select(newValue, savedDefinitions: savedDefinitions)
            }
            .accessibilityIdentifier("habit-measurement-picker")

            if draft.selectionID == HabitMeasurementDraft.customID {
                TextField("Measurement name", text: $draft.customName)
                    .focused(textInputFocus)
                    .textInputAutocapitalization(.words)
                    .accessibilityIdentifier("custom-measurement-name-field")

                TextField("Display unit", text: $draft.customUnit)
                    .focused(textInputFocus)
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("custom-measurement-unit-field")

                Picker("Value type", selection: $draft.customValueKind) {
                    ForEach(HabitMeasurementValueKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.symbolName)
                            .tag(kind)
                    }
                }
            }

            if let definition = draft.definition {
                Toggle(
                    "Prefill an amount",
                    isOn: Binding(
                        get: { draft.defaultValue != nil },
                        set: { enabled in
                            draft.defaultValue = enabled
                                ? (definition.valueKind == .ratingFive ? 3 : 1)
                                : nil
                        }
                    )
                )

                if draft.defaultValue != nil {
                    measurementValueRow(
                        definition: definition,
                        value: Binding(
                            get: { draft.defaultValue ?? 1 },
                            set: { draft.defaultValue = $0 }
                        )
                    )
                }

                LabeledContent("Preview") {
                    Text(definition.formatted(draft.defaultValue ?? sampleValue(for: definition)))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Measurement — Optional")
        } footer: {
            if draft.selectionID == HabitMeasurementDraft.customID {
                Text("Custom measurements are automatically available to your other relevant habits.")
            } else {
                Text("A prefilled amount can be changed before every entry is saved. Measurements add detail without changing the streak by themselves.")
            }
        }
    }

    @ViewBuilder
    private func measurementValueRow(
        definition: HabitMeasurementDefinition,
        value: Binding<Double>
    ) -> some View {
        if definition.valueKind == .ratingFive {
            VStack(alignment: .leading, spacing: 8) {
                Text("Prefill rating")
                    .font(.subheadline)
                FiveStarRatingPicker(value: value)
            }
        } else {
            LabeledContent("Default") {
                HStack(spacing: 6) {
                    TextField("1", value: value, format: .number)
                        .focused(textInputFocus)
                        .keyboardType(definition.valueKind == .wholeNumber ? .numberPad : .decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                        .accessibilityIdentifier("measurement-default-value-field")
                    if definition.valueKind != .currency {
                        Text(definition.unit)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func sampleValue(for definition: HabitMeasurementDefinition) -> Double {
        definition.valueKind == .ratingFive ? 3 : 1
    }
}

struct MeasurementInputSection: View {
    let definition: HabitMeasurementDefinition
    @Binding var value: Double?
    let textInputFocus: FocusState<Bool>.Binding
    let isRequired: Bool

    init(
        definition: HabitMeasurementDefinition,
        value: Binding<Double?>,
        textInputFocus: FocusState<Bool>.Binding,
        isRequired: Bool = false
    ) {
        self.definition = definition
        _value = value
        self.textInputFocus = textInputFocus
        self.isRequired = isRequired
    }

    var body: some View {
        Section {
            if !isRequired {
                Toggle(
                    "Include an amount",
                    isOn: Binding(
                        get: { value != nil },
                        set: { enabled in
                            value = enabled ? suggestedValue : nil
                        }
                    )
                )
                .accessibilityIdentifier("include-measurement-toggle")
            }

            if isRequired || value != nil {
                if definition.valueKind == .ratingFive {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(definition.name)
                            .font(.subheadline.weight(.medium))
                        FiveStarRatingPicker(value: nonOptionalValue)
                    }
                } else {
                    LabeledContent(definition.name) {
                        HStack(spacing: 6) {
                            TextField("0", value: nonOptionalValue, format: .number)
                                .focused(textInputFocus)
                                .keyboardType(definition.valueKind == .wholeNumber ? .numberPad : .decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 110)
                                .accessibilityIdentifier("measurement-value-field")
                            if definition.valueKind != .currency {
                                Text(definition.unit)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Text(definition.formatted(nonOptionalValue.wrappedValue))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } header: {
            Text(isRequired ? "Amount" : "Amount — Optional")
        } footer: {
            if isRequired {
                Text("This amount will be saved with the entry, so you will not need to edit its history afterward.")
            } else {
                Text("This adds context to the entry. It does not create extra slips or completions.")
            }
        }
        .onAppear {
            if isRequired && value == nil {
                value = suggestedValue
            }
        }
    }

    private var suggestedValue: Double {
        definition.valueKind == .ratingFive ? 3 : 1
    }

    private var nonOptionalValue: Binding<Double> {
        Binding(
            get: { value ?? suggestedValue },
            set: { value = min(max($0, 0), definition.valueKind.maximumValue) }
        )
    }
}

struct HabitMeasurementEntryRequest: Identifiable {
    enum Purpose {
        case completion
        case occurrence
    }

    let id = UUID()
    let habit: Habit
    let purpose: Purpose

    var title: String {
        switch purpose {
        case .completion: "Complete \(habit.name)"
        case .occurrence: "Log \(habit.name)"
        }
    }
}

struct HabitMeasurementEntryView: View {
    @Environment(\.dismiss) private var dismiss

    let request: HabitMeasurementEntryRequest
    let onSave: (Double) -> Void

    @State private var value: Double?
    @FocusState private var isTextInputFocused: Bool

    init(
        request: HabitMeasurementEntryRequest,
        onSave: @escaping (Double) -> Void
    ) {
        self.request = request
        self.onSave = onSave
        _value = State(initialValue: HabitMeasurementManager.initialEntryValue(for: request.habit))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let definition = request.habit.measurementDefinition {
                    Section {
                        Text(definition.entryPrompt)
                            .font(.headline)
                        Text("Enter the amount before saving this entry.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    MeasurementInputSection(
                        definition: definition,
                        value: $value,
                        textInputFocus: $isTextInputFocused,
                        isRequired: true
                    )
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(request.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let value, value > 0 else { return }
                        onSave(value)
                        dismiss()
                    }
                    .disabled(value.map { $0 <= 0 } ?? true)
                    .accessibilityIdentifier("save-habit-measurement-button")
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isTextInputFocused = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            guard request.habit.measurementDefinition?.valueKind != .ratingFive else { return }
            Task { @MainActor in
                await Task.yield()
                isTextInputFocused = true
            }
        }
    }
}

private struct FiveStarRatingPicker: View {
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { rating in
                Button {
                    value = Double(rating)
                } label: {
                    Image(systemName: rating <= Int(value.rounded()) ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(rating <= Int(value.rounded()) ? .yellow : .secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(rating) of 5")
                .accessibilityAddTraits(rating == Int(value.rounded()) ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
    }
}
