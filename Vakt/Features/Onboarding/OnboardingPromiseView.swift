import SwiftUI

struct OnboardingPromiseView: View {
    let stepIndex: Int
    let stepCount: Int
    let reduceMotion: Bool
    let onContinue: () -> Void

    @State private var phase: PromisePhase = .widget
    @State private var widgetMarked = false
    @State private var demoTask: Task<Void, Never>?

    var body: some View {
        VaktOnboardingShell(
            stepIndex: stepIndex,
            stepCount: stepCount,
            eyebrow: L10n.string("onboarding.promise.eyebrow"),
            title: L10n.string("onboarding.promise.title"),
            bodyText: L10n.string("onboarding.promise.body"),
            actionTitle: L10n.string("onboarding.promise.action.continue"),
            onContinue: onContinue
        ) {
            PromiseEverywhereScene(phase: phase, widgetMarked: widgetMarked, reduceMotion: reduceMotion)
        }
        .onAppear { startDemo() }
        .onDisappear { demoTask?.cancel() }
    }

    private func startDemo() {
        demoTask?.cancel()
        demoTask = Task { @MainActor in
            while !Task.isCancelled {
                setPhase(.widget)
                widgetMarked = false
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 2_400 : 1_250))
                guard !Task.isCancelled else { return }

                withAnimation(reduceMotion ? .none : .spring(response: 0.48, dampingFraction: 0.82)) {
                    widgetMarked = true
                }
                try? await Task.sleep(for: .milliseconds(1_550))
                guard !Task.isCancelled else { return }

                setPhase(.liveActivity)
                try? await Task.sleep(for: .milliseconds(2_650))
                guard !Task.isCancelled else { return }

                setPhase(.mosques)
                try? await Task.sleep(for: .milliseconds(2_900))
            }
        }
    }

    private func setPhase(_ nextPhase: PromisePhase) {
        withAnimation(reduceMotion ? .none : .easeInOut(duration: 0.52)) {
            phase = nextPhase
        }
    }
}

private enum PromisePhase: Int, CaseIterable {
    case widget
    case liveActivity
    case mosques

    var titleKey: String {
        switch self {
        case .widget: "onboarding.promise.surface.title"
        case .liveActivity: "onboarding.promise.live.title"
        case .mosques: "onboarding.promise.mosques.title"
        }
    }

    var detailKey: String {
        switch self {
        case .widget: "onboarding.promise.surface.detail"
        case .liveActivity: "onboarding.promise.live.detail"
        case .mosques: "onboarding.promise.mosques.detail"
        }
    }
}

private struct PromiseEverywhereScene: View {
    let phase: PromisePhase
    let widgetMarked: Bool
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 15) {
            ZStack {
                PromiseAmbientField(phase: phase)

                switch phase {
                case .widget:
                    PromiseWidgetScene(isMarked: widgetMarked)
                        .transition(sceneTransition)
                case .liveActivity:
                    PromiseLiveActivityScene()
                        .transition(sceneTransition)
                case .mosques:
                    PromiseMosqueScene()
                        .transition(sceneTransition)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 252)
            .clipped()

            VStack(spacing: 5) {
                Text(L10n.string(phase.titleKey))
                    .font(VaktFont.body(14))
                    .foregroundStyle(Color.vaktPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .contentTransition(.opacity)

                Text(L10n.string(phase.detailKey))
                    .font(VaktFont.caption(10))
                    .foregroundStyle(Color.vaktMuted)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.82)
                    .contentTransition(.opacity)
            }
            .frame(height: 44, alignment: .top)
            .padding(.horizontal, VaktSpace.xl)

            HStack(spacing: 6) {
                ForEach(PromisePhase.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item == phase ? Color.vaktPrimary : Color.vaktBorderStrong)
                        .frame(width: item == phase ? 24 : 6, height: 3)
                }
            }
            .animation(reduceMotion ? .none : .easeInOut(duration: 0.42), value: phase)
        }
        .padding(.top, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            L10n.string(phase.titleKey) + ". " + L10n.string(phase.detailKey)
        )
    }

    private var sceneTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.97)),
                removal: .opacity.combined(with: .scale(scale: 1.02))
            )
    }
}

