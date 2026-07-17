import SwiftUI

enum HorizonPresentation {
    case homePreview
    case lobbyFormation
}

struct HorizonView: View {
    let members: [SafMember]
    var liveMemberCount: Int? = nil
    var presentation: HorizonPresentation = .lobbyFormation
    var height: CGFloat = 160
    var showLegend = true
    var earthRatio: CGFloat = 0.42

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var representedMemberCount: Int {
        liveMemberCount ?? members.count
    }

    private var layout: PresenceHorizonLayout {
        PresenceHorizonLayout(memberCount: representedMemberCount)
    }

    var body: some View {
        VStack(spacing: 0) {
            Canvas { ctx, size in
                let lineY = size.height * (1 - earthRatio)
                let density = layout.density

                drawBase(ctx: ctx, size: size, lineY: lineY, density: density)

                drawDensityBands(ctx: ctx, size: size, lineY: lineY, density: density)
                if presentation == .lobbyFormation {
                    drawFormationGuides(ctx: ctx, size: size, lineY: lineY, density: density)
                }

                drawHorizonLine(ctx: ctx, size: size, lineY: lineY, density: density)
                drawCompanionDots(ctx: ctx, size: size, lineY: lineY)
                drawCurrentUser(ctx: ctx, size: size, lineY: lineY, density: density)
            }
            .frame(height: height)
            .accessibilityLabel(accessibilityDescription)

            if showLegend {
                horizonLegend
                    .padding(.horizontal, VaktSpace.md)
                    .padding(.top, VaktSpace.xs)
            }
        }
    }

    private func drawBase(ctx: GraphicsContext, size: CGSize, lineY: CGFloat, density: Double) {
        switch presentation {
        case .homePreview:
            let glowRect = CGRect(
                x: size.width * (0.08 - density * 0.04),
                y: lineY - size.height * 0.20,
                width: size.width * (0.84 + density * 0.08),
                height: size.height * 0.28
            )
            ctx.fill(
                Path(ellipseIn: glowRect),
                with: .color(.vaktAccent.opacity(0.032 + 0.045 * density))
            )

            let fadeRect = CGRect(x: 0, y: lineY, width: size.width, height: size.height - lineY)
            ctx.fill(Path(fadeRect), with: .color(.vaktDeep.opacity(0.62)))

        case .lobbyFormation:
            ctx.fill(
                Path(CGRect(x: 0, y: lineY, width: size.width, height: size.height - lineY)),
                with: .color(.vaktDeep)
            )
        }
    }

    private func drawDensityBands(ctx: GraphicsContext, size: CGSize, lineY: CGFloat, density: Double) {
        for band in layout.bands {
            var path = Path()
            path.move(to: CGPoint(x: size.width * band.start, y: lineY + band.yOffset))
            path.addLine(to: CGPoint(x: size.width * band.end, y: lineY + band.yOffset))

            let opacityScale = presentation == .homePreview ? 0.72 : 1
            let widthScale = presentation == .homePreview ? 0.48 : 0.72
            ctx.stroke(
                path,
                with: .color(.vaktGlow.opacity(band.opacity * opacityScale)),
                lineWidth: max(0.45, band.width * widthScale)
            )
        }
    }

    private func drawFormationGuides(ctx: GraphicsContext, size: CGSize, lineY: CGFloat, density: Double) {
        let guideCount = 6
        for index in 0..<guideCount {
            let step = CGFloat(index) / CGFloat(guideCount - 1)
            let x = size.width * (0.14 + step * 0.72)
            let height = CGFloat(index == guideCount / 2 ? 13 : 8)
            var tick = Path()
            tick.move(to: CGPoint(x: x, y: lineY + 9))
            tick.addLine(to: CGPoint(x: x, y: lineY + 9 + height))
            ctx.stroke(tick, with: .color(.vaktBorderStrong.opacity(0.22 + 0.10 * density)), lineWidth: 0.6)
        }

        var lowerLine = Path()
        lowerLine.move(to: CGPoint(x: size.width * 0.18, y: lineY + 22))
        lowerLine.addLine(to: CGPoint(x: size.width * 0.82, y: lineY + 22))
        ctx.stroke(lowerLine, with: .color(.vaktBorder.opacity(0.36)), lineWidth: 0.5)
    }

