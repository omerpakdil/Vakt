import SwiftUI
import UserNotifications

struct OnboardingView: View {
    @ObservedObject var store: OnboardingStore
    @ObservedObject var prayerStore: PrayerScheduleStore
    @ObservedObject var notificationManager: NotificationManager

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    private var page: OnboardingPage {
        store.pages[store.currentPage]
    }

    var body: some View {
        ZStack {
            Color.vaktBg.ignoresSafeArea()

            if page.id == .arrival {
                OnboardingArrivalView(
                    stepIndex: store.currentPage,
                    stepCount: OnboardingStore.plannedPageCount,
                    reduceMotion: reduceMotion
                ) {
                    store.advance()
                }
                .transition(.opacity)
            } else if page.id == .markPrayer {
                OnboardingPrayerMarkView(
                    stepIndex: store.currentPage,
                    stepCount: OnboardingStore.plannedPageCount,
                    reduceMotion: reduceMotion
                ) {
                    store.advance()
                }
                .transition(.opacity)
            } else if page.id == .friends {
                OnboardingFriendsView(
                    stepIndex: store.currentPage,
                    stepCount: OnboardingStore.plannedPageCount,
                    reduceMotion: reduceMotion
                ) {
                    store.advance()
                }
                .transition(.opacity)
            } else if page.id == .makeupCalendar {
                OnboardingMakeupCalendarView(
                    stepIndex: store.currentPage,
                    stepCount: OnboardingStore.plannedPageCount,
                    reduceMotion: reduceMotion
                ) {
                    store.advance()
                }
                .transition(.opacity)
            } else if page.id == .closingReminder {
                OnboardingClosingReminderView(
                    stepIndex: store.currentPage,
                    stepCount: OnboardingStore.plannedPageCount,
                    reduceMotion: reduceMotion
                ) {
                    store.advance()
                }
                .transition(.opacity)
            } else if page.id == .promise {
                OnboardingPromiseView(
                    stepIndex: store.currentPage,
                    stepCount: OnboardingStore.plannedPageCount,
                    reduceMotion: reduceMotion
                ) {
                    store.complete()
                }
                .transition(.opacity)
            } else if page.id == .gathering {
                OnboardingSafGatheringView(
                    stepIndex: store.currentPage,
                    stepCount: OnboardingStore.plannedPageCount,
                    reduceMotion: reduceMotion
                ) {
                    store.advance()
                }
                .transition(.opacity)
            } else if page.id == .placement {
                OnboardingSafPlacementView(
                    stepIndex: store.currentPage,
                    stepCount: OnboardingStore.plannedPageCount,
                    reduceMotion: reduceMotion
                ) {
                    store.advance()
                }
                .transition(.opacity)
            } else if page.id == .anonymousSaf {
                OnboardingAnonymousSafView(
                    stepIndex: store.currentPage,
                    stepCount: OnboardingStore.plannedPageCount,
                    reduceMotion: reduceMotion
                ) {
                    store.advance()
                }
                .transition(.opacity)
            } else if page.id == .location {
                OnboardingLocationView(
                    stepIndex: store.currentPage,
                    stepCount: OnboardingStore.plannedPageCount,
                    prayerStore: prayerStore,
                    reduceMotion: reduceMotion,
                    onContinue: {
                        prayerStore.requestLocationPermission()
                        store.advance()
                    },
                    onSkip: {
                        store.advance()
                    }
                )
                .transition(.opacity)
            } else if page.id == .reminders {
                OnboardingRemindersView(
                    stepIndex: store.currentPage,
                    stepCount: OnboardingStore.plannedPageCount,
                    notificationManager: notificationManager,
                    reduceMotion: reduceMotion,
                    onEnable: {
                        _ = await notificationManager.enableRemindersAndRequestAuthorization()
                        store.complete()
                    },
                    onSkip: {
                        notificationManager.setReminderEnabled(false)
                        store.complete()
                    }
                )
                .transition(.opacity)
            } else {
                genericPage
                    .transition(.opacity)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.9).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
        .animation(.easeInOut(duration: 0.32), value: store.currentPage)
    }

    private var genericPage: some View {
        VStack(spacing: 0) {
            onboardingHeader
                .padding(.top, VaktSpace.xl)

            OnboardingHorizonScene(
                kind: page.id,
                progress: pageProgress,
                isBreathing: isBreathing && !reduceMotion,
                reduceMotion: reduceMotion
            )
            .frame(height: 255)
            .padding(.top, VaktSpace.lg)
            .padding(.horizontal, -VaktSpace.lg)

            VStack(alignment: .leading, spacing: VaktSpace.md) {
                EyebrowLabel(text: page.eyebrow)

                Text(page.title)
                    .font(VaktFont.title(30))
                    .foregroundStyle(Color.vaktPrimary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text(page.body)
                    .font(VaktFont.body(14))
                    .foregroundStyle(Color.vaktMuted)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)

                pageDetail
                    .padding(.top, VaktSpace.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, VaktSpace.lg)
            .padding(.top, VaktSpace.md)

            Spacer(minLength: VaktSpace.md)

            actions
                .padding(.horizontal, VaktSpace.lg)
                .padding(.bottom, VaktSpace.lg)
        }
    }

    private var onboardingHeader: some View {
        HStack(spacing: VaktSpace.sm) {
            ForEach(store.pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index <= store.currentPage ? Color.vaktPrimary : Color.vaktBorderStrong)
                    .frame(height: 3)
                    .opacity(index <= store.currentPage ? 0.95 : 0.55)
            }
        }
        .padding(.horizontal, VaktSpace.lg)
        .accessibilityLabel(L10n.formatString("onboarding.step_accessibility", store.currentPage + 1, store.pages.count))
    }

    @ViewBuilder
    private var pageDetail: some View {
        switch page.id {
        case .arrival:
            OnboardingSignalRow(items: [
                (Prayer.asr.displayName, "12 \(L10n.string("onboarding.arrival.minute_short"))"),
                (L10n.string("common.saf"), L10n.string("onboarding.arrival.signal.gathering")),
                (L10n.string("onboarding.arrival.signal.you"), L10n.string("onboarding.gathering.status.ready"))
            ])
        case .markPrayer:
            EmptyView()
        case .friends:
            EmptyView()
        case .makeupCalendar:
            EmptyView()
        case .closingReminder:
            EmptyView()
        case .promise:
            EmptyView()
        case .gathering:
            EmptyView()
        case .placement:
            EmptyView()
        case .anonymousSaf:
            VStack(spacing: 0) {
                OnboardingPrivacyRow(title: L10n.string("onboarding.privacy.row.name"), value: L10n.string("onboarding.privacy.row.hidden"))
                VaktDivider()
                OnboardingPrivacyRow(title: L10n.string("onboarding.privacy.row.location"), value: L10n.string("onboarding.privacy.row.not_shown"))
                VaktDivider()
                OnboardingPrivacyRow(title: L10n.string("onboarding.privacy.row.saf_presence"), value: L10n.string("onboarding.privacy.row.private"))
            }
            .padding(.horizontal, VaktSpace.md)
            .background(Color.vaktSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.vaktBorder, lineWidth: 0.5)
            )
        case .location:
            OnboardingPermissionStatus(
                icon: "location.fill",
                title: locationStatusTitle,
                detail: prayerStore.statusMessage ?? L10n.string("onboarding.location.fallback"),
                isActive: locationStatusIsActive
            )
        case .reminders:
            OnboardingPermissionStatus(
                icon: notificationManager.areRemindersActive ? "bell.badge.fill" : "bell",
                title: reminderStatusTitle,
                detail: reminderStatusDetail,
                isActive: notificationManager.areRemindersActive
            )
        }
    }

