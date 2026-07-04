import SwiftUI

struct OnboardingLocationView: View {
    let stepIndex: Int
    let stepCount: Int
    @ObservedObject var prayerStore: PrayerScheduleStore
    let reduceMotion: Bool
    let onContinue: () -> Void
    let onSkip: () -> Void

    @State private var dayPosition: CGFloat = 0.58
    @State private var isDragging = false
    @State private var isBreathing = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.vaktBg.ignoresSafeArea()

                LocationDayArcScene(
                    dayPosition: dayPosition,
                    isDragging: isDragging,
                    isBreathing: isBreathing && !reduceMotion,
                    reduceMotion: reduceMotion
                )
                .frame(height: proxy.size.height * 0.50)
                .frame(maxHeight: .infinity, alignment: .top)
                .offset(y: proxy.size.height * 0.105)
                .ignoresSafeArea()
                .gesture(dayArcGesture(width: proxy.size.width))

                VStack(spacing: 0) {
                    LocationPageMark(stepIndex: stepIndex, stepCount: stepCount)
                        .padding(.top, VaktSpace.xl)
                        .padding(.horizontal, VaktSpace.lg)

                    Spacer(minLength: proxy.size.height * 0.44)

                    VStack(alignment: .leading, spacing: 15) {
                        EyebrowLabel(text: "Local Time")

                        Text("Let Vakt find your prayer times.")
                            .font(VaktFont.title(31))
                            .foregroundStyle(Color.vaktPrimary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Approximate location is used only for local salah times. Your exact location is not shown.")
                            .font(VaktFont.body(14))
                            .foregroundStyle(Color.vaktMuted)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)

                        LocationQuietFact(status: prayerStore.status, onSkip: onSkip)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, VaktSpace.lg)
                    .padding(.bottom, 25)

                    LocationPrimaryActions(
                        status: prayerStore.status,
                        onContinue: onContinue
                    )
                    .padding(.horizontal, VaktSpace.lg)
                    .padding(.bottom, VaktSpace.lg)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }

    private func dayArcGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard width > 0 else { return }
                isDragging = true
                withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.86)) {
                    dayPosition = min(0.84, max(0.16, value.location.x / width))
                }
            }
            .onEnded { _ in
                isDragging = false
                withAnimation(.spring(response: 0.46, dampingFraction: 0.82)) {
                    dayPosition = 0.58
                }
            }
    }
}

private struct LocationPageMark: View {
    let stepIndex: Int
    let stepCount: Int

    var body: some View {
        HStack {
            Text("0\(stepIndex + 1) / 0\(stepCount)")
                .font(VaktFont.caption(11))
                .foregroundStyle(Color.vaktMuted)
                .monospacedDigit()
                .tracking(0.5)

            Spacer()
        }
        .accessibilityLabel("Onboarding step \(stepIndex + 1) of \(stepCount)")
    }
}

private struct LocationDayArcScene: View {
    let dayPosition: CGFloat
    let isDragging: Bool
    let isBreathing: Bool
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let breath = CGFloat((sin(time * 0.52) + 1) / 2)

