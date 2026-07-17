import SwiftUI

struct OnboardingArrivalView: View {
    let stepIndex: Int
    let stepCount: Int
    let reduceMotion: Bool
    let onContinue: () -> Void

    @State private var selectedPrayer: Prayer = .fajr
    @State private var journeyStage: PrayerJourneyStage = .approaching
    @State private var sceneIsVisible = false
    @State private var demoTask: Task<Void, Never>?

    var body: some View {
        VaktOnboardingShell(
            stepIndex: stepIndex,
            stepCount: stepCount,
            eyebrow: L10n.string("onboarding.arrival.eyebrow"),
            title: L10n.string("onboarding.arrival.title"),
            bodyText: L10n.string("onboarding.arrival.body"),
            actionTitle: L10n.string("action.continue"),
            onContinue: onContinue
        ) {
            PrayerDayInstrument(
                selectedPrayer: $selectedPrayer,
                journeyStage: journeyStage,
                sceneIsVisible: sceneIsVisible,
                reduceMotion: reduceMotion,
                onManualSelection: { demoTask?.cancel() }
            )
        }
        .onAppear {
            withAnimation(reduceMotion ? .none : .easeOut(duration: 0.8)) {
                sceneIsVisible = true
            }
            startDemo()
        }
        .onDisappear { demoTask?.cancel() }
    }

    private func startDemo() {
        demoTask?.cancel()
        let prayers: [Prayer] = [.fajr, .dhuhr, .asr, .maghrib, .isha]

        demoTask = Task { @MainActor in
            while !Task.isCancelled {
                for prayer in prayers {
                    guard !Task.isCancelled else { return }
                    withAnimation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.88)) {
                        selectedPrayer = prayer
                        journeyStage = .approaching
                    }

                    if prayer == .asr {
                        for stage in PrayerJourneyStage.allCases {
                            guard !Task.isCancelled else { return }
                            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.48)) {
                                journeyStage = stage
                            }
                            try? await Task.sleep(for: .milliseconds(1_550))
                        }
                    } else {
                        try? await Task.sleep(for: .milliseconds(1_400))
                    }
                }
                try? await Task.sleep(for: .milliseconds(1_000))
            }
        }
    }
}

private enum PrayerJourneyStage: Int, CaseIterable {
    case approaching
    case prepare
    case pray
    case record

    var title: String {
        switch self {
        case .approaching: L10n.string("onboarding.arrival.stage.approaching")
        case .prepare: L10n.string("onboarding.arrival.stage.prepare")
        case .pray: L10n.string("onboarding.arrival.stage.pray")
        case .record: L10n.string("onboarding.arrival.stage.record")
        }
    }
}

struct VaktOnboardingShell<Scene: View>: View {
    let stepIndex: Int
    let stepCount: Int
    let eyebrow: String
    let title: String
    let bodyText: String
    let actionTitle: String
    let onContinue: () -> Void
    @ViewBuilder let scene: () -> Scene

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                OnboardingShellBackground()

                VStack(spacing: 0) {
                    VaktOnboardingStepHeader(stepIndex: stepIndex, stepCount: stepCount)
                        .padding(.horizontal, VaktSpace.lg)
                        .padding(.top, max(16, proxy.safeAreaInsets.top + 8))

                    scene()
                        .frame(height: min(400, max(326, proxy.size.height * 0.47)))
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(eyebrow.uppercased(with: VaktLocalization.appLocale))
                            .font(VaktFont.eyebrow(9))
                            .tracking(1.8)
                            .foregroundStyle(Color.vaktSecondary)

                        Text(title)
                            .font(VaktFont.title(29))
                            .foregroundStyle(Color.vaktPrimary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(bodyText)
                            .font(VaktFont.body(13))
                            .foregroundStyle(Color.vaktMuted)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, VaktSpace.lg)

                    Spacer(minLength: 14)

                    VaktOnboardingPrimaryAction(title: actionTitle, action: onContinue)
                        .padding(.horizontal, VaktSpace.lg)
                        .padding(.bottom, max(18, proxy.safeAreaInsets.bottom + 10))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

struct VaktOnboardingStepHeader: View {
    let stepIndex: Int
    let stepCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(OnboardingStepNumberFormatter.string(stepIndex + 1))
                .font(VaktFont.caption(10))
                .foregroundStyle(Color.vaktPrimary)
                .monospacedDigit()

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.vaktBorderStrong.opacity(0.5))

                    Capsule()
                        .fill(Color.vaktPrimary.opacity(0.88))
                        .frame(
                            width: proxy.size.width * CGFloat(stepIndex + 1) / CGFloat(max(1, stepCount))
                        )
                }
            }
            .frame(height: 2)

            Text(OnboardingStepNumberFormatter.string(stepCount))
                .font(VaktFont.caption(10))
                .foregroundStyle(Color.vaktMuted)
                .monospacedDigit()
        }
        .frame(height: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.formatString("onboarding.step_accessibility", stepIndex + 1, stepCount)
        )
    }
}

