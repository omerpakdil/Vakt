import SwiftUI

struct ProfileCompletionView: View {
    private enum Availability: Equatable {
        case idle
        case invalid
        case checking
        case available
        case taken
        case unavailable
    }

    @ObservedObject var store: SocialAccountStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: Field?

    @State private var displayName: String
    @State private var username: String
    @State private var suggestions: [String] = []
    @State private var availability: Availability = .idle
    @State private var hasEditedUsername = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var availabilityTask: Task<Void, Never>?
    @State private var suggestionTask: Task<Void, Never>?

    private enum Field { case name, username }

    init(store: SocialAccountStore) {
        self.store = store
        let profile = store.profile
        _displayName = State(initialValue: profile?.displayName ?? "")
        _username = State(initialValue: Self.isGeneratedUsername(profile?.username) ? "" : profile?.username ?? "")
    }

    var body: some View {
        ZStack {
            Color.vaktDeep.ignoresSafeArea()
            ProfileCompletionBackdrop()

            GeometryReader { proxy in
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        header
                            .padding(.top, 14)

                        identityPreview
                            .padding(.top, 24)

                        fields
                            .padding(.top, 24)

                        Spacer(minLength: 18)

                        completionAction
                    }
                    .padding(.horizontal, VaktSpace.lg)
                    .padding(.bottom, 16)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .task { await prepareProfile() }
        .onChange(of: displayName) { _, _ in scheduleSuggestionRefresh() }
        .onChange(of: username) { _, newValue in
            guard hasEditedUsername else { return }
            scheduleAvailabilityCheck(for: newValue)
        }
        .onDisappear {
            availabilityTask?.cancel()
            suggestionTask?.cancel()
        }
    }

    private var header: some View {
        VStack(spacing: 9) {
            Text(L10n.string("profile.completion.eyebrow"))
                .font(VaktFont.caption(10))
                .foregroundStyle(Color.vaktGlow)

            Text(L10n.string("profile.completion.title"))
                .font(VaktFont.title(29))
                .foregroundStyle(Color.vaktPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            Text(L10n.string("profile.completion.subtitle"))
                .font(VaktFont.body(12))
                .foregroundStyle(Color.vaktSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 330)
    }

    private var identityPreview: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.vaktPrimary.opacity(0.09))
                Circle()
                    .strokeBorder(Color.vaktGlow.opacity(0.42), lineWidth: 1)

                Text(initials)
                    .font(VaktFont.title(17))
                    .foregroundStyle(Color.vaktPrimary)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName.isEmpty ? L10n.string("account.profile.name") : displayName)
                    .font(VaktFont.title(18))
                    .foregroundStyle(Color.vaktPrimary)
                    .lineLimit(1)

                Text(username.isEmpty ? "@username" : "@\(UsernamePolicy.normalizedInput(username))")
                    .font(VaktFont.body(11))
                    .foregroundStyle(username.isEmpty ? Color.vaktMuted : Color.vaktGlow)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(Color.vaktGlow.opacity(0.82))
        }
        .padding(.horizontal, 16)
        .frame(height: 78)
        .background(Color.vaktSurface.opacity(0.54))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.vaktBorderStrong.opacity(0.72), lineWidth: 0.7)
        }
    }

    private var fields: some View {
        VStack(spacing: 14) {
            completionField(
                title: L10n.string("account.profile.name"),
                hint: L10n.string("profile.completion.name_hint"),
                text: $displayName,
                field: .name,
                prefix: nil
            )

            VStack(alignment: .leading, spacing: 9) {
                completionField(
                    title: L10n.string("account.profile.username"),
                    hint: availabilityMessage,
                    text: usernameBinding,
                    field: .username,
                    prefix: "@"
                )

                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(L10n.string("profile.completion.suggestions"))
                            .font(VaktFont.caption(9))
                            .foregroundStyle(Color.vaktMuted)

                        HStack(spacing: 7) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button {
                                    selectSuggestion(suggestion)
                                } label: {
                                    Text("@\(suggestion)")
                                        .font(VaktFont.caption(10))
                                        .foregroundStyle(username == suggestion ? Color.vaktDeep : Color.vaktPrimary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.72)
                                        .padding(.horizontal, 10)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 32)
                                        .background(username == suggestion ? Color.vaktPrimary : Color.vaktSurface.opacity(0.62))
                                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                }
                                .buttonStyle(VaktPressStyle())
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.22), value: suggestions)
    }

    private func completionField(
        title: String,
        hint: String,
        text: Binding<String>,
        field: Field,
        prefix: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(VaktFont.caption(9))
                .foregroundStyle(Color.vaktMuted)

            HStack(spacing: 7) {
                if let prefix {
                    Text(prefix)
                        .font(VaktFont.body(15))
                        .foregroundStyle(Color.vaktGlow)
                }

                TextField(title, text: text)
                    .focused($focusedField, equals: field)
                    .textInputAutocapitalization(field == .name ? .words : .never)
                    .autocorrectionDisabled(field == .username)
                    .textContentType(field == .name ? .name : .username)
                    .font(VaktFont.body(15))
                    .foregroundStyle(Color.vaktPrimary)
                    .submitLabel(field == .name ? .next : .done)
                    .onSubmit {
                        focusedField = field == .name ? .username : nil
                    }

                if field == .username {
                    availabilityIndicator
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Color.vaktSurface.opacity(0.68))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(fieldBorderColor(field), lineWidth: 0.8)
            }

            Text(hint)
                .font(VaktFont.caption(9))
                .foregroundStyle(hintColor(field))
                .lineLimit(2)
                .frame(minHeight: 12)
        }
    }

    @ViewBuilder
    private var availabilityIndicator: some View {
        switch availability {
        case .checking:
            ProgressView()
                .controlSize(.small)
                .tint(Color.vaktGlow)
        case .available:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.vaktPrimary)
        case .invalid, .taken, .unavailable:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(Color.vaktAccent)
        case .idle:
            EmptyView()
        }
    }

    private var completionAction: some View {
        VStack(spacing: 9) {
            if let errorMessage {
                Text(errorMessage)
                    .font(VaktFont.caption(10))
                    .foregroundStyle(Color.vaktAccent)
                    .multilineTextAlignment(.center)
            }

            Button(action: completeProfile) {
                HStack(spacing: 9) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.vaktDeep)
                    } else {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .semibold))
                    }

                    Text(L10n.string(isSaving ? "profile.completion.saving" : "profile.completion.action"))
                        .font(VaktFont.button(15))
                }
                .foregroundStyle(Color.vaktDeep)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.vaktPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(VaktPressStyle())
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.48)

            Label(L10n.string("profile.completion.privacy"), systemImage: "lock")
                .font(VaktFont.caption(9))
                .foregroundStyle(Color.vaktMuted)
        }
    }

    private var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let value = parts.compactMap(\.first).map(String.init).joined()
        return value.isEmpty ? "V" : value.uppercased()
    }

    private var availabilityMessage: String {
        switch availability {
        case .idle, .invalid: L10n.string("profile.completion.username_hint")
        case .checking: L10n.string("profile.completion.username_checking")
        case .available: L10n.string("profile.completion.username_available")
        case .taken: L10n.string("profile.completion.username_taken")
        case .unavailable: L10n.string("profile.completion.username_unavailable")
        }
    }

    private var canSubmit: Bool {
        !isSaving &&
            !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            UsernamePolicy.isValid(username) &&
            availability == .available
    }

    private func fieldBorderColor(_ field: Field) -> Color {
        guard field == .username else {
            return focusedField == field ? Color.vaktGlow.opacity(0.62) : Color.vaktBorderStrong
        }
        return switch availability {
        case .available: Color.vaktPrimary.opacity(0.72)
        case .invalid, .taken, .unavailable: Color.vaktAccent.opacity(0.72)
        case .idle, .checking: focusedField == field ? Color.vaktGlow.opacity(0.62) : Color.vaktBorderStrong
        }
    }

    private func hintColor(_ field: Field) -> Color {
        guard field == .username else { return .vaktMuted }
        return switch availability {
        case .available: .vaktPrimary
        case .invalid, .taken, .unavailable: .vaktAccent
        case .idle, .checking: .vaktMuted
        }
    }

    private func scheduleAvailabilityCheck(for value: String) {
        availabilityTask?.cancel()
        let candidate = UsernamePolicy.normalizedInput(value)
        guard UsernamePolicy.isValid(candidate) else {
            availability = candidate.isEmpty ? .idle : .invalid
            return
        }

        availability = .checking
        availabilityTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            do {
                let available = try await store.availableUsernames([candidate])
                guard candidate == UsernamePolicy.normalizedInput(username) else { return }
                availability = available.contains(candidate) ? .available : .taken
            } catch {
                guard !Task.isCancelled else { return }
                availability = .unavailable
            }
        }
    }

    private var usernameBinding: Binding<String> {
        Binding(
            get: { username },
            set: { newValue in
                hasEditedUsername = true
                username = UsernamePolicy.normalizedInput(newValue)
            }
        )
    }

    @MainActor
    private func prepareProfile() async {
        if UsernamePolicy.isValid(username) {
            do {
                let available = try await store.availableUsernames([username])
                availability = available.contains(username) ? .available : .taken
            } catch {
                availability = .unavailable
            }
        }
        await refreshSuggestions(autoselect: username.isEmpty)
    }

    private func scheduleSuggestionRefresh() {
        suggestionTask?.cancel()
        suggestionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            await refreshSuggestions(autoselect: !hasEditedUsername)
        }
    }

    @MainActor
    private func refreshSuggestions(autoselect: Bool) async {
        let candidates = UsernamePolicy.candidates(
            displayName: displayName,
            fallbackSeed: store.profile?.username ?? "vakt"
        )
        do {
            let available = try await store.availableUsernames(candidates)
            guard !Task.isCancelled else { return }
            suggestions = available
            if autoselect, let first = available.first {
                username = first
                availability = .available
            }
        } catch {
            suggestions = []
        }
    }

    private func selectSuggestion(_ suggestion: String) {
        hasEditedUsername = false
        availabilityTask?.cancel()
        username = suggestion
        availability = .available
        focusedField = nil
    }

    private func completeProfile() {
        guard canSubmit else { return }
        focusedField = nil
        isSaving = true
        errorMessage = nil

        Task { @MainActor in
            do {
                try await store.completeProfile(displayName: displayName, username: username)
            } catch BackendError.conflict {
                availability = .taken
                errorMessage = L10n.string("profile.completion.username_taken")
                await refreshSuggestions(autoselect: false)
            } catch {
                errorMessage = L10n.string("profile.completion.error")
            }
            isSaving = false
        }
    }

    private static func isGeneratedUsername(_ username: String?) -> Bool {
        guard let username else { return true }
        return username.range(of: "^vakt_[a-z0-9]{6,10}$", options: .regularExpression) != nil
    }
}

private struct ProfileCompletionBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let centerX = size.width / 2
                var path = Path()
                path.move(to: CGPoint(x: centerX, y: 0))
                path.addLine(to: CGPoint(x: centerX, y: size.height))
                context.stroke(path, with: .color(.vaktPrimary.opacity(0.035)), lineWidth: 1)

                let upper = CGRect(x: centerX - 112, y: -76, width: 224, height: 224)
                context.stroke(
                    Path(ellipseIn: upper),
                    with: .color(.vaktGlow.opacity(0.055)),
                    lineWidth: 1
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