    private func drawHorizonLine(ctx: GraphicsContext, size: CGSize, lineY: CGFloat, density: Double) {
        switch presentation {
        case .homePreview:
            var softLine = Path()
            softLine.move(to: CGPoint(x: size.width * 0.12, y: lineY))
            softLine.addLine(to: CGPoint(x: size.width * 0.88, y: lineY))
            ctx.stroke(softLine, with: .color(.vaktAccent.opacity(0.18 + 0.12 * density)), lineWidth: 0.45)

            var brightCenter = Path()
            brightCenter.move(to: CGPoint(x: size.width * 0.34, y: lineY))
            brightCenter.addLine(to: CGPoint(x: size.width * 0.66, y: lineY))
            ctx.stroke(brightCenter, with: .color(.vaktPrimary.opacity(0.14 + 0.08 * density)), lineWidth: 0.8)

        case .lobbyFormation:
            var line = Path()
            line.move(to: CGPoint(x: size.width * 0.06, y: lineY))
            line.addLine(to: CGPoint(x: size.width * 0.94, y: lineY))
            ctx.stroke(line, with: .color(.vaktAccent.opacity(0.42 + 0.16 * density)), lineWidth: 0.5 + density * 0.35)

            var activeLine = Path()
            activeLine.move(to: CGPoint(x: size.width * 0.24, y: lineY))
            activeLine.addLine(to: CGPoint(x: size.width * 0.76, y: lineY))
            ctx.stroke(activeLine, with: .color(.vaktPrimary.opacity(0.16 + 0.08 * density)), lineWidth: 1.1 + density * 0.25)
        }
    }

    private func drawCompanionDots(ctx: GraphicsContext, size: CGSize, lineY: CGFloat) {
        for (index, dot) in layout.dots.enumerated() {
            let x = size.width * dot.x
            let y = lineY + dot.yOffset * (presentation == .homePreview ? 0.32 : 0.55)
            let radius = dot.radius * (presentation == .homePreview ? 0.58 : 0.82)
            let path = Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            let preparing = index % 5 == 0
            let opacityBoost = presentation == .homePreview ? 0.02 : 0.12

            ctx.fill(
                path,
                with: .color(preparing ? .vaktSurface.opacity(dot.opacity + 0.06) : .vaktAccent.opacity(dot.opacity + opacityBoost))
            )

            if preparing && presentation == .lobbyFormation {
                ctx.stroke(path, with: .color(.vaktAccent.opacity(0.55)), lineWidth: 0.65)
            }
        }
    }

    private func drawCurrentUser(ctx: GraphicsContext, size: CGSize, lineY: CGFloat, density: Double) {
        let x = size.width * 0.5
        let radius: CGFloat = presentation == .homePreview ? 4.8 : 6
        let dotPath = Path(ellipseIn: CGRect(x: x - radius, y: lineY - radius, width: radius * 2, height: radius * 2))

        if !reduceMotion {
            let glowRadius = CGFloat((presentation == .homePreview ? 18 : 13) + density * 6)
            ctx.fill(
                Path(ellipseIn: CGRect(x: x - glowRadius, y: lineY - glowRadius, width: glowRadius * 2, height: glowRadius * 2)),
                with: .color(.vaktPrimary.opacity((presentation == .homePreview ? 0.06 : 0.10) + 0.04 * density))
            )
        }

        ctx.fill(dotPath, with: .color(.vaktPrimary))
    }

    private var horizonLegend: some View {
        HStack(spacing: VaktSpace.md) {
            LegendItem(color: .vaktSurface, borderColor: .vaktAccent, label: L10n.text(.horizonLegendPreparing))
            LegendItem(color: .vaktAccent, borderColor: nil, label: L10n.text(.horizonLegendReady))
            LegendItem(color: .vaktPrimary, borderColor: nil, label: L10n.text(.horizonLegendYou), glowing: true)
            Spacer()
        }
    }

    private var accessibilityDescription: String {
        let ready = members.filter { $0.status == .ready || $0.status == .praying }.count
        return L10n.format(
            .horizonPresenceAccessibility,
            max(representedMemberCount, PresenceHorizonLayout.minimumDisplayedCount),
            ready
        )
    }
}

private struct LegendItem: View {
    let color: Color
    let borderColor: Color?
    let label: String
    var glowing = false

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