private enum OnboardingStepNumberFormatter {
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = VaktLocalization.appLocale
        formatter.numberStyle = .decimal
        formatter.minimumIntegerDigits = 2
        formatter.maximumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        return formatter
    }()

    static func string(_ value: Int) -> String {
        formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

struct VaktOnboardingPrimaryAction: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(VaktFont.button(15))

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Color.vaktDeep)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.vaktPrimary)
            .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
        }
        .buttonStyle(VaktPressStyle())
        .accessibilityLabel(title)
    }
}

private struct PrayerDayInstrument: View {
    @Binding var selectedPrayer: Prayer
    let journeyStage: PrayerJourneyStage
    let sceneIsVisible: Bool
    let reduceMotion: Bool
    let onManualSelection: () -> Void

    private var moments: [PrayerMoment] {
        [
            PrayerMoment(
                prayer: .fajr,
                hour: 5,
                minute: 18,
                context: L10n.string("onboarding.arrival.context.before_sunrise")
            ),
            PrayerMoment(
                prayer: .dhuhr,
                hour: 13,
                minute: 12,
                context: L10n.string("onboarding.arrival.context.midday")
            ),
            PrayerMoment(
                prayer: .asr,
                hour: 17,
                minute: 8,
                context: L10n.timeRemaining(minutes: 134)
            ),
            PrayerMoment(
                prayer: .maghrib,
                hour: 20,
                minute: 31,
                context: L10n.string("onboarding.arrival.context.sunset")
            ),
            PrayerMoment(
                prayer: .isha,
                hour: 22,
                minute: 4,
                context: L10n.string("onboarding.arrival.context.quiet_night")
            )
        ]
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                DayInstrumentLight(selectedIndex: selectedIndex, reduceMotion: reduceMotion)

                VStack(spacing: 0) {
                    ForEach(Array(moments.enumerated()), id: \.element.id) { index, moment in
                        prayerRow(moment, index: index)
                    }
                }
                .padding(.horizontal, VaktSpace.lg)
                .padding(.vertical, 12)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .opacity(sceneIsVisible ? 1 : 0)
        .offset(y: sceneIsVisible || reduceMotion ? 0 : 10)
    }

    private var selectedIndex: Int {
        moments.firstIndex { $0.prayer == selectedPrayer } ?? 2
    }

