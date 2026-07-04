import SwiftUI

struct VaktSplashView: View {
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var holdProgress: CGFloat = 0
    @State private var isHolding = false
    @State private var didComplete = false
    @State private var touchX: CGFloat = 0.5
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.vaktDeep.ignoresSafeArea()

                QuietSplashScene(
                    progress: holdProgress,
                    touchX: touchX,
                    isHolding: isHolding,
                    reduceMotion: reduceMotion
                )
                .ignoresSafeArea()
                .gesture(trackTouch(width: proxy.size.width))

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    VStack(spacing: 8) {
                        Text("Vakt")
                            .font(.system(size: 62, weight: .ultraLight, design: .default))
                            .foregroundStyle(Color.vaktPrimary)
                            .tracking(1.2)

                        Text("Come to prayer gently")
                            .font(VaktFont.body(14))
                            .foregroundStyle(Color.vaktMuted)
                            .tracking(0.6)
                    }
                    .padding(.bottom, 108)

                    QuietSplashHoldButton(
                        progress: holdProgress,
                        isHolding: isHolding,
                        onPressingChanged: setHolding
                    )
                    .padding(.horizontal, VaktSpace.lg)
                    .padding(.bottom, VaktSpace.xl)
                }
            }
        }
    }

    private func trackTouch(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard width > 0 else { return }
                touchX = min(1, max(0, value.location.x / width))
            }
    }

    private func setHolding(_ holding: Bool) {
        guard !didComplete, holding != isHolding else { return }

        isHolding = holding
        holdTask?.cancel()

        if holding {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            startHoldProgress()
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                holdProgress = 0
            }
        }
    }

    private func startHoldProgress() {
        holdTask = Task { @MainActor in
            let steps = 36

            for step in 1...steps {
                try? await Task.sleep(nanoseconds: 34_000_000)
                guard isHolding, !didComplete, !Task.isCancelled else { return }

                withAnimation(.linear(duration: 0.034)) {
                    holdProgress = CGFloat(step) / CGFloat(steps)
                }
            }

            complete()
        }
    }

    private func complete() {
        guard !didComplete else { return }

        didComplete = true
        holdTask?.cancel()
        holdProgress = 1
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            onComplete()
        }
    }
}

private struct QuietSplashScene: View {
    let progress: CGFloat
    let touchX: CGFloat
    let isHolding: Bool
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let breath = CGFloat((sin(time * 0.65) + 1) / 2)
                let lineY = size.height * 0.54

                drawSky(ctx: ctx, size: size, breath: breath)
                drawTouchGlow(ctx: ctx, size: size, lineY: lineY, breath: breath)
                drawHorizon(ctx: ctx, size: size, lineY: lineY, breath: breath)
                drawCompanions(ctx: ctx, size: size, lineY: lineY, breath: breath)
                drawYou(ctx: ctx, size: size, lineY: lineY, breath: breath)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawSky(ctx: GraphicsContext, size: CGSize, breath: CGFloat) {
        let upper = CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.62)
        ctx.fill(Path(upper), with: .color(.vaktBg.opacity(0.9)))

        let lower = CGRect(x: 0, y: size.height * 0.54, width: size.width, height: size.height * 0.46)
        ctx.fill(Path(lower), with: .color(.vaktDeep))

        let glowWidth = size.width * (0.52 + progress * 0.18)
        let glowHeight = size.height * (0.20 + progress * 0.08)
        let glow = CGRect(
            x: (size.width - glowWidth) / 2,
            y: size.height * 0.30,
            width: glowWidth,
            height: glowHeight
        )

