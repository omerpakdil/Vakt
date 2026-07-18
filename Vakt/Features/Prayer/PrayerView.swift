import SwiftUI

struct PrayerView: View {
    @ObservedObject var prayerStore: PrayerScheduleStore
    @ObservedObject var reflectionStore: PrayerReflectionStore
    @ObservedObject var sessionStore: PrayerSessionStore
    @ObservedObject var socialPrayerStore: SocialPrayerStore
    @ObservedObject var spiritualContentStore: SpiritualContentStore
    let onReviewOpportunity: (Int) -> Void

    @State private var activeSession: PrayerQuietSession?
    @State private var makeupSheetPresented = false

    var body: some View {
        let prayerTime = prayerStore.activePrayer ?? prayerStore.nextPrayer
        let trackingStatus = reflectionStore.trackingStatus(
            for: prayerTime,
            sessionStatus: sessionStore.status(for: prayerTime)
        )

        GeometryReader { geometry in
            ZStack {
                PrayerPreparationAtmosphere()

                VStack(alignment: .leading, spacing: 0) {
                    PrayerPreparationHeader(
                        prayerTime: prayerTime,
                        countdown: prayerStore.nextCountdown,
                        status: trackingStatus
                    )

                    Spacer(minLength: 8)

                    PrayerMatRitual(
                        prayer: prayerTime.prayer,
                        status: trackingStatus,
                        onBegin: { beginQuietPrayer(prayerTime: prayerTime) }
                    )
                    .frame(height: min(474, max(414, geometry.size.height * 0.54)))

                    Spacer(minLength: 72)

                    PrayerContextLine(
                        prayer: prayerTime.prayer,
                        summaries: socialPrayerStore.friendSummaries,
                        makeupCount: socialPrayerStore.openMakeupPrayerCount,
                        onMakeup: {
                            if socialPrayerStore.openMakeupPrayerCount > 0 {
                                makeupSheetPresented = true
                            }
                        }
                    )
                }
                .padding(.horizontal, VaktSpace.lg)
                .padding(.top, max(17, geometry.safeAreaInsets.top + 13))
                .padding(.bottom, max(8, geometry.safeAreaInsets.bottom + 5))
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .navigationDestination(isPresented: $makeupSheetPresented) {
            MakeupPrayerCenterView(store: socialPrayerStore)
        }
        .fullScreenCover(item: $activeSession, onDismiss: {
            onReviewOpportunity(reflectionStore.startedTogetherCount)
        }) { session in
            QuietSalahView(
                session: session,
                reflectionStore: reflectionStore,
                sessionStore: sessionStore,
                socialPrayerStore: socialPrayerStore,
                spiritualContentStore: spiritualContentStore
            )
        }
        .onAppear {
            socialPrayerStore.refresh(for: prayerTime.time, timeZone: prayerTime.timeZone)
        }
        .onChange(of: prayerTime.prayer) { _, _ in
            socialPrayerStore.refresh(for: prayerTime.time, timeZone: prayerTime.timeZone)
        }
    }

    private func beginQuietPrayer(prayerTime: PrayerTime) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        activeSession = sessionStore.beginSession(for: prayerTime, companionCount: 0)
    }
}

private struct PrayerPreparationAtmosphere: View {
    var body: some View {
        ZStack {
            Color.vaktDeep.ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color(hex: "#111827"),
                    Color.vaktBg,
                    Color.vaktDeep
                ],
                startPoint: .topLeading,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color.vaktGlow.opacity(0.11), .clear],
                center: UnitPoint(x: 0.5, y: 0.38),
                startRadius: 18,
                endRadius: 330
            )
            .ignoresSafeArea()

