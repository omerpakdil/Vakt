import AuthenticationServices
import SwiftUI

struct SocialSignInView: View {
    @ObservedObject var store: SocialAccountStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scenePhase: SignInScenePhase = .waiting

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                SignInArchitectureBackground()

                VStack(spacing: 0) {
                    header
                        .padding(.top, max(18, proxy.safeAreaInsets.top + 14))

                    SignInIdentityScene(phase: scenePhase, reduceMotion: reduceMotion)
                        .frame(height: min(292, max(252, proxy.size.height * 0.34)))
                        .padding(.top, 4)

                    accountPromises

                    Spacer(minLength: 20)

                    SignInActionArea(store: store)
                        .padding(.bottom, max(18, proxy.safeAreaInsets.bottom + 8))
                }
                .padding(.horizontal, VaktSpace.lg)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .task { await runIdentityStory() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("auth.sign_in.eyebrow")
                .uppercased(with: VaktLocalization.appLocale))
                .font(VaktFont.eyebrow(9))
                .foregroundStyle(Color.vaktSecondary)

            Text(L10n.string("auth.sign_in.title"))
                .font(VaktFont.timeDisplay(35))
                .foregroundStyle(Color.vaktPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(L10n.string("auth.sign_in.body"))
                .font(VaktFont.body(13))
                .foregroundStyle(Color.vaktMuted)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accountPromises: some View {
        VStack(spacing: 0) {
            SignInPromiseRow(
                icon: "person.crop.circle",
                title: L10n.string("auth.sign_in.promise.records")
            )

            Rectangle()
                .fill(Color.vaktBorder.opacity(0.58))
                .frame(height: 0.5)
                .padding(.leading, 39)

            SignInPromiseRow(
                icon: "lock",
                title: L10n.string("auth.sign_in.promise.makeup_private")
            )
        }
        .padding(.horizontal, 2)
    }

    private func runIdentityStory() async {
        while !Task.isCancelled {
            for phase in SignInScenePhase.allCases {
                guard !Task.isCancelled else { return }
                withAnimation(reduceMotion ? .none : .spring(response: 0.58, dampingFraction: 0.9)) {
                    scenePhase = phase
                }
                let duration = phase == .connected ? 2_500 : 1_450
                try? await Task.sleep(for: .milliseconds(duration))
            }
        }
    }
}

private struct SignInArchitectureBackground: View {
    var body: some View {
        GeometryReader { proxy in
            Image("SignInArchitecture")
                .resizable()
                .scaledToFill()
                .saturation(0.72)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.vaktDeep.opacity(0.64),
                            Color.vaktDeep.opacity(0.42),
                            Color.vaktDeep.opacity(0.70),
                            Color.vaktDeep.opacity(0.97)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .overlay(Color.vaktBg.opacity(0.24))
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

private enum SignInScenePhase: Int, CaseIterable {
    case waiting
    case circleAppears
    case youAppear
    case connected
}

private struct SignInIdentityScene: View {
    let phase: SignInScenePhase
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                IdentityConnections(phase: phase)

                identityPlace(
                    name: "Ayşe",
                    isUser: false,
                    visible: phase.rawValue >= SignInScenePhase.circleAppears.rawValue
                )
                .position(x: proxy.size.width * 0.24, y: proxy.size.height * 0.50)

                identityPlace(
                    name: "Yusuf",
                    isUser: false,
                    visible: phase.rawValue >= SignInScenePhase.circleAppears.rawValue
                )
                .position(x: proxy.size.width * 0.76, y: proxy.size.height * 0.50)

                identityPlace(
                    name: L10n.string("auth.sign_in.scene.place.you"),
                    isUser: true,
                    visible: phase.rawValue >= SignInScenePhase.youAppear.rawValue
                )
                .position(x: proxy.size.width * 0.50, y: proxy.size.height * 0.53)

                VStack(spacing: 5) {
                    Text(sceneTitle)
                        .font(VaktFont.body(12))
                        .foregroundStyle(Color.vaktPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)

                    Text(sceneDetail)
                        .font(VaktFont.caption(9))
                        .foregroundStyle(Color.vaktMuted)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .multilineTextAlignment(.center)
                }
                .id(phase)
                .transition(.opacity)
                .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.88)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.55), value: phase)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.formatString("auth.sign_in.scene.accessibility", sceneTitle))
    }

    private func identityPlace(
        name: String,
        isUser: Bool,
        visible: Bool
    ) -> some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(Color.vaktPrimary.opacity(isUser ? 0.16 : 0.07))
                    .frame(width: isUser ? 12 : 7, height: isUser ? 122 : 82)
                    .blur(radius: isUser ? 5 : 3)

                Capsule()
                    .fill(isUser ? Color.vaktPrimary.opacity(0.92) : Color.vaktSecondary.opacity(0.55))
                    .frame(width: isUser ? 2 : 1, height: isUser ? 116 : 76)

                Capsule()
                    .fill(isUser ? Color.vaktPrimary : Color.vaktSecondary)
                    .frame(width: isUser ? 34 : 20, height: isUser ? 2 : 1)
                    .shadow(color: isUser ? Color.vaktPrimary.opacity(0.4) : .clear, radius: 8)
            }

            Text(name)
                .font(VaktFont.caption(10))
                .foregroundStyle(isUser ? Color.vaktPrimary : Color.vaktMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible ? 1 : 0.88)
    }

    private var sceneTitle: String {
        switch phase {
        case .waiting:
            L10n.string("auth.sign_in.scene.waiting.title")
        case .circleAppears:
            L10n.string("auth.sign_in.scene.circle.title")
        case .youAppear:
            L10n.string("auth.sign_in.scene.you.title")
        case .connected:
            L10n.string("auth.sign_in.scene.connected.title")
        }
    }

    private var sceneDetail: String {
        switch phase {
        case .waiting: ""
        case .circleAppears:
            L10n.string("auth.sign_in.scene.circle.detail")
        case .youAppear:
            L10n.string("auth.sign_in.scene.you.detail")
        case .connected:
            L10n.string("auth.sign_in.scene.connected.detail")
        }
    }
}

