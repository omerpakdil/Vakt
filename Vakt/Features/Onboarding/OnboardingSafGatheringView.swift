import SwiftUI

struct OnboardingSafGatheringView: View {
    let stepIndex: Int
    let stepCount: Int
    let reduceMotion: Bool
    let onContinue: () -> Void

    @State private var occupiedSlots = Self.initialOccupiedSlots

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.vaktBg.ignoresSafeArea()

                VStack(spacing: 0) {
                    GatheringPageMark(stepIndex: stepIndex, stepCount: stepCount)
                        .padding(.top, VaktSpace.xl)
                        .padding(.horizontal, VaktSpace.lg)

                    MiniSafScene(
                        occupiedSlots: occupiedSlots,
                        reduceMotion: reduceMotion
                    )
                        .frame(height: min(350, proxy.size.height * 0.43))
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 15) {
                        EyebrowLabel(text: L10n.string("onboarding.gathering.eyebrow"))

                        Text(L10n.string("onboarding.gathering.title"))
                            .font(VaktFont.title(30))
                            .foregroundStyle(Color.vaktPrimary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(L10n.string("onboarding.gathering.body"))
                            .font(VaktFont.body(14))
                            .foregroundStyle(Color.vaktMuted)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)

                        GatheringStatusLine()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, VaktSpace.lg)
                    .padding(.top, 20)

                    Spacer(minLength: 18)

                    GatheringContinueButton(onContinue: onContinue)
                        .padding(.horizontal, VaktSpace.lg)
                        .padding(.bottom, VaktSpace.lg)
                }
            }
        }
        .task {
            guard !reduceMotion else { return }
            await animateGathering()
        }
    }

    private func animateGathering() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Double.random(in: 1.2...2.4)))
            guard !Task.isCancelled else { return }

            let openSlots = Set(0..<35).subtracting(occupiedSlots)
            let shouldJoin = occupiedSlots.count < 19 || (occupiedSlots.count < 22 && Bool.random())

            withAnimation(.spring(response: 0.52, dampingFraction: 0.86)) {
                if shouldJoin, let next = openSlots.randomElement() {
                    occupiedSlots.insert(next)
                } else if occupiedSlots.count > 16, let leaving = occupiedSlots.randomElement() {
                    occupiedSlots.remove(leaving)
                }
            }
        }
    }

    private static let initialOccupiedSlots: Set<Int> = [
        2, 3, 4,
        8, 10, 11, 12,
        15, 16, 18, 19,
        23, 24, 25, 26,
        30, 31, 32
    ]
}

private struct GatheringPageMark: View {
    let stepIndex: Int
    let stepCount: Int

    var body: some View {
        HStack(spacing: VaktSpace.sm) {
            Text(verbatim: "0\(stepIndex + 1)")
                .font(VaktFont.caption(11))
                .foregroundStyle(Color.vaktPrimary)
                .monospacedDigit()

            HStack(spacing: 4) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Capsule()
                        .fill(index <= stepIndex ? Color.vaktPrimary : Color.vaktBorderStrong)
                        .frame(height: 3)
                        .opacity(index <= stepIndex ? 0.92 : 0.52)
                }
            }

            Text(verbatim: "0\(stepCount)")
                .font(VaktFont.caption(11))
                .foregroundStyle(Color.vaktMuted)
                .monospacedDigit()
        }
        .accessibilityLabel(L10n.formatString("onboarding.step_accessibility", stepIndex + 1, stepCount))
    }
}

