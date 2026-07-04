import SwiftUI

struct OnboardingArrivalView: View {
    let stepIndex: Int
    let stepCount: Int
    let reduceMotion: Bool
    let onContinue: () -> Void

    @State private var focusX: CGFloat = 0.5
    @State private var isTouching = false
    @State private var isBreathing = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.vaktBg.ignoresSafeArea()

                ArrivalHorizonScene(
                    focusX: focusX,
                    isTouching: isTouching,
                    isBreathing: isBreathing && !reduceMotion,
                    reduceMotion: reduceMotion
                )
                .ignoresSafeArea()
                .gesture(sceneGesture(width: proxy.size.width))

                VStack(spacing: 0) {
                    ArrivalStepHeader(stepIndex: stepIndex, stepCount: stepCount)
                        .padding(.top, VaktSpace.xl)
                        .padding(.horizontal, VaktSpace.lg)

                    Spacer(minLength: 0)

                    ArrivalMomentPanel(isActive: isTouching || isBreathing)
                        .padding(.horizontal, VaktSpace.lg)
                        .padding(.bottom, 34)

                    VStack(alignment: .leading, spacing: 14) {
                        EyebrowLabel(text: "Next Prayer")

                        Text("Keep the next salah close.")
                            .font(VaktFont.title(30))
                            .foregroundStyle(Color.vaktPrimary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Vakt keeps the next time in view and shows the Saf gathering as the prayer draws near.")
                            .font(VaktFont.body(14))
                            .foregroundStyle(Color.vaktMuted)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)

                        ArrivalMicroSignals()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, VaktSpace.lg)

                    Spacer(minLength: 18)

                    ArrivalContinueButton(onContinue: onContinue)
                        .padding(.horizontal, VaktSpace.lg)
                        .padding(.bottom, VaktSpace.lg)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.1).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }

    private func sceneGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard width > 0 else { return }
                isTouching = true
                focusX = min(0.86, max(0.14, value.location.x / width))
            }
            .onEnded { _ in
                isTouching = false
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    focusX = 0.5
                }
            }
    }
}

private struct ArrivalStepHeader: View {
    let stepIndex: Int
    let stepCount: Int

    var body: some View {
        HStack(spacing: VaktSpace.sm) {
            Text("0\(stepIndex + 1)")
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

            Text("0\(stepCount)")
                .font(VaktFont.caption(11))
                .foregroundStyle(Color.vaktMuted)
                .monospacedDigit()
        }
        .accessibilityLabel("Onboarding step \(stepIndex + 1) of \(stepCount)")
    }
}

private struct ArrivalMomentPanel: View {
    let isActive: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: VaktSpace.md) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Next")
                    .font(VaktFont.caption(11))
                    .foregroundStyle(Color.vaktMuted)
                    .textCase(.uppercase)
                    .tracking(0.7)

                Text("Asr")
                    .font(VaktFont.prayerDisplay(46))
                    .foregroundStyle(Color.vaktPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: VaktSpace.md)

            VStack(alignment: .trailing, spacing: 7) {
                Text("in")
                    .font(VaktFont.caption(11))
                    .foregroundStyle(Color.vaktMuted)
                    .textCase(.uppercase)
                    .tracking(0.7)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("12")
                        .font(VaktFont.timeDisplay(34))
                        .foregroundStyle(Color.vaktAccent)
                        .monospacedDigit()

                    Text("min")
                        .font(VaktFont.body(13))
                        .foregroundStyle(Color.vaktMuted)
                }
            }
        }
        .padding(.horizontal, VaktSpace.md)
        .padding(.vertical, 15)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.vaktSurface.opacity(0.88))
                .overlay(alignment: .topLeading) {
                    LinearGradient(
                        colors: [
                            Color.vaktPrimary.opacity(isActive ? 0.12 : 0.07),
                            Color.vaktAccent.opacity(0.025),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.vaktAccent.opacity(isActive ? 0.48 : 0.26), lineWidth: 0.7)
        )
        .shadow(color: Color.vaktDeep.opacity(0.24), radius: 18, y: 14)
    }
}

private struct ArrivalMicroSignals: View {
    var body: some View {
        HStack(spacing: VaktSpace.sm) {
            ArrivalSignalPill(title: "Time", value: "kept near")
            ArrivalSignalPill(title: "Saf", value: "gathering")
        }
    }
}

private struct ArrivalSignalPill: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color.vaktAccent.opacity(0.82))
                .frame(width: 5, height: 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(VaktFont.caption(10))
                    .foregroundStyle(Color.vaktMuted)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Text(value)
                    .font(VaktFont.caption(11))
                    .foregroundStyle(Color.vaktSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vaktSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.vaktBorder, lineWidth: 0.5)
        )
    }
}

