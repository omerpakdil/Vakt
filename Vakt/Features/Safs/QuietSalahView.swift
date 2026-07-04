import SwiftUI

struct QuietSalahView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let session: PrayerQuietSession
    @ObservedObject var presenceStore: LiveSafPresenceStore
    @ObservedObject var reflectionStore: PrayerReflectionStore
    @ObservedObject var sessionStore: PrayerSessionStore

    @State private var appeared = false
    @State private var quietStartedAt = Date()
    @State private var quietEndedAt = Date()
    @State private var checkInPresented = false
    @State private var checkInCompleted = false

    var body: some View {
        ZStack {
            quietBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: VaktSpace.xxxl)

                VStack(spacing: VaktSpace.sm) {
                    Text("FOR SALAH")
                        .font(VaktFont.eyebrow(10))
                        .foregroundStyle(Color.vaktAccent.opacity(0.42))
                        .tracking(2.6)

                    Text(session.prayer.displayName)
                        .font(VaktFont.prayerDisplay(54))
                        .foregroundStyle(Color.vaktPrimary.opacity(0.82))
                        .tracking(1.2)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)

                Spacer(minLength: VaktSpace.xl)

                QuietPresenceField(memberCount: displayedPresenceCount, event: presenceStore.lastEvent)
                    .frame(height: 260)
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.94)
                    .padding(.horizontal, -VaktSpace.lg)

                VStack(spacing: VaktSpace.xs) {
                    Text("Put the phone away")
                        .font(VaktFont.title(20))
                        .foregroundStyle(Color.vaktPrimary.opacity(0.72))

                    PresenceCountLine(
                        count: displayedPresenceCount,
                        direction: presenceCountDirection,
                        reduceMotion: reduceMotion
                    )

                    Text(presenceEventLine)
                        .font(VaktFont.caption(10))
                        .foregroundStyle(Color.vaktPrimary.opacity(presenceStore.lastEvent == nil ? 0 : 0.62))
                        .tracking(0.45)
                        .frame(height: 14)
                        .contentTransition(.opacity)
                        .animation(reduceMotion ? .none : .easeOut(duration: 0.22), value: presenceStore.lastEvent)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)

                Spacer()

                Text("May this prayer be accepted.")
                    .font(VaktFont.caption(11))
                    .foregroundStyle(Color.vaktMuted.opacity(0.55))
                    .tracking(0.35)
                    .padding(.bottom, VaktSpace.md)

                Button("I have finished") {
                    finishQuietMode()
                }
                .font(VaktFont.body(14))
                .foregroundStyle(Color.vaktMuted.opacity(0.65))
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .overlay(
                    Capsule()
                        .stroke(Color.vaktAccent.opacity(0.12), lineWidth: 0.5)
                )
                .padding(.bottom, VaktSpace.xl)
            }
            .padding(.horizontal, VaktSpace.lg)

            if checkInPresented {
                if checkInCompleted {
                    PostPrayerCompletionTransition(
                        prayer: session.prayer,
                        companionCount: displayedPresenceCount,
                        onDismiss: {
                            dismiss()
                        }
                    )
                    .transition(.opacity)
                } else {
                    Color.vaktDeep.opacity(0.72)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    PostPrayerCheckInView(
                        prayer: session.prayer,
                        companionCount: displayedPresenceCount,
                        onSelect: recordReflectionAndComplete,
                        onSkip: skipReflectionAndDismiss
                    )
                    .padding(.horizontal, VaktSpace.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            quietStartedAt = session.startedAt
            withAnimation(reduceMotion ? .none : .easeOut(duration: 1.1)) {
                appeared = true
            }
        }
    }

    private var quietBackground: some View {
        ZStack {
            Color.vaktDeep

            RadialGradient(
                colors: [
                    Color.vaktElevated.opacity(0.58),
                    Color.vaktBg.opacity(0.24),
                    Color.vaktDeep.opacity(0)
                ],
                center: .center,
                startRadius: 20,
                endRadius: 340
            )
            .scaleEffect(1.25)

            LinearGradient(
                colors: [
                    Color.vaktDeep.opacity(0.96),
                    Color.vaktBg.opacity(0.72),
                    Color.vaktDeep
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var presenceEventLine: String {
        guard let presenceEvent = presenceStore.lastEvent else { return " " }
        switch presenceEvent.direction {
        case .joined:
            return "+\(presenceEvent.magnitude) came to the Saf"
        case .left:
            return "-\(presenceEvent.magnitude) stepped away"
        }
    }

    private var presenceCountDirection: Int {
        presenceStore.countDirection
    }

    private var displayedPresenceCount: Int {
        presenceStore.displayMemberCount
    }

    private func finishQuietMode() {
        guard !checkInPresented else { return }

        quietEndedAt = Date()
        checkInCompleted = false

        let completedSession = sessionStore.completeSession(
            id: session.id,
            endedAt: quietEndedAt,
            companionCount: displayedPresenceCount
        ) ?? session

        quietStartedAt = completedSession.startedAt

        if sessionStore.shouldRequestReflection(for: session.id) {
            withAnimation(reduceMotion ? .none : .spring(response: 0.42, dampingFraction: 0.86)) {
                checkInPresented = true
            }
        } else {
            presentCompletionAndDismiss()
        }
    }

    private func recordReflectionAndComplete(_ outcome: PrayerReflectionOutcome) {
        guard !checkInCompleted else { return }
        guard sessionStore.shouldRequestReflection(for: session.id) else {
            presentCompletionAndDismiss()
            return
        }

        let resolvedSession = sessionStore.session(with: session.id) ?? session

        reflectionStore.record(
            prayer: resolvedSession.prayer,
            prayerDate: resolvedSession.prayerDate,
            outcome: outcome,
            companionCount: resolvedSession.companionCount,
            quietStartedAt: resolvedSession.startedAt,
            quietEndedAt: resolvedSession.endedAt ?? quietEndedAt
        )

        sessionStore.markReflectionRecorded(for: session.id)
        presentCompletionAndDismiss()
    }

    private func skipReflectionAndDismiss() {
        if sessionStore.shouldRequestReflection(for: session.id) {
            sessionStore.markReflectionSkipped(for: session.id)
        }

        dismiss()
    }

    private func presentCompletionAndDismiss() {
        guard !checkInCompleted else { return }

        if !checkInPresented {
            checkInPresented = true
        }

        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.44)) {
            checkInCompleted = true
        }

        let dismissDelay: UInt64 = reduceMotion ? 1_150_000_000 : 2_550_000_000
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: dismissDelay)
            dismiss()
        }
    }
}

