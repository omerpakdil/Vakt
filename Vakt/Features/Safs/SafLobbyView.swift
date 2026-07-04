import SwiftUI

struct SafLobbyView: View {
    @ObservedObject var presenceStore: LiveSafPresenceStore
    @ObservedObject var prayerStore: PrayerScheduleStore
    @ObservedObject var reflectionStore: PrayerReflectionStore
    @ObservedObject var sessionStore: PrayerSessionStore

    @State private var selectedStatus: PrepStatus = .wudu
    @State private var activeSession: PrayerQuietSession?
    @State private var placementPresented = false
    @State private var pendingSessionAfterPlacement: PrayerQuietSession?

    var body: some View {
        let prayerTime = prayerStore.nextPrayer
        let sessionStatus = sessionStore.status(for: prayerTime)

        ZStack {
            Color.vaktBg.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                HorizonView(
                    members: membersWithCurrentStatus,
                    liveMemberCount: presenceStore.displayMemberCount,
                    presentation: .lobbyFormation,
                    height: 210,
                    showLegend: true,
                    earthRatio: 0.40
                )

                StatusSelector(selectedStatus: $selectedStatus)
                    .padding(.top, VaktSpace.md)

                Spacer(minLength: VaktSpace.lg)

                VStack(spacing: VaktSpace.sm) {
                    QuietModeEntryButton(prayer: prayerTime.prayer, sessionStatus: sessionStatus) {
                        handleQuietModeEntry(prayerTime: prayerTime, status: sessionStatus)
                    }

                    Text(helperText(for: sessionStatus))
                        .font(VaktFont.caption(11))
                        .foregroundStyle(Color.vaktShadow)
                        .tracking(0.3)
                }
                .padding(.horizontal, VaktSpace.lg)
                .padding(.bottom, VaktSpace.xl)
            }
        }
        .fullScreenCover(isPresented: $placementPresented) {
            SafPlacementView(
                prayer: prayerTime.prayer,
                memberCount: presenceStore.displayMemberCount,
                onCancel: {
                    placementPresented = false
                },
                onSelect: { placement in
                    selectedStatus = .praying
                    pendingSessionAfterPlacement = sessionStore.beginSession(
                        for: prayerTime,
                        companionCount: presenceStore.displayMemberCount,
                        placement: placement
                    )
                    placementPresented = false
                }
            )
        }
        .fullScreenCover(item: $activeSession) { session in
            QuietSalahView(
                session: session,
                presenceStore: presenceStore,
                reflectionStore: reflectionStore,
                sessionStore: sessionStore
            )
        }
        .onChange(of: placementPresented) { _, isPresented in
            guard !isPresented, let pendingSessionAfterPlacement else { return }
            self.pendingSessionAfterPlacement = nil

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 260_000_000)
                activeSession = pendingSessionAfterPlacement
            }
        }
        .onAppear {
            presenceStore.join(status: selectedStatus)
        }
        .onChange(of: selectedStatus) { _, status in
            presenceStore.updateStatus(status)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            EyebrowLabel(text: "Saf")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(prayerStore.nextPrayer.prayer.displayName) ·")
                    .font(VaktFont.title())
                    .foregroundStyle(Color.vaktPrimary)
                    .tracking(-0.5)

                VaktRollingNumberText(
                    value: presenceStore.displayMemberCount,
                    direction: presenceStore.countDirection,
                    font: VaktFont.title(),
                    color: .vaktPrimary,
                    digitWidth: 13,
                    digitHeight: 27
                )

                Text("people")
                    .font(VaktFont.title())
                    .foregroundStyle(Color.vaktPrimary)
                    .tracking(-0.5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, VaktSpace.lg)
        .padding(.top, VaktSpace.xxl)
        .padding(.bottom, VaktSpace.md)
        .overlay(alignment: .bottom) {
            VaktDivider()
        }
    }

    private var membersWithCurrentStatus: [SafMember] {
        VaktMockData.globalSaf.members.map { member in
            guard member.isCurrentUser else { return member }
            return SafMember(
                id: member.id,
                normalizedPosition: member.normalizedPosition,
                status: selectedStatus,
                isCurrentUser: true
            )
        }
    }

    private func helperText(for status: PrayerSessionStatus) -> String {
        switch status {
        case .ready:
            return "Join the Saf, then put the phone away"
        case .inProgress:
            return "Return to your salah screen"
        case .primaryCompleted:
            return "Kept privately on this device"
        }
    }

    private func handleQuietModeEntry(prayerTime: PrayerTime, status: PrayerSessionStatus) {
        switch status {
        case .ready:
            selectedStatus = .ready
            placementPresented = true
        case .inProgress, .primaryCompleted:
            selectedStatus = .praying
            activeSession = sessionStore.beginSession(
                for: prayerTime,
                companionCount: presenceStore.displayMemberCount
            )
        }
    }

}

