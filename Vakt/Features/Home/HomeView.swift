import SwiftUI

struct HomeView: View {
    @Binding var selectedTab: VaktTab
    @ObservedObject var prayerStore: PrayerScheduleStore
    @ObservedObject var sessionStore: PrayerSessionStore
    @ObservedObject var reflectionStore: PrayerReflectionStore
    @ObservedObject var socialPrayerStore: SocialPrayerStore

    @StateObject private var qiblaStore = QiblaCompassStore()
    @State private var qiblaPresented = false

    var body: some View {
        let nextPrayer = prayerStore.nextPrayer
        let activeWindow = prayerStore.activePrayerWindow
        let currentPrayer = activeWindow?.prayerTime
        let focusPrayer = currentPrayer ?? nextPrayer
        let selectedOutcome = currentPrayer.flatMap { reflectionStore.outcome(for: $0) } ?? .missed
        let trackingStatus = currentPrayer.map {
            reflectionStore.trackingStatus(
                for: $0,
                sessionStatus: sessionStore.status(for: $0)
            )
        }

        GeometryReader { geometry in
            ZStack {
                HomeDayAtmosphere(prayer: focusPrayer.prayer)

                VStack(spacing: 0) {
                    HomeTopBar(onQibla: { qiblaPresented = true })

                    HomePrayerFocus(
                        activeWindow: activeWindow,
                        nextPrayerTime: nextPrayer,
                        now: prayerStore.now,
                        trackingStatus: trackingStatus
                    )
                    .padding(.top, 18)

                    Spacer(minLength: 14)

                    VStack(spacing: 0) {
                        if let currentPrayer, let trackingStatus {
                            HomePrayerActions(
                                prayer: currentPrayer.prayer,
                                selectedOutcome: selectedOutcome,
                                trackingStatus: trackingStatus,
                                onMark: { mark(currentPrayer, outcome: $0) },
                                onBegin: { selectedTab = .prayer }
                            )

                            HomeSocialLine(
                                prayer: currentPrayer.prayer,
                                summaries: socialPrayerStore.friendSummaries,
                                onOpen: { selectedTab = .circle }
                            )
                            .padding(.top, 18)
                        } else {
                            HomeBetweenPrayersNote()
                        }

                        HomePrayerTimeline(prayers: prayerStore.upcomingPrayers)
                            .padding(.top, 21)
                    }
                    .offset(y: 18)
                }
                .padding(.horizontal, VaktSpace.lg)
                .padding(.top, max(14, geometry.safeAreaInsets.top + 8))
                .padding(.bottom, max(4, geometry.safeAreaInsets.bottom - 4))
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
        }
        .sheet(isPresented: $qiblaPresented) {
            QiblaSheet(store: qiblaStore)
        }
        .onAppear {
            refreshSocialPrayer(for: currentPrayer)
        }
        .onChange(of: currentPrayer?.time) { _, _ in
            refreshSocialPrayer(for: currentPrayer)
        }
    }

    private func refreshSocialPrayer(for prayerTime: PrayerTime?) {
        guard let prayerTime else { return }
        socialPrayerStore.refresh(for: prayerTime.time, timeZone: prayerTime.timeZone)
    }

    private func mark(_ prayerTime: PrayerTime, outcome: PrayerReflectionOutcome) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if outcome == .prayed {
            sessionStore.markPrayerCompleted(for: prayerTime)
        }

        reflectionStore.mark(
            prayer: prayerTime.prayer,
            prayerDate: prayerTime.time,
            outcome: outcome
        )
        socialPrayerStore.mark(prayerTime, outcome: outcome)
    }
}

private struct HomeDayAtmosphere: View {
    let prayer: Prayer

