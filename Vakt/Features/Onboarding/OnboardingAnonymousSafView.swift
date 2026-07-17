import SwiftUI

struct OnboardingAnonymousSafView: View {
    let stepIndex: Int
    let stepCount: Int
    let reduceMotion: Bool
    let onContinue: () -> Void

    @State private var dissolve: CGFloat = 0.34
    @State private var focus = CGPoint(x: 0.5, y: 0.36)
    @State private var isTouching = false
    @State private var isBreathing = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.vaktDeep.ignoresSafeArea()

                AnonymousPresenceField(
                    dissolve: dissolve,
                    focus: focus,
                    isTouching: isTouching,
                    isBreathing: isBreathing && !reduceMotion,
                    reduceMotion: reduceMotion
                )
                .ignoresSafeArea()
                .gesture(fieldGesture(size: proxy.size))

                VStack(spacing: 0) {
                    AnonymousHeader(stepIndex: stepIndex, stepCount: stepCount)
                        .padding(.top, VaktSpace.xl)
                        .padding(.horizontal, VaktSpace.lg)

                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 15) {
                        EyebrowLabel(text: L10n.string("onboarding.privacy.eyebrow"))

                        Text(L10n.string("onboarding.privacy.title.anonymous"))
                            .font(VaktFont.title(31))
                            .foregroundStyle(Color.vaktPrimary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(L10n.string("onboarding.privacy.body.anonymous"))
                            .font(VaktFont.body(14))
                            .foregroundStyle(Color.vaktMuted)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)

                        AnonymousQuietLine(dissolve: dissolve)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, VaktSpace.lg)
                    .padding(.bottom, 26)

                    AnonymousGlassContinue(dissolve: dissolve, onContinue: onContinue)
                        .padding(.horizontal, VaktSpace.lg)
                        .padding(.bottom, VaktSpace.lg)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }

    private func fieldGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard size.width > 0, size.height > 0 else { return }
                isTouching = true
                focus = CGPoint(
                    x: min(0.88, max(0.12, value.location.x / size.width)),
                    y: min(0.54, max(0.18, value.location.y / size.height))
                )

                withAnimation(.easeOut(duration: 0.16)) {
                    dissolve = 1
                }
            }
            .onEnded { _ in
                isTouching = false
                withAnimation(.spring(response: 0.58, dampingFraction: 0.84)) {
                    focus = CGPoint(x: 0.5, y: 0.36)
                    dissolve = 0.62
                }
            }
    }
}

private struct AnonymousHeader: View {
    let stepIndex: Int
    let stepCount: Int

    var body: some View {
        HStack(spacing: VaktSpace.sm) {
            Text(verbatim: "0\(stepIndex + 1)")
                .font(VaktFont.caption(11))
                .foregroundStyle(Color.vaktPrimary)
                .monospacedDigit()

            HStack(spacing: 4) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Capsule()
                        .fill(index <= stepIndex ? Color.vaktPrimary : Color.vaktBorderStrong)
                        .frame(height: 3)
                        .opacity(index <= stepIndex ? 0.92 : 0.52)
                }
            }

            Text(verbatim: "0\(stepCount)")
                .font(VaktFont.caption(11))
                .foregroundStyle(Color.vaktMuted)
                .monospacedDigit()
        }
        .accessibilityLabel(L10n.formatString("onboarding.step_accessibility", stepIndex + 1, stepCount))
    }
}

private struct AnonymousPresenceField: View {
    let dissolve: CGFloat
    let focus: CGPoint
    let isTouching: Bool
    let isBreathing: Bool
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let breath = CGFloat((sin(time * 0.54) + 1) / 2)
                let center = CGPoint(x: size.width * focus.x, y: size.height * focus.y)
                let horizonY = size.height * 0.38