    private var actions: some View {
        VStack(spacing: VaktSpace.sm) {
            VaktButton(title: page.primaryAction, style: .primary) {
                handlePrimaryAction()
            }

            if let secondaryAction = page.secondaryAction {
                Button {
                    handleSecondaryAction()
                } label: {
                    Text(secondaryAction)
                        .font(VaktFont.body(14))
                        .foregroundStyle(Color.vaktMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(VaktPressStyle())
            }
        }
    }

    private var pageProgress: Double {
        guard store.pages.count > 1 else { return 1 }
        return Double(store.currentPage) / Double(store.pages.count - 1)
    }

    private var locationStatusTitle: String {
        switch prayerStore.status {
        case .ready, .usingSavedTimes:
            return L10n.string("onboarding.location.ready")
        case .denied:
            return L10n.string("onboarding.location.off")
        case .failed:
            return L10n.string("onboarding.location.failed")
        case .locating, .loading:
            return L10n.string("onboarding.location.finding")
        }
    }

    private var locationStatusIsActive: Bool {
        switch prayerStore.status {
        case .ready, .usingSavedTimes, .loading, .locating:
            return true
        case .denied, .failed:
            return false
        }
    }

    private var reminderStatusTitle: String {
        switch notificationManager.reminderState {
        case .denied:
            return L10n.string("onboarding.reminders.off")
        case .notRequested:
            return L10n.string("action.allow_prayer_reminders")
        case .enabled:
            return L10n.string("onboarding.reminders.on")
        case .paused:
            return L10n.string("onboarding.reminders.paused")
        }
    }

    private var reminderStatusDetail: String {
        switch notificationManager.reminderState {
        case .denied:
            return L10n.string("onboarding.reminders.denied_detail")
        case .notRequested:
            return L10n.string("reminder.master.permission.detail")
        case .enabled:
            return L10n.string("onboarding.reminders.on_detail")
        case .paused:
            return L10n.string("onboarding.reminders.paused_detail")
        }
    }

    private func handlePrimaryAction() {
        switch page.id {
        case .arrival, .markPrayer, .friends, .makeupCalendar, .closingReminder, .promise, .gathering, .placement, .anonymousSaf:
            store.advance()
        case .location:
            prayerStore.requestLocationPermission()
            store.advance()
        case .reminders:
            notificationManager.setReminderEnabled(true)
            store.complete()
        }
    }

    private func handleSecondaryAction() {
        switch page.id {
        case .location:
            store.advance()
        case .reminders:
            notificationManager.setReminderEnabled(false)
            store.complete()
        case .arrival, .markPrayer, .friends, .makeupCalendar, .closingReminder, .promise, .gathering, .placement, .anonymousSaf:
            store.advance()
        }
    }
}

private struct OnboardingHorizonScene: View {
    let kind: OnboardingPage.Kind
    let progress: Double
    let isBreathing: Bool
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let lineY = size.height * 0.58
                drawSky(ctx: ctx, size: size, time: time)
                drawHorizon(ctx: ctx, size: size, lineY: lineY, time: time)
                drawSceneDots(ctx: ctx, size: size, lineY: lineY, time: time)
                drawFocus(ctx: ctx, size: size, lineY: lineY)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawSky(ctx: GraphicsContext, size: CGSize, time: TimeInterval) {
        let pulse = CGFloat((sin(time * 0.8) + 1) / 2)
        let glowWidth = size.width * (0.64 + CGFloat(progress) * 0.18)
        let glowRect = CGRect(
            x: (size.width - glowWidth) / 2,
            y: size.height * 0.18,
            width: glowWidth,
            height: size.height * 0.38
        )

        ctx.fill(
            Path(ellipseIn: glowRect),
            with: .color(.vaktAccent.opacity(0.055 + 0.025 * pulse))
        )

        let lowerRect = CGRect(x: 0, y: size.height * 0.58, width: size.width, height: size.height * 0.42)
        ctx.fill(Path(lowerRect), with: .color(.vaktDeep.opacity(0.82)))
    }

    private func drawHorizon(ctx: GraphicsContext, size: CGSize, lineY: CGFloat, time: TimeInterval) {
        let shimmer = CGFloat((sin(time * 1.1) + 1) / 2)

        for index in 0..<3 {
            let inset = size.width * CGFloat(0.12 + Double(index) * 0.06)
            var path = Path()
            path.move(to: CGPoint(x: inset, y: lineY + CGFloat(index * 8)))
            path.addLine(to: CGPoint(x: size.width - inset, y: lineY + CGFloat(index * 8)))
            ctx.stroke(
                path,
                with: .color(.vaktAccent.opacity(0.11 + shimmer * 0.05 - CGFloat(index) * 0.025)),
                lineWidth: index == 0 ? 0.9 : 0.55
            )
        }
    }

    private func drawSceneDots(ctx: GraphicsContext, size: CGSize, lineY: CGFloat, time: TimeInterval) {
        let count = dotCount
        for index in 0..<count {
            let seed = CGFloat(index)
            let xBase = CGFloat(index + 1) / CGFloat(count + 1)
            let wave = CGFloat(sin(time * 0.7 + Double(index) * 0.82)) * 0.012
            let x = size.width * min(0.9, max(0.1, xBase + wave))
            let y = lineY + CGFloat(index % 3 - 1) * 5 + CGFloat(sin(Double(seed) * 1.7)) * 4
            let radius = index == count / 2 ? CGFloat(4.7) : CGFloat(2.3 + Double(index % 3) * 0.5)
            let opacity = index == count / 2 ? 0.92 : 0.26 + Double(index % 4) * 0.08

            if kind == .anonymousSaf, index % 3 == 0 {
                let ringRadius = radius + 4
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: x - ringRadius, y: y - ringRadius, width: ringRadius * 2, height: ringRadius * 2)),
                    with: .color(.vaktAccent.opacity(0.16)),
                    lineWidth: 0.5
                )
            }

            ctx.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                with: .color(index == count / 2 ? .vaktPrimary.opacity(opacity) : .vaktAccent.opacity(opacity))
            )
        }
    }

    private func drawFocus(ctx: GraphicsContext, size: CGSize, lineY: CGFloat) {
        let radius: CGFloat = isBreathing ? 18 : 12
        let center = CGPoint(x: size.width * 0.5, y: lineY)

        ctx.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(.vaktPrimary.opacity(isBreathing ? 0.09 : 0.045))
        )
    }

    private var dotCount: Int {
        switch kind {
        case .arrival:
            return 9
        case .markPrayer:
            return 9
        case .friends:
            return 7
        case .makeupCalendar:
            return 5
        case .closingReminder:
            return 6
        case .promise:
            return 4
        case .gathering:
            return 9
        case .placement:
            return 9
        case .anonymousSaf:
            return 13
        case .location:
            return 7
        case .reminders:
            return 11
        }
    }
}

