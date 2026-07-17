import SwiftUI

struct OnboardingClosingReminderView: View {
    let stepIndex: Int
    let stepCount: Int
    let reduceMotion: Bool
    let onContinue: () -> Void

    @State private var phase: ClosingReminderPhase = .approaching
    @State private var demoTask: Task<Void, Never>?

    var body: some View {
        VaktOnboardingShell(
            stepIndex: stepIndex,
            stepCount: stepCount,
            eyebrow: L10n.string("onboarding.closing_reminder.eyebrow"),
            title: L10n.string("onboarding.closing_reminder.title"),
            bodyText: L10n.string("onboarding.closing_reminder.body"),
            actionTitle: L10n.string("action.continue"),
            onContinue: onContinue
        ) {
            ClosingReminderScene(
                phase: phase,
                reduceMotion: reduceMotion,
                onAnswer: answer
            )
        }
        .onAppear { startDemo() }
        .onDisappear { demoTask?.cancel() }
    }

    private func startDemo() {
        demoTask?.cancel()
        demoTask = Task { @MainActor in
            while !Task.isCancelled {
                setPhase(.approaching)
                try? await Task.sleep(for: .milliseconds(1_800))
                setPhase(.question)
                try? await Task.sleep(for: .milliseconds(2_100))
                setPhase(.answeringPrayed)
                try? await Task.sleep(for: .milliseconds(950))
                setPhase(.saved)
                try? await Task.sleep(for: .milliseconds(2_650))
            }
        }
    }

    private func answer(prayed: Bool) {
        demoTask?.cancel()
        UISelectionFeedbackGenerator().selectionChanged()
        setPhase(prayed ? .answeringPrayed : .answeringMissed)

        demoTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            setPhase(prayed ? .saved : .noted)
        }
    }

    private func setPhase(_ nextPhase: ClosingReminderPhase) {
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? .none : .spring(response: 0.52, dampingFraction: 0.88)) {
            phase = nextPhase
        }
    }
}

private enum ClosingReminderPhase: Equatable {
    case approaching
    case question
    case answeringPrayed
    case answeringMissed
    case saved
    case noted
}

private struct ClosingReminderScene: View {
    let phase: ClosingReminderPhase
    let reduceMotion: Bool
    let onAnswer: (Bool) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ClosingTimeAtmosphere(phase: phase, reduceMotion: reduceMotion)

                timeline
                    .frame(width: 72)
                    .position(x: 58, y: proxy.size.height * 0.50)

