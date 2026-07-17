import SwiftUI

struct OnboardingPrayerMarkView: View {
    let stepIndex: Int
    let stepCount: Int
    let reduceMotion: Bool
    let onContinue: () -> Void

    @State private var state: PrayerMarkDemoState = .unmarked
    @State private var quietPreviewTask: Task<Void, Never>?
    @State private var demoTask: Task<Void, Never>?

    var body: some View {
        VaktOnboardingShell(
            stepIndex: stepIndex,
            stepCount: stepCount,
            eyebrow: L10n.string("onboarding.mark_prayer.eyebrow"),
            title: L10n.string("onboarding.mark_prayer.title"),
            bodyText: L10n.string("onboarding.mark_prayer.body"),
            actionTitle: L10n.string("action.continue"),
            onContinue: onContinue
        ) {
            PrayerMarkInstrument(
                state: state,
                reduceMotion: reduceMotion,
                onSelect: select,
                onQuietPreview: previewQuietMode
            )
        }
        .onAppear { startDemo() }
        .onDisappear {
            quietPreviewTask?.cancel()
            demoTask?.cancel()
        }
    }

    private func select(_ nextState: PrayerMarkDemoState) {
        demoTask?.cancel()
        quietPreviewTask?.cancel()
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(reduceMotion ? .none : .spring(response: 0.48, dampingFraction: 0.86)) {
            state = nextState
        }
    }

    private func previewQuietMode() {
        demoTask?.cancel()
        quietPreviewTask?.cancel()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.5)) {
            state = .quiet
        }

        quietPreviewTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 500 : 1_550))
            guard !Task.isCancelled, state == .quiet else { return }
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.5)) {
                state = .unmarked
            }
        }
    }

    private func startDemo() {
        demoTask?.cancel()
        demoTask = Task { @MainActor in
            let sequence: [PrayerMarkDemoState] = [.unmarked, .prayed, .missed, .quiet]

            while !Task.isCancelled {
                for nextState in sequence {
                    guard !Task.isCancelled else { return }
                    withAnimation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.88)) {
                        state = nextState
                    }
                    let duration = nextState == .quiet ? 2_800 : 2_200
                    try? await Task.sleep(for: .milliseconds(duration))
                }
            }
        }
    }
}

private enum PrayerMarkDemoState: Equatable {
    case unmarked
    case prayed
    case missed
    case quiet
}

private struct PrayerMarkInstrument: View {
    let state: PrayerMarkDemoState
    let reduceMotion: Bool
    let onSelect: (PrayerMarkDemoState) -> Void
    let onQuietPreview: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                PrayerMarkAtmosphere(state: state, reduceMotion: reduceMotion)