private struct MiniSafScene: View {
    let occupiedSlots: Set<Int>
    let reduceMotion: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        VStack(spacing: 14) {
            sceneHeader
                .padding(.horizontal, VaktSpace.lg)

            qiblaLine
                .padding(.horizontal, VaktSpace.lg)

            ZStack {
                MiniSafRowGuides()
                    .padding(.horizontal, VaktSpace.lg + 8)

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(0..<35, id: \.self) { index in
                        MiniSafPlace(
                            isOccupied: occupiedSlots.contains(index),
                            reduceMotion: reduceMotion
                        )
                    }
                }
                .padding(.horizontal, VaktSpace.lg)
            }
        }
        .padding(.top, 22)
        .padding(.bottom, 20)
        .background(Color.vaktDeep.opacity(0.72))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.vaktBorder.opacity(0.48))
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.formatString("onboarding.gathering.scene_accessibility", Prayer.asr.displayName))
    }

    private var sceneHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(L10n.formatString("onboarding.gathering.scene_title", Prayer.asr.displayName))
                .font(VaktFont.title(20))
                .foregroundStyle(Color.vaktPrimary)

            Text(L10n.string("onboarding.gathering.scene_status"))
                .font(VaktFont.body(12))
                .foregroundStyle(Color.vaktMuted)

            Spacer()

            Text(verbatim: "\(occupiedSlots.count)")
                .font(VaktFont.timeDisplay(20))
                .foregroundStyle(Color.vaktSecondary)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }

    private var qiblaLine: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.vaktAccent.opacity(0.18))
                .frame(height: 0.5)

            Text(L10n.string("placement.qibla"))
                .font(VaktFont.eyebrow(8))
                .foregroundStyle(Color.vaktAccent.opacity(0.46))
                .tracking(1.5)

            Rectangle()
                .fill(Color.vaktAccent.opacity(0.18))
                .frame(height: 0.5)
        }
    }
}

private struct MiniSafPlace: View {
    let isOccupied: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isOccupied ? Color.vaktGlow.opacity(0.065) : Color.vaktSurface.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isOccupied ? Color.vaktPrimary.opacity(0.22) : Color.vaktBorder.opacity(0.20),
                            lineWidth: 0.45
                        )
                )

            if isOccupied {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.vaktPrimary.opacity(0.74))
                        .frame(width: 19, height: 25)
                        .shadow(
                            color: Color.vaktPrimary.opacity(reduceMotion ? 0.10 : 0.18),
                            radius: 5
                        )

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.vaktGlow.opacity(0.46))
                        .frame(width: 12, height: 17)
                }
                .transition(.scale(scale: 0.64).combined(with: .opacity))
            } else {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.vaktMuted.opacity(0.16), lineWidth: 0.45)
                    .frame(width: 10, height: 17)
                    .transition(.opacity)
            }
        }
        .frame(height: 34)
        .animation(reduceMotion ? .none : .spring(response: 0.52, dampingFraction: 0.86), value: isOccupied)
    }
}

private struct MiniSafRowGuides: View {
    var body: some View {
        VStack(spacing: 40) {
            ForEach(0..<5, id: \.self) { row in
                Rectangle()
                    .fill(Color.vaktAccent.opacity(row == 0 ? 0.075 : 0.04))
                    .frame(height: 0.5)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct GatheringStatusLine: View {
    var body: some View {
        HStack(spacing: 10) {
            status(L10n.string("onboarding.gathering.status.getting_ready"))
            divider
            status(L10n.string("onboarding.gathering.status.wudu"))
            divider
            status(L10n.string("onboarding.gathering.status.ready"))
        }
        .accessibilityLabel(L10n.string("onboarding.gathering.status_accessibility"))
    }

    private func status(_ title: String) -> some View {
        Text(title)
            .font(VaktFont.caption(11))
            .foregroundStyle(Color.vaktSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
    }

    private var divider: some View {
        Circle()
            .fill(Color.vaktShadow)
            .frame(width: 3, height: 3)
    }
}

private struct GatheringContinueButton: View {
    let onContinue: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onContinue()
        } label: {
            HStack(spacing: VaktSpace.sm) {
                Text(L10n.string("action.continue"))
                    .font(VaktFont.button(15))
                    .foregroundStyle(Color.vaktBg)

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.vaktBg)
            }
            .padding(.horizontal, VaktSpace.md)
            .frame(height: 54)
            .background(Color.vaktPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(VaktPressStyle())
        .accessibilityLabel(L10n.string("action.continue"))
    }
}
