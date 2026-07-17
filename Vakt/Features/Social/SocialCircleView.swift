import SwiftUI

struct SocialCircleView: View {
    @ObservedObject var socialPrayerStore: SocialPrayerStore
    @ObservedObject var prayerStore: PrayerScheduleStore
    @ObservedObject var referralStore: ReferralStore
    @ObservedObject var subscriptionStore: SubscriptionStore

    @State private var addFriendPresented = false
    @State private var allFriendsPresented = false
    @State private var referralPresented = false

    var body: some View {
        let nextPrayer = prayerStore.nextPrayer
        let circlePrayer = prayerStore.activePrayer ?? nextPrayer

        GeometryReader { geometry in
            ZStack {
                CircleAtmosphere()

                VStack(alignment: .leading, spacing: 13) {
                    header

                    if !socialPrayerStore.pendingRequests.isEmpty {
                        PendingRequestsBand(
                            requests: socialPrayerStore.pendingRequests,
                            onAccept: { request in
                                socialPrayerStore.acceptFriendship(
                                    request,
                                    date: circlePrayer.time,
                                    timeZone: circlePrayer.timeZone
                                )
                            }
                        )
                    }

                    SocialPrayerPulse(
                        prayer: circlePrayer.prayer,
                        summaries: socialPrayerStore.friendSummaries
                    )

                    friendsSection(prayerTime: circlePrayer)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, VaktSpace.lg)
                .padding(.top, max(18, geometry.safeAreaInsets.top + 12))
                .padding(.bottom, max(10, geometry.safeAreaInsets.bottom + 8))
                .frame(width: geometry.size.width, alignment: .top)
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
        }
        .sheet(isPresented: $addFriendPresented) {
            AddFriendSheet(
                store: socialPrayerStore,
                referralStore: referralStore,
                subscriptionStore: subscriptionStore
            )
        }
        .sheet(isPresented: $allFriendsPresented) {
            AllFriendsSheet(
                store: socialPrayerStore,
                prayerTime: circlePrayer,
                nudgeIsEligible: nudgeIsEligible(for: circlePrayer)
            )
        }
        .sheet(isPresented: $referralPresented) {
            ReferralCenterView(store: referralStore, subscriptionStore: subscriptionStore)
        }
        .onAppear {
            socialPrayerStore.refresh(for: circlePrayer.time, timeZone: circlePrayer.timeZone)
        }
        .onChange(of: circlePrayer.prayer) { _, _ in
            socialPrayerStore.refresh(for: circlePrayer.time, timeZone: circlePrayer.timeZone)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: VaktSpace.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    EyebrowLabel(text: L10n.string("social.header.eyebrow"))

                    Text(L10n.string("social.header.title"))
                        .font(VaktFont.timeDisplay(28))
                        .foregroundStyle(Color.vaktPrimary)
                        .tracking(-0.8)
                        .lineLimit(2)
                        .minimumScaleFactor(0.76)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: VaktSpace.md)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    addFriendPresented = true
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.vaktBg)
                        .frame(width: 42, height: 42)
                        .background(Color.vaktPrimary)
                        .clipShape(Circle())
                }
                .buttonStyle(VaktPressStyle())
                .accessibilityLabel(L10n.string("social.action.add_friend"))
            }

            Text(L10n.string("social.header.body"))
                .font(VaktFont.body(12))
                .foregroundStyle(Color.vaktMuted)
                .lineSpacing(3)
                .lineLimit(2)
                .minimumScaleFactor(0.76)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func friendsSection(prayerTime: PrayerTime) -> some View {
        VStack(alignment: .leading, spacing: VaktSpace.sm) {
            HStack {
                Text(L10n.string("social.friends.title"))
                    .font(VaktFont.body(14))
                    .foregroundStyle(Color.vaktPrimary)

                Spacer()

                if socialPrayerStore.isSyncing {
                    ProgressView()
                        .tint(Color.vaktMuted)
                        .scaleEffect(0.7)
                }

                Button {
                    openReferrals()
                } label: {
                    Label(L10n.string("social.action.invite"), systemImage: "square.and.arrow.up")
                        .font(VaktFont.caption(11))
                        .foregroundStyle(Color.vaktPrimary)
                        .padding(.horizontal, 11)
                        .frame(height: 32)
                        .background(Color.vaktPrimary.opacity(0.08))
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(Color.vaktPrimary.opacity(0.18), lineWidth: 0.5)
                        }
                }
                .buttonStyle(VaktPressStyle())
                .accessibilityHint(L10n.string("social.action.invite.hint"))
            }

            if socialPrayerStore.friendSummaries.isEmpty {
                EmptyCircleState(
                    onAdd: { addFriendPresented = true },
                    onInvite: openReferrals
                )
            } else {
                VStack(spacing: 7) {
                    ForEach(Array(socialPrayerStore.friendSummaries.prefix(3))) { friend in
                        FriendPrayerRow(
                            friend: friend,
                            prayerTime: prayerTime,
                            nudgeState: nudgeState(for: friend, prayerTime: prayerTime),
                            onNudge: {
                                socialPrayerStore.sendNudge(to: friend, prayerTime: prayerTime)
                            }
                        )
                    }

                    if socialPrayerStore.friendSummaries.count > 3 {
                        MoreFriendsRow(count: socialPrayerStore.friendSummaries.count - 3) {
                            allFriendsPresented = true
                        }
                    }
                }
            }
        }
    }

    private func openReferrals() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        referralStore.clearMessage()
        referralPresented = true
    }

    private func nudgeIsEligible(for prayerTime: PrayerTime) -> Bool {
        guard prayerStore.activePrayer?.prayer == prayerTime.prayer else { return false }
        return prayerStore.now >= prayerTime.time.addingTimeInterval(15 * 60)
    }

    private func nudgeState(for friend: FriendPrayerSummary, prayerTime: PrayerTime) -> FriendNudgeState {
        if friend.statuses[PrayerKey(prayerTime.prayer)]?.isPrayed == true {
            return .prayed
        }
        if socialPrayerStore.hasSentNudge(to: friend, prayerTime: prayerTime) {
            return .sent
        }
        if socialPrayerStore.isSendingNudge(to: friend, prayerTime: prayerTime) {
            return .sending
        }
        return nudgeIsEligible(for: prayerTime) ? .available : .tooEarly
    }
}

