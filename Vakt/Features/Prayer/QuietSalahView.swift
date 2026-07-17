import SwiftUI

struct QuietSalahView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let session: PrayerQuietSession
    @ObservedObject var reflectionStore: PrayerReflectionStore
    @ObservedObject var sessionStore: PrayerSessionStore
    @ObservedObject var socialPrayerStore: SocialPrayerStore
    @ObservedObject var spiritualContentStore: SpiritualContentStore

    @State private var appeared = false
    @State private var quietStartedAt = Date()
    @State private var quietEndedAt = Date()
    @State private var checkInPresented = false
    @State private var checkInCompleted = false
    @State private var completionIsLeaving = false
    @State private var completionContent: SpiritualContent?
    @State private var introVisible = true
    @State private var controlsVisible = false
    @State private var hideControlsTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            quietBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 70)

                VStack(spacing: VaktSpace.sm) {
                    Text(L10n.string("quiet.eyebrow"))
                        .font(VaktFont.eyebrow(10))
                        .foregroundStyle(Color.vaktAccent.opacity(0.38))
                        .tracking(2.6)

                    Text(session.prayer.displayName)
                        .font(VaktFont.prayerDisplay(54))
                        .foregroundStyle(Color.vaktPrimary.opacity(0.82))
                }
                .opacity(appeared && introVisible ? 1 : 0)
                .offset(y: appeared && introVisible ? 0 : -8)

                Spacer(minLength: 18)

                QuietPrayerFocusField()
                    .frame(height: 390)
                    .opacity(appeared ? (introVisible ? 0.9 : 0.46) : 0)
                    .scaleEffect(appeared ? (introVisible ? 1 : 1.055) : 0.95, anchor: .bottom)
                    .padding(.horizontal, -34)

                VStack(spacing: VaktSpace.xs) {
                    Text(L10n.string("quiet.phone_aside"))
                        .font(VaktFont.title(20))
                        .foregroundStyle(Color.vaktPrimary.opacity(0.72))

                    Text(L10n.string("quiet.with_intention"))
                        .font(VaktFont.body(13))
                        .foregroundStyle(Color.vaktAccent.opacity(0.48))
                }
                .opacity(appeared && introVisible ? 1 : 0)
                .offset(y: appeared && introVisible ? 0 : 8)

                Spacer()

                Button {
                    finishQuietMode()
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))

                        Text(L10n.string("quiet.finished"))
                            .font(VaktFont.body(13))
                    }
                    .foregroundStyle(Color.vaktPrimary.opacity(0.68))
                    .padding(.horizontal, 22)
                    .frame(height: 44)
                    .background(Color.vaktSurface.opacity(0.24))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.vaktAccent.opacity(0.14), lineWidth: 0.5)
                    )
                }
                .buttonStyle(VaktPressStyle())
                .opacity(controlsVisible ? 1 : 0)
                .offset(y: controlsVisible ? 0 : 8)
                .allowsHitTesting(controlsVisible)
                .padding(.bottom, VaktSpace.xl)
            }
            .padding(.horizontal, VaktSpace.lg)

            if checkInPresented {
                if checkInCompleted {
                    PostPrayerCompletionTransition(
                        prayer: session.prayer,
                        content: completionContent,
                        isLeaving: completionIsLeaving,
                        onDismiss: {
                            dismissCompletionSoon()
                        }
                    )
                    .transition(.opacity)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            revealControls()
        }
        .onAppear {
            quietStartedAt = session.startedAt
            withAnimation(reduceMotion ? .none : .easeOut(duration: 1.1)) {
                appeared = true
            }

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(reduceMotion ? 1 : 4))
                withAnimation(reduceMotion ? .none : .easeInOut(duration: 1.2)) {
                    introVisible = false
                }

                try? await Task.sleep(for: .seconds(reduceMotion ? 1 : 8))
                revealControls(autoHide: false)
            }
        }
        .onDisappear {
            hideControlsTask?.cancel()
        }
    }

    private func revealControls(autoHide: Bool = true) {
        guard !checkInPresented else { return }
        hideControlsTask?.cancel()

        withAnimation(reduceMotion ? .none : .easeOut(duration: 0.42)) {
            controlsVisible = true
        }

        guard autoHide else { return }
        hideControlsTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.55)) {
                controlsVisible = false
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

    private func finishQuietMode() {
        guard !checkInPresented else { return }

        quietEndedAt = Date()
        checkInCompleted = false
        completionIsLeaving = false

        let completedSession = sessionStore.completeSession(
            id: session.id,
            endedAt: quietEndedAt,
            companionCount: 0
        ) ?? session

        quietStartedAt = completedSession.startedAt

        if sessionStore.shouldRequestReflection(for: session.id) {
            reflectionStore.record(
                prayer: completedSession.prayer,
                prayerDate: completedSession.prayerDate,
                outcome: .prayed,
                companionCount: completedSession.companionCount,
                quietStartedAt: completedSession.startedAt,
                quietEndedAt: completedSession.endedAt ?? quietEndedAt
            )
            sessionStore.markReflectionRecorded(for: session.id)
        }

        let prayerTime = PrayerTime(
            prayer: completedSession.prayer,
            time: completedSession.prayerDate,
            countdown: 0,
            timeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier
        )
        socialPrayerStore.mark(prayerTime, outcome: .prayed, markedAt: quietEndedAt)

        presentCompletionAndDismiss(outcome: .prayed)
    }

    private func presentCompletionAndDismiss(outcome: PrayerReflectionOutcome?) {
        guard !checkInCompleted else { return }

        completionContent = spiritualContentStore.content(
            for: session.prayer,
            outcome: outcome,
            at: Date(),
            languageCode: VaktLocalization.languageCode
        )
        completionIsLeaving = false

        if !checkInPresented {
            checkInPresented = true
        }

        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.7)) {
            checkInCompleted = true
        }

        let readingDelay: UInt64 = reduceMotion ? 2_200_000_000 : 5_250_000_000
        let exitDelay: UInt64 = reduceMotion ? 120_000_000 : 1_050_000_000
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: readingDelay)
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 1.0)) {
                completionIsLeaving = true
            }
            try? await Task.sleep(nanoseconds: exitDelay)
            dismiss()
        }
    }

    private func dismissCompletionSoon() {
        guard checkInCompleted else {
            dismiss()
            return
        }

        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.42)) {
            completionIsLeaving = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: reduceMotion ? 80_000_000 : 460_000_000)
            dismiss()
        }
    }
}

