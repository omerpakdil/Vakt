import SwiftUI

struct OnboardingFriendsView: View {
    let stepIndex: Int
    let stepCount: Int
    let reduceMotion: Bool
    let onContinue: () -> Void

    @State private var selectedFriendID: String?
    @State private var remindedFriendID: String?
    @State private var isSending = false
    @State private var resetTask: Task<Void, Never>?
    @State private var demoTask: Task<Void, Never>?

    var body: some View {
        VaktOnboardingShell(
            stepIndex: stepIndex,
            stepCount: stepCount,
            eyebrow: L10n.string("onboarding.friends.eyebrow"),
            title: L10n.string("onboarding.friends.title"),
            bodyText: L10n.string("onboarding.friends.body"),
            actionTitle: L10n.string("action.continue"),
            onContinue: onContinue
        ) {
            FriendsReminderScene(
                selectedFriendID: selectedFriendID,
                remindedFriendID: remindedFriendID,
                isSending: isSending,
                reduceMotion: reduceMotion,
                onSelect: select,
                onRemind: sendReminder
            )
        }
        .onAppear { startDemo() }
        .onDisappear {
            resetTask?.cancel()
            demoTask?.cancel()
        }
    }

    private func select(_ id: String) {
        demoTask?.cancel()
        guard !isSending else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(reduceMotion ? .none : .spring(response: 0.44, dampingFraction: 0.84)) {
            selectedFriendID = id
            remindedFriendID = nil
        }
    }

    private func sendReminder() {
        demoTask?.cancel()
        guard selectedFriendID == "yusuf", !isSending else { return }
        resetTask?.cancel()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()

        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.42)) {
            isSending = true
        }

        resetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 180 : 780))
            guard !Task.isCancelled else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.88)) {
                isSending = false
                remindedFriendID = selectedFriendID
            }
        }
    }

    private func startDemo() {
        demoTask?.cancel()
        demoTask = Task { @MainActor in
            while !Task.isCancelled {
                await showFriend("ayse", for: 1_650)
                await showFriend("meryem", for: 1_650)
                await showFriend("yusuf", for: 1_900)
                guard !Task.isCancelled else { return }

                withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.42)) {
                    isSending = true
                }
                try? await Task.sleep(for: .milliseconds(1_050))
                guard !Task.isCancelled else { return }

                withAnimation(reduceMotion ? .none : .spring(response: 0.5, dampingFraction: 0.88)) {
                    isSending = false
                    remindedFriendID = "yusuf"
                }
                try? await Task.sleep(for: .milliseconds(2_500))
                guard !Task.isCancelled else { return }

                withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.35)) {
                    selectedFriendID = nil
                    remindedFriendID = nil
                }
                try? await Task.sleep(for: .milliseconds(900))
            }
        }
    }

    private func showFriend(_ id: String, for milliseconds: Int) async {
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? .none : .spring(response: 0.44, dampingFraction: 0.84)) {
            selectedFriendID = id
            remindedFriendID = nil
            isSending = false
        }
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }
}

private struct FriendsReminderScene: View {
    let selectedFriendID: String?
    let remindedFriendID: String?
    let isSending: Bool
    let reduceMotion: Bool
    let onSelect: (String) -> Void
    let onRemind: () -> Void