private struct PostPrayerCheckInView: View {
    let prayer: Prayer
    let companionCount: Int
    let onSelect: (PrayerReflectionOutcome) -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            options
            skipButton
        }
        .padding(VaktSpace.md)
        .background(Color.vaktBg)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.vaktAccent.opacity(0.22), lineWidth: 0.6)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 28, y: 18)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            EyebrowLabel(text: "After salah")

            Text("Did you pray \(prayer.displayName)?")
                .font(VaktFont.title(28))
                .foregroundStyle(Color.vaktPrimary)
                .tracking(-0.4)

            Text("\(max(companionCount - 1, 6)) others were with the Saf. Keep only what helps you remember.")
                .font(VaktFont.body(13))
                .foregroundStyle(Color.vaktMuted)
                .lineSpacing(4)
        }
    }

    private var options: some View {
        VStack(spacing: VaktSpace.sm) {
            ForEach(PrayerReflectionOutcome.allCases) { outcome in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onSelect(outcome)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: outcome.symbolName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(outcome == .missed ? Color.vaktMuted : Color.vaktPrimary)
                            .frame(width: 20)

                        Text(outcome.title)
                            .font(VaktFont.body(15))
                            .foregroundStyle(Color.vaktPrimary)

                        Spacer()

                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.vaktShadow)
                    }
                    .padding(.horizontal, VaktSpace.md)
                    .frame(height: 52)
                    .background(Color.vaktSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.vaktBorder, lineWidth: 0.5)
                    )
                }
                .buttonStyle(VaktPressStyle())
            }
        }
    }

    private var skipButton: some View {
        Button {
            onSkip()
        } label: {
            Text("Not now")
                .font(VaktFont.body(14))
                .foregroundStyle(Color.vaktMuted)
            .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(VaktPressStyle())
    }
}

