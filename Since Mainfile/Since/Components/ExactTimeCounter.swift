import SwiftUI

struct ExactTimeCounter: View {
    let startAt: Date
    @ScaledMetric(relativeTo: .largeTitle) private var counterFontSize: CGFloat = 64

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = ElapsedTime(from: startAt, to: context.date)

            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(elapsed.days)")
                        .font(.system(size: min(counterFontSize, 84), weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                    Text(elapsed.days == 1 ? "day" : "days")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Text(
                    "\(elapsed.hours.formatted(.number.precision(.integerLength(2)))) hours  ·  "
                    + "\(elapsed.minutes.formatted(.number.precision(.integerLength(2)))) minutes  ·  "
                    + "\(elapsed.seconds.formatted(.number.precision(.integerLength(2)))) seconds"
                )
                .font(.subheadline.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(elapsed.days) days, \(elapsed.hours) hours, \(elapsed.minutes) minutes")
        }
    }
}

struct ExactCountdownCounter: View {
    let targetAt: Date
    @ScaledMetric(relativeTo: .largeTitle) private var counterFontSize: CGFloat = 64

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = ElapsedTime(from: context.date, to: targetAt)
            let isComplete = context.date >= targetAt

            VStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(remaining.days)")
                        .font(.system(size: min(counterFontSize, 84), weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                    Text(remaining.days == 1 ? "day" : "days")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                if isComplete {
                    Label("The date has arrived", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Text(
                        "\(remaining.hours.formatted(.number.precision(.integerLength(2)))) hours  ·  "
                        + "\(remaining.minutes.formatted(.number.precision(.integerLength(2)))) minutes  ·  "
                        + "\(remaining.seconds.formatted(.number.precision(.integerLength(2)))) seconds"
                    )
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                isComplete
                    ? "Countdown complete"
                    : "\(remaining.days) days, \(remaining.hours) hours, \(remaining.minutes) minutes remaining"
            )
        }
    }
}