    var body: some View {
        ZStack {
            Color.vaktBg.ignoresSafeArea()

            LinearGradient(
                colors: [topColor.opacity(0.38), Color.vaktBg.opacity(0.97), Color.vaktDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [glowColor.opacity(0.2), .clear],
                center: UnitPoint(x: 0.82, y: 0.16),
                startRadius: 0,
                endRadius: 250
            )
            .ignoresSafeArea()

            Canvas { context, size in
                let horizonY = size.height * 0.44
                var horizon = Path()
                horizon.move(to: CGPoint(x: 0, y: horizonY))
                horizon.addCurve(
                    to: CGPoint(x: size.width, y: horizonY + 18),
                    control1: CGPoint(x: size.width * 0.28, y: horizonY - 9),
                    control2: CGPoint(x: size.width * 0.66, y: horizonY + 30)
                )
                context.stroke(horizon, with: .color(Color.vaktGlow.opacity(0.075)), lineWidth: 0.7)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    private var topColor: Color {
        switch prayer {
        case .fajr: Color(hex: "#23395A")
        case .dhuhr: Color(hex: "#263B4F")
        case .asr: Color(hex: "#3A3545")
        case .maghrib: Color(hex: "#422B3B")
        case .isha: Color(hex: "#17223B")
        }
    }

    private var glowColor: Color {
        switch prayer {
        case .fajr: Color(hex: "#AABED3")
        case .dhuhr: Color(hex: "#B6C8D5")
        case .asr: Color(hex: "#C2A7A0")
        case .maghrib: Color(hex: "#C18C83")
        case .isha: Color.vaktGlow
        }
    }
}

private struct HomeTopBar: View {
    let onQibla: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(VaktFont.body(14))
                    .foregroundStyle(Color.vaktPrimary)

                Text(dateText)
                    .font(VaktFont.caption(10))
                    .foregroundStyle(Color.vaktMuted)
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onQibla()
            } label: {
                Image(systemName: "location.north.line")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.vaktPrimary.opacity(0.9))
                    .frame(width: 38, height: 38)
                    .background(Color.vaktSurface.opacity(0.45))
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.vaktBorderStrong.opacity(0.6), lineWidth: 0.5))
            }
            .buttonStyle(VaktPressStyle())
            .accessibilityLabel(L10n.string("home.open_qibla"))
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return switch hour {
        case 5..<12: L10n.string("home.greeting.morning")
        case 12..<18: L10n.string("home.greeting.day")
        default: L10n.string("home.greeting.evening")
        }
    }

    private var dateText: String {
        Date().formatted(
            .dateTime
                .weekday(.wide)
                .day()
                .month(.wide)
                .locale(VaktLocalization.appLocale)
        )
    }
}

private struct HomePrayerFocus: View {
    let activeWindow: ActivePrayerWindow?
    let nextPrayerTime: PrayerTime
    let now: Date
    let trackingStatus: PrayerTrackingStatus?

    var body: some View {
        if let activeWindow, let trackingStatus {
            activePrayerFocus(activeWindow, trackingStatus: trackingStatus)
        } else {
            upcomingPrayerFocus
        }
    }

    private func activePrayerFocus(
        _ window: ActivePrayerWindow,
        trackingStatus: PrayerTrackingStatus
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(L10n.string("home.current_prayer")
                    .uppercased(with: VaktLocalization.appLocale))
                    .font(VaktFont.eyebrow(9))
                    .foregroundStyle(Color.vaktMuted)
                    .tracking(1.8)

                Spacer()

                HomeQuietStatus(status: trackingStatus)
            }

            Text(window.prayerTime.prayer.displayName)
                .font(VaktFont.prayerDisplay(64))
                .foregroundStyle(Color.vaktPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.opacity)

            HomePrayerWindowRail(
                window: window,
                now: now
            )
            .padding(.top, 10)
        }
    }

    private var upcomingPrayerFocus: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.string("home.next_prayer")
                .uppercased(with: VaktLocalization.appLocale))
                .font(VaktFont.eyebrow(9))
                .foregroundStyle(Color.vaktMuted)
                .tracking(1.8)

            Text(nextPrayerTime.prayer.displayName)
                .font(VaktFont.prayerDisplay(64))
                .foregroundStyle(Color.vaktPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.opacity)

            Text(VaktTimeFormatter.string(from: nextPrayerTime.time, timeZone: nextPrayerTime.timeZone))
                .font(VaktFont.timeDisplay(20))
                .foregroundStyle(Color.vaktGlow)
                .monospacedDigit()

            CountdownLabel(
                seconds: max(0, nextPrayerTime.time.timeIntervalSince(now)),
                fontSize: 12,
                digitWidth: 7.5,
                digitHeight: 16
            )
            .padding(.top, 7)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HomePrayerWindowRail: View {
    let window: ActivePrayerWindow
    let now: Date

    var body: some View {
        VStack(spacing: 9) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.vaktBorderStrong.opacity(0.72))

                    Capsule()
                        .fill(Color.vaktGlow.opacity(0.76))
                        .frame(width: proxy.size.width * CGFloat(window.progress(at: now)))
                }
            }
            .frame(height: 2)

            HStack(alignment: .top, spacing: 18) {
                Text(VaktTimeFormatter.string(
                    from: window.prayerTime.time,
                    timeZone: window.prayerTime.timeZone
                ))
                .font(VaktFont.body(13))
                .foregroundStyle(Color.vaktGlow)
                .monospacedDigit()

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(endingTitle)
                            .font(VaktFont.body(13))
                            .foregroundStyle(Color.vaktSecondary)

                        Text(VaktTimeFormatter.string(
                            from: window.endsAt,
                            timeZone: window.prayerTime.timeZone
                        ))
                        .font(VaktFont.body(13))
                        .foregroundStyle(Color.vaktGlow)
                        .monospacedDigit()
                    }

                    CountdownLabel(
                        seconds: window.remaining(at: now),
                        fontSize: 10,
                        digitWidth: 6.5,
                        digitHeight: 14
                    )
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var endingTitle: String {
        window.endingPrayer?.displayName ?? L10n.string("home.sunrise")
    }
}

