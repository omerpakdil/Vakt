import SwiftUI
import UserNotifications

struct ProfileView: View {
    @ObservedObject var prayerStore: PrayerScheduleStore
    @ObservedObject var notificationManager: NotificationManager
    @ObservedObject var reflectionStore: PrayerReflectionStore
    @ObservedObject var sessionStore: PrayerSessionStore
    @ObservedObject var onboardingStore: OnboardingStore
    @ObservedObject var profileSettings: ProfileSettingsStore

    @Environment(\.openURL) private var openURL
    @State private var modal: VaktModalState?

    var body: some View {
        ZStack {
            Color.vaktBg.ignoresSafeArea()

            GeometryReader { geometry in
                ScrollView {
                    profileContent(availableHeight: geometry.size.height)
                }
            }
        }
        .onAppear {
            notificationManager.refreshAuthorizationStatus()
        }
        .vaktModal($modal)
    }

    @ViewBuilder
    private func profileContent(availableHeight: CGFloat) -> some View {
        #if DEBUG
        VStack(alignment: .leading, spacing: 11) {
            header
            prayerTimingSection
            notificationSection
            privacySection
            localDataSection
            developerSection
        }
        .padding(.horizontal, VaktSpace.lg)
        .padding(.top, 17)
        .padding(.bottom, 14)
        #else
        VStack(alignment: .leading, spacing: 11) {
            header
            prayerTimingSection
            notificationSection
            privacySection

            Spacer(minLength: 14)

            localDataSection
        }
        .padding(.horizontal, VaktSpace.lg)
        .padding(.top, 17)
        .padding(.bottom, 14)
        .frame(minHeight: availableHeight, alignment: .top)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("My Vakt")
                .font(VaktFont.timeDisplay(30))
                .foregroundStyle(Color.vaktPrimary)

            Text("Prayer times, reminders, and privacy")
                .font(VaktFont.body(12))
                .foregroundStyle(Color.vaktMuted)
        }
    }

    private var prayerTimingSection: some View {
        ProfileSection(title: "Prayer Times") {
            prayerTimesStatusRow

            VaktDivider()

            calculationMethodRow

            VaktDivider()

            asrMethodRow
        }
    }

    private var prayerTimesStatusRow: some View {
        HStack(spacing: 11) {
            ProfileIconBubble(icon: "location", accent: locationAccent)

            VStack(alignment: .leading, spacing: 1) {
                Text("Local prayer times")
                    .font(VaktFont.body(14))
                    .foregroundStyle(Color.vaktSecondary)

                Text(prayerTimesSummary)
                    .font(VaktFont.caption(11))
                    .foregroundStyle(Color.vaktMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if prayerStore.status == .denied {
                Button("Settings", action: openSystemSettings)
                    .font(VaktFont.caption(11))
                    .foregroundStyle(Color.vaktGlow)
                    .buttonStyle(VaktPressStyle())
            }
        }
        .padding(.vertical, 8)
    }

    private var calculationMethodRow: some View {
        HStack(spacing: 11) {
            Image(systemName: "function")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.vaktMuted)
                .frame(width: 28)

            Text("Calculation")
                .font(VaktFont.body(14))
                .foregroundStyle(Color.vaktSecondary)

            Spacer(minLength: VaktSpace.sm)

            Picker("Calculation method", selection: $profileSettings.prayerCalculationMethod) {
                ForEach(PrayerCalculationMethodPreference.allCases) { method in
                    Text(method.title).tag(method)
                }
            }
            .pickerStyle(.menu)
            .tint(.vaktGlow)
        }
        .frame(minHeight: 38)
    }

    private var asrMethodRow: some View {
        HStack(spacing: 11) {
            Image(systemName: "sun.horizon")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.vaktMuted)
                .frame(width: 28)

            Text("Asr method")
                .font(VaktFont.body(14))
                .foregroundStyle(Color.vaktSecondary)

            Spacer(minLength: VaktSpace.sm)

            Picker("Asr method", selection: $profileSettings.asrJuristicMethod) {
                ForEach(AsrJuristicPreference.allCases) { method in
                    Text(method.title).tag(method)
                }
            }
            .pickerStyle(.menu)
            .tint(.vaktGlow)
        }
        .frame(minHeight: 38)
    }

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            EyebrowLabel(text: "Prayer Reminders")

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 11) {
                    ProfileIconBubble(icon: notificationIcon, accent: notificationAccent)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(notificationTitle)
                            .font(VaktFont.body(14))
                            .foregroundStyle(Color.vaktPrimary)

                        Text(notificationSubtitle)
                            .font(VaktFont.caption(11))
                            .foregroundStyle(Color.vaktMuted)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: VaktSpace.sm)
                    notificationControl
                }

                Text("10 min before  ·  prayer time  ·  Fajr wake-up")
                    .font(VaktFont.caption(11))
                    .foregroundStyle(notificationManager.isReminderEnabled ? Color.vaktMuted : Color.vaktShadow)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.leading, 43)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.vaktSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(notificationAccent.opacity(notificationManager.authorizationStatus.allowsPrayerNotifications ? 0.34 : 0.18), lineWidth: 0.6)
            )
        }
    }

    private var privacySection: some View {
        ProfileSection(title: "Privacy") {
            CompactProfileToggleRow(
                icon: "circle.grid.cross",
                title: "Saf privacy",
                isOn: $profileSettings.anonymousSafEnabled
            )

            VaktDivider()

            CompactProfileToggleRow(
                icon: "location.slash",
                title: "Approximate location",
                isOn: $profileSettings.approximateLocationOnly
            )

            VaktDivider()

            CompactProfileToggleRow(
                icon: "speaker.wave.1",
                title: "Soft reminder sound",
                isOn: $profileSettings.quietNotificationSoundEnabled
            )
        }
    }

    private var localDataSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(reflectionStore.entries.isEmpty ? Color.vaktShadow : Color.vaktAccent)

            Text(reflectionDetail)
                .font(VaktFont.caption(11))
                .foregroundStyle(Color.vaktMuted)

            Spacer()

            Text("Kept on this device")
                .font(VaktFont.caption(11))
                .foregroundStyle(Color.vaktShadow)
        }
        .padding(.horizontal, 2)
        .frame(height: 28)
    }

    #if DEBUG
    private var developerSection: some View {
        ProfileSection(title: "Developer") {
            ProfileActionRow(icon: "arrow.counterclockwise", title: "Reset onboarding", detail: "Show splash and onboarding again") {
                presentDeveloperModal(.resetOnboarding)
            }

            VaktDivider()

            ProfileActionRow(icon: "trash", title: "Clear entries", detail: "Remove prayer entries from this device") {
                presentDeveloperModal(.clearReflections)
            }
        }
    }
    #endif

    @ViewBuilder
    private var notificationControl: some View {
        if notificationManager.authorizationStatus == .denied {
            Button {
                openSystemSettings()
            } label: {
                Text("Settings")
                    .font(VaktFont.caption(12))
                    .foregroundStyle(Color.vaktGlow)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.vaktBorderStrong, lineWidth: 0.6)
                    )
            }
            .buttonStyle(VaktPressStyle())
        } else {
            Button {
                notificationManager.setReminderEnabled(!notificationManager.isReminderEnabled)
            } label: {
                VaktTogglePill(isOn: notificationManager.isReminderEnabled)
            }
            .buttonStyle(VaktPressStyle())
            .accessibilityLabel("Prayer reminders")
            .accessibilityValue(notificationManager.isReminderEnabled ? "On" : "Off")
        }
    }

    private var locationAccent: Color {
        switch prayerStore.status {
        case .ready, .usingSavedTimes:
            return .vaktAccent
        case .loading, .locating:
            return .vaktPrimary
        case .denied, .failed:
            return .vaktShadow
        }
    }

    private var prayerTimesSummary: String {
        switch prayerStore.status {
        case .ready:
            return "Ready for your location"
        case .usingSavedTimes:
            return "Using saved prayer times"
        case .loading, .locating:
            return "Refreshing nearby times"
        case .denied:
            return "Location permission is off"
        case .failed:
            return "Using fallback times"
        }
    }

    private var notificationTitle: String {
        switch notificationManager.authorizationStatus {
        case .notDetermined:
            return notificationManager.isReminderEnabled ? "Ready to ask permission" : "Reminders are paused"
        case .denied:
            return "Reminders are off"
        case .authorized, .provisional, .ephemeral:
            return notificationManager.isReminderEnabled ? "Prayer reminders are on" : "Reminders are paused"
        @unknown default:
            return "Prayer reminders"
        }
    }

    private var notificationSubtitle: String {
        switch notificationManager.authorizationStatus {
        case .notDetermined:
            return notificationManager.isReminderEnabled
                ? "Vakt will ask before sending prayer reminders."
                : "Turn them back on when you want help remembering."
        case .denied:
            return "Allow notifications in Settings when you want prayer reminders."
        case .authorized, .provisional, .ephemeral:
            return notificationManager.isReminderEnabled
                ? "Reminders follow the prayer times near you."
                : "No prayer reminders will be sent."
        @unknown default:
            return "Manage prayer reminders before salah."
        }
    }

    private var notificationIcon: String {
        notificationManager.isReminderEnabled && notificationManager.authorizationStatus != .denied ? "bell.badge.fill" : "bell"
    }

    private var notificationAccent: Color {
        notificationManager.isReminderEnabled && notificationManager.authorizationStatus != .denied ? .vaktAccent : .vaktShadow
    }

    private var reflectionDetail: String {
        let count = reflectionStore.entries.count
        guard count > 0 else { return "No prayer entries yet" }
        return "\(count) prayer entries"
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func presentDeveloperModal(_ action: DeveloperAction) {
        modal = VaktModalState(
            tone: .destructive,
            title: developerTitle(for: action),
            message: developerMessage(for: action),
            primaryAction: VaktModalAction(
                title: developerButtonTitle(for: action),
                role: .destructive,
                action: { runDeveloperAction(action) }
            ),
            secondaryAction: VaktModalAction(
                title: "Cancel",
                role: .secondary,
                action: {}
            )
        )
    }

    private func developerTitle(for action: DeveloperAction) -> String {
        switch action {
        case .resetOnboarding:
            return "Reset onboarding?"
        case .clearReflections:
            return "Clear entries?"
        }
    }

    private func developerButtonTitle(for action: DeveloperAction) -> String {
        switch action {
        case .resetOnboarding:
            return "Reset onboarding"
        case .clearReflections:
            return "Clear entries"
        }
    }

    private func developerMessage(for action: DeveloperAction) -> String {
        switch action {
        case .resetOnboarding:
            return "This will bring the splash and onboarding flow back on this device. Your app data stays local."
        case .clearReflections:
            return "This removes prayer entries from this device. Prayer times and settings stay untouched."
        }
    }

    private func runDeveloperAction(_ action: DeveloperAction) {
        switch action {
        case .resetOnboarding:
            onboardingStore.reset()
        case .clearReflections:
            reflectionStore.clear()
            sessionStore.clear()
        }
    }
}

