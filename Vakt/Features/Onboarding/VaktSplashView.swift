import SwiftUI

struct VaktSplashView: View {
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealProgress: CGFloat = 0
    @State private var actionIsVisible = false
    @State private var isLeaving = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                CinematicLightSurface(
                    revealProgress: revealProgress,
                    isLeaving: isLeaving,
                    reduceMotion: reduceMotion
                )

                LinearGradient(
                    colors: [
                        Color.vaktDeep.opacity(0.12),
                        .clear,
                        Color.vaktDeep.opacity(0.28),
                        Color.vaktDeep.opacity(0.78)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                Text(L10n.string("common.app_name"))
                    .font(.system(size: 62, weight: .ultraLight, design: .serif))
                    .tracking(1.8)
                    .foregroundStyle(Color(hex: "#F2F0EA"))
                    .opacity(isLeaving ? 0 : wordmarkOpacity)
                    .blur(radius: wordmarkBlur)
                    .scaleEffect(isLeaving ? 1.025 : 1)
                    .position(
                        x: proxy.size.width / 2,
                        y: proxy.size.height * 0.44
                    )

                VStack(spacing: 0) {
                    Spacer()

                    SplashContinueControl(
                        isVisible: actionIsVisible,
                        isLeaving: isLeaving
                    )
                    .padding(.horizontal, VaktSpace.lg)
                    .padding(.bottom, max(24, proxy.safeAreaInsets.bottom + 18))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .overlay {
                OnboardingShellBackground()
                    .opacity(isLeaving ? 1 : 0)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                leaveSplash()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.string("common.app_name"))
            .accessibilityHint(
                actionIsVisible
                    ? L10n.string("splash.accessibility.tap_to_begin")
                    : L10n.string("splash.accessibility.preparing")
            )
            .accessibilityAddTraits(actionIsVisible ? .isButton : [])
            .accessibilityAction {
                leaveSplash()
            }
        }
        .background(Color.vaktDeep)
        .task { await reveal() }
    }

    private var wordmarkOpacity: Double {
        min(1, max(0, Double((revealProgress - 0.2) / 0.55)))
    }

    private var wordmarkBlur: CGFloat {
        max(0, 8 * (1 - revealProgress * 1.4))
    }

    private func reveal() async {
        guard revealProgress == 0 else { return }

        withAnimation(reduceMotion ? .none : .easeInOut(duration: 1.55)) {
            revealProgress = 1
        }

        try? await Task.sleep(for: .milliseconds(reduceMotion ? 80 : 1_250))
        withAnimation(reduceMotion ? .none : .easeOut(duration: 0.45)) {
            actionIsVisible = true
        }
    }

    private func leaveSplash() {
        guard actionIsVisible, !isLeaving else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()

        withAnimation(.easeInOut(duration: reduceMotion ? 0.16 : 0.82)) {
            isLeaving = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 100 : 760))
            onComplete()
        }
    }
}

private struct CinematicLightSurface: View {
    let revealProgress: CGFloat
    let isLeaving: Bool
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let driftX = reduceMotion ? 0 : CGFloat(sin(time * 0.13)) * 4
                let driftY = reduceMotion ? 0 : CGFloat(cos(time * 0.11)) * 3

                ZStack {
                    Image("SplashArchitectureDark")
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(1.045 + revealProgress * 0.012)
                        .offset(x: driftX, y: driftY)

                    Canvas { context, size in
                        drawMovingLight(context: context, size: size, time: time)
                        drawTexture(context: context, size: size)
                    }

                    LinearGradient(
                        colors: [
                            Color.vaktDeep.opacity(0.16),
                            Color.vaktDeep.opacity(0.08),
                            Color.vaktDeep.opacity(0.32),
                            Color.vaktDeep.opacity(0.68)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        }
        .scaleEffect(isLeaving ? 1.018 : 1)
        .clipped()
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func drawMovingLight(
        context: GraphicsContext,
        size: CGSize,
        time: TimeInterval
    ) {
        let drift = reduceMotion ? 0 : CGFloat(sin(time * 0.16)) * size.width * 0.035
        let expansion = revealProgress * size.width * 0.06
        let center = CGPoint(
            x: size.width * 0.57 + drift,
            y: size.height * 0.44
        )
        let lightSize = CGSize(
            width: size.width * 0.86 + expansion,
            height: size.height * 0.58 + expansion
        )
        let rect = CGRect(
            x: center.x - lightSize.width / 2,
            y: center.y - lightSize.height / 2,
            width: lightSize.width,
            height: lightSize.height
        )

        context.fill(
            Path(ellipseIn: rect),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color(hex: "#F0DFC0").opacity(0.08 * Double(revealProgress)), location: 0),
                    .init(color: Color.vaktGlow.opacity(0.035 * Double(revealProgress)), location: 0.42),
                    .init(color: .clear, location: 1)
                ]),
                center: center,
                startRadius: 4,
                endRadius: max(rect.width, rect.height) * 0.5
            )
        )
    }

    private func drawTexture(context: GraphicsContext, size: CGSize) {
        for index in 0..<34 {
            let x = size.width * CGFloat((index * 43) % 107) / 107
            let y = size.height * CGFloat((index * 67) % 127) / 127
            let radius: CGFloat = index % 4 == 0 ? 1.1 : 0.65
            context.fill(
                Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
                with: .color(Color.vaktPrimary.opacity(0.022 + Double(index % 3) * 0.008))
            )
        }
    }
}

private struct SplashContinueControl: View {
    let isVisible: Bool
    let isLeaving: Bool

    var body: some View {
        TimelineView(.animation(paused: !isVisible || isLeaving)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let breath = (sin(time * 1.7) + 1) / 2

            ZStack {
                Ellipse()
                    .fill(Color(hex: "#F0DFC0").opacity(0.03 + breath * 0.03))
                    .frame(width: 170 + breath * 10, height: 48)
                    .blur(radius: 12)

                VStack(spacing: 10) {
                    Text(L10n.string("splash.action.tap_to_begin"))
                        .font(VaktFont.body(12))
                        .foregroundStyle(Color.vaktPrimary.opacity(0.66 + breath * 0.14))

                    ZStack {
                        Capsule()
                            .fill(Color.vaktPrimary.opacity(0.07))
                            .frame(width: 72, height: 1)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, Color(hex: "#F2E7D2"), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: 30 + breath * 28, height: 1.5)
                            .shadow(color: Color(hex: "#F0DFC0").opacity(0.22), radius: 6)
                    }
                }
            }
            .frame(width: 188, height: 70)
        }
        .opacity(isVisible && !isLeaving ? 1 : 0)
        .offset(y: isVisible ? 0 : 10)
        .accessibilityHidden(!isVisible)
        .allowsHitTesting(false)
    }
}