private struct PromiseAmbientField: View {
    let phase: PromisePhase

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [accent.opacity(0.12), accent.opacity(0.025), .clear],
                center: .center,
                startRadius: 2,
                endRadius: 190
            )

            Circle()
                .strokeBorder(accent.opacity(0.08), lineWidth: 0.7)
                .frame(width: 238, height: 238)

            Circle()
                .strokeBorder(accent.opacity(0.05), lineWidth: 0.7)
                .frame(width: 190, height: 190)
        }
    }

    private var accent: Color {
        switch phase {
        case .widget: .vaktGlow
        case .liveActivity: .vaktPrimary
        case .mosques: Color(hex: "#78A998")
        }
    }
}

private struct PromiseWidgetScene: View {
    let isMarked: Bool

    var body: some View {
        VStack(spacing: 9) {
            HStack {
                Text(L10n.string("onboarding.promise.surface.widget_label")
                    .uppercased(with: VaktLocalization.appLocale))
                    .font(VaktFont.eyebrow(8))
                    .foregroundStyle(Color.vaktMuted)

                Spacer()

                Text("16:56")
                    .font(VaktFont.caption(9))
                    .foregroundStyle(Color.vaktSecondary)
                    .monospacedDigit()
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Prayer.asr.displayName)
                        .font(VaktFont.title(25))
                        .foregroundStyle(Color.vaktPrimary)

                    Text(isMarked
                        ? L10n.string("home.status.prayed")
                        : L10n.string("notification.action.missed"))
                        .font(VaktFont.caption(10))
                        .foregroundStyle(isMarked ? Color.vaktPrimary : Color.vaktMuted)
                        .contentTransition(.numericText())
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(isMarked ? Color.vaktPrimary : Color.vaktElevated)
                        .frame(width: 42, height: 42)

                    Image(systemName: isMarked ? "checkmark" : "checkmark.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isMarked ? Color.vaktDeep : Color.vaktSecondary)
                        .contentTransition(.symbolEffect(.replace))
                }
            }

            HStack(spacing: 7) {
                PromiseActionPill(
                    title: L10n.string("home.status.prayed"),
                    selected: isMarked
                )
                PromiseActionPill(
                    title: L10n.string("notification.action.missed"),
                    selected: !isMarked
                )
            }
        }
        .padding(17)
        .frame(width: 286, height: 158)
        .background(Color.vaktSurface.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.vaktBorderStrong.opacity(0.68), lineWidth: 0.7)
        }
        .shadow(color: Color.black.opacity(0.22), radius: 22, y: 10)
    }
}

private struct PromiseActionPill: View {
    let title: String
    let selected: Bool

    var body: some View {
        Text(title)
            .font(VaktFont.button(9))
            .foregroundStyle(selected ? Color.vaktDeep : Color.vaktSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(selected ? Color.vaktPrimary : Color.vaktElevated)
            .clipShape(Capsule())
    }
}

private struct PromiseLiveActivityScene: View {
    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                VaktMosqueGlyph()
                    .stroke(Color.vaktSecondary, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                    .frame(width: 18, height: 22)

                Text(Prayer.asr.displayName)
                    .font(VaktFont.body(12))
                    .foregroundStyle(Color.vaktPrimary)

                Spacer()

                Text("08:42")
                    .font(VaktFont.body(12))
                    .foregroundStyle(Color.vaktPrimary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .frame(width: 286, height: 50)
            .background(Color.black.opacity(0.88))
            .clipShape(Capsule())
            .overlay { Capsule().strokeBorder(Color.vaktBorderStrong.opacity(0.38), lineWidth: 0.5) }

            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill(Color.vaktPrimary.opacity(0.08))
                        .frame(width: 48, height: 48)
                    Image(systemName: "iphone.slash")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(Color.vaktSecondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("onboarding.promise.live.quiet_label")
                        .uppercased(with: VaktLocalization.appLocale))
                        .font(VaktFont.eyebrow(8))
                        .foregroundStyle(Color.vaktSecondary)

                    Text(L10n.string("onboarding.promise.live.lock_message"))
                        .font(VaktFont.body(12))
                        .foregroundStyle(Color.vaktPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer()
            }
            .padding(.horizontal, 15)
            .frame(width: 274, height: 76)
            .background(Color.vaktSurface.opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.vaktBorder.opacity(0.6), lineWidth: 0.6)
            }
        }
    }
}