            Canvas { context, size in
                var floor = Path()
                floor.move(to: CGPoint(x: 0, y: size.height * 0.68))
                floor.addLine(to: CGPoint(x: size.width, y: size.height * 0.68))
                context.stroke(floor, with: .color(Color.vaktBorder.opacity(0.22)), lineWidth: 0.5)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

private struct PrayerPreparationHeader: View {
    let prayerTime: PrayerTime
    let countdown: TimeInterval
    let status: PrayerTrackingStatus

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string("prayer.preparation.eyebrow"))
                    .font(VaktFont.eyebrow(9))
                    .foregroundStyle(Color.vaktMuted)
                    .tracking(1.8)

                Text(title)
                    .font(VaktFont.title(31))
                    .foregroundStyle(Color.vaktPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(VaktFont.body(12))
                    .foregroundStyle(Color.vaktMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 6) {
                Text(prayerTime.prayer.displayName)
                    .font(VaktFont.body(14))
                    .foregroundStyle(Color.vaktPrimary)

                Text(VaktTimeFormatter.string(from: prayerTime.time, timeZone: prayerTime.timeZone))
                    .font(VaktFont.timeDisplay(17))
                    .foregroundStyle(Color.vaktGlow)
                    .monospacedDigit()

                Text(remainingText)
                    .font(VaktFont.caption(9))
                    .foregroundStyle(Color.vaktMuted)
                    .monospacedDigit()
            }
        }
    }

    private var title: String {
        switch status {
        case .ready, .missed: L10n.string("prayer.header.ready.title")
        case .inProgress: L10n.string("prayer.header.in_progress.title")
        case .prayed, .later: L10n.string("prayer.header.complete.title")
        }
    }

    private var subtitle: String {
        switch status {
        case .ready, .missed: L10n.string("prayer.header.ready.subtitle")
        case .inProgress: L10n.string("prayer.header.in_progress.subtitle")
        case .prayed, .later: L10n.string("prayer.header.complete.subtitle")
        }
    }

    private var remainingText: String {
        let minutes = max(0, Int(ceil(countdown / 60)))
        return L10n.timeRemaining(minutes: minutes)
    }
}