private struct PostPrayerCompletionTransition: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let prayer: Prayer
    let companionCount: Int
    let onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.vaktDeep
                .opacity(0.96)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                Text(prayer.displayName)
                    .font(VaktFont.eyebrow(10))
                    .foregroundStyle(Color.vaktAccent.opacity(0.38))
                    .tracking(2.4)

                Text("Kept with care")
                    .font(VaktFont.title(30))
                    .foregroundStyle(Color.vaktPrimary.opacity(0.9))
                    .tracking(-0.35)

                Text("This stays private on your device.")
                    .font(VaktFont.body(14))
                    .foregroundStyle(Color.vaktMuted.opacity(0.78))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, VaktSpace.xl)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onDismiss()
        }
        .onAppear {
            withAnimation(reduceMotion ? .none : .easeOut(duration: 0.55)) {
                appeared = true
            }
        }
    }
}

private struct QuietPresenceField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let memberCount: Int
    let event: LiveSafPresenceEvent?
    private var layout: PresenceHorizonLayout {
        PresenceHorizonLayout(memberCount: memberCount)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let horizonY = size.height * 0.50
                let center = CGPoint(x: size.width * 0.5, y: horizonY)
                let breath = (sin(time * 1.15) + 1) / 2

                drawAtmosphere(ctx: ctx, size: size, horizonY: horizonY, breath: breath, density: layout.density)
                drawDensityBands(ctx: ctx, size: size, horizonY: horizonY, breath: breath, bands: layout.bands)
                drawHorizon(ctx: ctx, size: size, horizonY: horizonY, density: layout.density)
                drawMembers(ctx: ctx, size: size, horizonY: horizonY, time: time, dots: layout.dots)
                drawEvent(ctx: ctx, size: size, horizonY: horizonY, time: time, event: event)
                drawCurrentUser(ctx: ctx, center: center, breath: breath, density: layout.density)
            }
            .accessibilityLabel(accessibilityDescription)
        }
    }

    private var accessibilityDescription: String {
        "\(max(memberCount, 7)) people standing with you in the Saf"
    }

    private func drawAtmosphere(ctx: GraphicsContext, size: CGSize, horizonY: CGFloat, breath: Double, density: Double) {
        let glowHeight = size.height * (0.46 + CGFloat(density) * 0.14 + CGFloat(breath) * 0.05)
        let glowRect = CGRect(
            x: size.width * (0.10 - CGFloat(density) * 0.06),
            y: horizonY - glowHeight * 0.52,
            width: size.width * (0.80 + CGFloat(density) * 0.12),
            height: glowHeight
        )

        ctx.fill(
            Path(ellipseIn: glowRect),
            with: .color(.vaktAccent.opacity(0.045 + 0.06 * density + 0.025 * breath))
        )

        let lowerRect = CGRect(x: 0, y: horizonY, width: size.width, height: size.height - horizonY)
        ctx.fill(Path(lowerRect), with: .color(.vaktDeep.opacity(0.45)))
    }

    private func drawDensityBands(ctx: GraphicsContext, size: CGSize, horizonY: CGFloat, breath: Double, bands: [PresenceHorizonBand]) {
        for band in bands {
            let y = horizonY + band.yOffset + CGFloat(breath - 0.5) * band.drift
            var path = Path()
            path.move(to: CGPoint(x: size.width * band.start, y: y))
            path.addLine(to: CGPoint(x: size.width * band.end, y: y))

            ctx.stroke(
                path,
                with: .color(.vaktGlow.opacity(band.opacity + 0.018 * breath)),
                lineWidth: band.width
            )
        }
    }

    private func drawHorizon(ctx: GraphicsContext, size: CGSize, horizonY: CGFloat, density: Double) {
        var baseline = Path()
        baseline.move(to: CGPoint(x: size.width * 0.08, y: horizonY))
        baseline.addLine(to: CGPoint(x: size.width * 0.92, y: horizonY))
        ctx.stroke(baseline, with: .color(.vaktAccent.opacity(0.22 + 0.12 * density)), lineWidth: 0.6 + density * 0.35)

        var nearLine = Path()
        nearLine.move(to: CGPoint(x: size.width * (0.27 - CGFloat(density) * 0.06), y: horizonY))
        nearLine.addLine(to: CGPoint(x: size.width * (0.73 + CGFloat(density) * 0.06), y: horizonY))
        ctx.stroke(nearLine, with: .color(.vaktPrimary.opacity(0.16 + 0.08 * density)), lineWidth: 1 + density * 0.45)
    }

    private func drawMembers(ctx: GraphicsContext, size: CGSize, horizonY: CGFloat, time: TimeInterval, dots: [PresenceHorizonDot]) {
        for dot in dots {
            let phase = time * dot.speed + dot.phase
            let pulse = reduceMotion ? 0.45 : (sin(phase) + 1) / 2
            let radius = dot.radius + CGFloat(pulse) * dot.pulse
            let x = size.width * dot.x
            let y = horizonY + dot.yOffset + CGFloat(sin(phase * 0.45)) * dot.drift
            let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)

            if dot.glow > 0 {
                let glowRadius = radius + dot.glow
                let glowRect = CGRect(x: x - glowRadius, y: y - glowRadius, width: glowRadius * 2, height: glowRadius * 2)
                ctx.fill(Path(ellipseIn: glowRect), with: .color(.vaktAccent.opacity(dot.opacity * 0.18)))
            }

            ctx.fill(Path(ellipseIn: rect), with: .color(.vaktAccent.opacity(dot.opacity + 0.14 * pulse)))
        }
    }

    private func drawEvent(ctx: GraphicsContext, size: CGSize, horizonY: CGFloat, time: TimeInterval, event: LiveSafPresenceEvent?) {
        guard let event else { return }

        let elapsed = reduceMotion ? 1 : min(1, max(0, time - event.createdAt.timeIntervalSinceReferenceDate) / 1.55)
        let eased = elapsed * elapsed * (3 - 2 * elapsed)
        let pulse = reduceMotion ? 0.55 : (sin(time * 7.5 + Double(event.companionIndex)) + 1) / 2
        let jitter = CGFloat((event.companionIndex % 3) - 1) * 0.014
        let x = size.width * min(0.9, max(0.1, event.anchor + jitter))
        let startY = event.direction == .joined ? horizonY - 58 : horizonY - 1
        let endY = event.direction == .joined ? horizonY - 2 : horizonY + 52
        let y = startY + (endY - startY) * CGFloat(eased)
        let coreRadius = CGFloat(event.direction == .joined ? 3.8 + eased * 1.9 : 5.2 - eased * 2.4)
        let ringRadius = CGFloat(15 + pulse * 10 + Double(event.magnitude - 1) * 4)
        let opacity = event.direction == .joined ? min(1, elapsed * 2.4) : max(0, 1 - elapsed * 0.92)
        let eventColor = event.direction == .joined ? Color.vaktPrimary : Color.vaktAccent

        var trail = Path()
        trail.move(to: CGPoint(x: x, y: event.direction == .joined ? y - 24 : horizonY))
        trail.addLine(to: CGPoint(x: x, y: y))
        ctx.stroke(
            trail,
            with: .color(eventColor.opacity(0.24 * opacity)),
            lineWidth: 1.1
        )

        ctx.fill(
            Path(ellipseIn: CGRect(x: x - ringRadius, y: y - ringRadius, width: ringRadius * 2, height: ringRadius * 2)),
            with: .color(eventColor.opacity((event.direction == .joined ? 0.13 : 0.07) * opacity))
        )

        ctx.stroke(
            Path(ellipseIn: CGRect(x: x - ringRadius * 0.58, y: y - ringRadius * 0.58, width: ringRadius * 1.16, height: ringRadius * 1.16)),
            with: .color(eventColor.opacity((event.direction == .joined ? 0.44 : 0.22) * opacity)),
            lineWidth: event.direction == .joined ? 1.1 : 0.8
        )

        ctx.fill(
            Path(ellipseIn: CGRect(x: x - coreRadius, y: y - coreRadius, width: coreRadius * 2, height: coreRadius * 2)),
            with: .color(eventColor.opacity((event.direction == .joined ? 0.96 : 0.46) * opacity))
        )
    }

    private func drawCurrentUser(ctx: GraphicsContext, center: CGPoint, breath: Double, density: Double) {
        let outerRadius = CGFloat(34 + density * 12 + breath * 12)
        let middleRadius = CGFloat(16 + density * 5 + breath * 5)
        let coreRadius = CGFloat(6.5)

        ctx.fill(
            Path(ellipseIn: CGRect(
                x: center.x - outerRadius,
                y: center.y - outerRadius,
                width: outerRadius * 2,
                height: outerRadius * 2
            )),
            with: .color(.vaktPrimary.opacity(0.032 + density * 0.025 + breath * 0.035))
        )

        ctx.fill(
            Path(ellipseIn: CGRect(
                x: center.x - middleRadius,
                y: center.y - middleRadius,
                width: middleRadius * 2,
                height: middleRadius * 2
            )),
            with: .color(.vaktGlow.opacity(0.11 + density * 0.04 + breath * 0.06))
        )

        ctx.fill(
            Path(ellipseIn: CGRect(
                x: center.x - coreRadius,
                y: center.y - coreRadius,
                width: coreRadius * 2,
                height: coreRadius * 2
            )),
            with: .color(.vaktPrimary.opacity(0.9))
        )
    }
}