private struct CircleAtmosphere: View {
    var body: some View {
        ZStack {
            Color.vaktBg.ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.vaktElevated.opacity(0.34),
                    Color.vaktBg.opacity(0.96),
                    Color.vaktDeep
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [Color.vaktGlow.opacity(0.13), Color.clear],
                center: .topTrailing,
                startRadius: 18,
                endRadius: 280
            )
            .ignoresSafeArea()
        }
    }
}

private struct SocialPrayerPulse: View {
    let prayer: Prayer
    let summaries: [FriendPrayerSummary]

    private var prayedCount: Int {
        summaries.filter { summary in
            summary.statuses[PrayerKey(prayer)]?.isPrayed == true
        }.count
    }

    private var waitingCount: Int {
        max(0, summaries.count - prayedCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: VaktSpace.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(prayer.localizedName)
                        .font(VaktFont.title(24))
                        .foregroundStyle(Color.vaktPrimary)

                    Text(L10n.string("social.pulse.subtitle"))
                        .font(VaktFont.caption(11))
                        .foregroundStyle(Color.vaktMuted)
                }

                Spacer()

                Text(verbatim: "\(SocialNumberFormatter.string(prayedCount))/\(SocialNumberFormatter.string(summaries.count))")
                    .font(VaktFont.timeDisplay(24))
                    .foregroundStyle(Color.vaktGlow)
                    .contentTransition(.numericText())
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                let ratio = summaries.isEmpty ? 0 : CGFloat(prayedCount) / CGFloat(max(1, summaries.count))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.vaktBorder.opacity(0.5))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.vaktPrimary.opacity(0.92), Color.vaktGlow.opacity(0.76)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(18, width * ratio))
                        .opacity(summaries.isEmpty ? 0.22 : 1)
                }
            }
            .frame(height: 8)

            HStack {
                Label(prayedText, systemImage: "checkmark")
                Spacer()
                Label(waitingText, systemImage: "clock")
            }
            .font(VaktFont.caption(11))
            .foregroundStyle(Color.vaktMuted)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(14)
        .background(Color.vaktSurface.opacity(0.56))
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                .strokeBorder(Color.vaktBorder.opacity(0.72), lineWidth: 0.5)
        )
    }

    private var waitingText: String {
        guard waitingCount > 0 else {
            return L10n.string("social.pulse.everyone_marked")
        }
        let key = waitingCount == 1 ? "social.pulse.waiting.one" : "social.pulse.waiting.many"
        return L10n.formatString(key, SocialNumberFormatter.string(waitingCount))
    }

    private var prayedText: String {
        let key = prayedCount == 1 ? "social.pulse.prayed.one" : "social.pulse.prayed.many"
        return L10n.formatString(key, SocialNumberFormatter.string(prayedCount))
    }
}