        ctx.fill(
            Path(ellipseIn: glow),
            with: .color(.vaktAccent.opacity(0.035 + Double(progress) * 0.055 + Double(breath) * 0.012))
        )
    }

    private func drawTouchGlow(ctx: GraphicsContext, size: CGSize, lineY: CGFloat, breath: CGFloat) {
        let x = size.width * touchX
        let width = size.width * (0.16 + progress * 0.10)
        let rect = CGRect(
            x: x - width / 2,
            y: lineY - size.height * 0.24,
            width: width,
            height: size.height * 0.34
        )

        ctx.fill(
            Path(ellipseIn: rect),
            with: .color(.vaktPrimary.opacity((isHolding ? 0.045 : 0.018) + Double(progress) * 0.03 + Double(breath) * 0.01))
        )
    }

    private func drawHorizon(ctx: GraphicsContext, size: CGSize, lineY: CGFloat, breath: CGFloat) {
        let start = size.width * 0.17
        let end = size.width * 0.83

        var base = Path()
        base.move(to: CGPoint(x: start, y: lineY))
        base.addLine(to: CGPoint(x: end, y: lineY))
        ctx.stroke(
            base,
            with: .color(.vaktAccent.opacity(0.15 + Double(progress) * 0.22 + Double(breath) * 0.03)),
            lineWidth: 0.6 + progress * 0.7
        )

        var near = Path()
        near.move(to: CGPoint(x: size.width * 0.29, y: lineY + 18))
        near.addLine(to: CGPoint(x: size.width * 0.71, y: lineY + 18))
        ctx.stroke(
            near,
            with: .color(.vaktBorderStrong.opacity(0.32 + Double(progress) * 0.18)),
            lineWidth: 0.5
        )
    }

    private func drawCompanions(ctx: GraphicsContext, size: CGSize, lineY: CGFloat, breath: CGFloat) {
        let dots: [(x: CGFloat, y: CGFloat)] = [
            (0.24, -4),
            (0.34, 7),
            (0.43, -1),
            (0.57, 2),
            (0.66, -6),
            (0.76, 6)
        ]

        for (index, dot) in dots.enumerated() {
            let side: CGFloat = dot.x < 0.5 ? -1 : 1
            let approach = progress * 0.035 * side
            let float = reduceMotion ? 0 : CGFloat(sin(Double(index) + breath * 2.0)) * 1.6
            let x = size.width * (dot.x - approach)
            let y = lineY + dot.y + float
            let radius = 2.5 + progress * 1.2
            let opacity = 0.22 + Double(progress) * 0.38

            ctx.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                with: .color(.vaktAccent.opacity(opacity))
            )
        }
    }

    private func drawYou(ctx: GraphicsContext, size: CGSize, lineY: CGFloat, breath: CGFloat) {
        let center = CGPoint(x: size.width * 0.5, y: lineY)
        let glowRadius = 14 + progress * 16 + breath * 3
        let coreRadius = 5 + progress * 1.2

        ctx.fill(
            Path(ellipseIn: CGRect(
                x: center.x - glowRadius,
                y: center.y - glowRadius,
                width: glowRadius * 2,
                height: glowRadius * 2
            )),
            with: .color(.vaktPrimary.opacity(0.035 + Double(progress) * 0.10))
        )

        ctx.fill(
            Path(ellipseIn: CGRect(
                x: center.x - coreRadius,
                y: center.y - coreRadius,
                width: coreRadius * 2,
                height: coreRadius * 2
            )),
            with: .color(.vaktPrimary.opacity(0.94))
        )
    }
}

private struct QuietSplashHoldButton: View {
    let progress: CGFloat
    let isHolding: Bool
    let onPressingChanged: (Bool) -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.vaktSurface)

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.vaktPrimary.opacity(0.08 + Double(progress) * 0.13))

            GeometryReader { proxy in
                let width = proxy.size.width
                let glowSize = width * (0.22 + progress * 0.16)
                let x = max(glowSize / 2, min(width - glowSize / 2, width * (0.18 + progress * 0.64)))

                Circle()
                    .fill(Color.vaktPrimary.opacity(0.10 + Double(progress) * 0.22))
                    .frame(width: glowSize, height: glowSize)
                    .blur(radius: 16)
                    .position(x: x, y: proxy.size.height / 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill(Color.vaktDeep.opacity(0.72))
                        .frame(width: 38, height: 38)

                    Circle()
                        .trim(from: 0, to: max(0.001, progress))
                        .stroke(Color.vaktPrimary.opacity(isHolding ? 0.78 : 0.34), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 26, height: 26)

                    Circle()
                        .fill(isHolding ? Color.vaktPrimary : Color.vaktAccent)
                        .frame(width: 6, height: 6)
                        .shadow(color: Color.vaktPrimary.opacity(isHolding ? 0.42 : 0.16), radius: isHolding ? 8 : 4)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(isHolding ? "Keep holding" : "Hold to begin")
                        .font(VaktFont.button(15))
                        .foregroundStyle(Color.vaktPrimary)
                        .contentTransition(.opacity)

                    Text(isHolding ? "Take a quiet breath" : "Begin with calm")
                        .font(VaktFont.caption(11))
                        .foregroundStyle(Color.vaktMuted)
                        .contentTransition(.opacity)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
        }
        .frame(height: 70)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.vaktAccent.opacity(isHolding ? 0.50 : 0.24), lineWidth: 0.7)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    onPressingChanged(true)
                }
                .onEnded { _ in
                    onPressingChanged(false)
                }
        )
        .accessibilityLabel("Hold to begin")
        .accessibilityAddTraits(.isButton)
    }
}