private struct PromiseMosqueScene: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            PromiseMapField()
                .frame(width: 292, height: 194)
                .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))

            HStack(spacing: 11) {
                ZStack {
                    Circle()
                        .fill(Color.vaktSecondary.opacity(0.14))
                        .frame(width: 36, height: 36)
                    VaktMosqueGlyph()
                        .stroke(Color.vaktSecondary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .frame(width: 15, height: 19)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string("onboarding.promise.mosques.sample_name"))
                        .font(VaktFont.body(11))
                        .foregroundStyle(Color.vaktPrimary)
                        .lineLimit(1)

                    Text(L10n.string("onboarding.promise.mosques.sample_distance"))
                        .font(VaktFont.caption(9))
                        .foregroundStyle(Color.vaktMuted)
                }

                Spacer()

                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.vaktSecondary)
            }
            .padding(.horizontal, 12)
            .frame(width: 266, height: 58)
            .background(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .padding(.bottom, 10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 23, style: .continuous)
                .strokeBorder(Color.vaktBorderStrong.opacity(0.6), lineWidth: 0.7)
        }
        .shadow(color: Color.black.opacity(0.2), radius: 20, y: 9)
    }
}

private struct PromiseMapField: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: "#101B22")))

            let roads: [(CGPoint, CGPoint)] = [
                (CGPoint(x: -10, y: 42), CGPoint(x: size.width + 12, y: 126)),
                (CGPoint(x: 20, y: size.height + 8), CGPoint(x: size.width * 0.62, y: -8)),
                (CGPoint(x: size.width * 0.38, y: size.height + 8), CGPoint(x: size.width + 10, y: 44)),
                (CGPoint(x: -5, y: 150), CGPoint(x: size.width + 6, y: 164))
            ]
            for road in roads {
                var path = Path()
                path.move(to: road.0)
                path.addLine(to: road.1)
                context.stroke(path, with: .color(Color.vaktSecondary.opacity(0.13)), lineWidth: 9)
                context.stroke(path, with: .color(Color.vaktSecondary.opacity(0.19)), lineWidth: 1)
            }

            let blocks = [
                CGRect(x: 15, y: 16, width: 60, height: 35),
                CGRect(x: 202, y: 17, width: 70, height: 42),
                CGRect(x: 20, y: 100, width: 56, height: 39),
                CGRect(x: 204, y: 112, width: 60, height: 35)
            ]
            for block in blocks {
                context.fill(Path(roundedRect: block, cornerRadius: 5), with: .color(Color.vaktElevated.opacity(0.62)))
            }
        }
        .overlay {
            ZStack {
                PromiseMapPin().offset(x: -70, y: -48)
                PromiseMapPin().offset(x: 76, y: -27)
                PromiseMapPin(isSelected: true).offset(x: 20, y: 2)

                Circle()
                    .fill(Color.vaktGlow)
                    .frame(width: 8, height: 8)
                    .overlay { Circle().stroke(Color.vaktPrimary.opacity(0.8), lineWidth: 3) }
                    .offset(x: -22, y: 34)
            }
        }
    }
}

private struct PromiseMapPin: View {
    var isSelected = false

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.vaktPrimary : Color.vaktSecondary)
                .frame(width: isSelected ? 31 : 24, height: isSelected ? 31 : 24)
                .shadow(color: Color.black.opacity(0.28), radius: 6, y: 3)

            VaktMosqueGlyph()
                .stroke(Color.vaktDeep, style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))
                .frame(width: 10, height: 13)
        }
    }
}