private enum FriendNudgeState: Equatable {
    case tooEarly
    case available
    case sending
    case sent
    case prayed
}

private struct FriendPrayerRow: View {
    let friend: FriendPrayerSummary
    let prayerTime: PrayerTime
    let nudgeState: FriendNudgeState
    let onNudge: () -> Void

    private var canNudge: Bool {
        nudgeState == .available
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: VaktSpace.sm) {
                FriendAvatar(profile: friend.profile)

                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.profile.displayName)
                        .font(VaktFont.body(14))
                        .foregroundStyle(Color.vaktPrimary)
                        .lineLimit(1)

                    Text(verbatim: "@\(friend.profile.username)")
                        .font(VaktFont.caption(10))
                        .foregroundStyle(Color.vaktMuted)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onNudge()
                } label: {
                    nudgeLabel
                }
                .buttonStyle(VaktPressStyle())
                .disabled(!canNudge)
                .accessibilityLabel(nudgeAccessibilityLabel)
            }

            HStack(spacing: 5) {
                ForEach(PrayerKey.allCases, id: \.self) { prayer in
                    FriendPrayerStatusCapsule(
                        prayer: prayer,
                        status: friend.statuses[prayer]
                    )
                }
            }
        }
        .padding(12)
        .background(Color.vaktSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                .strokeBorder(Color.vaktBorder.opacity(0.68), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var nudgeLabel: some View {
        switch nudgeState {
        case .available:
            Image(systemName: "bell")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.vaktBg)
                .frame(width: 34, height: 34)
                .background(Color.vaktPrimary)
                .clipShape(Circle())
        case .sending:
            ProgressView()
                .tint(Color.vaktMuted)
                .scaleEffect(0.7)
                .frame(width: 34, height: 34)
        case .sent:
            Label(L10n.string("social.nudge.sent"), systemImage: "checkmark")
                .font(VaktFont.caption(9))
                .foregroundStyle(Color.vaktGlow)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(Color.vaktGlow.opacity(0.1))
                .clipShape(Capsule())
        case .tooEarly:
            Image(systemName: "bell")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.vaktMuted.opacity(0.55))
                .frame(width: 34, height: 34)
        case .prayed:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.vaktMuted)
                .frame(width: 34, height: 34)
        }
    }

    private var nudgeAccessibilityLabel: String {
        switch nudgeState {
        case .available: L10n.string("social.nudge.available")
        case .sending: L10n.string("social.nudge.sending")
        case .sent: L10n.string("social.nudge.sent")
        case .tooEarly: L10n.string("social.nudge.too_early")
        case .prayed: L10n.string("social.nudge.prayed")
        }
    }
}

private struct MoreFriendsRow: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack {
                Text(moreText)
                    .font(VaktFont.caption(11))
                    .foregroundStyle(Color.vaktMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Spacer()

                Text(L10n.string("social.friends.view_all"))
                    .font(VaktFont.caption(11))
                    .foregroundStyle(Color.vaktPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color.vaktSurface.opacity(0.34))
            .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
        }
        .buttonStyle(VaktPressStyle())
    }

    private var moreText: String {
        let key = count == 1 ? "social.friends.more.one" : "social.friends.more.many"
        return L10n.formatString(key, SocialNumberFormatter.string(count))
    }
}

private struct FriendPrayerStatusCapsule: View {
    let prayer: PrayerKey
    let status: SocialPrayerStatus?

    var body: some View {
        Text(prayer.shortTitle)
            .font(VaktFont.caption(8))
            .foregroundStyle(textColor)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(background)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(borderColor, lineWidth: 0.5)
            )
            .accessibilityLabel(
                L10n.formatString(
                    "social.prayer_status.accessibility",
                    prayer.localizedName,
                    accessibilityStatus
                )
            )
    }

    private var background: Color {
        switch status {
        case .prayedOnTime, .prayedLater:
            Color.vaktPrimary.opacity(0.88)
        case .preparing:
            Color.vaktGlow.opacity(0.18)
        case .notMarked:
            Color.vaktBorder.opacity(0.55)
        case .madeUp:
            Color.vaktAccent.opacity(0.42)
        case nil:
            Color.clear
        }
    }

    private var textColor: Color {
        switch status {
        case .prayedOnTime, .prayedLater:
            Color.vaktBg
        case .preparing, .madeUp:
            Color.vaktPrimary
        case .notMarked, nil:
            Color.vaktMuted
        }
    }

    private var borderColor: Color {
        status == nil ? Color.vaktBorder.opacity(0.72) : Color.clear
    }

    private var accessibilityStatus: String {
        switch status {
        case .preparing:
            L10n.string("social.status.preparing")
        case .prayedOnTime, .prayedLater:
            L10n.string("social.status.prayed")
        case .notMarked:
            L10n.string("social.status.not_marked")
        case .madeUp:
            L10n.string("social.status.made_up")
        case nil:
            L10n.string("social.status.unknown")
        }
    }
}

