import SwiftUI

struct OnboardingSafPlacementView: View {
    let stepIndex: Int
    let stepCount: Int
    let reduceMotion: Bool
    let onContinue: () -> Void

    @State private var selectedSlot: Int?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.vaktDeep.ignoresSafeArea()

                VStack(spacing: 0) {
                    PlacementPageMark(stepIndex: stepIndex, stepCount: stepCount)
                        .padding(.top, VaktSpace.xl)
                        .padding(.horizontal, VaktSpace.lg)

                    VStack(alignment: .leading, spacing: 15) {
                        EyebrowLabel(text: "Join the Saf")

                        Text(selectedSlot == nil ? "Choose where you will join." : "You are ready to begin.")
                            .font(VaktFont.title(30))
                            .foregroundStyle(Color.vaktPrimary)
                            .lineSpacing(3)
                            .contentTransition(.opacity)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(bodyText)
                            .font(VaktFont.body(14))
                            .foregroundStyle(Color.vaktMuted)
                            .lineSpacing(5)
                            .contentTransition(.opacity)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, VaktSpace.lg)
                    .padding(.top, 30)

                    PracticeSafBoard(
                        occupiedSlots: Self.occupiedSlots,
                        selectedSlot: selectedSlot,
                        reduceMotion: reduceMotion,
                        onSelect: select
                    )
                    .padding(.top, 28)

                    PlacementNextStep(isSelected: selectedSlot != nil)
                        .padding(.horizontal, VaktSpace.lg)
                        .padding(.top, 16)

                    Spacer(minLength: 18)

                    PlacementContinueButton(
                        isEnabled: selectedSlot != nil,
                        onContinue: onContinue
                    )
                    .padding(.horizontal, VaktSpace.lg)
                    .padding(.bottom, VaktSpace.lg)
                }
            }
        }
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.28), value: selectedSlot)
    }

    private var bodyText: String {
        if selectedSlot == nil {
            return "Open places are softly lit. Tap one to join this Saf for the moment."
        }

        return "Nothing has been reserved. When you are ready, hold to begin salah and put the phone away."
    }

    private func select(_ slot: Int) {
        guard !Self.occupiedSlots.contains(slot) else { return }
        UISelectionFeedbackGenerator().selectionChanged()

        withAnimation(reduceMotion ? .none : .spring(response: 0.42, dampingFraction: 0.82)) {
            selectedSlot = slot
        }
    }

    private static let occupiedSlots: Set<Int> = [
        2, 3, 4,
        8, 10, 11, 12,
        15, 16, 18, 19,
        23, 24, 25, 26,
        30, 31, 32
    ]
}

private struct PlacementPageMark: View {
    let stepIndex: Int
    let stepCount: Int

    var body: some View {
        HStack {
            Text("0\(stepIndex + 1) / 0\(stepCount)")
                .font(VaktFont.caption(11))
                .foregroundStyle(Color.vaktMuted)
                .monospacedDigit()
                .tracking(0.5)

            Spacer()
        }
        .accessibilityLabel("Onboarding step \(stepIndex + 1) of \(stepCount)")
    }
}

private struct PracticeSafBoard: View {
    let occupiedSlots: Set<Int>
    let selectedSlot: Int?
    let reduceMotion: Bool
    let onSelect: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    var body: some View {
        VStack(spacing: 14) {
            qiblaLine
                .padding(.horizontal, VaktSpace.lg)

            ZStack {
                PracticeRowGuides()
                    .padding(.horizontal, VaktSpace.lg + 8)

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(0..<35, id: \.self) { index in
                        PracticeSafPlace(
                            index: index,
                            isOccupied: occupiedSlots.contains(index),
                            isSelected: selectedSlot == index,
                            isDimmed: selectedSlot != nil && selectedSlot != index,
                            reduceMotion: reduceMotion,
                            onSelect: onSelect
                        )
                    }
                }
                .padding(.horizontal, VaktSpace.lg)
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 22)
        .background(Color.vaktBg.opacity(0.78))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.vaktBorder.opacity(0.42))
                .frame(height: 0.5)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.vaktBorder.opacity(0.42))
                .frame(height: 0.5)
        }
    }

    private var qiblaLine: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.vaktAccent.opacity(0.20))
                .frame(height: 0.5)

            Image(systemName: "arrow.up")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color.vaktAccent.opacity(0.54))

            Text("QIBLA")
                .font(VaktFont.eyebrow(8))
                .foregroundStyle(Color.vaktAccent.opacity(0.48))
                .tracking(1.5)

            Rectangle()
                .fill(Color.vaktAccent.opacity(0.20))
                .frame(height: 0.5)
        }
        .accessibilityHidden(true)
    }
}