private struct OnboardingSignalRow: View {
    let items: [(String, String)]

    var body: some View {
        HStack(spacing: VaktSpace.sm) {
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.0)
                        .font(VaktFont.caption(11))
                        .foregroundStyle(Color.vaktMuted)

                    Text(item.1)
                        .font(VaktFont.body(13))
                        .foregroundStyle(Color.vaktSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, VaktSpace.sm + 2)
                .padding(.vertical, VaktSpace.sm)
                .background(Color.vaktSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.vaktBorder, lineWidth: 0.5)
                )
            }
        }
    }
}

private struct OnboardingPrivacyRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(VaktFont.body(13))
                .foregroundStyle(Color.vaktSecondary)

            Spacer()

            Text(value)
                .font(VaktFont.caption(11))
                .foregroundStyle(Color.vaktMuted)
        }
        .padding(.vertical, 10)
    }
}

private struct OnboardingPermissionStatus: View {
    let icon: String
    let title: String
    let detail: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: VaktSpace.sm) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isActive ? Color.vaktAccent : Color.vaktShadow)
                .frame(width: 32, height: 32)
                .background((isActive ? Color.vaktAccent : Color.vaktShadow).opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(VaktFont.body(13))
                    .foregroundStyle(Color.vaktSecondary)

                Text(detail)
                    .font(VaktFont.caption(11))
                    .foregroundStyle(Color.vaktMuted)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(VaktSpace.md)
        .background(Color.vaktSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.vaktBorder, lineWidth: 0.5)
        )
    }
}
