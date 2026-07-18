import SwiftUI

enum VaktButtonStyle {
    case primary
    case critical
    case secondary
    case ghost
}

struct VaktButton: View {
    let title: String
    let style: VaktButtonStyle
    var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            Text(title)
                .font(style == .ghost ? VaktFont.body(15) : VaktFont.button())
                .foregroundStyle(foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: style == .ghost ? nil : .infinity)
                .padding(.vertical, style == .ghost ? VaktSpace.sm : 18)
                .padding(.horizontal, VaktSpace.md)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 0.5)
                )
                .opacity(isEnabled ? 1.0 : 0.4)
        }
        .buttonStyle(VaktPressStyle())
        .accessibilityLabel(title)
    }

    private var background: Color {
        switch style {
        case .primary: .vaktPrimary
        case .critical: .vaktSurface
        case .secondary: .clear
        case .ghost: .clear
        }
    }

    private var foreground: Color {
        switch style {
        case .primary: .vaktBg
        case .critical: .vaktPrimary
        case .secondary: .vaktGlow
        case .ghost: .vaktAccent
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary: .clear
        case .critical: .vaktAccent
        case .secondary: .vaktBorder
        case .ghost: .clear
        }
    }
}

struct VaktPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

enum VaktModalTone {
    case neutral
    case warm
    case permission
    case destructive

    var accent: Color {
        switch self {
        case .neutral:
            return .vaktAccent
        case .warm:
            return .vaktGlow
        case .permission:
            return .vaktPrimary
        case .destructive:
            return .vaktAccent
        }
    }

    var symbol: String {
        switch self {
        case .neutral:
            return "circle"
        case .warm:
            return "sparkle"
        case .permission:
            return "hand.raised"
        case .destructive:
            return "exclamationmark"
        }
    }
}

enum VaktModalActionRole {
    case primary
    case secondary
    case destructive
}

struct VaktModalAction {
    let title: String
    let role: VaktModalActionRole
    let action: () -> Void

    init(title: String, role: VaktModalActionRole = .primary, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }
}

struct VaktModalState: Identifiable {
    let id = UUID()
    let tone: VaktModalTone
    let title: String
    let message: String
    let primaryAction: VaktModalAction
    let secondaryAction: VaktModalAction?

    init(
        tone: VaktModalTone = .neutral,
        title: String,
        message: String,
        primaryAction: VaktModalAction,
        secondaryAction: VaktModalAction? = nil
    ) {
        self.tone = tone
        self.title = title
        self.message = message
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
    }
}

struct VaktModalModifier: ViewModifier {
    @Binding var modal: VaktModalState?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        ZStack {
            content

            if let modal {
                VaktModalOverlay(
                    modal: modal,
                    reduceMotion: reduceMotion,
                    dismiss: { self.modal = nil }
                )
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.22), value: modal?.id)
    }
}

extension View {
    func vaktModal(_ modal: Binding<VaktModalState?>) -> some View {
        modifier(VaktModalModifier(modal: modal))
    }
}

private struct VaktModalOverlay: View {
    let modal: VaktModalState
    let reduceMotion: Bool
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.vaktDeep.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            VaktModalCard(modal: modal, dismiss: dismiss)
                .padding(.horizontal, VaktSpace.lg)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .scale(scale: 0.96).combined(with: .opacity)
                )
        }
        .accessibilityAddTraits(.isModal)
    }
}

private struct VaktModalCard: View {
    let modal: VaktModalState
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VaktModalHeader(tone: modal.tone)

