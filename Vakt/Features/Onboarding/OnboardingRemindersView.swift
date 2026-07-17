import SwiftUI
import UserNotifications

struct OnboardingRemindersView: View {
    let stepIndex: Int
    let stepCount: Int
    @ObservedObject var notificationManager: NotificationManager
    let reduceMotion: Bool
    let onEnable: () async -> Void
    let onSkip: () -> Void

    @State private var signalPhase: CGFloat = 0.18
    @State private var isTuning = false
    @State private var isBreathing = false

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Color.vaktDeep.ignoresSafeArea()
                    .frame(height: 0)

                ZStack(alignment: .topLeading) {
                    ReminderSignalField(
                        signalPhase: signalPhase,
                        isTuning: isTuning,
                        isBreathing: isBreathing && !reduceMotion,
                        reduceMotion: reduceMotion
                    )
                    .gesture(tuningGesture(width: proxy.size.width))

                    ReminderPageMark(stepIndex: stepIndex, stepCount: stepCount)
                        .padding(.top, VaktSpace.xl)
                        .padding(.horizontal, VaktSpace.lg)

                    ReminderSignalDial(
                        signalPhase: signalPhase,
                        isTuning: isTuning,
                        authorizationStatus: notificationManager.authorizationStatus
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                .frame(height: min(390, proxy.size.height * 0.48))
                .background(Color.vaktBg)

                VStack(alignment: .leading, spacing: 15) {
                    EyebrowLabel(text: L10n.string("onboarding.reminders.eyebrow"))

                    Text(L10n.string("onboarding.reminders.title.screen"))
                        .font(VaktFont.title(30))
                        .foregroundStyle(Color.vaktPrimary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(L10n.string("onboarding.reminders.body.screen"))
                        .font(VaktFont.body(14))
                        .foregroundStyle(Color.vaktMuted)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)

                    ReminderWhisperLine(onSkip: onSkip)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, VaktSpace.lg)
                .padding(.top, VaktSpace.lg)
                .padding(.bottom, 22)

                Spacer(minLength: 0)

                ReminderActions(
                    authorizationStatus: notificationManager.authorizationStatus,
                    onEnable: onEnable
                )
                .padding(.horizontal, VaktSpace.lg)
                .padding(.bottom, VaktSpace.lg)
            }
            .background(Color.vaktDeep.ignoresSafeArea())
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }

    private func tuningGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard width > 0 else { return }
                isTuning = true
                withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.84)) {
                    signalPhase = min(1, max(0, value.location.x / width))
                }
            }
            .onEnded { _ in
                isTuning = false
                withAnimation(.spring(response: 0.50, dampingFraction: 0.84)) {
                    signalPhase = 0.72
                }
            }
    }
}

private struct ReminderPageMark: View {
    let stepIndex: Int
    let stepCount: Int

    var body: some View {
        HStack {
            Text(verbatim: "0\(stepIndex + 1) / 0\(stepCount)")
                .font(VaktFont.caption(11))
                .foregroundStyle(Color.vaktMuted)
                .monospacedDigit()
                .tracking(0.5)

            Spacer()
        }
        .accessibilityLabel(L10n.formatString("onboarding.step_accessibility", stepIndex + 1, stepCount))
    }
}

private struct ReminderSignalDial: View {
    let signalPhase: CGFloat
    let isTuning: Bool
    let authorizationStatus: UNAuthorizationStatus

    var body: some View {
        let dialSize: CGFloat = 210

        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(Color.vaktAccent.opacity(0.09 + Double(index) * 0.035 + (isTuning ? 0.04 : 0)), lineWidth: 0.7)
                    .frame(width: CGFloat(86 + index * 34), height: CGFloat(86 + index * 34))
                    .scaleEffect(isTuning ? 1.02 : 1)
            }

            ForEach(ReminderPetal.allCases) { petal in
                ReminderPetalView(petal: petal, isActive: petal.activation <= signalPhase)
                    .position(petal.position(in: dialSize, signalPhase: signalPhase, isTuning: isTuning))
            }

