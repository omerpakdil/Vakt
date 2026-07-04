// VaktComponents.swift
// Vakt — Ortak UI Bileşenleri
//
// Butonlar, etiketler, boş durum, yükleniyor hali

import SwiftUI

// MARK: - VaktButton

enum VaktButtonStyle {
    case primary    // Beyaz — "Namaza Başla"
    case critical   // Koyu zemin + accent kenarlık — "Safa Katıl"
    case secondary  // Şeffaf — "Durumu Güncelle"
    case ghost      // Sadece metin — "Atla"
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
                .frame(maxWidth: style == .ghost ? nil : .infinity)
                .padding(.vertical, style == .ghost ? VaktSpace.sm : 18)
                .padding(.horizontal, style == .ghost ? VaktSpace.md : 0)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: VaktRadius.md)
                        .strokeBorder(borderColor, lineWidth: 0.5)
                )
                .opacity(isEnabled ? 1.0 : 0.4)
        }
        .buttonStyle(VaktPressStyle())
        .accessibilityLabel(title)
    }

    private var background: Color {
        switch style {
        case .primary:   return .vaktPrimary
        case .critical:  return .vaktSurface
        case .secondary: return .clear
        case .ghost:     return .clear
        }
    }

    private var foreground: Color {
        switch style {
        case .primary:   return .vaktBg
        case .critical:  return .vaktPrimary
        case .secondary: return .vaktGlow
        case .ghost:     return .vaktAccent
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary:   return .clear
        case .critical:  return .vaktAccent
        case .secondary: return .vaktBorder
        case .ghost:     return .clear
        }
    }
}

// Basma animasyonu
struct VaktPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - PrayerRow

struct PrayerRow: View {
    let prayerTime: PrayerTime
    var isNext: Bool = false

    var body: some View {
        HStack {
            Text(prayerTime.prayer.rawValue)
                .font(VaktFont.body(14))
                .foregroundStyle(isNext ? Color.vaktSecondary : Color.vaktMuted)

            Spacer()

            Text(timeString(prayerTime.time))
                .font(VaktFont.body(14))
                .foregroundStyle(isNext ? Color.vaktAccent : Color.vaktShadow)
                .monospacedDigit()
        }
        .padding(.vertical, VaktSpace.sm + 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(prayerTime.prayer.rawValue), saat \(timeString(prayerTime.time))")
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Countdown Label

struct CountdownLabel: View {
    let seconds: TimeInterval

    var body: some View {
        Text(countdownText)
            .font(VaktFont.body(13))
            .foregroundStyle(Color.vaktMuted)
            .monospacedDigit()
            .accessibilityLabel("Kalan süre: \(countdownText)")
    }

    private var countdownText: String {
        let minutes = Int(seconds) / 60
        if minutes >= 60 {
            let hours = minutes / 60
            let mins  = minutes % 60
            return "\(hours) saat \(mins) dakika kaldı"
        }
        return "\(minutes) dakika kaldı"
    }
}

// MARK: - HorizonEmpty (Boş Durum)

struct HorizonEmpty: View {
    let prayer: Prayer

    var body: some View {
        VStack(spacing: VaktSpace.md) {
            // Minimal ufuk işareti
            ZStack {
                Rectangle()
                    .fill(Color.vaktBorder)
                    .frame(width: 60, height: 0.5)

                Circle()
                    .fill(Color.vaktBorder)
                    .frame(width: 8, height: 8)
            }

            VStack(spacing: VaktSpace.xs) {
                Text("Henüz kimse yok")
                    .font(VaktFont.body(16))
                    .foregroundStyle(Color.vaktMuted)

                Text("\(prayer.rawValue) vakti yaklaştığında\nufukta başkaları belirir.")
                    .font(VaktFont.caption(13))
                    .foregroundStyle(Color.vaktShadow)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .padding(VaktSpace.xxxl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Henüz kimse yok. \(prayer.rawValue) vakti yaklaştığında ufukta başkaları belirir.")
    }
}

// MARK: - Loading Horizon

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
            .accessibilityLabel("Yükleniyor")
    }
}

// MARK: - Eyebrow Label

struct EyebrowLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(VaktFont.eyebrow())
            .foregroundStyle(Color.vaktMuted)
            .tracking(0.8)
    }
}

// MARK: - SafMember Extension (borderColor helper)

extension SafMember {
    var borderColor: Color? {
        status.borderColor
    }
}

// MARK: - Offline Banner

struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: VaktSpace.sm) {
            Circle()
                .fill(Color.vaktMuted)
                .frame(width: 6, height: 6)

            Text("Bağlantı yok — ufuk bilgisi güncellenemiyor")
                .font(VaktFont.caption(12))
                .foregroundStyle(Color.vaktMuted)
        }
        .padding(.horizontal, VaktSpace.md)
        .padding(.vertical, VaktSpace.sm)
        .background(Color.vaktSurface)
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: VaktRadius.sm)
                .strokeBorder(Color.vaktBorder, lineWidth: 0.5)
        )
        .accessibilityLabel("Çevrimdışısın. Ufuk bilgisi güncellenemiyor.")
    }
}

// MARK: - VaktDivider

struct VaktDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.vaktBorder)
            .frame(height: 0.5)
    }
}