                VStack(spacing: 0) {
                    Spacer(minLength: 10)

                    prayerMoment

                    Spacer(minLength: 14)

                    Group {
                        if state == .quiet {
                            quietPresence
                                .transition(.opacity.combined(with: .scale(scale: 0.94)))
                        } else {
                            VStack(spacing: 10) {
                                markControls
                                quietAction
                            }
                            .padding(.horizontal, VaktSpace.lg)
                            .transition(.opacity)
                        }
                    }
                    .frame(height: 117)

                    Spacer(minLength: 8)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var prayerMoment: some View {
        VStack(spacing: 11) {
            Text(
                L10n.formatString(
                    "onboarding.mark_prayer.prayer_time",
                    Prayer.asr.localizedName,
                    OnboardingDemoTimeFormatter.string(hour: 17, minute: 8)
                ).uppercased(with: VaktLocalization.appLocale)
            )
                .font(VaktFont.eyebrow(9))
                .tracking(1.8)
                .foregroundStyle(Color.vaktMuted)

            Text(momentTitle)
                .font(VaktFont.prayerDisplay(state == .unmarked ? 37 : 38))
                .foregroundStyle(momentColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .contentTransition(.opacity)
                .id(momentTitle)

            ZStack {
                Capsule()
                    .fill(Color.vaktBorderStrong.opacity(0.62))
                    .frame(width: 126, height: 1)

                Capsule()
                    .fill(momentColor.opacity(0.8))
                    .frame(width: momentLineWidth, height: 2)
            }

            Text(momentDetail)
                .font(VaktFont.body(11))
                .foregroundStyle(state == .unmarked ? Color.vaktPrimary.opacity(0.82) : Color.vaktSecondary)
                .multilineTextAlignment(.center)
                .frame(height: 18)
                .contentTransition(.opacity)
                .id(momentDetail)
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.38), value: state)
        .accessibilityElement(children: .combine)
    }

    private var markControls: some View {
        HStack(spacing: 8) {
            markButton(
                title: L10n.string("onboarding.mark_prayer.action.prayed"),
                icon: "checkmark",
                target: .prayed
            )

            markButton(
                title: L10n.string("onboarding.mark_prayer.action.missed"),
                icon: "minus",
                target: .missed
            )
        }
        .padding(5)
        .background(Color.vaktSurface.opacity(state == .unmarked ? 0.78 : 0.58))
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                .strokeBorder(
                    state == .unmarked ? Color.vaktGlow.opacity(0.34) : Color.vaktBorder.opacity(0.7),
                    lineWidth: state == .unmarked ? 0.8 : 0.5
                )
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.35), value: state)
    }

    private var quietPresence: some View {
        VStack(spacing: 10) {
            ZStack {
                Capsule()
                    .fill(Color.vaktPrimary.opacity(0.18))
                    .frame(width: 1, height: 48)

                Circle()
                    .fill(Color.vaktPrimary)
                    .frame(width: 6, height: 6)
                    .shadow(color: Color.vaktPrimary.opacity(0.5), radius: 10)
            }

            Text(L10n.string("onboarding.mark_prayer.quiet.active"))
                .font(VaktFont.eyebrow(8))
                .tracking(1.4)
                .foregroundStyle(Color.vaktSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func markButton(
        title: String,
        icon: String,
        target: PrayerMarkDemoState
    ) -> some View {
        let selected = state == target

        return Button {
            onSelect(target)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))

                Text(title)
                    .font(VaktFont.body(12))
            }
            .foregroundStyle(selected ? Color.vaktDeep : (state == .unmarked ? Color.vaktPrimary : Color.vaktMuted))
            .frame(maxWidth: .infinity)
            .frame(height: 43)
            .background(selected ? Color.vaktPrimary : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(VaktPressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var quietAction: some View {
        Button(action: onQuietPreview) {
            HStack(spacing: 11) {
                Image(systemName: state == .quiet ? "moon.stars.fill" : "moon.stars")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(state == .quiet ? Color.vaktPrimary : Color.vaktGlow)
                    .contentTransition(.symbolEffect(.replace))

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("prayer.action.begin"))
                        .font(VaktFont.body(12))
                        .foregroundStyle(Color.vaktPrimary)

                    Text(L10n.string("onboarding.mark_prayer.quiet.subtitle"))
                        .font(VaktFont.caption(8))
                        .foregroundStyle(Color.vaktMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.vaktMuted)
            }
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background(Color.vaktElevated.opacity(state == .quiet ? 0.65 : 0.34))
            .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                    .strokeBorder(Color.vaktBorderStrong.opacity(0.62), lineWidth: 0.5)
            }
        }
        .buttonStyle(VaktPressStyle())
    }

    private var momentTitle: String {
        switch state {
        case .unmarked: L10n.string("onboarding.mark_prayer.state.unmarked.title")
        case .prayed: L10n.string("onboarding.mark_prayer.state.prayed.title")
        case .missed: L10n.string("onboarding.mark_prayer.state.missed.title")
        case .quiet: L10n.string("onboarding.mark_prayer.state.quiet.title")
        }
    }

    private var momentDetail: String {
        switch state {
        case .unmarked: L10n.string("onboarding.mark_prayer.state.unmarked.detail")
        case .prayed:
            L10n.formatString(
                "onboarding.mark_prayer.state.prayed.detail",
                Prayer.asr.localizedName
            )
        case .missed: L10n.string("onboarding.mark_prayer.state.missed.detail")
        case .quiet: L10n.string("onboarding.mark_prayer.state.quiet.detail")
        }
    }

    private var momentColor: Color {
        switch state {
        case .unmarked: .vaktPrimary
        case .prayed: Color(hex: "#C8DDD3")
        case .missed: .vaktSecondary
        case .quiet: Color(hex: "#D8DDF0")
        }
    }

    private var momentLineWidth: CGFloat {
        switch state {
        case .unmarked: 28
        case .prayed: 112
        case .missed: 74
        case .quiet: 52
        }
    }
}

private struct PrayerMarkAtmosphere: View {
    let state: PrayerMarkDemoState
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let breath = CGFloat((sin(time * 0.52) + 1) / 2)
                let center = CGPoint(x: size.width * 0.5, y: size.height * 0.39)
                let radius = size.width * (state == .quiet ? 0.46 : 0.36) + breath * 8
                let color = glowColor

                context.fill(
                    Path(ellipseIn: CGRect(
                        x: center.x - radius,
                        y: center.y - radius * 0.62,
                        width: radius * 2,
                        height: radius * 1.24
                    )),
                    with: .radialGradient(
                        Gradient(colors: [color.opacity(0.09), .clear]),
                        center: center,
                        startRadius: 2,
                        endRadius: radius
                    )
                )

                if state == .quiet {
                    context.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .color(Color.vaktDeep.opacity(0.16))
                    )
                }
            }
        }
        .animation(.easeInOut(duration: 0.5), value: state)
        .accessibilityHidden(true)
    }

    private var glowColor: Color {
        switch state {
        case .unmarked: .vaktGlow
        case .prayed: Color(hex: "#8FB9A5")
        case .missed: .vaktAccent
        case .quiet: Color(hex: "#9199C5")
        }
    }
}
