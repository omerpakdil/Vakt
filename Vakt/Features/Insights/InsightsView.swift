import SwiftUI

struct InsightsView: View {
    @ObservedObject var reflectionStore: PrayerReflectionStore
    @State private var selectedPeriod: ReflectionPeriod = .week

    var body: some View {
        let summary = reflectionStore.summary(for: selectedPeriod)

        ZStack {
            Color.vaktBg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: VaktSpace.lg) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(periodTitle)
                            .font(VaktFont.timeDisplay(32))
                            .foregroundStyle(Color.vaktPrimary)
                            .tracking(-1)
                            .contentTransition(.opacity)

                        Text(periodSubtitle)
                            .font(VaktFont.body(13))
                            .foregroundStyle(Color.vaktMuted)
                            .contentTransition(.opacity)
                    }
                    .padding(.top, VaktSpace.xxl)

                    periodSelector
                    if selectedPeriod == .month {
                        monthGrid(summary)
                    } else {
                        periodGrid(summary)
                    }

                    VStack(spacing: VaktSpace.sm) {
                        InsightStat(label: "Marked", value: reflectedValue(summary))
                        InsightStat(label: "Prayed", value: prayedValue(summary))
                        InsightStat(label: "Prayed later", value: laterValue(summary))
                        InsightStat(label: "Saf with you", value: withYouValue(summary))
                    }

                    reflectionFooter
                }
                .padding(.horizontal, VaktSpace.lg)
                .padding(.bottom, VaktSpace.xl)
            }
        }
    }

    private var periodTitle: String {
        switch selectedPeriod {
        case .week:
            return "This week"
        case .month:
            return "This month"
        case .year:
            return "This year"
        }
    }

    private var periodSubtitle: String {
        switch selectedPeriod {
        case .week:
            return "A private look at the prayers you marked this week."
        case .month:
            return "A gentle view of your prayer rhythm this month."
        case .year:
            return "A wider view of the months you came back to salah."
        }
    }

    private var periodSelector: some View {
        HStack(spacing: 4) {
            ForEach(ReflectionPeriod.allCases) { period in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedPeriod = period
                    }
                } label: {
                    Text(period.title)
                        .font(VaktFont.caption(11))
                        .foregroundStyle(selectedPeriod == period ? Color.vaktBg : Color.vaktMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            Capsule()
                                .fill(selectedPeriod == period ? Color.vaktPrimary : Color.clear)
                        )
                }
                .buttonStyle(VaktPressStyle())
            }
        }
        .padding(4)
        .background(Color.vaktSurface)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.vaktBorder, lineWidth: 0.5)
        )
    }

    private var reflectionFooter: some View {
        VStack(spacing: 8) {
            if let latest = reflectionStore.latestEntry {
                Text("Last entry · \(latest.prayer.displayName) · \(latest.outcome.title)")
                    .font(VaktFont.caption(11))
                    .foregroundStyle(Color.vaktMuted)
                    .tracking(0.35)
            }

            Text("Your entries stay private on this device.\nThey are here only to help you return.")
                .font(VaktFont.caption(11))
                .foregroundStyle(Color.vaktShadow)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .lineSpacing(4)
                .padding(.top, VaktSpace.xs)
        }
    }

    private func reflectedValue(_ summary: ReflectionPeriodSummary) -> String {
        let count = summary.reflectedCount
        return count == 0 ? "-" : "\(count)"
    }

    private func prayedValue(_ summary: ReflectionPeriodSummary) -> String {
        let count = summary.startedTogetherCount
        return count == 0 ? "-" : "\(count)"
    }

    private func laterValue(_ summary: ReflectionPeriodSummary) -> String {
        let count = summary.laterCount
        return count == 0 ? "-" : "\(count)"
    }

    private func withYouValue(_ summary: ReflectionPeriodSummary) -> String {
        guard let count = summary.averageCompanionCount else { return "-" }
        return "\(max(count - 1, 6)) others"
    }

    private func periodGrid(_ summary: ReflectionPeriodSummary) -> some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(summary.buckets) { bucket in
                let isCurrent = isCurrentBucket(bucket)
                let barHeight = isCurrent ? CGFloat(66) : CGFloat(58)

                VStack(spacing: 5) {
                    Text(bucket.label)
                        .font(VaktFont.caption(selectedPeriod == .month ? 7 : 9))
                        .foregroundStyle(isCurrent ? Color.vaktPrimary : Color.vaktShadow)
                        .tracking(0.3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.vaktSurface)
                            .frame(height: barHeight)

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(isCurrent ? Color.vaktPrimary : bucket.rhythmCount > 0 ? Color.vaktAccent : Color.vaktBorderStrong)
                            .frame(height: max(isCurrent ? 8 : 4, barHeight * bucket.fillRatio))
                    }

                    Text(bucket.rhythmCount == 0 ? "-" : "\(bucket.rhythmCount)")
                        .font(VaktFont.caption(selectedPeriod == .month ? 7 : 9))
                        .foregroundStyle(isCurrent ? Color.vaktPrimary : bucket.rhythmCount == 0 ? Color.vaktShadow : Color.vaktMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func monthGrid(_ summary: ReflectionPeriodSummary) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 10),
            spacing: 7
        ) {
            ForEach(summary.buckets) { bucket in
                let isCurrent = isCurrentBucket(bucket)

                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isCurrent ? Color.vaktPrimary.opacity(0.86) : bucket.rhythmCount > 0 ? Color.vaktAccent.opacity(0.72) : Color.vaktSurface)
                        .frame(height: isCurrent ? 22 : 18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(isCurrent ? Color.vaktGlow.opacity(0.48) : Color.vaktBorder, lineWidth: isCurrent ? 0.7 : 0.45)
                        )
                        .opacity(0.38 + Double(bucket.fillRatio) * 0.62)

                    Text(bucket.label)
                        .font(VaktFont.caption(7))
                        .foregroundStyle(isCurrent ? Color.vaktPrimary : Color.vaktShadow)
                        .lineLimit(1)
                }
            }
        }
    }

    private func isCurrentBucket(_ bucket: ReflectionPeriodBucket) -> Bool {
        let calendar = Calendar.current

        switch selectedPeriod {
        case .week, .month:
            return calendar.isDateInToday(bucket.date)
        case .year:
            return calendar.isDate(bucket.date, equalTo: Date(), toGranularity: .month)
        }
    }
}

private struct InsightStat: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(VaktFont.body(13))
                .foregroundStyle(Color.vaktMuted)
                .lineLimit(2)
                .minimumScaleFactor(0.86)

            Spacer()

            Text(value)
                .font(VaktFont.title(20))
                .foregroundStyle(Color.vaktGlow)
                .tracking(-0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(14)
        .background(Color.vaktSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.vaktBorder, lineWidth: 0.5)
        )
    }
}
