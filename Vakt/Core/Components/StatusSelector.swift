import SwiftUI

struct StatusSelector: View {
    @Binding var selectedStatus: PrepStatus

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let mainStatuses: [PrepStatus] = [.gettingUp, .wudu, .findingPlace, .ready]

    var body: some View {
        VStack(alignment: .leading, spacing: VaktSpace.sm) {
            Text("YOUR STATUS")
                .font(VaktFont.eyebrow())
                .foregroundStyle(Color.vaktMuted)
                .tracking(0.8)
                .padding(.horizontal, VaktSpace.md)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: VaktSpace.sm
            ) {
                ForEach(mainStatuses) { status in
                    StatusChip(
                        status: status,
                        isSelected: selectedStatus == status,
                        action: {
                            withAnimation(reduceMotion ? .none : VaktAnimation.spring) {
                                selectedStatus = status
                            }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    )
                }
            }
            .padding(.horizontal, VaktSpace.md)
        }
    }
}

struct StatusChip: View {
    let status: PrepStatus
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(categoryLabel)
                    .font(VaktFont.caption(10))
                    .foregroundStyle(foregroundSecondary)
                    .tracking(0.3)

                Text(status.shortLabel)
                    .font(VaktFont.body(13))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, VaktSpace.sm + 4)
            .padding(.vertical, VaktSpace.sm + 4)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: VaktRadius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VaktRadius.sm, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.5)
            )
            .animation(reduceMotion ? .none : VaktAnimation.fast, value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set status to \(status.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .contentShape(Rectangle())
        .frame(minWidth: 44, minHeight: 44)
    }

    private var categoryLabel: String {
        switch status {
        case .gettingUp: "standing"
        case .wudu: "wudu"
        case .findingPlace: "saf"
        case .ready: "ready"
        case .praying: "salah"
        }
    }

    private var background: Color {
        isSelected ? .vaktAccent : .vaktSurface
    }

    private var borderColor: Color {
        isSelected ? .vaktAccent : .vaktBorder
    }

    private var foreground: Color {
        isSelected ? .vaktBg : .vaktGlow
    }

    private var foregroundSecondary: Color {
        isSelected ? .vaktBg.opacity(0.7) : .vaktMuted
    }
}