    private func prayerRow(_ moment: PrayerMoment, index: Int) -> some View {
        let selected = moment.prayer == selectedPrayer

        return Button {
            guard selectedPrayer != moment.prayer else { return }
            onManualSelection()
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(reduceMotion ? .none : .spring(response: 0.48, dampingFraction: 0.86)) {
                selectedPrayer = moment.prayer
            }
        } label: {
            HStack(spacing: 14) {
                Capsule()
                    .fill(selected ? Color.vaktPrimary : Color.vaktBorderStrong.opacity(0.75))
                    .frame(width: 2, height: selected ? 52 : 18)

                VStack(alignment: .leading, spacing: selected ? 6 : 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(moment.prayer.localizedName)
                            .font(selected ? VaktFont.title(22) : VaktFont.body(13))
                            .foregroundStyle(selected ? Color.vaktPrimary : Color.vaktMuted)

                        Spacer()

                        Text(moment.time)
                            .font(selected ? VaktFont.timeDisplay(27) : VaktFont.body(13))
                            .foregroundStyle(selected ? Color.vaktPrimary : Color.vaktMuted.opacity(0.8))
                            .monospacedDigit()
                    }

                    if selected, moment.prayer == .asr {
                        PrayerJourneyProgress(stage: journeyStage)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    } else if selected {
                        HStack {
                            Text(
                                L10n.string("onboarding.arrival.instrument.time_of_day")
                                    .uppercased(with: VaktLocalization.appLocale)
                            )
                                .font(VaktFont.eyebrow(8))
                                .tracking(1.3)

                            Spacer()

                            Text(moment.context)
                                .font(VaktFont.caption(9))
                        }
                        .foregroundStyle(Color.vaktSecondary)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .padding(.horizontal, 14)
            .frame(height: selected ? 82 : 48)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.vaktElevated.opacity(0.42))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.vaktBorderStrong.opacity(0.55), lineWidth: 0.5)
                        }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(VaktPressStyle())
        .accessibilityLabel(
            L10n.formatString(
                "onboarding.arrival.moment_accessibility",
                moment.prayer.localizedName,
                moment.time,
                moment.context
            )
        )
    }
}

private struct PrayerJourneyProgress: View {
    let stage: PrayerJourneyStage

    var body: some View {
        HStack(spacing: 5) {
            ForEach(PrayerJourneyStage.allCases, id: \.rawValue) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Capsule()
                        .fill(item.rawValue <= stage.rawValue ? Color.vaktPrimary : Color.vaktBorderStrong)
                        .frame(height: item == stage ? 2 : 1)

                    Text(item.title.uppercased(with: VaktLocalization.appLocale))
                        .font(VaktFont.eyebrow(6))
                        .tracking(0.5)
                        .foregroundStyle(item == stage ? Color.vaktPrimary : Color.vaktMuted.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: stage)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.formatString("onboarding.arrival.journey_accessibility", stage.title)
        )
    }
}

private struct PrayerMoment: Identifiable {
    let prayer: Prayer
    let hour: Int
    let minute: Int
    let context: String

    var id: Prayer { prayer }

    var time: String {
        OnboardingDemoTimeFormatter.string(hour: hour, minute: minute)
    }
}

enum OnboardingDemoTimeFormatter {
    static func string(hour: Int, minute: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(
            from: DateComponents(year: 2001, month: 1, day: 1, hour: hour, minute: minute)
        ) ?? Date(timeIntervalSince1970: 0)
        let formatter = DateFormatter()
        formatter.locale = VaktLocalization.appLocale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct DayInstrumentLight: View {
    let selectedIndex: Int
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let breath = CGFloat((sin(time * 0.55) + 1) / 2)
                let rowHeight = size.height / 5
                let centerY = rowHeight * (CGFloat(selectedIndex) + 0.5)
                let glowRect = CGRect(
                    x: size.width * 0.08,
                    y: centerY - rowHeight * 0.8,
                    width: size.width * 0.84,
                    height: rowHeight * 1.6
                )

                context.fill(
                    Path(ellipseIn: glowRect),
                    with: .radialGradient(
                        Gradient(colors: [
                            Color.vaktGlow.opacity(0.08 + Double(breath) * 0.025),
                            Color.clear
                        ]),
                        center: CGPoint(x: glowRect.midX, y: glowRect.midY),
                        startRadius: 2,
                        endRadius: glowRect.width * 0.5
                    )
                )
            }
        }
        .animation(.easeInOut(duration: 0.45), value: selectedIndex)
        .accessibilityHidden(true)
    }
}

struct OnboardingShellBackground: View {
    var body: some View {
        ZStack {
            Color.vaktDeep.ignoresSafeArea()

            LinearGradient(
                colors: [Color(hex: "#111A2A"), Color.vaktBg, Color.vaktDeep],
                startPoint: .topLeading,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color.vaktGlow.opacity(0.06), .clear],
                center: UnitPoint(x: 0.72, y: 0.24),
                startRadius: 8,
                endRadius: 310
            )
            .ignoresSafeArea()
        }
    }
}
