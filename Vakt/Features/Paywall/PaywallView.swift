import SwiftUI

struct PaywallView: View {
    @ObservedObject var store: SubscriptionStore
    @ObservedObject var referralStore: ReferralStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    @State private var selectedPlanID: String?
    @State private var journeyPhase: PaywallJourneyPhase = .remind
    @State private var referralCodePresented = false
    @State private var referralLinkedMomentPresented = false

    private var preferredPlan: SubscriptionStore.Plan? {
        store.plans.first { $0.cadence == .yearly } ?? store.plans.first
    }

    private var selectedPlan: SubscriptionStore.Plan? {
        store.plans.first { $0.id == selectedPlanID } ?? preferredPlan
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                PaywallBackground()

                ViewThatFits(in: .vertical) {
                    paywallContent(bottomInset: proxy.safeAreaInsets.bottom)
                        .frame(maxHeight: .infinity, alignment: .top)

                    ScrollView(showsIndicators: false) {
                        paywallContent(bottomInset: max(12, proxy.safeAreaInsets.bottom))
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }

                if referralLinkedMomentPresented,
                   let invitation = referralStore.claimedInvitation {
                    ReferralLinkedMoment(inviterName: invitation.inviterName)
                        .transition(.opacity)
                        .zIndex(20)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .preferredColorScheme(.dark)
        .onAppear { selectPreferredPlan() }
        .onChange(of: store.plans) { _, _ in selectPreferredPlanIfNeeded() }
        .onChange(of: referralStore.claimedInvitation) { previous, invitation in
            guard previous == nil, invitation != nil else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                withAnimation(reduceMotion ? .none : .easeOut(duration: 0.24)) {
                    referralLinkedMomentPresented = true
                }
                try? await Task.sleep(for: .milliseconds(1_500))
                withAnimation(reduceMotion ? .none : .easeIn(duration: 0.32)) {
                    referralLinkedMomentPresented = false
                }
            }
        }
        .task { await runJourney() }
        .sheet(isPresented: $referralCodePresented) {
            ReferralCodeSheet(store: referralStore)
        }
    }

    private func paywallContent(bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            paywallHeader
                .padding(.top, 18)

            Spacer(minLength: 8)
                .frame(maxHeight: 22)

            PaywallJourney(phase: journeyPhase, reduceMotion: reduceMotion)
                .frame(height: 132)

            PaywallReasons()
                .padding(.top, 8)

            referralContext
                .padding(.top, 11)

            Spacer(minLength: 7)
                .frame(maxHeight: 18)

            if let reward = referralStore.dashboard.readyRewards.first {
                readyReward(reward)
            } else {
                planArea
            }

            Spacer(minLength: 8)
                .frame(maxHeight: 22)

            if referralStore.dashboard.readyRewards.isEmpty {
                purchaseArea
            }

            footer
                .padding(.top, 10)
                .padding(.bottom, max(12, bottomInset + 4))
        }
        .padding(.horizontal, VaktSpace.lg)
        .frame(maxWidth: .infinity)
    }