private struct PresenceCountLine: View {
    let count: Int
    let direction: Int
    let reduceMotion: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            RollingNumberText(value: count, direction: direction, reduceMotion: reduceMotion)

            Text("people standing with you")
                .font(VaktFont.body(13))
                .foregroundStyle(Color.vaktAccent.opacity(0.48))
                .tracking(0.5)
        }
        .padding(.top, 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) people standing with you")
    }
}

private struct RollingNumberText: View {
    let value: Int
    let direction: Int
    let reduceMotion: Bool
    @State private var isPulsing = false

    private var digits: [String] {
        String(max(0, value)).map(String.init)
    }

    var body: some View {
        HStack(spacing: 0.5) {
            ForEach(Array(digits.enumerated()), id: \.offset) { _, digit in
                RollingDigitText(digit: digit, direction: direction, reduceMotion: reduceMotion)
            }
        }
        .font(.system(size: 17, weight: .light, design: .default))
        .foregroundStyle(Color.vaktPrimary.opacity(0.9))
        .monospacedDigit()
        .tracking(0.5)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color.vaktPrimary.opacity(isPulsing ? 0.075 : 0.025))
        )
        .scaleEffect(isPulsing ? 1.08 : 1)
        .onChange(of: value) { _, _ in
            guard !reduceMotion else { return }
            withAnimation(.snappy(duration: 0.18, extraBounce: 0.05)) {
                isPulsing = true
            }

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 220_000_000)
                withAnimation(.easeOut(duration: 0.32)) {
                    isPulsing = false
                }
            }
        }
    }
}

private struct RollingDigitText: View {
    let digit: String
    let direction: Int
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Text(digit)
                .id(digit)
                .transition(digitTransition)
        }
        .frame(width: 10, height: 22)
        .clipped()
        .animation(reduceMotion ? .none : .spring(response: 0.34, dampingFraction: 0.82), value: digit)
    }

    private var digitTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }

        let insertionEdge: Edge = direction >= 0 ? .bottom : .top
        let removalEdge: Edge = direction >= 0 ? .top : .bottom
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }
}

private struct QuietPresenceEvent: Equatable {
    enum Direction {
        case joined
        case left
    }

    let id: UUID
    let direction: Direction
    let magnitude: Int
    let anchor: CGFloat
    let companionIndex: Int
    let createdAt: Date

    static func anchor(for index: Int) -> CGFloat {
        let anchors: [CGFloat] = [0.28, 0.72, 0.18, 0.82, 0.38, 0.62]
        return anchors[index % anchors.count]
    }
}
