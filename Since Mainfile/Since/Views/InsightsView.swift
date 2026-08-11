import Charts
import SwiftData
import SwiftUI

struct InsightsView: View {
    @EnvironmentObject private var healthKitManager: HealthKitManager
    @Query(sort: \Habit.createdAt) private var habits: [Habit]
    @Query private var plannerTasks: [PlannerTask]

    @State private var period: InsightPeriod = .thirtyDays
    @State private var selectedHabitID: UUID?

    private let calendar = Calendar.autoupdatingCurrent
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var activeHabits: [Habit] {
        habits.filter { !$0.isArchived }
    }

    private var selectedHabit: Habit? {
        guard let selectedHabitID else { return nil }
        return activeHabits.first { $0.id == selectedHabitID }
    }

    private func selectedHabitSnapshot(in snapshot: InsightsSnapshot) -> HabitInsightSnapshot? {
        guard let selectedHabitID else { return nil }
        return snapshot.habitSnapshots.first { $0.id == selectedHabitID }
    }

    var body: some View {
        let snapshot = InsightsEngine.makeSnapshot(
            habits: habits,
            tasks: plannerTasks,
            period: period,
            selectedHabitID: selectedHabitID,
            healthStepTotals: healthKitManager.stepTotals,
            calendar: calendar
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                controls(snapshot: snapshot)

                if activeHabits.isEmpty && plannerTasks.isEmpty {
                    ContentUnavailableView(
                        "No activity yet",
                        systemImage: "chart.xyaxis.line",
                        description: Text("Add a habit or planner task and Insights will summarize the recorded data.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    snapshotSection(snapshot: snapshot)
                    comparisonSection(snapshot: snapshot)
                    activitySection(snapshot: snapshot)
                    patternSection(snapshot: snapshot)
                    habitBreakdownSection(snapshot: snapshot)
                    dataCoverageSection(snapshot: snapshot)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Insights")
        .onChange(of: activeHabits.map(\.id)) { _, activeIDs in
            if let selectedHabitID, !activeIDs.contains(selectedHabitID) {
                self.selectedHabitID = nil
            }
        }
        .task(id: healthRefreshKey) {
            await refreshHealthRangeIfNeeded()
        }
    }

    private func controls(snapshot: InsightsSnapshot) -> some View {
        VStack(spacing: 12) {
            Picker("Time range", selection: $period) {
                ForEach(InsightPeriod.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("insights-period-picker")

            Menu {
                Button {
                    selectedHabitID = nil
                } label: {
                    if selectedHabitID == nil {
                        Label("All Habits", systemImage: "checkmark")
                    } else {
                        Text("All Habits")
                    }
                }

                ForEach(activeHabits) { habit in
                    Button {
                        selectedHabitID = habit.id
                    } label: {
                        if selectedHabitID == habit.id {
                            Label(habit.name, systemImage: "checkmark")
                        } else {
                            Label(habit.name, systemImage: habit.symbolName)
                        }
                    }
                }
            } label: {
                HStack {
                    Label(
                        selectedHabit?.name ?? "All Habits",
                        systemImage: selectedHabit?.symbolName ?? "square.grid.2x2"
                    )
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("insights-habit-filter")

            Text(rangeDescription(for: snapshot))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func snapshotSection(snapshot: InsightsSnapshot) -> some View {
        InsightSection(title: "Snapshot", subtitle: "Recorded results for the selected period") {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(metricCards(for: snapshot)) { card in
                    InsightMetricCard(card: card)
                }
            }
        }
    }

    private func comparisonSection(snapshot: InsightsSnapshot) -> some View {
        InsightSection(title: "What Changed", subtitle: comparisonSubtitle) {
            VStack(spacing: 10) {
                if snapshot.comparisons.isEmpty {
                    InsightEmptyCard(
                        symbol: period == .allTime ? "clock.arrow.circlepath" : "equal.circle",
                        title: period == .allTime ? "All-time view selected" : "No reliable comparison yet",
                        message: period == .allTime
                            ? "Choose 7D, 30D, or 90D to compare against the preceding period."
                            : "Since will compare periods after both contain enough recorded activity."
                    )
                } else {
                    ForEach(snapshot.comparisons) { finding in
                        InsightFindingRow(finding: finding)
                    }
                }
            }
        }
    }

    private func activitySection(snapshot: InsightsSnapshot) -> some View {
        InsightSection(title: "Activity", subtitle: "Habit logs, slips, and completed planner tasks") {
            VStack(alignment: .leading, spacing: 14) {
                if hasChartActivity(in: snapshot) {
                    Chart {
                        ForEach(snapshot.activity) { point in
                            BarMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("Completed tasks", point.completedTasks)
                            )
                            .foregroundStyle(.indigo.opacity(0.50))
                            .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                            .accessibilityValue("\(point.completedTasks) completed tasks")

                            LineMark(
                                x: .value("Date", point.date, unit: .day),
                                y: .value("Habit logs", point.habitLogs)
                            )
                            .foregroundStyle(.teal)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.catmullRom)

                            if point.habitLogs > 0 {
                                PointMark(
                                    x: .value("Date", point.date, unit: .day),
                                    y: .value("Habit logs", point.habitLogs)
                                )
                                .foregroundStyle(.teal)
                            }

                            if point.slips > 0 {
                                PointMark(
                                    x: .value("Date", point.date, unit: .day),
                                    y: .value("Slips", point.slips)
                                )
                                .foregroundStyle(.orange)
                                .symbolSize(70)
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: chartStride(for: snapshot))) { _ in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .frame(height: 220)
                    .accessibilityIdentifier("insights-activity-chart")

                    HStack(spacing: 16) {
                        InsightLegendItem(title: "Tasks", color: .indigo, symbol: "square.fill")
                        InsightLegendItem(title: "Habit logs", color: .teal, symbol: "circle.fill")
                        InsightLegendItem(title: "Slips", color: .orange, symbol: "diamond.fill")
                    }
                } else {
                    InsightEmptyCard(
                        symbol: "chart.bar.xaxis",
                        title: "No chart activity",
                        message: "Completed tasks and recorded habit events will appear here."
                    )
                }
            }
            .insightCard()
        }
    }

    private func patternSection(snapshot: InsightsSnapshot) -> some View {
        InsightSection(title: "Patterns", subtitle: "Facts appear only after the minimum sample size is reached") {
            VStack(spacing: 10) {
                if snapshot.patterns.isEmpty {
                    InsightEmptyCard(
                        symbol: "ellipsis",
                        title: "No repeatable pattern yet",
                        message: patternRequirementMessage
                    )
                } else {
                    ForEach(snapshot.patterns) { finding in
                        InsightFindingRow(finding: finding)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func habitBreakdownSection(snapshot: InsightsSnapshot) -> some View {
        if let habitSnapshot = selectedHabitSnapshot(in: snapshot) {
            InsightSection(
                title: habitSnapshot.name,
                subtitle: selectedHabit?.trackingTitle ?? habitSnapshot.type.title
            ) {
                VStack(spacing: 0) {
                    let rows = breakdownRows(for: habitSnapshot, snapshot: snapshot)
                    ForEach(rows) { row in
                        InsightBreakdownRow(row: row)
                        if row.id != rows.last?.id {
                            Divider()
                        }
                    }
                }
                .insightCard()
            }
        } else if !activeHabits.isEmpty {
            InsightSection(title: "Habit Breakdown", subtitle: "Select a habit for its full analysis") {
                VStack(spacing: 10) {
                    ForEach(activeHabits) { habit in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedHabitID = habit.id
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: habit.symbolName)
                                    .foregroundStyle(habit.tint.color)
                                    .frame(width: 32, height: 32)
                                    .background(habit.tint.color.opacity(0.12), in: Circle())

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(habit.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(
                                        habit.isHealthPowered
                                            ? healthHabitSummary(habit)
                                            : HabitTrackingManager.summary(for: habit)
                                    )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(14)
                            .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("insights-select-habit-\(habit.id)")
                    }
                }
            }
        }
    }

    private func dataCoverageSection(snapshot: InsightsSnapshot) -> some View {
        InsightSection(title: "Data Used", subtitle: "How these results were calculated") {
            VStack(alignment: .leading, spacing: 10) {
                Label(coverageDescription(for: snapshot), systemImage: "number")
                Label("Today is excluded from historical completion rates until the day ends.", systemImage: "calendar.badge.clock")
                Label("Patterns are associations in your records, not proof of cause.", systemImage: "equal.circle")
                Label("Everything is calculated privately on this device.", systemImage: "lock.fill")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .insightCard()
        }
    }

    private func metricCards(for snapshot: InsightsSnapshot) -> [InsightMetricCardModel] {
        if let habit = selectedHabitSnapshot(in: snapshot) {
            if selectedHabit?.isHealthPowered == true {
                return healthMetricCards(for: habit, snapshot: snapshot)
            }

            var cards = [
                InsightMetricCardModel(
                    id: "current",
                    title: currentMetricTitle(for: habit),
                    value: currentMetricValue(for: habit),
                    detail: "Current status",
                    symbol: selectedHabit?.symbolName ?? "timer",
                    tint: selectedHabit?.tint.color ?? .indigo
                )
            ]

            if let bestDays = habit.bestDays {
                cards.append(
                    InsightMetricCardModel(
                        id: "best",
                        title: "Personal best",
                        value: "\(bestDays)d",
                        detail: "All recorded history",
                        symbol: "chart.line.uptrend.xyaxis",
                        tint: .teal
                    )
                )
            } else if habit.type == .event {
                cards.append(
                    InsightMetricCardModel(
                        id: "occurrences",
                        title: "Occurrences",
                        value: "\(habit.occurrenceCount)",
                        detail: "Selected period",
                        symbol: "arrow.clockwise.circle",
                        tint: .blue
                    )
                )
            } else if habit.type == .positiveStreak, let rate = habit.completionRate {
                cards.append(rateCard(id: "habit-rate", title: "Consistency", rate: rate, detail: "\(habit.completedDays) of \(habit.eligibleDays) days"))
            }

            if let measurement = habit.measurementStatistics {
                cards.append(
                    InsightMetricCardModel(
                        id: "measurement",
                        title: measurement.definition.name,
                        value: measurement.definition.compactFormatted(measurement.total),
                        detail: "Total across \(measurement.measuredCount) measured entries",
                        symbol: measurement.definition.symbolName,
                        tint: selectedHabit?.tint.color ?? .indigo
                    )
                )
            }

            cards.append(plannerCard(for: snapshot))
            cards.append(
                InsightMetricCardModel(
                    id: "slips",
                    title: "Slips",
                    value: "\(habit.slipCount)",
                    detail: "\(habit.restartingSlipCount) restarted the streak",
                    symbol: "arrow.counterclockwise.circle",
                    tint: .orange
                )
            )
            return Array(cards.prefix(4))
        }

        return [
            InsightMetricCardModel(
                id: "habits",
                title: "Active habits",
                value: "\(activeHabits.count)",
                detail: selectedHabitID == nil ? "All tracked styles" : "Selected scope",
                symbol: "square.grid.2x2",
                tint: .indigo
            ),
            snapshot.habitCompletionRate.map {
                rateCard(
                    id: "habit-rate",
                    title: "Consistency",
                    rate: $0,
                    detail: "\(snapshot.completedHabitDays) of \(snapshot.eligibleHabitDays) eligible days"
                )
            } ?? InsightMetricCardModel(
                id: "logs",
                title: "Habit logs",
                value: "\(snapshot.activity.reduce(0) { $0 + $1.habitLogs })",
                detail: "Selected period",
                symbol: "checkmark.circle",
                tint: .teal
            ),
            plannerCard(for: snapshot),
            InsightMetricCardModel(
                id: "slips",
                title: "Slips",
                value: "\(snapshot.slipCount)",
                detail: "Selected period",
                symbol: "arrow.counterclockwise.circle",
                tint: .orange
            )
        ]
    }

    private func plannerCard(for snapshot: InsightsSnapshot) -> InsightMetricCardModel {
        if let rate = snapshot.planner.completionRate {
            return rateCard(
                id: "planner",
                title: "Planner",
                rate: rate,
                detail: "\(snapshot.planner.completedTasks) of \(snapshot.planner.scheduledTasks) tasks"
            )
        }
        return InsightMetricCardModel(
            id: "planner",
            title: "Planner",
            value: "—",
            detail: "No completed days yet",
            symbol: "checklist",
            tint: .blue
        )
    }

    private func rateCard(
        id: String,
        title: String,
        rate: Double,
        detail: String
    ) -> InsightMetricCardModel {
        InsightMetricCardModel(
            id: id,
            title: title,
            value: "\(Int((rate * 100).rounded()))%",
            detail: detail,
            symbol: "percent",
            tint: .teal
        )
    }

    private func currentMetricTitle(for habit: HabitInsightSnapshot) -> String {
        switch habit.type {
        case .abstinence, .frequency, .count, .duration: "Current segment"
        case .positiveStreak: "Current streak"
        case .event: "Since last time"
        case .sinceDate: "Time since"
        case .countdown: "Time remaining"
        }
    }

    private func currentMetricValue(for habit: HabitInsightSnapshot) -> String {
        if let remainingDays = habit.remainingDays {
            return "\(remainingDays)d"
        }
        return "\(habit.currentDays ?? 0)d"
    }

    private func breakdownRows(
        for habit: HabitInsightSnapshot,
        snapshot: InsightsSnapshot
    ) -> [InsightBreakdownRowModel] {
        if selectedHabit?.isHealthPowered == true {
            var rows: [InsightBreakdownRowModel] = [
                .init(id: "current", title: "Current streak", value: currentMetricValue(for: habit)),
                .init(id: "best", title: "Personal best", value: "\(habit.bestDays ?? 0) days"),
                .init(
                    id: "goal-days",
                    title: "Goal days",
                    value: "\(habit.completedDays) of \(habit.eligibleDays)"
                ),
                .init(
                    id: "average-steps",
                    title: "Average steps",
                    value: habit.averageSteps?.formatted() ?? "—"
                ),
                .init(
                    id: "highest-steps",
                    title: "Highest day",
                    value: habit.highestSteps?.formatted() ?? "—"
                ),
                .init(
                    id: "recorded-days",
                    title: "Days with Health data",
                    value: "\(habit.recordedStepDays)"
                )
            ]
            if snapshot.planner.linkedTasks > 0 {
                rows.append(.init(id: "linked-tasks", title: "Linked tasks analyzed", value: "\(snapshot.planner.linkedTasks)"))
            }
            return rows
        }

        var rows = [
            InsightBreakdownRowModel(
                id: "current",
                title: currentMetricTitle(for: habit),
                value: currentMetricValue(for: habit)
            )
        ]

        if let bestDays = habit.bestDays {
            rows.append(.init(id: "best", title: "Personal best", value: "\(bestDays) days"))
        }
        if let rate = habit.completionRate {
            rows.append(
                .init(
                    id: "consistency",
                    title: "Consistency",
                    value: "\(Int((rate * 100).rounded()))% · \(habit.completedDays)/\(habit.eligibleDays)"
                )
            )
        }
        if habit.type == .event {
            rows.append(.init(id: "occurrences", title: "Occurrences", value: "\(habit.occurrenceCount)"))
            if let average = habit.averageIntervalDays {
                rows.append(.init(id: "average-interval", title: "Average interval", value: decimalDays(average)))
            }
        }
        if habit.type == .abstinence || habit.slipCount > 0 {
            rows.append(.init(id: "slips", title: "Recorded slips", value: "\(habit.slipCount)"))
            rows.append(
                .init(
                    id: "non-restarting",
                    title: "Without restart",
                    value: "\(habit.slipCount - habit.restartingSlipCount)"
                )
            )
            if let median = habit.medianSegmentDays {
                rows.append(.init(id: "median-segment", title: "Median segment", value: decimalDays(median)))
            }
        }
        if let measurement = habit.measurementStatistics {
            rows.append(
                .init(
                    id: "measurement-total",
                    title: "\(measurement.definition.name) total",
                    value: measurement.definition.formatted(measurement.total)
                )
            )
            rows.append(
                .init(
                    id: "measurement-average",
                    title: "Average per entry",
                    value: measurement.definition.formatted(measurement.average)
                )
            )
            rows.append(
                .init(
                    id: "measurement-largest",
                    title: "Largest entry",
                    value: measurement.definition.formatted(measurement.maximum)
                )
            )
            rows.append(
                .init(
                    id: "measurement-recorded",
                    title: "Measured entries",
                    value: "\(measurement.measuredCount)"
                )
            )
        }
        if snapshot.planner.linkedTasks > 0 {
            rows.append(.init(id: "linked-tasks", title: "Linked tasks analyzed", value: "\(snapshot.planner.linkedTasks)"))
        }
        return rows
    }

    private func decimalDays(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value < 10 ? 1 : 0))) + " days"
    }

    private func hasChartActivity(in snapshot: InsightsSnapshot) -> Bool {
        snapshot.activity.contains {
            $0.habitLogs > 0 || $0.slips > 0 || $0.completedTasks > 0 || $0.scheduledTasks > 0
        }
    }

    private func chartStride(for snapshot: InsightsSnapshot) -> Int {
        max(1, snapshot.activity.count / 6)
    }

    private func rangeDescription(for snapshot: InsightsSnapshot) -> String {
        let start = snapshot.range.start.formatted(.dateTime.month(.abbreviated).day().year())
        let finalDay = calendar.date(byAdding: .day, value: -1, to: snapshot.range.endExclusive)
            ?? snapshot.range.endExclusive
        let end = finalDay.formatted(.dateTime.month(.abbreviated).day().year())
        return "Data from \(start) through \(end)"
    }

    private var comparisonSubtitle: String {
        period == .allTime
            ? "All recorded history"
            : "Compared with the immediately preceding \(period.dayCount ?? 0) days"
    }

    private var patternRequirementMessage: String {
        "Patterns require at least \(InsightsEngine.minimumHabitDays) eligible habit days, \(InsightsEngine.minimumPlannerTasks) scheduled tasks, or \(InsightsEngine.minimumSlipEvents) slips."
    }

    private func coverageDescription(for snapshot: InsightsSnapshot) -> String {
        var parts: [String] = []
        if snapshot.eligibleHabitDays > 0 {
            parts.append("\(snapshot.eligibleHabitDays) eligible habit days")
        }
        if snapshot.planner.scheduledTasks > 0 {
            parts.append("\(snapshot.planner.scheduledTasks) scheduled tasks")
        }
        if snapshot.slipCount > 0 {
            parts.append("\(snapshot.slipCount) slips")
        }
        if snapshot.occurrenceCount > 0 {
            parts.append("\(snapshot.occurrenceCount) occurrences")
        }
        return parts.isEmpty ? "No qualifying historical records in this period." : "Based on " + parts.joined(separator: ", ") + "."
    }

    private var healthRefreshKey: String {
        "\(period.rawValue)-\(selectedHabitID?.uuidString ?? "all")-\(activeHabits.filter(\.isHealthPowered).count)"
    }

    private func refreshHealthRangeIfNeeded() async {
        let healthHabits = activeHabits.filter(\.isHealthPowered)
        guard !healthHabits.isEmpty, healthKitManager.hasRequestedAccess else { return }

        let scoped = selectedHabitID.map { id in healthHabits.filter { $0.id == id } } ?? healthHabits
        guard !scoped.isEmpty else { return }
        let range = InsightsEngine.dateRange(
            for: period,
            habits: scoped,
            tasks: plannerTasks,
            now: .now,
            calendar: calendar
        )
        let start = InsightsEngine.previousRange(for: period, current: range, calendar: calendar)?.start
            ?? range.start
        await healthKitManager.refresh(from: start, to: range.endExclusive)
    }

    private func healthMetricCards(
        for habit: HabitInsightSnapshot,
        snapshot: InsightsSnapshot
    ) -> [InsightMetricCardModel] {
        [
            InsightMetricCardModel(
                id: "health-average",
                title: "Daily average",
                value: habit.averageSteps?.formatted() ?? "—",
                detail: "\(habit.recordedStepDays) days with Health data",
                symbol: "figure.walk",
                tint: selectedHabit?.tint.color ?? .indigo
            ),
            habit.completionRate.map {
                rateCard(
                    id: "health-goal-rate",
                    title: "Goal days",
                    rate: $0,
                    detail: "\(habit.completedDays) of \(habit.eligibleDays) scheduled days"
                )
            } ?? InsightMetricCardModel(
                id: "health-goal-rate",
                title: "Goal days",
                value: "—",
                detail: "Not enough completed days yet",
                symbol: "target",
                tint: .teal
            ),
            InsightMetricCardModel(
                id: "health-best",
                title: "Highest day",
                value: habit.highestSteps?.formatted() ?? "—",
                detail: "Selected period",
                symbol: "chart.line.uptrend.xyaxis",
                tint: .blue
            ),
            plannerCard(for: snapshot)
        ]
    }

    private func healthHabitSummary(_ habit: Habit) -> String {
        let today = healthKitManager.steps(on: .now)
        guard let progress = HealthGoalManager.progress(for: habit, on: .now, stepCount: today) else {
            return "Apple Health step goal"
        }
        guard let value = progress.value else { return "No step data available" }
        return "\(value.formatted()) of \(progress.target.formatted()) steps"
    }
}

private struct InsightSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.bold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content
        }
    }
}

private struct InsightMetricCardModel: Identifiable {
    let id: String
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color
}

private struct InsightMetricCard: View {
    let card: InsightMetricCardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: card.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(card.tint)
                .frame(width: 30, height: 30)
                .background(card.tint.opacity(0.12), in: Circle())

            Text(card.value)
                .font(.title2.monospacedDigit().weight(.bold))
                .minimumScaleFactor(0.75)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .font(.subheadline.weight(.semibold))
                Text(card.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        .insightCard()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("insights-metric-\(card.id)")
    }
}

private struct InsightFindingRow: View {
    let finding: InsightFinding

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: finding.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.indigo)
                .frame(width: 32, height: 32)
                .background(.indigo.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(finding.title)
                    .font(.subheadline.weight(.semibold))
                Text(finding.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .insightCard()
        .accessibilityElement(children: .combine)
    }
}

private struct InsightEmptyCard: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Color.secondary.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .insightCard()
    }
}

private struct InsightLegendItem: View {
    let title: String
    let color: Color
    let symbol: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(color)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct InsightBreakdownRowModel: Identifiable {
    let id: String
    let title: String
    let value: String
}

private struct InsightBreakdownRow: View {
    let row: InsightBreakdownRowModel

    var body: some View {
        HStack {
            Text(row.title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(row.value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 10)
    }
}

private extension View {
    func insightCard() -> some View {
        padding(14)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.secondary.opacity(0.08))
            }
    }
}

#Preview {
    NavigationStack {
        InsightsView()
    }
    .modelContainer(PreviewData.container)
    .environmentObject(HealthKitManager())
}