private struct HomeBetweenPrayersNote: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.horizon")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(Color.vaktGlow)

            Text(L10n.string("home.between_prayers"))
                .font(VaktFont.body(12))
                .foregroundStyle(Color.vaktSecondary)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.vaktBorder.opacity(0.62))
                .frame(height: 0.5)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.vaktBorder.opacity(0.62))
                .frame(height: 0.5)
        }
    }
}

private struct HomeQuietStatus: View {
    let status: PrayerTrackingStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)

            Text(title)
            .font(VaktFont.caption(10))
            .foregroundStyle(Color.vaktMuted)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
    }

    private var title: String {
        switch status {
        case .ready: L10n.string("home.status.unmarked")
        case .inProgress: L10n.string("home.status.in_prayer")
        case .prayed, .later: L10n.string("home.status.prayed")
        case .missed: L10n.string("home.status.missed")
        }
    }

    private var color: Color {
        switch status {
        case .prayed, .later: Color.vaktPrimary
        case .inProgress: Color.vaktGlow
        case .ready, .missed: Color.vaktMuted
        }
    }
}

private struct HomePrayerActions: View {
    let prayer: Prayer
    let selectedOutcome: PrayerReflectionOutcome
    let trackingStatus: PrayerTrackingStatus
    let onMark: (PrayerReflectionOutcome) -> Void
    let onBegin: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 0) {
                outcomeButton(
                    title: L10n.string("home.action.prayed"),
                    icon: "checkmark",
                    outcome: .prayed
                )

                Rectangle()
                    .fill(Color.vaktBorderStrong.opacity(0.7))
                    .frame(width: 0.5, height: 24)

                outcomeButton(
                    title: L10n.string("home.action.missed"),
                    icon: "minus",
                    outcome: .missed
                )
            }
            .frame(height: 49)
            .background(Color.vaktSurface.opacity(0.48))
            .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                    .strokeBorder(Color.vaktBorder.opacity(0.7), lineWidth: 0.5)
            )

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onBegin()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isOpen ? "arrow.uturn.forward" : "moon.stars")
                        .font(.system(size: 15, weight: .medium))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(actionTitle)
                            .font(VaktFont.button(16))

                        Text(actionSubtitle)
                            .font(VaktFont.caption(10))
                            .foregroundStyle(Color.vaktBg.opacity(0.58))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color.vaktBg)
                .padding(.horizontal, 17)
                .frame(height: 60)
                .background(Color.vaktPrimary)
                .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
            }
            .buttonStyle(VaktPressStyle())
            .accessibilityLabel(actionTitle)
            .accessibilityHint(actionSubtitle)
        }
    }

    private func outcomeButton(title: String, icon: String, outcome: PrayerReflectionOutcome) -> some View {
        let isSelected = selectedOutcome == outcome

        return Button {
            onMark(outcome)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : icon)
                    .font(.system(size: 12, weight: .medium))

                Text(title)
                    .font(VaktFont.body(13))
            }
            .foregroundStyle(isSelected ? Color.vaktPrimary : Color.vaktMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isSelected ? Color.vaktElevated.opacity(0.48) : Color.clear)
        }
        .buttonStyle(VaktPressStyle())
    }

    private var isOpen: Bool {
        if case .inProgress = trackingStatus { return true }
        return false
    }

    private var actionTitle: String {
        L10n.string(isOpen ? "home.action.return" : "home.action.begin")
    }

    private var actionSubtitle: String {
        if isOpen {
            return L10n.string("home.action.return.subtitle")
        }
        return L10n.formatString("home.action.begin.subtitle", prayer.displayName)
    }
}

