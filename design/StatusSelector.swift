// StatusSelector.swift
// Vakt — Durum Seçici Bileşeni
//
// Kullanıcı hazırlık durumunu günceller.
// Chip'ler, minimal, dokunma dostu.

import SwiftUI

struct StatusSelector: View {
    @Binding var selectedStatus: PrepStatus

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // 2x2 grid için sabit sıra (Namaz kılıyorum ayrı)
    private let mainStatuses: [PrepStatus] = [.gettingUp, .wudu, .findingPlace, .ready]

    var body: some View {
        VStack(alignment: .leading, spacing: VaktSpace.sm) {
            // Üst etiket
            Text("DURUMUN")
                .font(VaktFont.eyebrow())
                .foregroundStyle(Color.vaktMuted)
                .tracking(0.8)
                .padding(.horizontal, VaktSpace.md)

            // Chip ızgarası
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

// MARK: - StatusChip

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

                Text(status.rawValue)
                    .font(VaktFont.body(13))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, VaktSpace.sm + 4)
            .padding(.vertical, VaktSpace.sm + 4)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: VaktRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: VaktRadius.sm)
                    .strokeBorder(borderColor, lineWidth: 0.5)
            )
            .scaleEffect(isSelected ? 1.0 : 1.0)
            .animation(reduceMotion ? .none : VaktAnimation.fast, value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Durumu şu şekilde ayarla: \(status.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .contentShape(Rectangle())
        .frame(minWidth: 44, minHeight: 44)
    }

    // MARK: - Computed Styles

    private var categoryLabel: String {
        switch status {
        case .gettingUp:      return "ayakta"
        case .wudu:           return "temizlik"
        case .findingPlace:   return "yer"
        case .ready:          return "hazır"
        case .praying:        return "namaz"
        }
    }

    private var background: Color {
        if isSelected { return .vaktAccent }
        return .vaktSurface
    }

    private var borderColor: Color {
        if isSelected { return .vaktAccent }
        return .vaktBorder
    }

    private var foreground: Color {
        if isSelected { return .vaktBg }
        return .vaktGlow
    }

    private var foregroundSecondary: Color {
        if isSelected { return .vaktBg.opacity(0.7) }
        return .vaktMuted
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.vaktBg.ignoresSafeArea()

        VStack {
            Spacer()
            StatefulPreviewWrapper(PrepStatus.wudu) { binding in
                StatusSelector(selectedStatus: binding)
            }
            Spacer()
        }
    }
}

// Preview yardımcısı
struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> Content

    init(_ initialValue: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initialValue)
        self.content = content
    }

    var body: some View { content($value) }
}