                reminderContent
                    .frame(width: max(240, proxy.size.width - 132))
                    .position(x: proxy.size.width * 0.64, y: proxy.size.height * 0.51)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var timeline: some View {
        VStack(spacing: 0) {
            timeLabel(
                prayer: .asr,
                time: OnboardingDemoTimeFormatter.string(hour: 17, minute: 8),
                active: phase == .approaching
            )

            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color.vaktBorderStrong.opacity(0.62))
                    .frame(width: 1, height: 174)

                Capsule()
                    .fill(Color.vaktPrimary.opacity(0.82))
                    .frame(width: 2, height: timelineHeight)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.vaktPrimary)
                    .frame(width: 8, height: 3)
                    .offset(y: max(0, timelineHeight - 2))
                    .shadow(color: Color.vaktPrimary.opacity(0.32), radius: 7)
            }
            .frame(height: 174)
            .padding(.vertical, 7)

            timeLabel(
                prayer: .maghrib,
                time: OnboardingDemoTimeFormatter.string(hour: 20, minute: 31),
                active: phase != .approaching
            )
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 1.15), value: phase)
    }

    private func timeLabel(prayer: Prayer, time: String, active: Bool) -> some View {
        VStack(spacing: 3) {
            Text(L10n.prayerName(prayer).uppercased(with: VaktLocalization.appLocale))
                .font(VaktFont.eyebrow(7))
                .tracking(1.2)

            Text(time)
                .font(VaktFont.caption(9))
                .monospacedDigit()
        }
        .foregroundStyle(active ? Color.vaktPrimary : Color.vaktMuted)
    }

    @ViewBuilder
    private var reminderContent: some View {
        if phase == .approaching {
            VStack(alignment: .leading, spacing: 9) {
                Text(L10n.string("onboarding.closing_reminder.approaching.title"))
                    .font(VaktFont.title(21))
                    .foregroundStyle(Color.vaktPrimary)

                Text(L10n.string("onboarding.closing_reminder.approaching.body"))
                    .font(VaktFont.body(10))
                    .foregroundStyle(Color.vaktMuted)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        } else if phase == .saved || phase == .noted {
            savedResult
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else {
            questionSurface
                .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }

    private var questionSurface: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 9) {
                Image(systemName: "moon.stars")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.vaktGlow)

                Text(L10n.string("common.app_name").uppercased(with: VaktLocalization.appLocale))
                    .font(VaktFont.eyebrow(8))
                    .tracking(1.3)
                    .foregroundStyle(Color.vaktMuted)

                Spacer()

                Text(L10n.string("onboarding.closing_reminder.notification.now"))
                    .font(VaktFont.caption(8))
                    .foregroundStyle(Color.vaktMuted.opacity(0.72))
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.string("onboarding.closing_reminder.question.title"))
                    .font(VaktFont.title(19))
                    .foregroundStyle(Color.vaktPrimary)

                Text(L10n.string("onboarding.closing_reminder.question.context"))
                    .font(VaktFont.caption(9))
                    .foregroundStyle(Color.vaktMuted)
            }

            HStack(spacing: 7) {
                answerButton(
                    title: L10n.string("onboarding.mark_prayer.action.prayed"),
                    icon: "checkmark",
                    prayed: true
                )
                answerButton(
                    title: L10n.string("onboarding.mark_prayer.action.missed"),
                    icon: "minus",
                    prayed: false
                )
            }
        }
        .padding(16)
        .background(Color.vaktElevated.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                .strokeBorder(Color.vaktBorderStrong.opacity(0.72), lineWidth: 0.6)
        }
        .shadow(color: Color.vaktDeep.opacity(0.32), radius: 20, y: 10)
    }

    private func answerButton(title: String, icon: String, prayed: Bool) -> some View {
        let selected = prayed ? phase == .answeringPrayed : phase == .answeringMissed

        return Button { onAnswer(prayed) } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))

                Text(title)
                    .font(VaktFont.body(10))
            }
            .foregroundStyle(selected ? Color.vaktDeep : Color.vaktSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 37)
            .background(selected ? Color.vaktPrimary : Color.vaktSurface.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                if !selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.vaktBorder.opacity(0.8), lineWidth: 0.5)
                }
            }
        }
        .buttonStyle(VaktPressStyle())
    }

    private var savedResult: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: phase == .saved ? "checkmark" : "calendar.badge.clock")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.vaktPrimary)
                .frame(width: 40, height: 40)
                .background(Color.vaktPrimary.opacity(0.09))
                .clipShape(Circle())

            Text(L10n.string(phase == .saved
                ? "onboarding.closing_reminder.result.saved.title"
                : "onboarding.closing_reminder.result.missed.title"))
                .font(VaktFont.title(21))
                .foregroundStyle(Color.vaktPrimary)

            Text(L10n.string(phase == .saved
                ? "onboarding.closing_reminder.result.saved.body"
                : "onboarding.closing_reminder.result.missed.body"))
                .font(VaktFont.body(10))
                .foregroundStyle(Color.vaktMuted)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timelineHeight: CGFloat {
        switch phase {
        case .approaching: 64
        case .question, .answeringPrayed, .answeringMissed: 144
        case .saved, .noted: 174
        }
    }
}

private struct ClosingTimeAtmosphere: View {
    let phase: ClosingReminderPhase
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let breath = CGFloat((sin(time * 0.55) + 1) / 2)
                let center = CGPoint(x: size.width * 0.63, y: size.height * 0.5)
                let radius = size.width * 0.32 + breath * 7

                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                    with: .radialGradient(
                        Gradient(colors: [Color.vaktAccent.opacity(phase == .saved ? 0.1 : 0.055), .clear]),
                        center: center,
                        startRadius: 0,
                        endRadius: radius
                    )
                )
            }
        }
        .allowsHitTesting(false)
    }
}