    private var paywallHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.string("paywall.eyebrow").uppercased(with: VaktLocalization.appLocale))
                .font(VaktFont.eyebrow(9))
                .foregroundStyle(Color.vaktSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            VStack(alignment: .leading, spacing: 1) {
                Text(L10n.string("paywall.header.line_one"))
                    .font(VaktFont.title(28))
                    .foregroundStyle(Color.vaktSecondary)
                    .minimumScaleFactor(0.78)

                Text(L10n.string("paywall.header.line_two"))
                    .font(VaktFont.title(34))
                    .foregroundStyle(Color.vaktPrimary)
                    .minimumScaleFactor(0.72)
            }
            .fixedSize(horizontal: false, vertical: true)

            Text(L10n.string("paywall.body"))
                .font(VaktFont.body(11))
                .foregroundStyle(Color.vaktMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var referralContext: some View {
        Group {
            if let invitation = referralStore.claimedInvitation {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.vaktDeep)
                        .frame(width: 30, height: 30)
                        .background(Color.vaktPrimary)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.formatString(
                            "paywall.referral.connected.title",
                            invitation.inviterName
                        ))
                            .font(VaktFont.body(12))
                            .foregroundStyle(Color.vaktPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.84)

                        Text(L10n.string("paywall.referral.connected.visibility"))
                            .font(VaktFont.caption(9))
                            .foregroundStyle(Color.vaktSecondary)

                        Text(L10n.string("paywall.referral.connected.reward"))
                            .font(VaktFont.caption(9))
                            .foregroundStyle(Color.vaktMuted)
                    }

                    Spacer(minLength: 0)
                }
                .padding(13)
                .background(Color.vaktSurface.opacity(0.64))
                .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                        .strokeBorder(Color.vaktPrimary.opacity(0.16), lineWidth: 0.7)
                }
            } else {
                Button { referralCodePresented = true } label: {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(Color.vaktGlow)
                            .frame(width: 3, height: 25)
                            .shadow(color: Color.vaktGlow.opacity(0.38), radius: 5)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(L10n.string("paywall.referral.prompt.title"))
                                .font(VaktFont.body(11))
                                .foregroundStyle(Color.vaktPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)

                            Text(L10n.string("paywall.referral.prompt.detail"))
                                .font(VaktFont.caption(8))
                                .foregroundStyle(Color.vaktMuted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.76)
                        }

                        Spacer(minLength: 6)

                        HStack(spacing: 4) {
                            Text(L10n.string("paywall.referral.prompt.action"))
                                .font(VaktFont.button(10))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(Color.vaktPrimary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 48)
                    .background(Color.vaktSurface.opacity(0.34))
                    .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                            .strokeBorder(Color.vaktGlow.opacity(0.18), lineWidth: 0.7)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(VaktPressStyle())
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func readyReward(_ reward: ReferralReward) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(L10n.string("paywall.referral.reward_ready.title"), systemImage: "calendar.badge.plus")
                .font(VaktFont.body(14))
                .foregroundStyle(Color.vaktPrimary)

            Text(L10n.string("paywall.referral.reward_ready.body"))
                .font(VaktFont.caption(10))
                .foregroundStyle(Color.vaktMuted)

            Button {
                Task { await referralStore.redeem(reward, using: store) }
            } label: {
                Text(L10n.string("paywall.referral.reward_ready.action"))
                    .font(VaktFont.button(14))
                    .foregroundStyle(Color.vaktDeep)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.vaktPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(VaktPressStyle())
            .disabled(referralStore.activity != .idle)
        }
        .padding(15)
        .background(Color.vaktSurface.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
    }

    @ViewBuilder
    private var planArea: some View {
        if store.isLoadingProducts && store.plans.isEmpty {
            PaywallPlanLoading()
        } else if store.plans.isEmpty {
            PaywallPlanUnavailable {
                Task { await store.retryLoadingProducts() }
            }
        } else {
            PaywallPlanSelector(
                plans: store.plans.sorted { $0.cadence > $1.cadence },
                selectedPlanID: selectedPlan?.id,
                onSelect: { plan in
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.28)) {
                        selectedPlanID = plan.id
                    }
                }
            )
        }
    }

    private var purchaseArea: some View {
        VStack(spacing: 7) {
            if let purchaseMessage {
                Text(purchaseMessage)
                    .font(VaktFont.caption(10))
                    .foregroundStyle(purchaseMessageIsError ? Color.vaktAccent : Color.vaktSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .transition(.opacity)
            }

            Button {
                guard let selectedPlan else { return }
                Task { await store.purchase(planID: selectedPlan.id) }
            } label: {
                HStack(spacing: 9) {
                    if store.purchaseState == .purchasing {
                        ProgressView()
                            .tint(Color.vaktDeep)
                    }

                    Text(actionTitle)
                        .font(VaktFont.button(15))
                }
                .foregroundStyle(Color.vaktDeep)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.vaktPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            Color.white.opacity(selectedPlan?.cadence == .yearly ? 0.24 : 0.12),
                            lineWidth: 0.7
                        )
                }
                .shadow(
                    color: Color.vaktPrimary.opacity(selectedPlan?.cadence == .yearly ? 0.24 : 0.12),
                    radius: selectedPlan?.cadence == .yearly ? 22 : 14,
                    y: 7
                )
            }
            .buttonStyle(VaktPressStyle())
            .disabled(selectedPlan == nil || store.purchaseState == .purchasing)
            .opacity(selectedPlan == nil ? 0.48 : 1)
            .animation(.easeInOut(duration: 0.32), value: selectedPlan?.cadence)

            Text(L10n.string("paywall.renewal"))
                .font(VaktFont.caption(9))
                .foregroundStyle(Color.vaktMuted)
                .multilineTextAlignment(.center)
        }
        .animation(.easeInOut(duration: 0.25), value: store.purchaseState)
    }

    private var footer: some View {
        HStack(spacing: 11) {
            footerButton(L10n.string("paywall.restore")) {
                Task { await store.restorePurchases() }
            }

            footerDivider

            footerButton(L10n.string("common.terms")) { openURL(VaktExternalLinks.terms) }

            footerDivider

            footerButton(L10n.string("common.privacy")) { openURL(VaktExternalLinks.privacy) }
        }
        .frame(maxWidth: .infinity)
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(VaktFont.caption(9))
            .foregroundStyle(Color.vaktMuted)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .buttonStyle(.plain)
            .disabled(store.purchaseState == .purchasing)
    }

    private var footerDivider: some View {
        Rectangle()
            .fill(Color.vaktBorderStrong.opacity(0.72))
            .frame(width: 1, height: 9)
    }

    private var actionTitle: String {
        guard let selectedPlan else { return L10n.string("paywall.action.choose_plan") }
        return switch selectedPlan.cadence {
        case .monthly: L10n.string("paywall.action.continue_monthly")
        case .yearly: L10n.string("paywall.action.continue_yearly")
        }
    }

    private var purchaseMessage: String? {
        switch store.purchaseState {
        case .idle, .purchasing:
            nil
        case .pending:
            L10n.string("paywall.pending")
        case .failed(let message):
            message
        }
    }

    private var purchaseMessageIsError: Bool {
        if case .failed = store.purchaseState { return true }
        return false
    }

    private func selectPreferredPlan() {
        selectedPlanID = preferredPlan?.id
    }

    private func selectPreferredPlanIfNeeded() {
        guard selectedPlanID == nil || !store.plans.contains(where: { $0.id == selectedPlanID }) else {
            return
        }
        selectedPlanID = preferredPlan?.id
    }

    private func runJourney() async {
        while !Task.isCancelled {
            for phase in PaywallJourneyPhase.allCases {
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.48)) {
                    journeyPhase = phase
                }
                let duration = phase == .complete ? 2_200 : 1_500
                try? await Task.sleep(for: .milliseconds(duration))
            }
        }
    }
}