private struct QuietModeEntryButton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let prayer: Prayer
    let sessionStatus: PrayerSessionStatus
    let action: () -> Void

    @State private var progress: CGFloat = 0
    @State private var isPressing = false
    @State private var holdTask: Task<Void, Never>?

    private let holdDuration: TimeInterval = 1.35
    private let progressTick: UInt64 = 16_000_000

    var body: some View {
        if requiresHold {
            holdButton
        } else if isCompleted {
            completedPanel
        } else {
            tapButton
        }
    }

    private var holdButton: some View {
        ZStack {
            RoundedRectangle(cornerRadius: VaktRadius.lg, style: .continuous)
                .fill(Color.vaktSurface)

            GeometryReader { proxy in
                let width = proxy.size.width
                let progressY = proxy.size.height * 0.52
                let progressedWidth = width * progress
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: VaktRadius.lg, style: .continuous)
                        .fill(Color.vaktPrimary.opacity(0.08))
                        .frame(width: max(0, width * progress))

                    Rectangle()
                        .fill(Color.vaktAccent.opacity(0.42))
                        .frame(width: max(0, progressedWidth), height: 0.5)
                        .position(x: max(0, progressedWidth) / 2, y: progressY)

                    Circle()
                        .fill(progress >= 1 ? Color.vaktPrimary : Color.vaktAccent)
                        .frame(width: 10 + (8 * progress), height: 10 + (8 * progress))
                        .shadow(color: Color.vaktPrimary.opacity(0.25 * progress), radius: 10 * progress)
                        .position(
                            x: max(16, min(width - 16, progressedWidth)),
                            y: progressY
                        )
                        .opacity(progress > 0 ? 1 : 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: VaktRadius.lg, style: .continuous))
            }

            ZStack {
                VStack(alignment: .center, spacing: 3) {
                    Text(progress >= 1 ? "Begin now" : "Hold to Begin Salah")
                        .font(VaktFont.button())
                        .foregroundStyle(progress > 0.82 ? Color.vaktPrimary : Color.vaktPrimary)
                        .tracking(0.3)

                    Text(isPressing ? "Keep holding" : "Hold until ready")
                        .font(VaktFont.caption(11))
                        .foregroundStyle(Color.vaktMuted)
                        .tracking(0.4)
                }

                HStack {
                    Spacer()

                    Text("\(Int(progress * 100))%")
                        .font(VaktFont.caption(11))
                        .foregroundStyle(progress > 0 ? Color.vaktGlow : Color.vaktShadow)
                        .monospacedDigit()
                        .opacity(isPressing ? 1 : 0)
                }
            }
            .padding(.horizontal, VaktSpace.md)
        }
        .frame(height: 66)
        .overlay(
            RoundedRectangle(cornerRadius: VaktRadius.lg, style: .continuous)
                .strokeBorder(progress > 0 ? Color.vaktPrimary.opacity(0.65) : Color.vaktAccent, lineWidth: 0.5)
        )
        .scaleEffect(isPressing ? 0.985 : 1)
        .contentShape(RoundedRectangle(cornerRadius: VaktRadius.lg, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressing else { return }
                    beginHold()
                }
                .onEnded { _ in
                    cancelHold()
                }
        )
        .onDisappear {
            holdTask?.cancel()
        }
        .accessibilityLabel("Hold to begin salah")
        .accessibilityValue("\(Int(progress * 100)) percent")
        .accessibilityHint("Press and hold until you are ready to begin.")
    }

    private var tapButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: VaktSpace.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tapTitle)
                        .font(VaktFont.button())
                        .foregroundStyle(Color.vaktPrimary)
                        .tracking(0.3)

                    Text(tapSubtitle)
                        .font(VaktFont.caption(11))
                        .foregroundStyle(Color.vaktMuted)
                        .tracking(0.35)
                }

                Spacer()

                Image(systemName: tapIconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.vaktAccent.opacity(0.76))
                    .frame(width: 34, height: 34)
                    .background(Color.vaktAccent.opacity(0.08))
                    .clipShape(Circle())
            }
            .padding(.horizontal, VaktSpace.md)
            .frame(height: 66)
            .background(Color.vaktSurface)
            .clipShape(RoundedRectangle(cornerRadius: VaktRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VaktRadius.lg, style: .continuous)
                    .strokeBorder(Color.vaktAccent.opacity(0.32), lineWidth: 0.5)
            )
        }
        .buttonStyle(VaktPressStyle())
        .accessibilityLabel(tapTitle)
        .accessibilityHint(tapSubtitle)
    }

    private var completedPanel: some View {
        HStack(spacing: VaktSpace.md) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(prayer.displayName) kept")
                    .font(VaktFont.button())
                    .foregroundStyle(Color.vaktPrimary.opacity(0.78))
                    .tracking(0.3)

                Text("Kept privately on this device")
                    .font(VaktFont.caption(11))
                    .foregroundStyle(Color.vaktMuted)
                    .tracking(0.35)
            }

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action()
            } label: {
                Text("Reopen if needed")
                    .font(VaktFont.caption(11))
                    .foregroundStyle(Color.vaktAccent.opacity(0.72))
                    .tracking(0.25)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.vaktAccent.opacity(0.055))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.vaktAccent.opacity(0.14), lineWidth: 0.5)
                    )
            }
            .buttonStyle(VaktPressStyle())
            .accessibilityHint("Reopens the salah screen without marking this prayer again.")
        }
        .padding(.horizontal, VaktSpace.md)
        .frame(height: 66)
        .background(Color.vaktSurface.opacity(0.64))
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VaktRadius.lg, style: .continuous)
                .strokeBorder(Color.vaktBorder.opacity(0.82), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(prayer.displayName) kept")
        .accessibilityHint("This prayer is already kept. Reopen the salah screen only if needed.")
    }

    private var requiresHold: Bool {
        if case .ready = sessionStatus {
            return true
        }

        return false
    }

    private var isCompleted: Bool {
        if case .primaryCompleted = sessionStatus {
            return true
        }

        return false
    }

    private var tapTitle: String {
        switch sessionStatus {
        case .ready:
            return "Hold to Begin Salah"
        case .inProgress:
            return "Return to Salah Screen"
        case .primaryCompleted:
            return "\(prayer.displayName) kept"
        }
    }

    private var tapSubtitle: String {
        switch sessionStatus {
        case .ready:
            return "Hold until ready"
        case .inProgress:
            return "\(prayer.displayName) is still open"
        case .primaryCompleted(let additionalCount):
            return additionalCount == 0 ? "Kept privately on this device" : "Already kept, no need to mark it again"
        }
    }

    private var tapIconName: String {
        switch sessionStatus {
        case .ready:
            return "circle"
        case .inProgress:
            return "arrow.uturn.forward"
        case .primaryCompleted:
            return "moon"
        }
    }

    private func beginHold() {
        isPressing = true
        progress = 0
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        holdTask?.cancel()
        holdTask = Task {
            let start = ContinuousClock.now

            while !Task.isCancelled {
                let elapsed = start.duration(to: ContinuousClock.now)
                let elapsedSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000
                let nextProgress = min(1, elapsedSeconds / holdDuration)

                await MainActor.run {
                    if reduceMotion {
                        progress = nextProgress >= 1 ? 1 : 0
                    } else {
                        progress = nextProgress
                    }
                }

                if nextProgress >= 1 {
                    await MainActor.run {
                        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                        action()
                        resetHold()
                    }
                    return
                }

                try? await Task.sleep(nanoseconds: progressTick)
            }
        }
    }

    private func cancelHold() {
        guard isPressing else { return }
        holdTask?.cancel()
        withAnimation(reduceMotion ? .none : .easeOut(duration: 0.22)) {
            progress = 0
            isPressing = false
        }
    }

    private func resetHold() {
        progress = 0
        isPressing = false
        holdTask?.cancel()
        holdTask = nil
    }
}