            VStack(alignment: .leading, spacing: 8) {
                Text(modal.title)
                    .font(VaktFont.title(25))
                    .foregroundStyle(Color.vaktPrimary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text(modal.message)
                    .font(VaktFont.body(13))
                    .foregroundStyle(Color.vaktMuted)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: VaktSpace.sm) {
                modalButton(modal.primaryAction)

                if let secondaryAction = modal.secondaryAction {
                    modalButton(secondaryAction)
                }
            }
        }
        .padding(VaktSpace.md)
        .background(
            RoundedRectangle(cornerRadius: VaktRadius.xl, style: .continuous)
                .fill(Color.vaktBg)
                .overlay(alignment: .topLeading) {
                    LinearGradient(
                        colors: [
                            modal.tone.accent.opacity(0.12),
                            Color.vaktSurface.opacity(0.28),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: VaktRadius.xl, style: .continuous))
                }
        )
        .overlay(
            RoundedRectangle(cornerRadius: VaktRadius.xl, style: .continuous)
                .strokeBorder(modal.tone.accent.opacity(0.24), lineWidth: 0.7)
        )
        .shadow(color: Color.black.opacity(0.32), radius: 32, y: 18)
    }

    private func modalButton(_ action: VaktModalAction) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: action.role == .destructive ? .rigid : .medium).impactOccurred()
            dismiss()
            action.action()
        } label: {
            Text(action.title)
                .font(action.role == .secondary ? VaktFont.body(14) : VaktFont.button(15))
                .foregroundStyle(buttonForeground(for: action.role))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .frame(height: action.role == .secondary ? 42 : 52)
                .background(buttonBackground(for: action.role))
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(buttonBorder(for: action.role), lineWidth: 0.6)
                )
        }
        .buttonStyle(VaktPressStyle())
    }

    private func buttonForeground(for role: VaktModalActionRole) -> Color {
        switch role {
        case .primary:
            return .vaktBg
        case .secondary:
            return .vaktMuted
        case .destructive:
            return .vaktPrimary
        }
    }

    private func buttonBackground(for role: VaktModalActionRole) -> Color {
        switch role {
        case .primary:
            return .vaktPrimary
        case .secondary:
            return .clear
        case .destructive:
            return .vaktSurface
        }
    }

    private func buttonBorder(for role: VaktModalActionRole) -> Color {
        switch role {
        case .primary, .secondary:
            return .clear
        case .destructive:
            return .vaktAccent.opacity(0.48)
        }
    }
}

private struct VaktModalHeader: View {
    let tone: VaktModalTone

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(tone.accent.opacity(0.12))
                    .frame(width: 42, height: 42)

                Image(systemName: tone.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(tone.accent)
            }

            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(tone.accent.opacity(0.52))
                    .frame(width: 80, height: 2)

                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.vaktBorderStrong.opacity(0.72))
                    .frame(width: 42, height: 1)
            }

            Spacer()
        }
    }
}

struct PrayerRow: View {
    let prayerTime: PrayerTime
    var isNext = false

    var body: some View {
        HStack {
            Text(prayerTime.prayer.displayName)
                .font(VaktFont.body(14))
                .foregroundStyle(isNext ? Color.vaktSecondary : Color.vaktMuted)

            Spacer()

            Text(
                VaktTimeFormatter.string(
                    from: prayerTime.time,
                    timeZone: prayerTime.timeZone
                )
            )
                .font(VaktFont.body(14))
                .foregroundStyle(isNext ? Color.vaktAccent : Color.vaktShadow)
                .monospacedDigit()
        }
        .padding(.vertical, VaktSpace.sm + 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(prayerTime.prayer.displayName), \(VaktTimeFormatter.string(from: prayerTime.time, timeZone: prayerTime.timeZone))"
        )
    }
}

struct CountdownLabel: View {
    let seconds: TimeInterval
    var fontSize: CGFloat = 13
    var digitWidth: CGFloat = 8
    var digitHeight: CGFloat = 17

    private var totalSeconds: Int {
        max(0, Int(seconds.rounded(.down)))
    }

    private var totalMinutes: Int {
        max(0, Int(ceil(seconds / 60)))
    }

    var body: some View {
        HStack(spacing: fontSize < 13 ? 3 : 4) {
            if totalMinutes >= 60 {
                VaktRollingNumberText(
                    value: totalMinutes / 60,
                    direction: -1,
                    font: VaktFont.body(fontSize),
                    color: .vaktAccent.opacity(0.72),
                    digitWidth: digitWidth,
                    digitHeight: digitHeight,
                    showsPulse: false
                )

                Text(L10n.text(.timeRemainingHourUnit))
                    .font(VaktFont.body(fontSize))
                    .foregroundStyle(Color.vaktMuted)

                VaktRollingNumberText(
                    value: totalMinutes % 60,
                    direction: -1,
                    font: VaktFont.body(fontSize),
                    color: .vaktAccent.opacity(0.72),
                    digitWidth: digitWidth,
                    digitHeight: digitHeight,
                    showsPulse: false
                )

                Text(L10n.text(.timeRemainingMinuteRemainingUnit))
                    .font(VaktFont.body(fontSize))
                    .foregroundStyle(Color.vaktMuted)
            } else {
                VaktRollingNumberText(
                    value: max(1, totalMinutes),
                    direction: -1,
                    font: VaktFont.body(fontSize),
                    color: .vaktAccent.opacity(0.72),
                    digitWidth: digitWidth,
                    digitHeight: digitHeight,
                    showsPulse: false
                )

                Text(totalMinutes == 1 ? L10n.text(.minuteRemainingSuffix) : L10n.text(.minutesRemainingSuffix))
                    .font(VaktFont.body(fontSize))
                    .foregroundStyle(Color.vaktMuted)
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format(.timeRemainingAccessibility, countdownText))
        .animation(.easeOut(duration: 0.22), value: totalSeconds)
    }

    private var countdownText: String {
        L10n.timeRemaining(minutes: totalMinutes)
    }
}

struct VaktRollingNumberText: View {
    let value: Int
    var direction: Int = 1
    var font: Font = VaktFont.body(13)
    var color: Color = .vaktPrimary
    var digitWidth: CGFloat = 9
    var digitHeight: CGFloat = 18
    var showsPulse = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    private var digits: [String] {
        String(max(0, value)).map(String.init)
    }