private struct ReferralLinkedMoment: View {
    let inviterName: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var connected = false

    var body: some View {
        ZStack {
            Color.vaktDeep.opacity(0.985)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                ZStack {
                    Capsule()
                        .fill(Color.vaktPrimary.opacity(0.38))
                        .frame(width: connected ? 66 : 10, height: 1)

                    personMark(systemImage: "person", x: connected ? -42 : -68)
                    personMark(systemImage: "person.fill", x: connected ? 42 : 68)

                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.vaktDeep)
                        .frame(width: 27, height: 27)
                        .background(Color.vaktPrimary)
                        .clipShape(Circle())
                        .scaleEffect(connected ? 1 : 0.62)
                        .opacity(connected ? 1 : 0)
                }
                .frame(height: 52)

                VStack(spacing: 7) {
                    Text(L10n.string("paywall.referral.linked_moment.title"))
                        .font(VaktFont.title(27))
                        .foregroundStyle(Color.vaktPrimary)

                    Text(L10n.formatString("paywall.referral.linked_moment.body", inviterName))
                        .font(VaktFont.body(12))
                        .foregroundStyle(Color.vaktSecondary)
                        .multilineTextAlignment(.center)
                }
                .opacity(connected ? 1 : 0)
                .offset(y: connected ? 0 : 8)
            }
            .padding(.horizontal, 36)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.formatString(
            "paywall.referral.linked_moment.accessibility",
            inviterName
        ))
        .onAppear {
            withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.42)) {
                connected = true
            }
        }
    }

    private func personMark(systemImage: String, x: CGFloat) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.vaktPrimary)
            .frame(width: 34, height: 34)
            .background(Color.vaktElevated)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(Color.vaktPrimary.opacity(0.3), lineWidth: 0.7)
            }
            .offset(x: x)
    }
}

private struct PaywallBackground: View {
    var body: some View {
        ZStack {
            Color.vaktDeep

            LinearGradient(
                colors: [Color(hex: "#111A28"), Color.vaktBg, Color.vaktDeep],
                startPoint: .topLeading,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [Color.vaktGlow.opacity(0.055), .clear],
                center: UnitPoint(x: 0.78, y: 0.17),
                startRadius: 6,
                endRadius: 270
            )
        }
        .ignoresSafeArea()
    }
}

private enum PaywallJourneyPhase: Int, CaseIterable {
    case remind
    case quiet
    case record
    case support
    case complete
}

private struct PaywallJourney: View {
    let phase: PaywallJourneyPhase
    let reduceMotion: Bool