private struct IdentityConnections: View {
    let phase: SignInScenePhase

    var body: some View {
        Canvas { context, size in
            guard phase == .connected else { return }

            let left = CGPoint(x: size.width * 0.24, y: size.height * 0.42)
            let right = CGPoint(x: size.width * 0.76, y: size.height * 0.42)
            let user = CGPoint(x: size.width * 0.50, y: size.height * 0.50)

            var path = Path()
            path.move(to: left)
            path.addLine(to: user)
            path.addLine(to: right)

            context.stroke(
                path,
                with: .color(.vaktPrimary.opacity(0.22)),
                style: StrokeStyle(lineWidth: 0.7, dash: [4, 7])
            )
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}

private struct SignInPromiseRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.vaktSecondary)
                .frame(width: 26)

            Text(title)
                .font(VaktFont.body(11))
                .foregroundStyle(Color.vaktMuted)
                .lineLimit(2)
                .minimumScaleFactor(0.84)

            Spacer()
        }
        .frame(height: 38)
        .accessibilityElement(children: .combine)
    }
}

private struct SignInActionArea: View {
    @ObservedObject var store: SocialAccountStore

    @Environment(\.openURL) private var openURL

    private var isChecking: Bool {
        if case .checking = store.state { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 11) {
            SignInWithAppleButton(.continue) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                switch result {
                case .success(let authorization):
                    Task { await store.signIn(authorization: authorization) }
                case .failure(let error):
                    if (error as? ASAuthorizationError)?.code != .canceled {
                        store.showSignInError(L10n.string("auth.sign_in.error.apple_failed"))
                    }
                }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 55)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .disabled(isChecking)
            .opacity(isChecking ? 0.72 : 1)

            Text(statusText)
                .font(VaktFont.caption(10))
                .foregroundStyle(statusColor)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(minHeight: 28)

            HStack(spacing: 17) {
                Button(L10n.string("common.terms")) { openURL(VaktExternalLinks.terms) }
                Button(L10n.string("common.privacy")) { openURL(VaktExternalLinks.privacy) }
            }
            .font(VaktFont.caption(10))
            .foregroundStyle(Color.vaktMuted)
            .buttonStyle(.plain)
        }
    }

    private var statusText: String {
        switch store.state {
        case .checking:
            L10n.string("auth.sign_in.status.checking")
        case .failed(let message):
            message
        case .signedOut, .signedIn:
            L10n.string("auth.sign_in.status.idle")
        }
    }

    private var statusColor: Color {
        if case .failed = store.state { return .vaktAccent }
        return .vaktMuted
    }
}