private struct PostPrayerCompletionTransition: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let prayer: Prayer
    let content: SpiritualContent?
    let isLeaving: Bool
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var detailsAppeared = false

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
                    .opacity(detailsAppeared && !isLeaving ? 1 : 0)
                    .offset(y: detailsAppeared && !isLeaving ? 0 : 4)

                Text(contentText)
                    .font(VaktFont.title(contentText.count > 92 ? 23 : 27))
                    .foregroundStyle(Color.vaktPrimary.opacity(0.9))
                    .tracking(-0.35)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .opacity(appeared && !isLeaving ? 1 : 0)
                    .scaleEffect(appeared && !isLeaving ? 1 : 0.985)

                if let sourceDisplay {
                    VStack(spacing: 3) {
                        Text(sourceDisplay.primary)
                            .font(VaktFont.caption(11))
                            .foregroundStyle(Color.vaktAccent.opacity(0.52))
                            .multilineTextAlignment(.center)

                        if let secondary = sourceDisplay.secondary {
                            Text(secondary)
                                .font(VaktFont.caption(9))
                                .foregroundStyle(Color.vaktMuted.opacity(0.52))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.top, 4)
                    .opacity(detailsAppeared && !isLeaving ? 1 : 0)
                    .offset(y: detailsAppeared && !isLeaving ? 0 : 4)
                }
            }
            .padding(.horizontal, VaktSpace.xl)
            .opacity(appeared && !isLeaving ? 1 : 0)
            .offset(y: isLeaving ? -10 : (appeared ? 0 : 12))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onDismiss()
        }
        .onAppear {
            withAnimation(reduceMotion ? .none : .easeOut(duration: 0.9)) {
                appeared = true
            }

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: reduceMotion ? 0 : 220_000_000)
                withAnimation(reduceMotion ? .none : .easeOut(duration: 0.7)) {
                    detailsAppeared = true
                }
            }
        }
    }

    private var contentText: String {
        content?.text ?? L10n.string("completion.fallback")
    }

    private var sourceDisplay: CompletionSourceDisplay? {
        guard let content else { return nil }
        guard content.kind == .quran || content.kind == .hadith else { return nil }

        if let reference = content.reference, !reference.isEmpty {
            if content.kind == .quran {
                return CompletionSourceDisplay(
                    primary: QuranReferenceFormatter.displayReference(reference) ?? reference,
                    secondary: content.kind.displayName
                )
            }

            if let grade = content.grade, !grade.isEmpty {
                return CompletionSourceDisplay(
                    primary: L10n.formatString("spiritual.source.with_grade", content.kind.displayName, reference, grade),
                    secondary: nil
                )
            }

            return CompletionSourceDisplay(
                primary: L10n.formatString("spiritual.source.with_reference", content.kind.displayName, reference),
                secondary: nil
            )
        }

        return CompletionSourceDisplay(primary: content.kind.displayName, secondary: nil)
    }
}

