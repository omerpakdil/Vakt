import SwiftUI

struct OnboardingPromiseView: View {
    let stepIndex: Int
    let stepCount: Int
    let reduceMotion: Bool
    let onContinue: () -> Void

    @State private var phase: PromisePhase = .approaching
    @State private var demoTask: Task<Void, Never>?

    var body: some View {
        VaktOnboardingShell(
            stepIndex: stepIndex,
            stepCount: stepCount,
            eyebrow: L10n.string("onboarding.promise.eyebrow"),
            title: L10n.string("onboarding.promise.title"),
            bodyText: L10n.string("onboarding.promise.body"),
            actionTitle: L10n.string("onboarding.promise.action.continue"),
            onContinue: onContinue
        ) {
            PromiseJourneyScene(
                phase: phase,
                reduceMotion: reduceMotion,
                onAdvance: manualAdvance
            )
        }
        .onAppear { startDemo() }
        .onDisappear { demoTask?.cancel() }
    }

    private func startDemo() {
        demoTask?.cancel()
        demoTask = Task { @MainActor in
            while !Task.isCancelled {
                for nextPhase in PromisePhase.allCases {
                    guard !Task.isCancelled else { return }
                    setPhase(nextPhase)
                    let duration = nextPhase == .complete ? 3_000 : 2_150
                    try? await Task.sleep(for: .milliseconds(duration))
                }
            }
        }
    }

    private func manualAdvance() {
        demoTask?.cancel()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        let phases = PromisePhase.allCases
        setPhase(phases[(phase.rawValue + 1) % phases.count])
    }

    private func setPhase(_ nextPhase: PromisePhase) {
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? .none : .spring(response: 0.56, dampingFraction: 0.9)) {
            phase = nextPhase
        }
    }
}

private enum PromisePhase: Int, CaseIterable, Hashable {
    case approaching
    case quiet
    case recorded
    case supported
    case complete
}

private struct PromiseJourneyScene: View {
    let phase: PromisePhase
    let reduceMotion: Bool
    let onAdvance: () -> Void

    private var steps: [PromiseStep] {
        [
            PromiseStep(
                phase: .approaching,
                icon: "bell",
                title: L10n.string("onboarding.promise.step.approaching.title"),
                detail: L10n.string("onboarding.promise.step.approaching.detail")
            ),
            PromiseStep(
                phase: .quiet,
                icon: "moon.stars",
                title: L10n.string("onboarding.promise.step.quiet.title"),
                detail: L10n.string("onboarding.promise.step.quiet.detail")
            ),
            PromiseStep(
                phase: .recorded,
                icon: "checkmark",
                title: L10n.string("onboarding.promise.step.recorded.title"),
                detail: L10n.string("onboarding.promise.step.recorded.detail")
            ),
            PromiseStep(
                phase: .supported,
                icon: "person.2",
                title: L10n.string("onboarding.promise.step.supported.title"),
                detail: L10n.string("onboarding.promise.step.supported.detail")
            )
        ]
    }

    var body: some View {
        Button(action: onAdvance) {
            ZStack {
                RadialGradient(
                    colors: [Color.vaktGlow.opacity(phase == .complete ? 0.075 : 0.04), .clear],
                    center: .center,
                    startRadius: 4,
                    endRadius: 220
                )

                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(L10n.string("onboarding.promise.journey.title")
                            .uppercased(with: VaktLocalization.appLocale))
                            .font(VaktFont.eyebrow(8))
                            .tracking(1.6)
                            .foregroundStyle(Color.vaktMuted)

                        Spacer()

                        Text(L10n.string(phase == .complete
                            ? "onboarding.promise.journey.complete"
                            : "onboarding.promise.journey.prayer_today")
                            .uppercased(with: VaktLocalization.appLocale))
                            .font(VaktFont.caption(8))
                            .foregroundStyle(phase == .complete ? Color.vaktPrimary : Color.vaktSecondary)
                            .contentTransition(.opacity)
                    }
                    .frame(height: 34)

                    VStack(spacing: 5) {
                        ForEach(steps) { step in
                            journeyRow(step)
                        }
                    }

                    HStack(spacing: 9) {
                        Capsule()
                            .fill(Color.vaktPrimary.opacity(0.76))
                            .frame(width: phase == .complete ? 38 : 18, height: 2)

                        Text(phase == .complete
                            ? L10n.string("onboarding.promise.journey.complete_summary")
                            : currentSummary)
                            .font(VaktFont.body(10))
                            .foregroundStyle(phase == .complete ? Color.vaktPrimary : Color.vaktMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .contentTransition(.opacity)

                        Spacer()
                    }
                    .frame(height: 42)
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, VaktSpace.lg)
                .padding(.vertical, 10)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.48), value: phase)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(L10n.string("onboarding.promise.accessibility.next_hint"))
    }

    private func journeyRow(_ step: PromiseStep) -> some View {
        let isCurrent = phase == step.phase
        let isComplete = phase == .complete || step.phase.rawValue < phase.rawValue

        return HStack(spacing: 13) {
            Capsule()
                .fill(isCurrent || phase == .complete ? Color.vaktPrimary : Color.vaktBorderStrong)
                .frame(width: 2, height: isCurrent ? 40 : 18)

            Image(systemName: isComplete ? "checkmark" : step.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isCurrent || phase == .complete ? Color.vaktPrimary : Color.vaktMuted)
                .frame(width: 24)
                .contentTransition(.symbolEffect(.replace))

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(isCurrent ? VaktFont.body(13) : VaktFont.body(11))
                    .foregroundStyle(isCurrent || phase == .complete ? Color.vaktPrimary : Color.vaktSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)

                Text(step.detail)
                    .font(VaktFont.caption(8))
                    .foregroundStyle(Color.vaktMuted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .opacity(isCurrent || phase == .complete ? 1 : 0.48)
            }

            Spacer()

            if isCurrent {
                Text(L10n.string("onboarding.promise.now")
                    .uppercased(with: VaktLocalization.appLocale))
                    .font(VaktFont.eyebrow(7))
                    .tracking(1)
                    .foregroundStyle(Color.vaktSecondary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 61)
        .background(isCurrent ? Color.vaktElevated.opacity(0.42) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            if isCurrent {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.vaktBorderStrong.opacity(0.55), lineWidth: 0.5)
            }
        }
    }

    private var currentSummary: String {
        switch phase {
        case .approaching:
            L10n.string("onboarding.promise.summary.approaching")
        case .quiet:
            L10n.string("onboarding.promise.summary.quiet")
        case .recorded:
            L10n.string("onboarding.promise.summary.recorded")
        case .supported:
            L10n.string("onboarding.promise.summary.supported")
        case .complete:
            L10n.string("onboarding.promise.journey.complete_summary")
        }
    }

    private var accessibilityLabel: String {
        phase == .complete
            ? L10n.string("onboarding.promise.accessibility.complete")
            : currentSummary
    }
}

private struct PromiseStep: Identifiable {
    let phase: PromisePhase
    let icon: String
    let title: String
    let detail: String

    var id: PromisePhase { phase }
}
