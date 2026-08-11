import SwiftUI

struct HabitHeroCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let habit: Habit
    let now: Date
    var healthStepTotals: [Date: Int] = [:]
    var healthAccessState: HealthKitManager.AccessState = .notRequested
    var healthLastUpdated: Date?
    let openDetails: () -> Void
    let performPrimaryAction: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var streakFontSize: CGFloat = 64

    var body: some View {
        VStack(spacing: 24) {
            header

            if habit.isHealthPowered {
                healthStepsContent
            } else {
                switch habit.type {
                case .abstinence:
                    abstinenceContent
                case .positiveStreak:
                    positiveStreakContent
                case .event:
                    lastOccurrenceContent
                case .sinceDate:
                    sinceDateContent
                case .countdown:
                    countdownContent
                case .frequency, .count, .duration:
                    abstinenceContent
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(
                    color: colorScheme == .light ? .black.opacity(0.06) : .clear,
                    radius: 18,
                    y: 8
                )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(habit.tint.color.opacity(colorScheme == .light ? 0.14 : 0.28))
        }
    }

    private var header: some View {
        Button(action: openDetails) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Label {
                        Text(habit.name)
                            .foregroundStyle(.primary)
                    } icon: {
                        Image(systemName: habit.symbolName)
                            .foregroundStyle(habit.tint.color)
                    }
                    .font(.headline)
                    Text(habit.trackingTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if habit.isHealthPowered {
                    Text("HEALTH")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(habit.tint.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(habit.tint.color.opacity(0.12), in: Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .frame(minHeight: 44)
        // The card lives inside a horizontally paging scroll view. Giving its
        // header tap priority keeps a deliberate tap from being swallowed as
        // the beginning of a page swipe on smaller devices.
        .highPriorityGesture(
            TapGesture().onEnded(openDetails)
        )
        .accessibilityLabel("View details for \(habit.name)")
        .accessibilityHint("Shows history, measurements, and settings")
    }

    private var healthStepsContent: some View {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: now)
        let steps = healthStepTotals[today]
        let progress = HealthGoalManager.progress(
            for: habit,
            on: today,
            stepCount: steps,
            calendar: calendar
        )

        return VStack(spacing: 17) {
            VStack(spacing: 4) {
                Text(steps?.formatted() ?? "—")
                    .font(.system(size: 54, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("of \((progress?.target ?? Int(habit.healthGoalValue ?? 8_000)).formatted()) steps")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            if let progress {
                ProgressView(value: progress.fraction)
                    .tint(progress.isReached ? .teal : habit.tint.color)

                HStack {
                    Text(progressStatus(progress))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(progress.isReached ? Color.teal : Color.secondary)
                    Spacer()
                    Text("\(Int((progress.fraction * 100).rounded()))%")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            healthWeekRow(calendar: calendar, today: today)

            switch healthAccessState {
            case .notRequested:
                Button(action: performPrimaryAction) {
                    Label("Connect Apple Health", systemImage: "heart.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(habit.tint.color)
            case .unavailable:
                Text("Apple Health is unavailable on this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .failed:
                Button(action: performPrimaryAction) {
                    Label("Try Health Again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(habit.tint.color)
            case .ready:
                if steps == nil {
                    Button(action: performPrimaryAction) {
                        Label("Refresh Steps", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(habit.tint.color)
                } else if let healthLastUpdated {
                    Text("Updated \(healthLastUpdated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityIdentifier("health-steps-hero-card")
    }

    private func healthWeekRow(calendar: Calendar, today: Date) -> some View {
        HStack(spacing: 10) {
            ForEach((0..<7).reversed(), id: \.self) { offset in
                let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
                let value = healthStepTotals[calendar.startOfDay(for: date)]
                let progress = HealthGoalManager.progress(
                    for: habit,
                    on: date,
                    stepCount: value,
                    calendar: calendar
                )

                VStack(spacing: 5) {
                    Text(date.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: healthDaySymbol(progress))
                        .font(.caption)
                        .foregroundStyle(healthDayTint(progress))
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func progressStatus(_ progress: HealthGoalProgress) -> String {
        if !progress.isScheduled { return "Rest day" }
        if progress.isReached { return "Goal reached" }
        if progress.value == nil { return "No step data available" }
        return "\(progress.remaining.formatted()) remaining"
    }

    private func healthDaySymbol(_ progress: HealthGoalProgress?) -> String {
        guard let progress, progress.isScheduled else { return "minus" }
        if progress.isReached { return "circle.fill" }
        if let value = progress.value, value > 0 { return "circle.lefthalf.filled" }
        return "circle"
    }

    private func healthDayTint(_ progress: HealthGoalProgress?) -> Color {
        guard let progress, progress.isScheduled else { return Color.gray.opacity(0.45) }
        return progress.isReached ? habit.tint.color : .secondary
    }

    private var abstinenceContent: some View {
        let startAt = ElapsedTimeCalculator.currentStart(for: habit)

        return VStack(spacing: 20) {
            ExactTimeCounter(startAt: startAt)
            elapsedSupportingContent(since: startAt)

            Button(action: performPrimaryAction) {
                Label("Record a slip", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(habit.tint.color)
        }
    }

    private var positiveStreakContent: some View {
        let streak = HabitTrackingManager.dailyStreak(for: habit, now: now)
        let isCompletedToday = HabitTrackingManager.isCompleted(habit, on: now)

        return VStack(spacing: 18) {
            VStack(spacing: 5) {
                Text("\(streak.current)")
                    .font(.system(size: min(streakFontSize, 84), weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text("day streak")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: 12) {
                metric(title: "Best", value: "\(streak.best) days")
                metric(title: "Completed", value: "\(streak.totalCompletions)")
            }

            Button(action: performPrimaryAction) {
                Label(
                    isCompletedToday ? "Completed today" : "Mark today complete",
                    systemImage: isCompletedToday ? "checkmark.circle.fill" : "circle"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(isCompletedToday ? .teal : habit.tint.color)
            .accessibilityHint(isCompletedToday ? "Double tap to undo today’s completion" : "")
        }
    }

    private var lastOccurrenceContent: some View {
        let lastOccurrence = HabitTrackingManager.latestOccurrence(for: habit)

        return VStack(spacing: 20) {
            ExactTimeCounter(startAt: lastOccurrence)

            Text("Since \(lastOccurrence.formatted(date: .abbreviated, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button(action: performPrimaryAction) {
                Label("Log it happened now", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(habit.tint.color)
        }
    }

    private var sinceDateContent: some View {
        VStack(spacing: 18) {
            ExactTimeCounter(startAt: habit.startAt)
            elapsedSupportingContent(since: habit.startAt)
        }
    }

    private var countdownContent: some View {
        VStack(spacing: 18) {
            ExactCountdownCounter(targetAt: habit.startAt)
            Text("Until \(habit.startAt.formatted(date: .long, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func elapsedSupportingContent(since startAt: Date) -> some View {
        let elapsed = ElapsedTime(from: startAt, to: now)
        let milestone = MilestoneCalculator.progress(for: elapsed, customDay: habit.customMilestoneDays)

        return VStack(spacing: 6) {
            Text("Since \(startAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.subheadline)

            if milestone.isComplete, let completedDay = milestone.nextDay {
                Label("\(completedDay)-day milestone reached", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(habit.tint.color)
                    .padding(.top, 8)
            } else if let nextDay = milestone.nextDay {
                ProgressView(value: milestone.fractionComplete)
                    .tint(habit.tint.color)
                    .padding(.top, 8)

                Text("\(remainingDescription(for: milestone)) until \(nextDay) days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }

    private func remainingDescription(for milestone: MilestoneProgress) -> String {
        let days = milestone.remainingSeconds / 86_400
        let hours = (milestone.remainingSeconds % 86_400) / 3_600
        if days > 0 {
            return "\(days) \(days == 1 ? "day" : "days")"
        }
        return "\(max(1, hours)) \(hours == 1 ? "hour" : "hours")"
    }
}