    private var friends: [OnboardingFriend] {
        [
            OnboardingFriend(id: "ayse", name: "Ayşe", initials: "A", statusKey: "onboarding.friends.status.dhuhr_prayed", isComplete: true),
            OnboardingFriend(id: "yusuf", name: "Yusuf", initials: "Y", statusKey: "onboarding.friends.status.asr_unmarked", isComplete: false),
            OnboardingFriend(id: "meryem", name: "Meryem", initials: "M", statusKey: "onboarding.friends.status.asr_prayed", isComplete: true)
        ]
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                reminderAtmosphere(size: proxy.size)

                friendNode(friends[0], alignment: .leading)
                    .position(x: proxy.size.width * 0.25, y: proxy.size.height * 0.39)

                friendNode(friends[1], alignment: .center)
                    .position(x: proxy.size.width * 0.50, y: proxy.size.height * 0.62)

                friendNode(friends[2], alignment: .trailing)
                    .position(x: proxy.size.width * 0.75, y: proxy.size.height * 0.35)

                VStack(spacing: 8) {
                    Text(sceneMessage)
                        .font(VaktFont.caption(10))
                        .foregroundStyle(remindedFriendID == nil ? Color.vaktMuted : Color.vaktPrimary)
                        .contentTransition(.opacity)

                    if selectedFriendID == "yusuf", remindedFriendID == nil {
                        Button(action: onRemind) {
                            HStack(spacing: 8) {
                                Image(systemName: isSending ? "wave.3.right" : "hand.tap")
                                    .font(.system(size: 12, weight: .medium))
                                    .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isSending)

                                Text(L10n.string(isSending
                                    ? "onboarding.friends.action.sending"
                                    : "onboarding.friends.action.remind"))
                                    .font(VaktFont.body(12))
                            }
                            .foregroundStyle(Color.vaktDeep)
                            .padding(.horizontal, 18)
                            .frame(height: 42)
                            .background(Color.vaktPrimary)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(VaktPressStyle())
                        .disabled(isSending)
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    }
                }
                .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.88)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func friendNode(_ friend: OnboardingFriend, alignment: HorizontalAlignment) -> some View {
        let selected = selectedFriendID == friend.id
        let reminded = remindedFriendID == friend.id

        return Button { onSelect(friend.id) } label: {
            VStack(alignment: alignment, spacing: 8) {
                ZStack {
                    Circle()
                        .fill(selected ? Color.vaktPrimary.opacity(0.12) : Color.vaktElevated.opacity(0.72))
                        .frame(width: selected ? 82 : 72, height: selected ? 82 : 72)

                    Circle()
                        .strokeBorder(selected ? Color.vaktPrimary.opacity(0.72) : Color.vaktBorderStrong, lineWidth: selected ? 1.2 : 0.6)
                        .frame(width: selected ? 68 : 60, height: selected ? 68 : 60)

                    Text(friend.initials)
                        .font(VaktFont.title(22))
                        .foregroundStyle(selected ? Color.vaktPrimary : Color.vaktSecondary)

                    if friend.isComplete || reminded {
                        Image(systemName: reminded ? "bell.fill" : "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.vaktDeep)
                            .frame(width: 21, height: 21)
                            .background(Color.vaktPrimary)
                            .clipShape(Circle())
                            .offset(x: 25, y: 24)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                VStack(alignment: alignment, spacing: 2) {
                    Text(friend.name)
                        .font(VaktFont.body(12))
                        .foregroundStyle(selected ? Color.vaktPrimary : Color.vaktSecondary)

                    Text(reminded
                        ? L10n.string("onboarding.friends.status.reminder_delivered")
                        : friend.status)
                        .font(VaktFont.caption(8))
                        .foregroundStyle(Color.vaktMuted)
                        .lineLimit(1)
                }
            }
            .frame(width: 124)
            .contentShape(Rectangle())
        }
        .buttonStyle(VaktPressStyle())
        .accessibilityLabel(L10n.formatString(
            "onboarding.friends.friend_accessibility",
            friend.name,
            reminded ? L10n.string("onboarding.friends.status.reminder_delivered") : friend.status
        ))
        .accessibilityHint(L10n.string(friend.isComplete
            ? "onboarding.friends.hint.prayed"
            : "onboarding.friends.hint.select_to_remind"))
    }

    private func reminderAtmosphere(size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let points = [
                CGPoint(x: canvasSize.width * 0.25, y: canvasSize.height * 0.39),
                CGPoint(x: canvasSize.width * 0.50, y: canvasSize.height * 0.62),
                CGPoint(x: canvasSize.width * 0.75, y: canvasSize.height * 0.35)
            ]

            var path = Path()
            path.move(to: points[0])
            path.addQuadCurve(to: points[1], control: CGPoint(x: canvasSize.width * 0.30, y: canvasSize.height * 0.62))
            path.addQuadCurve(to: points[2], control: CGPoint(x: canvasSize.width * 0.70, y: canvasSize.height * 0.57))

            context.stroke(path, with: .color(.vaktAccent.opacity(0.14)), style: StrokeStyle(lineWidth: 0.7, dash: [3, 7]))

            if isSending, selectedFriendID != nil {
                context.stroke(path, with: .color(.vaktPrimary.opacity(0.42)), style: StrokeStyle(lineWidth: 1.2, dash: [12, 18], dashPhase: reduceMotion ? 0 : -10))
            }
        }
        .allowsHitTesting(false)
    }

    private var sceneMessage: String {
        if let remindedFriendID,
           let friend = friends.first(where: { $0.id == remindedFriendID }) {
            return L10n.formatString("onboarding.friends.scene.reminded", friend.name)
        }
        if isSending {
            return L10n.string("onboarding.friends.scene.sending")
        }
        if let selectedFriendID,
           let friend = friends.first(where: { $0.id == selectedFriendID }) {
            return friend.isComplete
                ? L10n.formatString("onboarding.friends.scene.prayed", friend.name)
                : L10n.string("onboarding.friends.scene.can_remind")
        }
        return L10n.string("onboarding.friends.scene.idle")
    }
}

private struct OnboardingFriend: Identifiable {
    let id: String
    let name: String
    let initials: String
    let statusKey: String
    let isComplete: Bool

    var status: String {
        L10n.string(statusKey)
    }
}