            ZStack {
                Circle()
                    .fill(Color.vaktSurface.opacity(0.92))
                    .frame(width: 72, height: 72)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.vaktAccent.opacity(isTuning ? 0.42 : 0.24), lineWidth: 0.7)
                    )

                Image(systemName: iconName)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.vaktPrimary)
                    .scaleEffect(isTuning ? 1.05 : 1)
            }
        }
        .frame(width: dialSize, height: dialSize)
        .accessibilityLabel(L10n.string("onboarding.reminders.signal_accessibility"))
    }

    private var iconName: String {
        authorizationStatus == .denied ? "bell.slash" : "bell"
    }
}

private struct ReminderPetalView: View {
    let petal: ReminderPetal
    let isActive: Bool

    var body: some View {
        VStack(spacing: 5) {
            Circle()
                .fill(isActive ? Color.vaktPrimary : Color.vaktAccent.opacity(0.38))
                .frame(width: isActive ? 8 : 5, height: isActive ? 8 : 5)
                .shadow(color: Color.vaktPrimary.opacity(isActive ? 0.24 : 0), radius: 7)

            Text(petal.title)
                .font(VaktFont.caption(10))
                .foregroundStyle(isActive ? Color.vaktPrimary : Color.vaktMuted)
                .tracking(0.2)
        }
        .frame(width: 62)
        .opacity(isActive ? 1 : 0.58)
    }
}

private enum ReminderPetal: CaseIterable, Identifiable {
    case before
    case time
    case fajr

    var id: Self { self }

    var title: String {
        switch self {
        case .before: L10n.string("onboarding.reminders.petal.before")
        case .time: L10n.string("onboarding.reminders.petal.now")
        case .fajr: L10n.string("onboarding.reminders.petal.wake")
        }
    }

    var angle: Double {
        switch self {
        case .before: -46
        case .time: 0
        case .fajr: 46
        }
    }

    var activation: CGFloat {
        switch self {
        case .before: 0.18
        case .time: 0.48
        case .fajr: 0.76
        }
    }

    func position(in size: CGFloat, signalPhase: CGFloat, isTuning: Bool) -> CGPoint {
        let orbit = CGFloat(isTuning ? 83 : 78)
        let phaseAngle = Double(signalPhase) * 12
        let radians = (angle + phaseAngle) * .pi / 180
        let center = size / 2

        return CGPoint(
            x: center + CGFloat(sin(radians)) * orbit,
            y: center - CGFloat(cos(radians)) * orbit
        )
    }
}

private struct ReminderWhisperLine: View {
    let onSkip: () -> Void

    var body: some View {
        HStack(spacing: VaktSpace.sm) {
            Text(L10n.string("onboarding.reminders.change_anytime"))
                .font(VaktFont.caption(11))
                .foregroundStyle(Color.vaktSecondary)

            Spacer(minLength: VaktSpace.sm)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onSkip()
            } label: {
                Text(L10n.string("action.not_now"))
                    .font(VaktFont.caption(11))
                    .foregroundStyle(Color.vaktMuted)
                    .padding(.horizontal, 6)
                    .frame(minHeight: 44)
            }
            .buttonStyle(VaktPressStyle())
        }
    }
}

private struct ReminderActions: View {
    let authorizationStatus: UNAuthorizationStatus
    let onEnable: () async -> Void

    @State private var isRunningEnableAction = false

    var body: some View {
        Button {
            guard !isRunningEnableAction else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            isRunningEnableAction = true

            Task { @MainActor in
                await onEnable()
                isRunningEnableAction = false
            }
        } label: {
            HStack(spacing: VaktSpace.sm) {
                Image(systemName: primaryIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.vaktBg)

                Text(primaryTitle)
                    .font(VaktFont.button(15))
                    .foregroundStyle(Color.vaktBg)

                Spacer()

                if isRunningEnableAction {
                    ProgressView()
                        .tint(Color.vaktBg)
                } else {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.vaktBg)
                }
            }
            .padding(.horizontal, VaktSpace.md)
            .frame(height: 56)
            .background(Color.vaktPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(VaktPressStyle())
        .disabled(isRunningEnableAction)
    }

    private var primaryTitle: String {
        authorizationStatus.allowsPrayerNotifications ? L10n.string("action.continue") : L10n.string("action.allow_prayer_reminders")
    }

    private var primaryIcon: String {
        authorizationStatus == .denied ? "bell.slash" : "bell.badge"
    }
}

private struct ReminderSignalField: View {
    let signalPhase: CGFloat
    let isTuning: Bool
    let isBreathing: Bool
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let breath = CGFloat((sin(time * 0.50) + 1) / 2)

