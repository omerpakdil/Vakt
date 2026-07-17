import SwiftUI

struct ReferralCenterView: View {
    @ObservedObject var store: ReferralStore
    @ObservedObject var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.vaktBg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        intro

                        if store.activity == .loading && !store.hasLoadedDashboard {
                            loadingState
                        } else if let error = store.dashboardLoadError,
                                  !store.hasLoadedDashboard {
                            loadFailure(error)
                        } else {
                            campaignCard
                            progressCard
                            rewards

                            if let error = store.dashboardLoadError {
                                refreshFailure(error)
                            }
                        }
                    }
                    .padding(VaktSpace.lg)
                }
            }
            .navigationTitle(L10n.string("referral.center.navigation.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("common.close")) { dismiss() }
                        .foregroundStyle(Color.vaktPrimary)
                }
            }
        }
        .task { await store.refresh() }
        .alert(L10n.string("referral.center.alert.title"), isPresented: messagePresented) {
            Button(L10n.string("common.done")) { store.clearMessage() }
        } message: {
            Text(store.message ?? "")
        }
    }

    private var loadingState: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(Color.vaktGlow)

            Text(L10n.string("referral.center.loading"))
                .font(VaktFont.body(12))
                .foregroundStyle(Color.vaktMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.vaktSurface.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
    }

    private func loadFailure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(L10n.string("referral.center.load_failed"))
                .font(VaktFont.body(14))
                .foregroundStyle(Color.vaktPrimary)

            Text(message)
                .font(VaktFont.caption(10))
                .foregroundStyle(Color.vaktMuted)

            Button {
                Task { await store.refresh() }
            } label: {
                Label(L10n.string("common.retry"), systemImage: "arrow.clockwise")
                    .font(VaktFont.button(12))
                    .foregroundStyle(Color.vaktDeep)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(Color.vaktPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(VaktPressStyle())
        }
        .padding(16)
        .background(Color.vaktSurface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
    }

    private func refreshFailure(_ message: String) -> some View {
        Button {
            Task { await store.refresh() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.clockwise")
                Text(L10n.string("referral.center.refresh_failed"))
                Spacer(minLength: 0)
            }
            .font(VaktFont.caption(10))
            .foregroundStyle(Color.vaktMuted)
            .padding(.horizontal, 14)
            .frame(minHeight: 42)
            .background(Color.vaktSurface.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
        }
        .buttonStyle(VaktPressStyle())
        .accessibilityHint(message)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string("referral.center.intro.title"))
                .font(VaktFont.title(26))
                .foregroundStyle(Color.vaktPrimary)

            Text(L10n.string("referral.center.intro.body"))
                .font(VaktFont.body(13))
                .foregroundStyle(Color.vaktMuted)
                .lineSpacing(4)
        }
    }

    @ViewBuilder
    private var campaignCard: some View {
        if let campaign = store.dashboard.campaign {
            VStack(spacing: 15) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.string("referral.center.campaign.code_label")
                            .uppercased(with: VaktLocalization.appLocale))
                            .font(VaktFont.eyebrow(9))
                            .foregroundStyle(Color.vaktMuted)
                        Text(campaign.code)
                            .font(.system(size: 27, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.vaktPrimary)
                    }

                    Spacer()

                    Text(L10n.formatString(
                        "referral.center.campaign.expires",
                        ReferralCenterFormatter.shortDate(campaign.expiresAt)
                    ))
                        .font(VaktFont.caption(10))
                        .foregroundStyle(Color.vaktSecondary)
                }

                ShareLink(item: shareText(code: campaign.code)) {
                    Label(L10n.string("referral.center.campaign.share_action"), systemImage: "square.and.arrow.up")
                        .font(VaktFont.button(14))
                        .foregroundStyle(Color.vaktDeep)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.vaktPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(VaktPressStyle())
            }
            .padding(17)
            .background(Color.vaktSurface.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                    .strokeBorder(Color.vaktBorder, lineWidth: 0.6)
            }
        } else {
            if subscriptionStore.entitlement == .active {
                Button {
                    Task {
                        await store.createCampaign(
                            allowDeveloperPreview: subscriptionStore.summary == nil
                        )
                    }
                } label: {
                    HStack(spacing: 10) {
                        if store.activity == .loading { ProgressView().tint(Color.vaktDeep) }
                        Text(L10n.string(store.activity == .loading
                            ? "referral.center.campaign.creating"
                            : "referral.center.campaign.create"))
                            .font(VaktFont.button(14))
                    }
                    .foregroundStyle(Color.vaktDeep)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.vaktPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(VaktPressStyle())
                .disabled(store.activity != .idle)
            } else {
                Label(L10n.string("referral.center.campaign.requires_active"), systemImage: "lock")
                    .font(VaktFont.body(12))
                    .foregroundStyle(Color.vaktMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.vaktSurface.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
            }
        }
    }

    private var progressCard: some View {
        HStack(spacing: 0) {
            metric(
                value: L10n.formatString(
                    "referral.center.metric.year_value",
                    ReferralCenterFormatter.number(store.dashboard.yearCount),
                    ReferralCenterFormatter.number(6)
                ),
                title: L10n.string("referral.center.metric.year")
            )
            divider
            metric(
                value: ReferralCenterFormatter.number(store.dashboard.readyRewards.count),
                title: L10n.string("referral.center.metric.ready")
            )
            divider
            metric(
                value: ReferralCenterFormatter.number(store.dashboard.pendingCount),
                title: L10n.string("referral.center.metric.pending")
            )
        }
        .padding(.vertical, 15)
        .background(Color.vaktElevated.opacity(0.48))
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
    }

    @ViewBuilder
    private var rewards: some View {
        if !store.dashboard.readyRewards.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("referral.center.rewards.ready_title"))
                    .font(VaktFont.body(14))
                    .foregroundStyle(Color.vaktPrimary)

                ForEach(store.dashboard.readyRewards) { reward in
                    HStack(spacing: 12) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 18, weight: .light))
                            .foregroundStyle(Color.vaktGlow)
                            .frame(width: 38, height: 38)
                            .background(Color.vaktGlow.opacity(0.09))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.string("referral.center.rewards.month_title"))
                                .font(VaktFont.body(13))
                                .foregroundStyle(Color.vaktPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                            Text(L10n.formatString(
                                "referral.center.rewards.expires",
                                ReferralCenterFormatter.mediumDate(reward.expiresAt)
                            ))
                                .font(VaktFont.caption(9))
                                .foregroundStyle(Color.vaktMuted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .layoutPriority(1)

                        Spacer()

                        Button(store.activity == .redeeming(reward.id)
                            ? L10n.string("referral.center.rewards.redeeming")
                            : L10n.string("referral.center.rewards.redeem")) {
                            Task { await store.redeem(reward, using: subscriptionStore) }
                        }
                        .font(VaktFont.button(11))
                        .foregroundStyle(Color.vaktDeep)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Color.vaktPrimary)
                        .clipShape(Capsule())
                        .buttonStyle(VaktPressStyle())
                        .disabled(store.activity != .idle)
                    }
                    .padding(14)
                    .background(Color.vaktSurface.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
                }
            }
        } else if store.dashboard.pendingCount > 0 {
            HStack(spacing: 12) {
                ProgressView().tint(Color.vaktGlow)
                Text(L10n.string("referral.center.rewards.pending_body"))
                    .font(VaktFont.body(12))
                    .foregroundStyle(Color.vaktMuted)
            }
            .padding(15)
            .background(Color.vaktSurface.opacity(0.52))
            .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
        }
    }

    private func metric(value: String, title: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(VaktFont.title(19)).foregroundStyle(Color.vaktPrimary)
            Text(title).font(VaktFont.caption(9)).foregroundStyle(Color.vaktMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(Color.vaktBorder).frame(width: 0.5, height: 28)
    }

    private func shareText(code: String) -> String {
        let link = VaktExternalLinks.appStore.map { "\n\($0.absoluteString)" } ?? ""
        return L10n.formatString("referral.center.share.text", code) + link
    }

    private var messagePresented: Binding<Bool> {
        Binding(get: { store.message != nil }, set: { if !$0 { store.clearMessage() } })
    }
}