    var body: some View {
        HStack(spacing: 0.5) {
            ForEach(Array(digits.enumerated()), id: \.offset) { _, digit in
                VaktRollingDigitText(
                    digit: digit,
                    direction: direction,
                    reduceMotion: reduceMotion,
                    width: digitWidth,
                    height: digitHeight
                )
            }
        }
        .font(font)
        .foregroundStyle(color)
        .monospacedDigit()
        .tracking(0.5)
        .scaleEffect(isPulsing ? 1.08 : 1)
        .onChange(of: value) { _, _ in
            guard showsPulse, !reduceMotion else { return }
            withAnimation(.snappy(duration: 0.18, extraBounce: 0.05)) {
                isPulsing = true
            }

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 220_000_000)
                withAnimation(.easeOut(duration: 0.32)) {
                    isPulsing = false
                }
            }
        }
    }
}

private struct VaktRollingDigitText: View {
    let digit: String
    let direction: Int
    let reduceMotion: Bool
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            Text(digit)
                .id(digit)
                .transition(digitTransition)
        }
        .frame(width: width, height: height)
        .clipped()
        .animation(reduceMotion ? .none : .spring(response: 0.34, dampingFraction: 0.82), value: digit)
    }

    private var digitTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }

        let insertionEdge: Edge = direction >= 0 ? .bottom : .top
        let removalEdge: Edge = direction >= 0 ? .top : .bottom
        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }
}

struct HorizonEmpty: View {
    let prayer: Prayer

    var body: some View {
        VStack(spacing: VaktSpace.md) {
            ZStack {
                Rectangle()
                    .fill(Color.vaktBorder)
                    .frame(width: 60, height: 0.5)

                Circle()
                    .fill(Color.vaktBorder)
                    .frame(width: 8, height: 8)
            }

            VStack(spacing: VaktSpace.xs) {
                Text(L10n.text(.noOneHereYet))
                    .font(VaktFont.body(16))
                    .foregroundStyle(Color.vaktMuted)

                Text(L10n.format(.horizonEmptyBody, prayer.displayName))
                    .font(VaktFont.caption(13))
                    .foregroundStyle(Color.vaktShadow)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .padding(VaktSpace.xxxl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.format(.horizonEmptyAccessibility, prayer.displayName))
    }
}

struct HorizonLoading: View {
    @State private var opacity: Double = 0.3

    var body: some View {
        Rectangle()
            .fill(Color.vaktBorder)
            .frame(height: 0.5)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    opacity = 0.8
                }
            }
            .accessibilityLabel(L10n.text(.loading))
    }
}

struct EyebrowLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(VaktFont.eyebrow())
            .foregroundStyle(Color.vaktMuted)
            .tracking(0.8)
    }
}

struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: VaktSpace.sm) {
            Circle()
                .fill(Color.vaktMuted)
                .frame(width: 6, height: 6)

            Text(L10n.text(.offlineSafPresence))
                .font(VaktFont.caption(12))
                .foregroundStyle(Color.vaktMuted)
        }
        .padding(.horizontal, VaktSpace.md)
        .padding(.vertical, VaktSpace.sm)
        .background(Color.vaktSurface)
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VaktRadius.sm, style: .continuous)
                .strokeBorder(Color.vaktBorder, lineWidth: 0.5)
        )
        .accessibilityLabel(L10n.text(.offlineSafPresenceAccessibility))
    }
}

struct VaktDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.vaktBorder)
            .frame(height: 0.5)
    }
}
