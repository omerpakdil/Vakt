// HorizonView.swift
// Vakt — İmza Bileşeni: Ufuk Noktası Varlık Görselleştirmesi
//
// Canvas tabanlı, hafif, 60fps'de çalışır.
// Kimlik göstermez. Sadece konum ve durum.

import SwiftUI

struct HorizonView: View {
    let members: [SafMember]
    var height: CGFloat = 160
    var showLegend: Bool = true
    var earthRatio: CGFloat = 0.42   // ekranın alt kısmının oranı

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Ufuk çizgisi Y konumu
    private var horizonY: CGFloat { height * (1 - earthRatio) }

    var body: some View {
        VStack(spacing: 0) {
            Canvas { ctx, size in
                let lineY = size.height * (1 - earthRatio)

                // Zemin (toprak)
                ctx.fill(
                    Path(CGRect(x: 0, y: lineY, width: size.width, height: size.height - lineY)),
                    with: .color(.vaktDeep)
                )

                // Gökyüzü (dolaylı — arka plan rengiyle aynı, sadece noktalara zemin)

                // Ufuk çizgisi — 0.5px, accent rengi
                var line = Path()
                line.move(to: CGPoint(x: 0, y: lineY))
                line.addLine(to: CGPoint(x: size.width, y: lineY))
                ctx.stroke(line, with: .color(.vaktAccent.opacity(0.5)), lineWidth: 0.5)

                // Diğer üyelerin noktaları
                for member in members where !member.isCurrentUser {
                    drawDot(ctx: ctx, member: member, lineY: lineY, canvasWidth: size.width)
                }

                // Kullanıcının noktası — en üstte
                for member in members where member.isCurrentUser {
                    drawDot(ctx: ctx, member: member, lineY: lineY, canvasWidth: size.width)
                    // Glow efekti — küçük şeffaf daire
                    if !reduceMotion {
                        let x = member.normalizedPosition * size.width
                        let glowRect = CGRect(
                            x: x - 12, y: lineY - 12,
                            width: 24, height: 24
                        )
                        ctx.fill(
                            Path(ellipseIn: glowRect),
                            with: .color(.vaktPrimary.opacity(0.12))
                        )
                    }
                }
            }
            .frame(height: height)
            .accessibilityLabel(accessibilityDescription)

            // Legend
            if showLegend {
                horizonLegend
                    .padding(.horizontal, VaktSpace.md)
                    .padding(.top, VaktSpace.xs)
            }
        }
    }

    // MARK: - Dot Drawing

    private func drawDot(ctx: GraphicsContext, member: SafMember, lineY: CGFloat, canvasWidth: CGFloat) {
        let x = member.normalizedPosition * canvasWidth
        let r = member.dotRadius
        let dotRect = CGRect(x: x - r, y: lineY - r, width: r * 2, height: r * 2)
        let dotPath = Path(ellipseIn: dotRect)

        // Dolgu
        ctx.fill(dotPath, with: .color(member.dotColor))

        // Kenarlık (hazır olmayan statüler)
        if let borderColor = member.borderColor {
            ctx.stroke(dotPath, with: .color(borderColor), lineWidth: 0.75)
        }
    }

    // MARK: - Legend

    private var horizonLegend: some View {
        HStack(spacing: VaktSpace.md) {
            LegendItem(color: .vaktSurface, borderColor: .vaktAccent, label: "Hazırlanıyor")
            LegendItem(color: .vaktAccent, borderColor: nil, label: "Hazır")
            LegendItem(color: .vaktPrimary, borderColor: nil, label: "Sen", glowing: true)
            Spacer()
        }
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        let total = members.count
        let ready = members.filter { $0.status == .ready || $0.status == .praying }.count
        return "\(total) kişi ufukta, \(ready) tanesi namaza hazır"
    }
}

// MARK: - LegendItem

private struct LegendItem: View {
    let color: Color
    let borderColor: Color?
    let label: String
    var glowing: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .overlay(
                    Circle()
                        .strokeBorder(borderColor ?? .clear, lineWidth: borderColor != nil ? 0.75 : 0)
                )
                .frame(width: 7, height: 7)
                .shadow(color: glowing ? .vaktPrimary.opacity(0.4) : .clear, radius: 3)

            Text(label)
                .font(VaktFont.caption(10))
                .foregroundStyle(Color.vaktMuted)
                .tracking(0.3)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.vaktBg.ignoresSafeArea()
        HorizonView(members: VaktMockData.globalSaf.members)
            .padding(.horizontal, VaktSpace.md)
    }
}