    private var steps: [(phase: PaywallJourneyPhase, icon: String, title: String)] {
        [
            (.remind, "bell", L10n.string("paywall.journey.step.remind")),
            (.quiet, "moon.stars", L10n.string("paywall.journey.step.quiet")),
            (.record, "checkmark", L10n.string("paywall.journey.step.record")),
            (.support, "person.2", L10n.string("paywall.journey.step.support"))
        ]
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.vaktBorderStrong.opacity(0.54))
                        .frame(height: 1)
                        .padding(.horizontal, proxy.size.width / 8)

                    Capsule()
                        .fill(Color.vaktPrimary.opacity(0.88))
                        .frame(width: progressWidth(in: proxy.size.width), height: 2)
                        .padding(.leading, proxy.size.width / 8)
                        .shadow(color: Color.vaktPrimary.opacity(0.32), radius: 8)

                    HStack(spacing: 0) {
                        ForEach(steps, id: \.phase.rawValue) { step in
                            journeyStep(step)
                        }
                    }
                }
                .frame(height: 72)

                HStack(spacing: 9) {
                    Capsule()
                        .fill(Color.vaktPrimary.opacity(phase == .complete ? 0.86 : 0.5))
                        .frame(width: phase == .complete ? 34 : 16, height: 2)

                    Text(journeyDetail)
                        .font(phase == .complete ? VaktFont.body(11) : VaktFont.caption(10))
                        .foregroundStyle(phase == .complete ? Color.vaktPrimary : Color.vaktMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .contentTransition(.opacity)

                    Spacer()
                }
                .padding(.horizontal, 3)
                .frame(height: 35)
                .animation(reduceMotion ? .none : .easeInOut(duration: 0.45), value: phase)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(journeyDetail)
    }

    private func journeyStep(
        _ step: (phase: PaywallJourneyPhase, icon: String, title: String)
    ) -> some View {
        let isCurrent = phase == step.phase
        let isPassed = phase == .complete || step.phase.rawValue < phase.rawValue
        let isLit = isCurrent || isPassed

        return VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(isCurrent ? Color.vaktPrimary : Color.vaktBg)
                    .frame(width: 29, height: 29)

                Circle()
                    .strokeBorder(
                        isLit ? Color.vaktPrimary.opacity(0.84) : Color.vaktBorderStrong,
                        lineWidth: isCurrent ? 1.2 : 0.7
                    )
                    .frame(width: 29, height: 29)

                Image(systemName: isPassed ? "checkmark" : step.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isCurrent ? Color.vaktDeep : (isLit ? Color.vaktPrimary : Color.vaktMuted))
                    .contentTransition(.symbolEffect(.replace))
            }
            .shadow(color: isCurrent ? Color.vaktPrimary.opacity(0.22) : .clear, radius: 10)

            Text(step.title)
                .font(VaktFont.caption(9))
                .foregroundStyle(isLit ? Color.vaktPrimary : Color.vaktMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.42), value: phase)
    }

    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        let usableWidth = totalWidth * 0.75
        let fraction: CGFloat
        switch phase {
        case .remind: fraction = 0
        case .quiet: fraction = 1 / 3
        case .record: fraction = 2 / 3
        case .support, .complete: fraction = 1
        }
        return usableWidth * fraction
    }

    private var journeyDetail: String {
        switch phase {
        case .remind: L10n.string("paywall.journey.detail.remind")
        case .quiet: L10n.string("paywall.journey.detail.quiet")
        case .record: L10n.string("paywall.journey.detail.record")
        case .support: L10n.string("paywall.journey.detail.support")
        case .complete: L10n.string("paywall.journey.detail.complete")
        }
    }
}