private struct ArrivalContinueButton: View {
    let onContinue: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onContinue()
        } label: {
            HStack(spacing: VaktSpace.sm) {
                Text("Continue")
                    .font(VaktFont.button(15))
                    .foregroundStyle(Color.vaktBg)

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.vaktBg)
            }
            .padding(.horizontal, VaktSpace.md)
            .frame(height: 54)
            .background(Color.vaktPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(VaktPressStyle())
        .accessibilityLabel("Continue")
    }
}

private struct ArrivalHorizonScene: View {
    let focusX: CGFloat
    let isTouching: Bool
    let isBreathing: Bool
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let breath = CGFloat((sin(time * 0.62) + 1) / 2)
                let lineY = size.height * 0.36

                drawBackground(ctx: ctx, size: size, breath: breath)
                drawPrayerWindow(ctx: ctx, size: size, lineY: lineY, breath: breath)
                drawHorizon(ctx: ctx, size: size, lineY: lineY, breath: breath)
                drawCompanions(ctx: ctx, size: size, lineY: lineY, breath: breath)
                drawCurrentUser(ctx: ctx, size: size, lineY: lineY, breath: breath)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawBackground(ctx: GraphicsContext, size: CGSize, breath: CGFloat) {
        ctx.fill(
            Path(CGRect(x: 0, y: 0, width: size.width, height: size.height)),
            with: .color(.vaktBg)
        )

        let glowWidth = size.width * (0.54 + (isTouching ? 0.08 : 0))
        let glow = CGRect(
            x: size.width * focusX - glowWidth / 2,
            y: size.height * 0.15,
            width: glowWidth,
            height: size.height * 0.26
        )
        ctx.fill(
            Path(ellipseIn: glow),
            with: .color(.vaktAccent.opacity(0.04 + Double(breath) * 0.02 + (isTouching ? 0.03 : 0)))
        )

        let earth = CGRect(x: 0, y: size.height * 0.36, width: size.width, height: size.height * 0.64)
        ctx.fill(Path(earth), with: .color(.vaktDeep.opacity(0.88)))
    }

    private func drawPrayerWindow(ctx: GraphicsContext, size: CGSize, lineY: CGFloat, breath: CGFloat) {
        let x = size.width * focusX
        let height = size.height * (0.20 + (isTouching ? 0.06 : 0))
        let rect = CGRect(
            x: x - size.width * 0.11,
            y: lineY - height * 0.78,
            width: size.width * 0.22,
            height: height
        )

        ctx.fill(
            Path(ellipseIn: rect),
            with: .color(.vaktPrimary.opacity(0.025 + Double(breath) * 0.018 + (isTouching ? 0.04 : 0)))
        )
    }

    private func drawHorizon(ctx: GraphicsContext, size: CGSize, lineY: CGFloat, breath: CGFloat) {
        var main = Path()
        main.move(to: CGPoint(x: size.width * 0.12, y: lineY))
        main.addLine(to: CGPoint(x: size.width * 0.88, y: lineY))
        ctx.stroke(
            main,
            with: .color(.vaktAccent.opacity(0.18 + Double(breath) * 0.04 + (isTouching ? 0.07 : 0))),
            lineWidth: isTouching ? 1.1 : 0.7
        )

        var soft = Path()
        soft.move(to: CGPoint(x: size.width * 0.25, y: lineY + 17))
        soft.addLine(to: CGPoint(x: size.width * 0.75, y: lineY + 17))
        ctx.stroke(soft, with: .color(.vaktBorderStrong.opacity(0.38)), lineWidth: 0.5)
    }

    private func drawCompanions(ctx: GraphicsContext, size: CGSize, lineY: CGFloat, breath: CGFloat) {
        let dots: [(x: CGFloat, y: CGFloat)] = [
            (0.19, -4), (0.28, 6), (0.38, -1), (0.62, 1), (0.72, -6), (0.81, 6)
        ]

        for (index, dot) in dots.enumerated() {
            let pull = (focusX - dot.x) * (isTouching ? 0.07 : 0.025)
            let float = reduceMotion ? 0 : CGFloat(sin(Double(index) * 0.9 + Double(breath) * 2.0)) * 1.4
            let x = size.width * (dot.x + pull)
            let y = lineY + dot.y + float
            let radius = CGFloat(index == 2 || index == 3 ? 3.5 : 2.7)

            ctx.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                with: .color(.vaktAccent.opacity(isTouching ? 0.62 : 0.36))
            )
        }
    }

    private func drawCurrentUser(ctx: GraphicsContext, size: CGSize, lineY: CGFloat, breath: CGFloat) {
        let center = CGPoint(x: size.width * 0.5, y: lineY)
        let glow = CGFloat((isBreathing ? 19 : 13) + breath * 4 + (isTouching ? 7 : 0))

        ctx.fill(
            Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)),
            with: .color(.vaktPrimary.opacity(0.05 + (isTouching ? 0.055 : 0)))
        )

        ctx.fill(
            Path(ellipseIn: CGRect(x: center.x - 5.2, y: center.y - 5.2, width: 10.4, height: 10.4)),
            with: .color(.vaktPrimary.opacity(0.95))
        )
    }
}