                drawBackground(ctx: ctx, size: size)
                drawAtmosphericBridge(ctx: ctx, size: size, breath: breath)
                drawDayArc(ctx: ctx, size: size, breath: breath)
                drawPrayerMarks(ctx: ctx, size: size, breath: breath)
                drawCurrentMarker(ctx: ctx, size: size, breath: breath)
                drawLabels(ctx: ctx, size: size)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawBackground(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.vaktBg.opacity(0.96)))
    }

    private func drawAtmosphericBridge(ctx: GraphicsContext, size: CGSize, breath: CGFloat) {
        let horizonY = size.height * 0.70
        let glowRect = CGRect(
            x: size.width * 0.10,
            y: horizonY - size.height * 0.15,
            width: size.width * 0.80,
            height: size.height * 0.24
        )

        ctx.fill(
            Path(ellipseIn: glowRect),
            with: .color(.vaktAccent.opacity(0.028 + Double(breath) * 0.018 + (isDragging ? 0.018 : 0)))
        )

        var horizon = Path()
        horizon.move(to: CGPoint(x: size.width * 0.18, y: horizonY))
        horizon.addLine(to: CGPoint(x: size.width * 0.82, y: horizonY))
        ctx.stroke(
            horizon,
            with: .color(.vaktAccent.opacity(0.10 + Double(breath) * 0.025 + (isDragging ? 0.04 : 0))),
            lineWidth: 0.55
        )

        var lower = Path()
        lower.move(to: CGPoint(x: size.width * 0.32, y: horizonY + 16))
        lower.addLine(to: CGPoint(x: size.width * 0.68, y: horizonY + 16))
        ctx.stroke(lower, with: .color(.vaktBorderStrong.opacity(0.24)), lineWidth: 0.45)

        let marker = point(on: size, at: dayPosition)
        var trace = Path()
        trace.move(to: CGPoint(x: marker.x, y: marker.y + 8))
        trace.addCurve(
            to: CGPoint(x: size.width * 0.5, y: horizonY + 30),
            control1: CGPoint(x: marker.x, y: marker.y + 48),
            control2: CGPoint(x: size.width * 0.5, y: horizonY - 6)
        )
        ctx.stroke(
            trace,
            with: .color(.vaktPrimary.opacity(0.035 + (isDragging ? 0.08 : 0))),
            lineWidth: isDragging ? 0.75 : 0.45
        )
    }

    private func point(on size: CGSize, at t: CGFloat) -> CGPoint {
        let x = size.width * (0.12 + t * 0.76)
        let arcHeight = size.height * 0.28
        let y = size.height * 0.68 - sin(t * .pi) * arcHeight
        return CGPoint(x: x, y: y)
    }

    private func drawDayArc(ctx: GraphicsContext, size: CGSize, breath: CGFloat) {
        var arc = Path()
        let samples = 56

        for index in 0...samples {
            let t = CGFloat(index) / CGFloat(samples)
            let p = point(on: size, at: t)
            if index == 0 {
                arc.move(to: p)
            } else {
                arc.addLine(to: p)
            }
        }

        ctx.stroke(
            arc,
            with: .color(.vaktAccent.opacity(0.18 + Double(breath) * 0.025)),
            lineWidth: isDragging ? 1.15 : 0.75
        )

        let activeSamples = max(1, Int(dayPosition * CGFloat(samples)))
        var activeArc = Path()
        for index in 0...activeSamples {
            let t = CGFloat(index) / CGFloat(samples)
            let p = point(on: size, at: t)
            if index == 0 {
                activeArc.move(to: p)
            } else {
                activeArc.addLine(to: p)
            }
        }

        ctx.stroke(
            activeArc,
            with: .color(.vaktPrimary.opacity(0.12 + (isDragging ? 0.12 : 0))),
            lineWidth: 1.1
        )
    }

    private func drawPrayerMarks(ctx: GraphicsContext, size: CGSize, breath: CGFloat) {
        let marks: [(label: String, t: CGFloat)] = [
            ("Fajr", 0.08),
            ("Dhuhr", 0.42),
            ("Asr", 0.58),
            ("Maghrib", 0.76),
            ("Isha", 0.92)
        ]

        for mark in marks {
            let p = point(on: size, at: mark.t)
            let isCurrent = mark.label == "Asr"
            let distance = abs(mark.t - dayPosition)
            let near = max(0, 1 - distance * 8)
            let radius = isCurrent ? CGFloat(4.8 + near * 1.4) : CGFloat(2.8 + near)

            ctx.fill(
                Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(isCurrent ? .vaktPrimary.opacity(0.92) : .vaktAccent.opacity(0.30 + Double(near) * 0.34))
            )

            if isDragging || isCurrent {
                let resolved = ctx.resolve(
                    Text(mark.label)
                        .font(VaktFont.caption(isCurrent ? 10 : 9))
                        .foregroundStyle((isCurrent ? Color.vaktPrimary : Color.vaktMuted).opacity(isCurrent ? 0.92 : 0.62))
                )
                ctx.draw(resolved, at: CGPoint(x: p.x, y: p.y - 17), anchor: .center)
            }
        }
    }

    private func drawCurrentMarker(ctx: GraphicsContext, size: CGSize, breath: CGFloat) {
        let marker = point(on: size, at: dayPosition)
        let ring = CGFloat((isBreathing ? 15 : 11) + (isDragging ? 7 : 0) + breath * 2)

        ctx.stroke(
            Path(ellipseIn: CGRect(x: marker.x - ring, y: marker.y - ring, width: ring * 2, height: ring * 2)),
            with: .color(.vaktPrimary.opacity(0.08 + (isDragging ? 0.12 : 0))),
            lineWidth: 0.7
        )

        ctx.fill(
            Path(ellipseIn: CGRect(x: marker.x - 5, y: marker.y - 5, width: 10, height: 10)),
            with: .color(.vaktPrimary.opacity(0.96))
        )
    }

    private func drawLabels(ctx: GraphicsContext, size: CGSize) {
        let dawn = ctx.resolve(
            Text("Dawn")
                .font(VaktFont.caption(10))
                .foregroundStyle(Color.vaktShadow)
        )
        let night = ctx.resolve(
            Text("Night")
                .font(VaktFont.caption(10))
                .foregroundStyle(Color.vaktShadow)
        )

        ctx.draw(dawn, at: CGPoint(x: size.width * 0.13, y: size.height * 0.75), anchor: .leading)
        ctx.draw(night, at: CGPoint(x: size.width * 0.87, y: size.height * 0.75), anchor: .trailing)
    }
}

private struct LocationQuietFact: View {
    let status: PrayerScheduleStatus
    let onSkip: () -> Void

    var body: some View {
        HStack(spacing: VaktSpace.sm) {
            Text(statusText)
                .font(VaktFont.caption(11))
                .foregroundStyle(Color.vaktSecondary)

            Spacer(minLength: VaktSpace.sm)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onSkip()
            } label: {
                Text("Not now")
                    .font(VaktFont.caption(11))
                    .foregroundStyle(Color.vaktMuted)
                    .padding(.horizontal, 6)
                    .frame(minHeight: 44)
            }
            .buttonStyle(VaktPressStyle())
        }
    }

    private var statusText: String {
        switch status {
        case .ready, .usingSavedTimes:
            return "Your prayer times are ready."
        case .denied:
            return "You can set this later."
        case .failed:
            return "You can try again later."
        case .locating, .loading:
            return "Finding your local prayer times."
        }
    }
}

private struct LocationPrimaryActions: View {
    let status: PrayerScheduleStatus
    let onContinue: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onContinue()
        } label: {
            HStack(spacing: VaktSpace.sm) {
                Image(systemName: primaryIcon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.vaktBg)

                Text(primaryTitle)
                    .font(VaktFont.button(15))
                    .foregroundStyle(Color.vaktBg)

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.vaktBg)
            }
            .padding(.horizontal, VaktSpace.md)
            .frame(height: 56)
            .background(Color.vaktPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(VaktPressStyle())
        .accessibilityLabel(primaryTitle)
    }

    private var primaryTitle: String {
        switch status {
        case .ready, .usingSavedTimes:
            return "Continue"
        default:
            return "Use Location"
        }
    }

    private var primaryIcon: String {
        switch status {
        case .ready, .usingSavedTimes:
            return "checkmark"
        default:
            return "location.fill"
        }
    }
}