private struct PaywallReasons: View {
    private var reasons: [(icon: String, title: String, detail: String)] {
        [
            ("clock", L10n.string("paywall.reason.reminders.title"), L10n.string("paywall.reason.reminders.detail")),
            ("calendar", L10n.string("paywall.reason.makeup.title"), L10n.string("paywall.reason.makeup.detail")),
            ("hand.raised", L10n.string("paywall.reason.support.title"), L10n.string("paywall.reason.support.detail"))
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(reasons.enumerated()), id: \.offset) { index, reason in
                HStack(spacing: 12) {
                    Image(systemName: reason.icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.vaktSecondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(reason.title)
                            .font(VaktFont.body(12))
                            .foregroundStyle(Color.vaktPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)

                        Text(reason.detail)
                            .font(VaktFont.caption(10))
                            .foregroundStyle(Color.vaktMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer()
                }
                .frame(height: 43)

                if index < reasons.count - 1 {
                    Rectangle()
                        .fill(Color.vaktBorder.opacity(0.52))
                        .frame(height: 0.5)
                        .padding(.leading, 36)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct PaywallPlanSelector: View {
    let plans: [SubscriptionStore.Plan]
    let selectedPlanID: String?
    let onSelect: (SubscriptionStore.Plan) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(plans.enumerated()), id: \.element.id) { index, plan in
                PaywallPlanRow(
                    plan: plan,
                    isSelected: selectedPlanID == plan.id,
                    action: { onSelect(plan) }
                )

                if index < plans.count - 1 {
                    Rectangle()
                        .fill(Color.vaktBorder.opacity(0.6))
                        .frame(height: 0.5)
                        .padding(.horizontal, 12)
                }
            }
        }
        .padding(4)
        .background(Color.vaktSurface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.vaktBorderStrong.opacity(0.72), lineWidth: 0.7)
        }
    }
}

private struct PaywallPlanRow: View {
    let plan: SubscriptionStore.Plan
    let isSelected: Bool
    let action: () -> Void

    private var isYearly: Bool { plan.cadence == .yearly }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.vaktPrimary : Color.vaktSecondary.opacity(0.72),
                            lineWidth: isSelected ? 1.4 : 1
                        )
                        .frame(width: 19, height: 19)

                    if isSelected {
                        Circle()
                            .fill(Color.vaktPrimary)
                            .frame(width: 11, height: 11)
                            .shadow(color: Color.vaktPrimary.opacity(0.38), radius: 4)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 7) {
                        Text(plan.title)
                            .font(VaktFont.button(14))
                            .foregroundStyle(isSelected ? Color.vaktPrimary : Color.vaktSecondary)

                        if isYearly {
                            Text(L10n.string("paywall.best_value")
                                .uppercased(with: VaktLocalization.appLocale))
                                .font(VaktFont.eyebrow(8))
                                .foregroundStyle(Color.vaktDeep)
                                .padding(.horizontal, 6)
                                .frame(height: 17)
                                .background(Color.vaktPrimary)
                                .clipShape(Capsule())
                        }
                    }

                    Text(planDetail)
                        .font(VaktFont.caption(10))
                        .foregroundStyle(isSelected ? Color.vaktSecondary : Color.vaktMuted)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if let originalPrice {
                        Text(originalPrice)
                            .font(VaktFont.caption(9))
                            .foregroundStyle(
                                isSelected ? Color.vaktMuted.opacity(0.92) : Color.vaktMuted.opacity(0.74)
                            )
                            .strikethrough(true)
                    }

                    Text(L10n.formatString(
                        isYearly ? "paywall.price.year" : "paywall.price.month",
                        plan.displayPrice
                    ))
                        .font(VaktFont.button(isSelected ? 15 : 14))
                        .foregroundStyle(isSelected ? Color.vaktPrimary : Color.vaktSecondary.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 64)
            .background(isSelected ? Color.vaktElevated.opacity(0.82) : Color.vaktSurface.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.vaktPrimary.opacity(0.5), lineWidth: 0.9)
                        .padding(1)
                }
            }
            .shadow(
                color: isSelected ? Color.vaktPrimary.opacity(0.09) : .clear,
                radius: 10,
                y: 2
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(VaktPressStyle())
        .animation(.easeInOut(duration: 0.24), value: isSelected)
        .accessibilityLabel(L10n.formatString(
            "paywall.plan.accessibility",
            plan.title,
            plan.displayPrice,
            planDetail
        ))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var originalPrice: String? {
        guard plan.displayPrice.contains("$") else { return nil }
        return isYearly ? "$249.99" : "$29.99"
    }

    private var planDetail: String {
        if isYearly {
            return plan.displayPrice.contains("$")
                ? L10n.string("paywall.yearly_month")
                : L10n.string("paywall.billing.yearly")
        }
        return L10n.string("paywall.billing.monthly")
    }
}

private struct PaywallPlanLoading: View {
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .tint(Color.vaktPrimary)

            Text(L10n.string("paywall.loading"))
                .font(VaktFont.caption(9))
                .foregroundStyle(Color.vaktMuted)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 118)
        .background(Color.vaktSurface.opacity(0.56))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PaywallPlanUnavailable: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(L10n.string("paywall.unavailable"))
                .font(VaktFont.body(11))
                .foregroundStyle(Color.vaktSecondary)

            Button(L10n.string("common.retry"), action: retry)
                .font(VaktFont.button(11))
                .foregroundStyle(Color.vaktPrimary)
                .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 118)
        .background(Color.vaktSurface.opacity(0.56))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
