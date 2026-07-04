import SwiftUI

struct HomeView: View {
    @Binding var selectedTab: VaktTab
    @ObservedObject var presenceStore: LiveSafPresenceStore
    @ObservedObject var prayerStore: PrayerScheduleStore
    @ObservedObject var sessionStore: PrayerSessionStore

    var body: some View {
        let nextPrayer = prayerStore.nextPrayer
        let upcomingPrayers = prayerStore.upcomingPrayers
        let sessionStatus = sessionStore.status(for: nextPrayer)

        ZStack {
            Color.vaktBg.ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    EyebrowLabel(text: "Next")
                        .padding(.bottom, 10)

                    Text(nextPrayer.prayer.displayName)
                        .font(VaktFont.prayerDisplay())
                        .foregroundStyle(Color.vaktPrimary)
                        .tracking(-2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .contentTransition(.opacity)

                    Text(
                        VaktTimeFormatter.string(
                            from: nextPrayer.time,
                            timeZone: nextPrayer.timeZone
                        )
                    )
                        .font(VaktFont.timeDisplay(18))
                        .foregroundStyle(Color.vaktAccent)
                        .tracking(1)
                        .padding(.top, 4)
                        .contentTransition(.numericText())

                    CountdownLabel(seconds: prayerStore.nextCountdown)
                        .padding(.top, 8)
                        .padding(.bottom, 32)

                    HorizonView(
                        members: VaktMockData.globalSaf.members,
                        liveMemberCount: presenceStore.displayMemberCount,
                        presentation: .homePreview,
                        height: 150,
                        showLegend: false,
                        earthRatio: 0.43
                    )
                    .padding(.horizontal, -VaktSpace.lg)
                    .overlay(alignment: .bottom) {
                        HStack(spacing: 4) {
                            VaktRollingNumberText(
                                value: presenceStore.displayMemberCount,
                                direction: presenceStore.countDirection,
                                font: VaktFont.caption(11),
                                color: .vaktGlow.opacity(0.82),
                                digitWidth: 7,
                                digitHeight: 14
                            )

                            Text("people preparing")
                                .font(VaktFont.caption(11))
                                .foregroundStyle(Color.vaktMuted)
                                .tracking(0.5)
                                .textCase(.uppercase)
                        }
                        .padding(.bottom, 14)
                        .animation(.easeOut(duration: 0.22), value: presenceStore.displayMemberCount)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, VaktSpace.lg)
                .padding(.top, VaktSpace.xxl)

                JoinSafCTAButton(prayer: nextPrayer.prayer, sessionStatus: sessionStatus) {
                    selectedTab = .safs
                }
                .padding(.horizontal, VaktSpace.lg)
                .padding(.top, VaktSpace.lg)

                VStack(alignment: .leading, spacing: 0) {
                    EyebrowLabel(text: "Later")
                        .foregroundStyle(Color.vaktShadow)
                        .padding(.bottom, VaktSpace.sm)

                    ForEach(upcomingPrayers.dropFirst()) { prayer in
                        PrayerRow(prayerTime: prayer)
                        VaktDivider()
                    }
                }
                .padding(.horizontal, VaktSpace.lg)
                .padding(.top, VaktSpace.lg)

                Spacer(minLength: VaktSpace.lg)
            }
        }
    }

}

private struct JoinSafCTAButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    let prayer: Prayer
    let sessionStatus: PrayerSessionStatus
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            HStack(spacing: VaktSpace.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(VaktFont.button(16))
                        .foregroundStyle(Color.vaktPrimary)
                        .tracking(0.25)

                    Text(subtitle)
                        .font(VaktFont.caption(11))
                        .foregroundStyle(Color.vaktMuted)
                        .tracking(0.25)
                }

                Spacer(minLength: VaktSpace.md)

                HorizonCue(isBreathing: isBreathing && !reduceMotion)
            }
            .padding(.horizontal, VaktSpace.md)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                    .fill(Color.vaktSurface)
                    .overlay(alignment: .topLeading) {
                        LinearGradient(
                            colors: [
                                Color.vaktPrimary.opacity(0.075),
                                Color.vaktAccent.opacity(0.018),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
                    }
            )
            .overlay(
                RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                    .strokeBorder(Color.vaktAccent.opacity(0.48), lineWidth: 0.6)
            )
        }
        .buttonStyle(VaktPressStyle())
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }

    private var title: String {
        switch sessionStatus {
        case .ready:
            return "Join the Saf"
        case .inProgress:
            return "Resume \(prayer.displayName)"
        case .primaryCompleted:
            return "\(prayer.displayName) kept"
        }
    }

    private var subtitle: String {
        switch sessionStatus {
        case .ready:
            return "Join the Saf for the next prayer"
        case .inProgress:
            return "Your salah screen is still open"
        case .primaryCompleted:
            return "Kept privately on this device"
        }
    }

    private var accessibilityHint: String {
        switch sessionStatus {
        case .ready:
            return "Opens the Saf for the next prayer."
        case .inProgress:
            return "Returns to your open salah screen."
        case .primaryCompleted:
            return "Opens the saf for this prayer."
        }
    }
}

private struct HorizonCue: View {
    let isBreathing: Bool

    var body: some View {
        ZStack {
            Capsule()
                .fill(Color.vaktAccent.opacity(0.22))
                .frame(width: 48, height: 1)

            Circle()
                .fill(Color.vaktPrimary.opacity(0.95))
                .frame(width: 9, height: 9)
                .shadow(color: Color.vaktPrimary.opacity(isBreathing ? 0.45 : 0.22), radius: isBreathing ? 8 : 4)
                .scaleEffect(isBreathing ? 1.12 : 1)
        }
        .frame(width: 58, height: 30)
    }
}