private struct PrayerMatRitual: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let prayer: Prayer
    let status: PrayerTrackingStatus
    let onBegin: () -> Void

    @State private var appeared = false
    @State private var buttonPressed = false

    var body: some View {
        ZStack(alignment: .bottom) {
            PrayerMatArtwork(status: status)
                .padding(.horizontal, 4)
                .padding(.bottom, 28)
                .scaleEffect(appeared ? 1 : 0.97, anchor: .bottom)
                .opacity(appeared ? 1 : 0)

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onBegin()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: isOpen ? "arrow.counterclockwise" : "moon.haze")
                        .font(.system(size: 17, weight: .light))
                        .foregroundStyle(Color.vaktGlow)
                        .frame(width: 28)

                    Rectangle()
                        .fill(Color.vaktBorderStrong.opacity(0.75))
                        .frame(width: 0.5, height: 34)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(buttonTitle)
                            .font(VaktFont.button(16))

                        Text(buttonSubtitle)
                            .font(VaktFont.caption(10))
                            .foregroundStyle(Color.vaktMuted)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.vaktDeep)
                        .frame(width: 34, height: 34)
                        .background(Color.vaktGlow)
                        .clipShape(Circle())
                }
                .foregroundStyle(Color.vaktPrimary)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .frame(height: 70)
                .background(
                    LinearGradient(
                        colors: [Color(hex: "#263C5B"), Color(hex: "#172840")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [Color.vaktGlow.opacity(0.5), Color.vaktGlow.opacity(0.08), Color.clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(height: 0.8)
                    .padding(.horizontal, 16)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                        .strokeBorder(Color.vaktGlow.opacity(0.46), lineWidth: 0.9)
                )
                .shadow(color: Color.vaktAccent.opacity(0.22), radius: 18, y: 8)
            }
            .buttonStyle(VaktPressStyle())
            .padding(.horizontal, 10)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 48 : 56)
        }
        .onAppear {
            withAnimation(reduceMotion ? .none : .easeOut(duration: 0.85)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var isOpen: Bool {
        if case .inProgress = status { return true }
        return false
    }

    private var buttonTitle: String {
        isOpen
            ? L10n.string("prayer.action.return")
            : L10n.string("prayer.action.begin")
    }

    private var buttonSubtitle: String {
        switch status {
        case .ready:
            L10n.formatString("prayer.action.begin.subtitle", prayer.localizedName)
        case .missed:
            L10n.string("prayer.action.begin.subtitle.missed")
        case .inProgress:
            L10n.string("prayer.action.return.subtitle")
        case .prayed, .later:
            L10n.string("prayer.action.begin.subtitle.complete")
        }
    }
}

private struct PrayerMatArtwork: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let status: PrayerTrackingStatus

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                drawMat(context: context, size: size, time: time)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawMat(context: GraphicsContext, size: CGSize, time: TimeInterval) {
        let breath = (sin(time * 0.52) + 1) * 0.5
        let centerX = size.width * 0.5
        let topY = size.height * 0.055
        let bottomY = size.height * 0.91
        let topWidth = size.width * 0.62
        let bottomWidth = size.width * 0.86

        let shadow = matPath(
            centerX: centerX,
            topY: topY + 8,
            bottomY: bottomY + 8,
            topWidth: topWidth + 8,
            bottomWidth: bottomWidth + 13
        )
        context.fill(shadow, with: .color(Color.black.opacity(0.26)))

        let mat = matPath(
            centerX: centerX,
            topY: topY,
            bottomY: bottomY,
            topWidth: topWidth,
            bottomWidth: bottomWidth
        )
        context.fill(
            mat,
            with: .linearGradient(
                Gradient(colors: [
                    Color(hex: "#2B4148").opacity(0.96),
                    Color(hex: "#193039"),
                    Color(hex: "#101F2A")
                ]),
                startPoint: CGPoint(x: centerX, y: topY),
                endPoint: CGPoint(x: centerX, y: bottomY)
            )
        )

        context.stroke(
            mat,
            with: .color(Color(hex: "#A89A75").opacity(0.34 + breath * 0.035)),
            lineWidth: 1
        )

        drawWovenField(
            context: context,
            centerX: centerX,
            topY: topY,
            bottomY: bottomY,
            topWidth: topWidth,
            bottomWidth: bottomWidth
        )

        let inner = matPath(
            centerX: centerX,
            topY: topY + 16,
            bottomY: bottomY - 17,
            topWidth: topWidth * 0.84,
            bottomWidth: bottomWidth * 0.87
        )
        context.stroke(inner, with: .color(Color(hex: "#A89A75").opacity(0.24)), lineWidth: 1)

        let secondBorder = matPath(
            centerX: centerX,
            topY: topY + 25,
            bottomY: bottomY - 29,
            topWidth: topWidth * 0.75,
            bottomWidth: bottomWidth * 0.77
        )
        context.stroke(secondBorder, with: .color(Color.vaktPrimary.opacity(0.075)), lineWidth: 0.7)

        drawNiche(
            context: context,
            centerX: centerX,
            topY: topY,
            matWidth: topWidth,
            matHeight: bottomY - topY,
            breath: breath
        )

        drawSideWeave(
            context: context,
            centerX: centerX,
            topY: topY,
            bottomY: bottomY,
            topWidth: topWidth,
            bottomWidth: bottomWidth
        )

        drawOrnamentalBands(
            context: context,
            centerX: centerX,
            topY: topY,
            bottomY: bottomY,
            topWidth: topWidth,
            bottomWidth: bottomWidth
        )

        drawTassels(
            context: context,
            centerX: centerX,
            bottomY: bottomY,
            width: bottomWidth
        )

        drawTopTassels(
            context: context,
            centerX: centerX,
            topY: topY,
            width: topWidth
        )

        let light = CGRect(
            x: centerX - topWidth * 0.53,
            y: topY - 14,
            width: topWidth * 1.06,
            height: topWidth * 0.92
        )
        context.fill(
            Path(ellipseIn: light),
            with: .color(Color.vaktGlow.opacity(0.025 + breath * 0.018))
        )
    }

    private func drawWovenField(
        context: GraphicsContext,
        centerX: CGFloat,
        topY: CGFloat,
        bottomY: CGFloat,
        topWidth: CGFloat,
        bottomWidth: CGFloat
    ) {
        for index in 1..<18 {
            let progress = CGFloat(index) / 18
            let y = topY + (bottomY - topY) * progress
            let width = topWidth + (bottomWidth - topWidth) * progress
            var line = Path()
            line.move(to: CGPoint(x: centerX - width * 0.43, y: y))
            line.addLine(to: CGPoint(x: centerX + width * 0.43, y: y))
            context.stroke(
                line,
                with: .color(Color.vaktPrimary.opacity(index.isMultiple(of: 4) ? 0.045 : 0.018)),
                lineWidth: index.isMultiple(of: 4) ? 0.65 : 0.35
            )
        }
    }

    private func drawNiche(
        context: GraphicsContext,
        centerX: CGFloat,
        topY: CGFloat,
        matWidth: CGFloat,
        matHeight: CGFloat,
        breath: Double
    ) {
        let baseY = topY + matHeight * 0.39
        let width = matWidth * 0.58
        let apexY = topY + matHeight * 0.095

        var niche = Path()
        niche.move(to: CGPoint(x: centerX - width / 2, y: baseY))
        niche.addLine(to: CGPoint(x: centerX - width / 2, y: apexY + 42))
        niche.addCurve(
            to: CGPoint(x: centerX, y: apexY),
            control1: CGPoint(x: centerX - width / 2, y: apexY + 13),
            control2: CGPoint(x: centerX - width * 0.12, y: apexY + 17)
        )
        niche.addCurve(
            to: CGPoint(x: centerX + width / 2, y: apexY + 42),
            control1: CGPoint(x: centerX + width * 0.12, y: apexY + 17),
            control2: CGPoint(x: centerX + width / 2, y: apexY + 13)
        )
        niche.addLine(to: CGPoint(x: centerX + width / 2, y: baseY))
        context.stroke(
            niche,
            with: .color(Color.vaktPrimary.opacity(0.16 + breath * 0.025)),
            lineWidth: 0.9
        )

        var base = Path()
        base.move(to: CGPoint(x: centerX - width * 0.66, y: baseY))
        base.addLine(to: CGPoint(x: centerX + width * 0.66, y: baseY))
        context.stroke(base, with: .color(Color.vaktAccent.opacity(0.13)), lineWidth: 0.7)

        let centerMark = CGRect(x: centerX - 2.2, y: apexY + 39, width: 4.4, height: 4.4)
        context.fill(Path(ellipseIn: centerMark), with: .color(Color.vaktPrimary.opacity(0.18)))
    }

    private func drawSideWeave(
        context: GraphicsContext,
        centerX: CGFloat,
        topY: CGFloat,
        bottomY: CGFloat,
        topWidth: CGFloat,
        bottomWidth: CGFloat
    ) {
        for side: CGFloat in [-1, 1] {
            var rail = Path()
            rail.move(to: CGPoint(x: centerX + side * topWidth * 0.38, y: topY + 17))
            rail.addLine(to: CGPoint(x: centerX + side * bottomWidth * 0.4, y: bottomY - 17))
            context.stroke(rail, with: .color(Color.vaktAccent.opacity(0.11)), lineWidth: 1)

            var innerRail = Path()
            innerRail.move(to: CGPoint(x: centerX + side * topWidth * 0.32, y: topY + 17))
            innerRail.addLine(to: CGPoint(x: centerX + side * bottomWidth * 0.34, y: bottomY - 17))
            context.stroke(innerRail, with: .color(Color.vaktPrimary.opacity(0.055)), lineWidth: 0.6)
        }
    }

    private func drawTassels(context: GraphicsContext, centerX: CGFloat, bottomY: CGFloat, width: CGFloat) {
        for index in 0..<13 {
            let progress = CGFloat(index) / 12
            let x = centerX - width * 0.39 + width * 0.78 * progress
            let length: CGFloat = index.isMultiple(of: 2) ? 10 : 7
            var tassel = Path()
            tassel.move(to: CGPoint(x: x, y: bottomY - 1))
            tassel.addLine(to: CGPoint(x: x + (index.isMultiple(of: 2) ? 1.5 : -1.5), y: bottomY + length))
            context.stroke(tassel, with: .color(Color.vaktMuted.opacity(0.3)), lineWidth: 0.7)
        }
    }

    private func drawTopTassels(context: GraphicsContext, centerX: CGFloat, topY: CGFloat, width: CGFloat) {
        for index in 0..<11 {
            let progress = CGFloat(index) / 10
            let x = centerX - width * 0.39 + width * 0.78 * progress
            let length: CGFloat = index.isMultiple(of: 2) ? 7 : 5
            var tassel = Path()
            tassel.move(to: CGPoint(x: x, y: topY + 1))
            tassel.addLine(to: CGPoint(x: x + (index.isMultiple(of: 2) ? -1 : 1), y: topY - length))
            context.stroke(tassel, with: .color(Color(hex: "#A89A75").opacity(0.3)), lineWidth: 0.65)
        }
    }

    private func drawOrnamentalBands(
        context: GraphicsContext,
        centerX: CGFloat,
        topY: CGFloat,
        bottomY: CGFloat,
        topWidth: CGFloat,
        bottomWidth: CGFloat
    ) {
        let positions: [CGFloat] = [0.18, 0.72]
        for position in positions {
            let y = topY + (bottomY - topY) * position
            let width = topWidth + (bottomWidth - topWidth) * position

            var upper = Path()
            upper.move(to: CGPoint(x: centerX - width * 0.34, y: y - 4))
            upper.addLine(to: CGPoint(x: centerX + width * 0.34, y: y - 4))
            context.stroke(upper, with: .color(Color(hex: "#A89A75").opacity(0.16)), lineWidth: 0.7)

            var lower = Path()
            lower.move(to: CGPoint(x: centerX - width * 0.34, y: y + 4))
            lower.addLine(to: CGPoint(x: centerX + width * 0.34, y: y + 4))
            context.stroke(lower, with: .color(Color(hex: "#A89A75").opacity(0.16)), lineWidth: 0.7)

            for index in 0..<7 {
                let progress = CGFloat(index) / 6
                let x = centerX - width * 0.27 + width * 0.54 * progress
                var diamond = Path()
                diamond.move(to: CGPoint(x: x, y: y - 3))
                diamond.addLine(to: CGPoint(x: x + 3, y: y))
                diamond.addLine(to: CGPoint(x: x, y: y + 3))
                diamond.addLine(to: CGPoint(x: x - 3, y: y))
                diamond.closeSubpath()
                context.stroke(diamond, with: .color(Color.vaktPrimary.opacity(0.09)), lineWidth: 0.55)
            }
        }
    }

    private func matPath(
        centerX: CGFloat,
        topY: CGFloat,
        bottomY: CGFloat,
        topWidth: CGFloat,
        bottomWidth: CGFloat
    ) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: centerX - topWidth / 2, y: topY))
        path.addQuadCurve(
            to: CGPoint(x: centerX + topWidth / 2, y: topY),
            control: CGPoint(x: centerX, y: topY - 3)
        )
        path.addLine(to: CGPoint(x: centerX + bottomWidth / 2, y: bottomY))
        path.addQuadCurve(
            to: CGPoint(x: centerX - bottomWidth / 2, y: bottomY),
            control: CGPoint(x: centerX, y: bottomY + 4)
        )
        path.closeSubpath()
        return path
    }
}