private enum DeveloperAction: Identifiable {
    case resetOnboarding
    case clearReflections

    var id: String {
        switch self {
        case .resetOnboarding:
            return "resetOnboarding"
        case .clearReflections:
            return "clearReflections"
        }
    }
}

private struct ProfileSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            EyebrowLabel(text: title)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 14)
            .background(Color.vaktSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.vaktBorder, lineWidth: 0.5)
            )
        }
    }
}

private struct CompactProfileToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isOn ? Color.vaktAccent : Color.vaktShadow)
                .frame(width: 28)

            Text(title)
                .font(VaktFont.body(14))
                .foregroundStyle(Color.vaktSecondary)
                .lineLimit(1)

            Spacer(minLength: VaktSpace.sm)

            Button {
                isOn.toggle()
            } label: {
                VaktTogglePill(isOn: isOn)
            }
            .buttonStyle(VaktPressStyle())
            .accessibilityLabel(title)
            .accessibilityValue(isOn ? "On" : "Off")
        }
        .frame(minHeight: 42)
    }
}

private struct ProfileStatusRow: View {
    let icon: String
    let title: String
    let detail: String
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            ProfileIconBubble(icon: icon, accent: accent)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(VaktFont.body(14))
                    .foregroundStyle(Color.vaktSecondary)