private enum ReferralCenterFormatter {
    private static let locale = VaktLocalization.appLocale

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter
    }()

    private static let mediumDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static func number(_ value: Int) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func shortDate(_ date: Date) -> String {
        shortDateFormatter.string(from: date)
    }

    static func mediumDate(_ date: Date) -> String {
        mediumDateFormatter.string(from: date)
    }
}

struct ReferralCodeSheet: View {
    @ObservedObject var store: ReferralStore
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color.vaktBg.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 18) {
                    Text(L10n.string("referral.code_sheet.title"))
                        .font(VaktFont.title(25))
                        .foregroundStyle(Color.vaktPrimary)
                    Text(L10n.string("referral.code_sheet.body"))
                        .font(VaktFont.body(13))
                        .foregroundStyle(Color.vaktMuted)
                        .lineSpacing(4)

                    TextField(L10n.string("referral.code_sheet.placeholder"), text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(size: 22, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.vaktPrimary)
                        .padding(.horizontal, 16)
                        .frame(height: 54)
                        .background(Color.vaktSurface)
                        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
                        .onChange(of: code) { _, value in
                            code = String(
                                value
                                    .uppercased(with: Locale(identifier: "en_US_POSIX"))
                                    .filter { $0.isLetter || $0.isNumber }
                                    .prefix(8)
                            )
                        }
                        .accessibilityLabel(L10n.string("referral.code_sheet.field.label"))
                        .accessibilityHint(L10n.string("referral.code_sheet.field.hint"))

                    if let message = store.message {
                        Text(message).font(VaktFont.caption(10)).foregroundStyle(Color.vaktGlow)
                    }

                    Button {
                        Task { if await store.claim(code: code) { dismiss() } }
                    } label: {
                        HStack(spacing: 8) {
                            if store.activity == .claiming { ProgressView().tint(Color.vaktDeep) }
                            Text(L10n.string(store.activity == .claiming
                                ? "referral.code_sheet.action.connecting"
                                : "referral.code_sheet.action.accept"))
                                .font(VaktFont.button(14))
                        }
                        .foregroundStyle(Color.vaktDeep)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.vaktPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(VaktPressStyle())
                    .disabled(code.count != 8 || store.activity != .idle)
                    .opacity(code.count == 8 ? 1 : 0.48)

                    Spacer()
                }
                .padding(VaktSpace.lg)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.string("common.close")) { dismiss() }
                        .foregroundStyle(Color.vaktPrimary)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear { store.clearMessage() }
        .onDisappear { store.clearMessage() }
    }
}