private struct PrayerContextLine: View {
    let prayer: Prayer
    let summaries: [FriendPrayerSummary]
    let makeupCount: Int
    let onMakeup: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "person.2")
                    .font(.system(size: 12, weight: .light))

                Text(circleText)
                    .font(VaktFont.caption(10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(Color.vaktMuted)

            Spacer()

            if makeupCount > 0 {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onMakeup()
                } label: {
                    HStack(spacing: 6) {
                        Text(makeupText)
                            .font(VaktFont.caption(10))

                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(Color.vaktMuted)
                }
                .buttonStyle(VaktPressStyle())
            }
        }
        .frame(height: 34)
    }

    private var circleText: String {
        guard !summaries.isEmpty else {
            return L10n.string("prayer.context.friends.empty")
        }
        let prayed = summaries.filter { summary in
            switch summary.statuses[PrayerKey(prayer)] {
            case .prayedOnTime, .prayedLater, .madeUp: true
            case .preparing, .notMarked, nil: false
            }
        }.count
        let key = prayed == 1
            ? "prayer.context.friends.one"
            : "prayer.context.friends.many"
        return L10n.formatString(key, prayed)
    }

    private var makeupText: String {
        let key = makeupCount == 1
            ? "prayer.context.makeup.one"
            : "prayer.context.makeup.many"
        return L10n.formatString(key, makeupCount)
    }
}