                Text(detail)
                    .font(VaktFont.caption(11))
                    .foregroundStyle(Color.vaktMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
    }
}

private struct ProfileToggleRow: View {
    let icon: String
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            ProfileIconBubble(icon: icon, accent: isOn ? .vaktAccent : .vaktShadow)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(VaktFont.body(14))
                    .foregroundStyle(Color.vaktSecondary)

                Text(detail)
                    .font(VaktFont.caption(11))
                    .foregroundStyle(Color.vaktMuted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: VaktSpace.sm)

            Button {
                isOn.toggle()
            } label: {
                VaktTogglePill(isOn: isOn)
            }
            .buttonStyle(VaktPressStyle())
            .accessibilityLabel(title)
            .accessibilityValue(isOn ? "On" : "Off")
        }
        .padding(.vertical, 11)
    }
}

private struct ProfileActionRow: View {
    let icon: String
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 12) {
                ProfileIconBubble(icon: icon, accent: .vaktShadow)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(VaktFont.body(14))
                        .foregroundStyle(Color.vaktSecondary)

                    Text(detail)
                        .font(VaktFont.caption(11))
                        .foregroundStyle(Color.vaktMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.vaktShadow)
            }
            .padding(.vertical, 11)
        }
        .buttonStyle(VaktPressStyle())
    }
}

private struct ProfileIconBubble: View {
    let icon: String
    let accent: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.12))
                .frame(width: 32, height: 32)

            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(accent)
        }
    }
}

private struct VaktTogglePill: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? Color.vaktAccent.opacity(0.88) : Color.vaktBorderStrong)
                .frame(width: 44, height: 26)

            Circle()
                .fill(isOn ? Color.vaktBg : Color.vaktMuted)
                .frame(width: 20, height: 20)
                .padding(.horizontal, 3)
        }
    }
}