private struct PracticeSafPlace: View {
    let index: Int
    let isOccupied: Bool
    let isSelected: Bool
    let isDimmed: Bool
    let reduceMotion: Bool
    let onSelect: (Int) -> Void

    var body: some View {
        Button {
            onSelect(index)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: isSelected ? 0.9 : 0.45)
                    )

                placeMark
            }
            .frame(height: 40)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(VaktPressStyle())
        .disabled(isOccupied)
        .opacity(isDimmed ? 0.38 : 1)
        .scaleEffect(isSelected && !reduceMotion ? 1.07 : 1)
        .animation(reduceMotion ? .none : .spring(response: 0.38, dampingFraction: 0.82), value: isSelected)
        .animation(reduceMotion ? .none : .easeOut(duration: 0.2), value: isDimmed)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isOccupied ? "This place is already filled." : "Select this open place to join the Saf.")
    }

    private var backgroundColor: Color {
        if isSelected { return Color.vaktPrimary.opacity(0.12) }
        return isOccupied ? Color.vaktSurface.opacity(0.14) : Color.vaktGlow.opacity(0.055)
    }

    private var borderColor: Color {
        if isSelected { return Color.vaktPrimary.opacity(0.62) }
        return isOccupied ? Color.vaktBorder.opacity(0.22) : Color.vaktPrimary.opacity(0.22)
    }

    @ViewBuilder
    private var placeMark: some View {
        if isSelected {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.vaktPrimary.opacity(0.94))
                    .frame(width: 22, height: 29)
                    .shadow(color: Color.vaktPrimary.opacity(reduceMotion ? 0.18 : 0.42), radius: 12)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.vaktGlow.opacity(0.42))
                    .frame(width: 12, height: 18)
            }
        } else if isOccupied {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.vaktAccent.opacity(0.24))
                .frame(width: 9, height: 17)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.vaktPrimary.opacity(0.10))
                    .frame(width: 22, height: 29)
                    .shadow(color: Color.vaktGlow.opacity(reduceMotion ? 0.10 : 0.22), radius: 8)

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.vaktGlow.opacity(0.36))
                    .frame(width: 12, height: 18)
            }
        }
    }

    private var accessibilityLabel: String {
        let row = index / 7 + 1
        let column = index % 7 + 1
        if isSelected { return "Selected place, row \(row), position \(column)" }
        if isOccupied { return "Filled place, row \(row), position \(column)" }
        return "Open place, row \(row), position \(column)"
    }
}

private struct PracticeRowGuides: View {
    var body: some View {
        VStack(spacing: 46) {
            ForEach(0..<5, id: \.self) { row in
                Rectangle()
                    .fill(Color.vaktAccent.opacity(row == 0 ? 0.075 : 0.04))
                    .frame(height: 0.5)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct PlacementNextStep: View {
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isSelected ? "hand.tap.fill" : "hand.tap")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? Color.vaktPrimary : Color.vaktMuted)

            Text(isSelected ? "Next, hold to begin salah" : "Open places are softly lit")
                .font(VaktFont.caption(11))
                .foregroundStyle(isSelected ? Color.vaktSecondary : Color.vaktMuted)
                .contentTransition(.opacity)

            Spacer()
        }
        .accessibilityLabel(isSelected ? "Next, hold to begin salah" : "Open places are softly lit")
    }
}

private struct PlacementContinueButton: View {
    let isEnabled: Bool
    let onContinue: () -> Void

    var body: some View {
        Button {
            guard isEnabled else { return }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onContinue()
        } label: {
            HStack(spacing: VaktSpace.sm) {
                Text(isEnabled ? "Continue" : "Choose an open place")
                    .font(VaktFont.button(15))
                    .foregroundStyle(isEnabled ? Color.vaktBg : Color.vaktMuted)

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isEnabled ? Color.vaktBg : Color.vaktMuted)
            }
            .padding(.horizontal, VaktSpace.md)
            .frame(height: 54)
            .background(isEnabled ? Color.vaktPrimary : Color.vaktSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isEnabled ? Color.clear : Color.vaktBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(VaktPressStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(isEnabled ? "Continue" : "Choose an open place before continuing")
    }
}