                drawGround(ctx: ctx, size: size, horizonY: horizonY)
                drawVeil(ctx: ctx, size: size, center: center, breath: breath)
                drawIdentityTraces(ctx: ctx, size: size, center: center, breath: breath)
                drawHorizon(ctx: ctx, size: size, horizonY: horizonY, breath: breath)
                drawPresence(ctx: ctx, size: size, horizonY: horizonY, breath: breath)
                drawSelf(ctx: ctx, size: size, horizonY: horizonY, breath: breath)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawGround(ctx: GraphicsContext, size: CGSize, horizonY: CGFloat) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.vaktBg.opacity(0.96)))

        ctx.fill(
            Path(CGRect(x: 0, y: horizonY, width: size.width, height: size.height - horizonY)),
            with: .color(.vaktDeep.opacity(0.94))
        )
    }

    private func drawVeil(ctx: GraphicsContext, size: CGSize, center: CGPoint, breath: CGFloat) {
        let radius = size.width * (0.26 + dissolve * 0.08 + breath * 0.015)
        let rect = CGRect(x: center.x - radius, y: center.y - radius * 0.58, width: radius * 2, height: radius * 1.16)

        ctx.fill(
            Path(ellipseIn: rect),
            with: .color(.vaktPrimary.opacity(0.025 + Double(dissolve) * 0.055 + (isTouching ? 0.025 : 0)))
        )

        for index in 0..<3 {
            let inset = CGFloat(index) * 18
            ctx.stroke(
                Path(ellipseIn: rect.insetBy(dx: inset, dy: inset * 0.48)),
                with: .color(.vaktAccent.opacity(0.028 + Double(dissolve) * 0.035 - Double(index) * 0.008)),
                lineWidth: 0.45
            )
        }
    }

    private func drawIdentityTraces(ctx: GraphicsContext, size: CGSize, center: CGPoint, breath: CGFloat) {
        let traces: [(String, CGFloat, CGFloat)] = [
            (L10n.string("onboarding.privacy.trace.name"), 0.22, 0.24),
            (L10n.string("onboarding.privacy.trace.profile"), 0.70, 0.22),
            (L10n.string("onboarding.privacy.trace.location"), 0.27, 0.47),
            (L10n.string("onboarding.privacy.trace.proof"), 0.66, 0.48)
        ]

        for (index, trace) in traces.enumerated() {
            let start = CGPoint(x: size.width * trace.1, y: size.height * trace.2)
            let pull = CGPoint(
                x: start.x + (center.x - start.x) * dissolve * 0.18,
                y: start.y + (center.y - start.y) * dissolve * 0.18
            )
            let float = reduceMotion ? 0 : CGFloat(sin(Double(index) + Double(breath) * 2.2)) * 2.0
            let opacity = max(0.0, 0.34 - Double(dissolve) * 0.28)

            let resolved = ctx.resolve(
                Text(trace.0.uppercased())
                    .font(VaktFont.caption(10))
                    .foregroundStyle(Color.vaktMuted.opacity(opacity))
            )
            ctx.draw(resolved, at: CGPoint(x: pull.x, y: pull.y + float), anchor: .center)

            if dissolve > 0.28 {
                let dotRadius = 1.8 + dissolve * 1.2
                ctx.fill(
                    Path(ellipseIn: CGRect(
                        x: pull.x - dotRadius,
                        y: pull.y + float - dotRadius,
                        width: dotRadius * 2,
                        height: dotRadius * 2
                    )),
                    with: .color(.vaktAccent.opacity(0.10 + Double(dissolve) * 0.24))
                )
            }
        }
    }

    private func drawHorizon(ctx: GraphicsContext, size: CGSize, horizonY: CGFloat, breath: CGFloat) {
        var line = Path()
        line.move(to: CGPoint(x: size.width * 0.12, y: horizonY))
        line.addLine(to: CGPoint(x: size.width * 0.88, y: horizonY))
        ctx.stroke(
            line,
            with: .color(.vaktAccent.opacity(0.16 + Double(dissolve) * 0.15 + Double(breath) * 0.025)),
            lineWidth: 0.65 + dissolve * 0.4
        )

        var quietLine = Path()
        quietLine.move(to: CGPoint(x: size.width * 0.30, y: horizonY + 18))
        quietLine.addLine(to: CGPoint(x: size.width * 0.70, y: horizonY + 18))
        ctx.stroke(quietLine, with: .color(.vaktBorderStrong.opacity(0.34)), lineWidth: 0.5)
    }

    private func drawPresence(ctx: GraphicsContext, size: CGSize, horizonY: CGFloat, breath: CGFloat) {
        let lights: [(CGFloat, CGFloat)] = [
            (0.18, -5), (0.26, 5), (0.34, -1), (0.42, 6),
            (0.58, -4), (0.66, 3), (0.74, -6), (0.82, 6)
        ]

        for (index, light) in lights.enumerated() {
            let driftToCenter = (0.5 - light.0) * dissolve * 0.06
            let float = reduceMotion ? 0 : CGFloat(sin(Double(index) * 0.83 + Double(breath) * 2.0)) * 1.5
            let x = size.width * (light.0 + driftToCenter)
            let y = horizonY + light.1 + float
            let radius = 2.4 + dissolve * 1.8

            if dissolve > 0.72 && index % 3 == 0 {
                let ring = radius + 4 + breath * 1.4
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: x - ring, y: y - ring, width: ring * 2, height: ring * 2)),
                    with: .color(.vaktPrimary.opacity(0.04 + Double(dissolve) * 0.045)),
                    lineWidth: 0.5
                )
            }

            ctx.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                with: .color(.vaktAccent.opacity(0.25 + Double(dissolve) * 0.42))
            )
        }
    }

    private func drawSelf(ctx: GraphicsContext, size: CGSize, horizonY: CGFloat, breath: CGFloat) {
        let center = CGPoint(x: size.width * 0.5, y: horizonY)
        let glow = CGFloat((isBreathing ? 18 : 13) + dissolve * 9 + breath * 3)

        ctx.fill(
            Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)),
            with: .color(.vaktPrimary.opacity(0.045 + Double(dissolve) * 0.06))
        )

        ctx.fill(
            Path(ellipseIn: CGRect(x: center.x - 5.3, y: center.y - 5.3, width: 10.6, height: 10.6)),
            with: .color(.vaktPrimary.opacity(0.95))
        )
    }
}

private struct AnonymousQuietLine: View {
    let dissolve: CGFloat

    var body: some View {
        Text(L10n.string("onboarding.privacy.quiet_line"))
            .font(VaktFont.caption(11))
            .foregroundStyle(Color.vaktSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
        .padding(.top, 2)
        .opacity(0.72 + Double(dissolve) * 0.28)
    }
}

private struct AnonymousGlassContinue: View {
    let dissolve: CGFloat
    let onContinue: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onContinue()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.vaktPrimary)

                HStack(spacing: VaktSpace.sm) {
                    Text(L10n.string("action.continue"))
                        .font(VaktFont.button(15))
                        .foregroundStyle(Color.vaktBg)

                    Spacer()

                    ZStack {
                        Circle()
                            .fill(Color.vaktBg.opacity(0.12))
                            .frame(width: 30, height: 30)

                        Circle()
                            .fill(Color.vaktBg)
                            .frame(width: 5.5 + dissolve * 2, height: 5.5 + dissolve * 2)
                    }
                }
                .padding(.horizontal, VaktSpace.md)
            }
            .frame(height: 56)
        }
        .buttonStyle(VaktPressStyle())
        .accessibilityLabel(L10n.string("action.continue"))
    }
}