private struct PendingRequestsBand: View {
    let requests: [PendingFriendRequest]
    let onAccept: (PendingFriendRequest) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VaktSpace.sm) {
            Text(requestTitle)
                .font(VaktFont.caption(11))
                .foregroundStyle(Color.vaktMuted)

            ForEach(requests) { request in
                HStack(spacing: 10) {
                    FriendAvatar(profile: request.requester)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.requester.displayName)
                            .font(VaktFont.body(13))
                            .foregroundStyle(Color.vaktPrimary)

                        Text(verbatim: "@\(request.requester.username)")
                            .font(VaktFont.caption(10))
                            .foregroundStyle(Color.vaktMuted)
                    }

                    Spacer()

                    Button(L10n.string("social.requests.accept")) {
                        onAccept(request)
                    }
                    .font(VaktFont.caption(11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(Color.vaktBg)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Color.vaktPrimary)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(VaktSpace.md)
        .background(Color.vaktGlow.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
    }

    private var requestTitle: String {
        requests.count == 1
            ? L10n.string("social.requests.one")
            : L10n.string("social.requests.many")
    }
}

private struct EmptyCircleState: View {
    let onAdd: () -> Void
    let onInvite: () -> Void

    var body: some View {
        VStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(Color.vaktSurface.opacity(0.9))
                    .frame(width: 58, height: 58)

                Image(systemName: "person.2")
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(Color.vaktPrimary)
            }

            VStack(spacing: 5) {
                Text(L10n.string("social.empty.title"))
                    .font(VaktFont.title(18))
                    .foregroundStyle(Color.vaktPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(L10n.string("social.empty.body"))
                    .font(VaktFont.body(12))
                    .foregroundStyle(Color.vaktMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
            }

            HStack(spacing: 9) {
                Button {
                    onAdd()
                } label: {
                    Text(L10n.string("social.action.find_friend"))
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
                .foregroundStyle(Color.vaktBg)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Color.vaktPrimary)
                .clipShape(Capsule())

                Button {
                    onInvite()
                } label: {
                    Label(L10n.string("social.action.invite_to_vakt"), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(Color.vaktPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Color.vaktElevated.opacity(0.76))
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(Color.vaktBorder, lineWidth: 0.6)
                }
            }
            .font(VaktFont.body(11))
            .buttonStyle(VaktPressStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, VaktSpace.md)
        .background(Color.vaktSurface.opacity(0.46))
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                .strokeBorder(Color.vaktBorder.opacity(0.65), lineWidth: 0.5)
        )
    }
}

private struct AddFriendSheet: View {
    @ObservedObject var store: SocialPrayerStore
    @ObservedObject var referralStore: ReferralStore
    @ObservedObject var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var referralPresented = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.vaktBg.ignoresSafeArea()

                VStack(alignment: .leading, spacing: VaktSpace.md) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.string("social.add.title"))
                            .font(VaktFont.title(24))
                            .foregroundStyle(Color.vaktPrimary)

                        Text(L10n.string("social.add.subtitle"))
                            .font(VaktFont.body(13))
                            .foregroundStyle(Color.vaktMuted)
                            .lineSpacing(4)
                    }

                    Button {
                        referralStore.clearMessage()
                        referralPresented = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.vaktGlow)
                                .frame(width: 34, height: 34)
                                .background(Color.vaktGlow.opacity(0.09))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(L10n.string("social.action.invite_to_vakt"))
                                    .font(VaktFont.body(13))
                                    .foregroundStyle(Color.vaktPrimary)
                                Text(L10n.string("social.add.invite.body"))
                                    .font(VaktFont.caption(9))
                                    .foregroundStyle(Color.vaktMuted)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.72)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.vaktMuted)
                        }
                        .padding(.horizontal, 13)
                        .frame(height: 58)
                        .background(Color.vaktElevated.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
                    }
                    .buttonStyle(VaktPressStyle())

                    HStack(spacing: VaktSpace.sm) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.vaktMuted)

                        TextField(L10n.string("social.add.search.placeholder"), text: $query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(VaktFont.body(14))
                            .foregroundStyle(Color.vaktPrimary)
                            .onChange(of: query) { _, newValue in
                                store.searchProfiles(matching: newValue)
                            }
                    }
                    .padding(.horizontal, VaktSpace.md)
                    .frame(height: 46)
                    .background(Color.vaktSurface)
                    .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))

                    if store.profileSearchResults.isEmpty {
                        Spacer()

                        Text(query.count < 2
                             ? L10n.string("social.add.search.minimum")
                             : L10n.string("social.add.search.empty"))
                            .font(VaktFont.body(13))
                            .foregroundStyle(Color.vaktMuted)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)

                        Spacer()
                    } else {
                        ScrollView {
                            VStack(spacing: VaktSpace.sm) {
                                ForEach(store.profileSearchResults) { profile in
                                    SearchProfileRow(profile: profile) {
                                        store.requestFriendship(with: profile)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(VaktSpace.lg)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("social.action.close")) {
                        dismiss()
                    }
                    .font(VaktFont.caption(12))
                    .foregroundStyle(Color.vaktPrimary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $referralPresented) {
            ReferralCenterView(store: referralStore, subscriptionStore: subscriptionStore)
        }
    }
}

private struct SearchProfileRow: View {
    let profile: SocialProfile
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: VaktSpace.sm) {
            FriendAvatar(profile: profile)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(VaktFont.body(14))
                    .foregroundStyle(Color.vaktPrimary)

                Text(verbatim: "@\(profile.username)")
                    .font(VaktFont.caption(10))
                    .foregroundStyle(Color.vaktMuted)
            }

            Spacer()

            Button(L10n.string("social.action.add")) {
                onAdd()
            }
            .font(VaktFont.caption(11))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(Color.vaktBg)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Color.vaktPrimary)
            .clipShape(Capsule())
            .buttonStyle(VaktPressStyle())
        }
        .padding(VaktSpace.md)
        .background(Color.vaktSurface.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
    }
}