                drawBase(ctx: ctx, size: size)
                drawSignalEnvelope(ctx: ctx, size: size, breath: breath)
                drawSoftWaves(ctx: ctx, size: size, breath: breath)
                drawNotificationDrops(ctx: ctx, size: size, breath: breath)
                drawHorizonTrace(ctx: ctx, size: size, breath: breath)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawBase(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.vaktDeep))

        let upper = CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.72)
        ctx.fill(Path(upper), with: .color(.vaktBg.opacity(0.92)))
    }

    private func drawSignalEnvelope(ctx: GraphicsContext, size: CGSize, breath: CGFloat) {
        let rect = CGRect(
            x: size.width * (0.14 + signalPhase * 0.08),
            y: size.height * 0.18,
            width: size.width * (0.72 - signalPhase * 0.16),
            height: size.height * 0.34
        )

        ctx.fill(
            Path(ellipseIn: rect),
            with: .color(.vaktAccent.opacity(0.032 + Double(signalPhase) * 0.044 + Double(breath) * 0.015))
        )
    }

    private func drawSoftWaves(ctx: GraphicsContext, size: CGSize, breath: CGFloat) {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.35)

        for index in 0..<4 {
            let radius = size.width * CGFloat(0.14 + Double(index) * 0.075 + Double(signalPhase) * 0.018)
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            var arc = Path()
            arc.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(Double(205 - index * 9)),
                endAngle: .degrees(Double(335 + index * 7) + Double(breath) * 5),
                clockwise: false
            )

            ctx.stroke(
                arc,
                with: .color(.vaktPrimary.opacity(0.035 + Double(index) * 0.012 + (isTuning ? 0.04 : 0))),
                lineWidth: 0.55
            )
            ctx.stroke(Path(ellipseIn: rect), with: .color(.vaktAccent.opacity(0.008)), lineWidth: 0.3)
        }
    }

    private func drawNotificationDrops(ctx: GraphicsContext, size: CGSize, breath: CGFloat) {
        let drops: [(x: CGFloat, y: CGFloat, activation: CGFloat)] = [
            (0.25, 0.34, 0.16),
            (0.50, 0.26, 0.48),
            (0.75, 0.34, 0.76)
        ]

        for (index, drop) in drops.enumerated() {
            let active = max(0, min(1, (signalPhase - drop.activation) / 0.20))
            let float = reduceMotion ? 0 : CGFloat(sin(Double(index) + Double(breath) * 2.2)) * 2
            let x = size.width * drop.x
            let y = size.height * drop.y + float
            let radius = 2.4 + active * 3.2

            ctx.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                with: .color(.vaktPrimary.opacity(0.16 + Double(active) * 0.62))
            )
        }
    }

    private func drawHorizonTrace(ctx: GraphicsContext, size: CGSize, breath: CGFloat) {
        let y = size.height * 0.71

        var horizon = Path()
        horizon.move(to: CGPoint(x: size.width * 0.20, y: y))
        horizon.addLine(to: CGPoint(x: size.width * 0.80, y: y))
        ctx.stroke(
            horizon,
            with: .color(.vaktAccent.opacity(0.10 + Double(breath) * 0.022 + (isTuning ? 0.04 : 0))),
            lineWidth: 0.55
        )

        var trace = Path()
        trace.move(to: CGPoint(x: size.width * 0.5, y: size.height * 0.40))
        trace.addCurve(
            to: CGPoint(x: size.width * 0.5, y: y + 26),
            control1: CGPoint(x: size.width * (0.42 + signalPhase * 0.10), y: size.height * 0.50),
            control2: CGPoint(x: size.width * 0.5, y: y - 8)
        )
        ctx.stroke(
            trace,
            with: .color(.vaktPrimary.opacity(0.035 + (isTuning ? 0.07 : 0))),
            lineWidth: isTuning ? 0.75 : 0.45
        )
    }
}