private struct HomeSocialLine: View {
    let prayer: Prayer
    let summaries: [FriendPrayerSummary]
    let onOpen: () -> Void

    private var prayedFriends: [FriendPrayerSummary] {
        summaries.filter { summary in
            switch summary.statuses[PrayerKey(prayer)] {
            case .prayedOnTime, .prayedLater, .madeUp: true
            case .preparing, .notMarked, nil: false
            }
        }
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onOpen()
        } label: {
            HStack(spacing: 12) {
                HomeAvatarStack(friends: Array(prayedFriends.prefix(3)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("home.social.title"))
                        .font(VaktFont.body(13))
                        .foregroundStyle(Color.vaktPrimary)

                    Text(summary)
                        .font(VaktFont.caption(10))
                        .foregroundStyle(Color.vaktMuted)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.vaktMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(VaktPressStyle())
    }

    private var summary: String {
        if summaries.isEmpty { return L10n.string("home.social.no_friends") }
        if prayedFriends.isEmpty { return L10n.string("home.social.no_signal") }
        if prayedFriends.count == 1 {
            return L10n.formatString("home.social.one_prayed", prayer.displayName)
        }
        return L10n.formatString(
            "home.social.many_prayed",
            HomeNumberFormatter.string(prayedFriends.count),
            prayer.displayName
        )
    }
}

private struct HomeAvatarStack: View {
    let friends: [FriendPrayerSummary]

    var body: some View {
        HStack(spacing: -8) {
            if friends.isEmpty {
                Image(systemName: "person.2")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(Color.vaktMuted)
                    .frame(width: 34, height: 34)
                    .background(Color.vaktSurface)
                    .clipShape(Circle())
            } else {
                ForEach(friends) { friend in
                    Text(initials(friend.profile.displayName))
                        .font(VaktFont.eyebrow(8))
                        .foregroundStyle(Color.vaktPrimary)
                        .frame(width: 32, height: 32)
                        .background(Color.vaktElevated)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.vaktBg, lineWidth: 2))
                }
            }
        }
        .frame(minWidth: 34, alignment: .leading)
    }

    private func initials(_ name: String) -> String {
        name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased(with: VaktLocalization.appLocale)
    }
}

private struct HomePrayerTimeline: View {
    let prayers: [PrayerTime]

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(L10n.string("home.timeline.title")
                    .uppercased(with: VaktLocalization.appLocale))
                    .font(VaktFont.eyebrow(9))
                    .foregroundStyle(Color.vaktMuted)
                    .tracking(1.5)

                Spacer()

                Text(L10n.string("home.timeline.local_time"))
                    .font(VaktFont.caption(9))
                    .foregroundStyle(Color.vaktMuted.opacity(0.7))
            }

            HStack(spacing: 5) {
                ForEach(Array(prayers.prefix(5).enumerated()), id: \.element.id) { index, prayer in
                    HomePrayerTimelineItem(
                        prayer: prayer,
                        isCurrent: index == 0
                    )
                }
            }
            .padding(5)
            .background(Color.vaktSurface.opacity(0.34))
            .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                    .strokeBorder(Color.vaktBorder.opacity(0.55), lineWidth: 0.5)
            )
        }
    }
}

private enum HomeNumberFormatter {
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = VaktLocalization.appLocale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    static func string(_ value: Int) -> String {
        formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

private struct HomePrayerTimelineItem: View {
    let prayer: PrayerTime
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Rectangle()
                .fill(isCurrent ? Color.vaktPrimary : Color.clear)
                .frame(width: isCurrent ? 25 : 0, height: 1.5)

            Text(prayer.prayer.displayName)
                .font(VaktFont.body(isCurrent ? 11 : 10))
                .foregroundStyle(isCurrent ? Color.vaktPrimary : Color.vaktMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Text(VaktTimeFormatter.string(from: prayer.time, timeZone: prayer.timeZone))
                .font(VaktFont.timeDisplay(isCurrent ? 14 : 12))
                .foregroundStyle(Color.vaktPrimary.opacity(isCurrent ? 0.94 : 0.58))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(isCurrent ? Color.vaktElevated.opacity(0.58) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