private struct FriendAvatar: View {
    let profile: SocialProfile

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.vaktGlow.opacity(0.12))

            Text(initials)
                .font(VaktFont.caption(12))
                .foregroundStyle(Color.vaktPrimary)
        }
        .frame(width: 38, height: 38)
        .overlay(
            Circle()
                .strokeBorder(Color.vaktAccent.opacity(0.24), lineWidth: 0.6)
        )
    }

    private var initials: String {
        let parts = profile.displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
        let value = String(parts).uppercased()
        return value.isEmpty ? "V" : value
    }
}

private extension PrayerKey {
    var localizedName: String {
        switch self {
        case .fajr:
            Prayer.fajr.localizedName
        case .dhuhr:
            Prayer.dhuhr.localizedName
        case .asr:
            Prayer.asr.localizedName
        case .maghrib:
            Prayer.maghrib.localizedName
        case .isha:
            Prayer.isha.localizedName
        }
    }

    var shortTitle: String {
        localizedName
    }
}

private struct AllFriendsSheet: View {
    @ObservedObject var store: SocialPrayerStore
    @Environment(\.dismiss) private var dismiss
    let prayerTime: PrayerTime
    let nudgeIsEligible: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.vaktBg.ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.friendSummaries) { friend in
                            FriendPrayerRow(
                                friend: friend,
                                prayerTime: prayerTime,
                                nudgeState: nudgeState(for: friend),
                                onNudge: {
                                    store.sendNudge(to: friend, prayerTime: prayerTime)
                                }
                            )
                        }
                    }
                    .padding(VaktSpace.lg)
                }
            }
            .navigationTitle(L10n.string("social.friends.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("social.action.close")) { dismiss() }
                        .font(VaktFont.caption(12))
                        .foregroundStyle(Color.vaktPrimary)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func nudgeState(for friend: FriendPrayerSummary) -> FriendNudgeState {
        if friend.statuses[PrayerKey(prayerTime.prayer)]?.isPrayed == true {
            return .prayed
        }
        if store.hasSentNudge(to: friend, prayerTime: prayerTime) {
            return .sent
        }
        if store.isSendingNudge(to: friend, prayerTime: prayerTime) {
            return .sending
        }
        return nudgeIsEligible ? .available : .tooEarly
    }
}

private enum SocialNumberFormatter {
    static func string(_ value: Int) -> String {
        value.formatted(.number.locale(VaktLocalization.appLocale))
    }
}

private extension SocialPrayerStatus {
    var isPrayed: Bool {
        switch self {
        case .prayedOnTime, .prayedLater, .madeUp:
            true
        case .preparing, .notMarked:
            false
        }
    }
}