private struct CompletionSourceDisplay {
    let primary: String
    let secondary: String?
}

private struct QuietPrayerFocusField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let drift = (sin(time * 0.32) + 1) / 2
                drawWovenMat(ctx: ctx, size: size, drift: drift)
            }
            .accessibilityLabel(L10n.string("quiet.focus_accessibility"))
        }
    }

    private func drawWovenMat(ctx: GraphicsContext, size: CGSize, drift: Double) {
        let centerX = size.width * 0.5
        let topY = size.height * 0.04
        let bottomY = size.height * 0.98
        let topWidth = size.width * 0.48
        let bottomWidth = size.width * 0.92

        let mat = matPath(
            centerX: centerX,
            topY: topY,
            bottomY: bottomY,
            topWidth: topWidth,
            bottomWidth: bottomWidth
        )
        ctx.fill(
            mat,
            with: .linearGradient(
                Gradient(colors: [
                    Color.vaktElevated.opacity(0.18 + drift * 0.025),
                    Color.vaktSurface.opacity(0.12),
                    Color.vaktDeep.opacity(0.04),
                ]),
                startPoint: CGPoint(x: centerX, y: topY),
                endPoint: CGPoint(x: centerX, y: bottomY)
            )
        )
        ctx.stroke(mat, with: .color(Color.vaktGlow.opacity(0.07 + drift * 0.025)), lineWidth: 0.7)

        let inner = matPath(
            centerX: centerX,
            topY: topY + 20,
            bottomY: bottomY - 20,
            topWidth: topWidth * 0.8,
            bottomWidth: bottomWidth * 0.84
        )
        ctx.stroke(inner, with: .color(Color.vaktPrimary.opacity(0.045)), lineWidth: 0.6)

        let apexY = topY + size.height * 0.08
        let baseY = topY + size.height * 0.36
        let nicheWidth = topWidth * 0.48
        var niche = Path()
        niche.move(to: CGPoint(x: centerX - nicheWidth / 2, y: baseY))
        niche.addLine(to: CGPoint(x: centerX - nicheWidth / 2, y: apexY + 34))
        niche.addCurve(
            to: CGPoint(x: centerX, y: apexY),
            control1: CGPoint(x: centerX - nicheWidth / 2, y: apexY + 12),
            control2: CGPoint(x: centerX - nicheWidth * 0.1, y: apexY + 12)
        )
        niche.addCurve(
            to: CGPoint(x: centerX + nicheWidth / 2, y: apexY + 34),
            control1: CGPoint(x: centerX + nicheWidth * 0.1, y: apexY + 12),
            control2: CGPoint(x: centerX + nicheWidth / 2, y: apexY + 12)
        )
        niche.addLine(to: CGPoint(x: centerX + nicheWidth / 2, y: baseY))
        ctx.stroke(niche, with: .color(Color.vaktPrimary.opacity(0.065 + drift * 0.018)), lineWidth: 0.65)

        for index in 1..<16 {
            let progress = CGFloat(index) / 16
            let y = topY + (bottomY - topY) * progress
            let width = topWidth + (bottomWidth - topWidth) * progress
            var weave = Path()
            weave.move(to: CGPoint(x: centerX - width * 0.4, y: y))
            weave.addLine(to: CGPoint(x: centerX + width * 0.4, y: y))
            ctx.stroke(
                weave,
                with: .color(Color.vaktPrimary.opacity(index.isMultiple(of: 4) ? 0.032 : 0.012)),
                lineWidth: 0.45
            )
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
        path.addLine(to: CGPoint(x: centerX + topWidth / 2, y: topY))
        path.addLine(to: CGPoint(x: centerX + bottomWidth / 2, y: bottomY))
        path.addLine(to: CGPoint(x: centerX - bottomWidth / 2, y: bottomY))
        path.closeSubpath()
        return path
    }
}
