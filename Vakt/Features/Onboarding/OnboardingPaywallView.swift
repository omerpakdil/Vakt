import SwiftUI

struct OnboardingPaywallView: View {
    @ObservedObject var paywallStore: PaywallStore

    let stepIndex: Int
    let stepCount: Int
    let reduceMotion: Bool
    let onComplete: () -> Void

    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            Color.vaktBg.ignoresSafeArea()

            VStack(spacing: 0) {
                progressHeader
                    .padding(.top, VaktSpace.xl)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        PaywallSafScene(reduceMotion: reduceMotion)
                            .frame(height: 196)
                            .padding(.horizontal, -VaktSpace.lg)
                            .padding(.top, VaktSpace.sm)

                        content
                    }
                    .padding(.horizontal, VaktSpace.lg)
                }

                actions
                    .padding(.horizontal, VaktSpace.lg)
                    .padding(.top, VaktSpace.sm)
                    .padding(.bottom, VaktSpace.md)
            }
        }
        .onAppear {
            paywallStore.start()

            withAnimation(reduceMotion ? .none : .easeOut(duration: 0.7).delay(0.15)) {
                hasAppeared = true
            }
        }
    }

    private var progressHeader: some View {
        HStack(spacing: VaktSpace.sm) {
            ForEach(0..<stepCount, id: \.self) { index in
                Capsule()
                    .fill(index <= stepIndex ? Color.vaktPrimary : Color.vaktBorderStrong)
                    .frame(height: 3)
                    .opacity(index <= stepIndex ? 0.95 : 0.55)
            }
        }
        .padding(.horizontal, VaktSpace.lg)
        .accessibilityLabel("Onboarding step \(stepIndex + 1) of \(stepCount)")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: VaktSpace.md) {
            EyebrowLabel(text: "Vakt+")

            Text("Protect every vakt.")
                .font(VaktFont.title(30))
                .foregroundStyle(Color.vaktPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Text("You\u2019ve found your place in the Saf. Vakt+ keeps the next salah close \u2014 before it begins, while you pray, and through the quiet hours of Fajr.")
                .font(VaktFont.body(14))
                .foregroundStyle(Color.vaktMuted)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            featureCard
                .padding(.top, VaktSpace.xs)

            planCards
                .padding(.top, VaktSpace.xs)

            if let message = paywallStore.statusMessage {
                Text(message)
                    .font(VaktFont.caption(11))
                    .foregroundStyle(Color.vaktMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, VaktSpace.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, VaktSpace.md)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 14)
    }

    private var featureCard: some View {
        VStack(spacing: 0) {
            PaywallFeatureRow(
                icon: "sparkles",
                title: "Live Saf on your Lock Screen",
                detail: "Live Activity and Dynamic Island as the Saf gathers."
            )
            VaktDivider()
            PaywallFeatureRow(
                icon: "sunrise",
                title: "A gentler Fajr",
                detail: "A calm wake flow for the quietest prayer."
            )
            VaktDivider()
            PaywallFeatureRow(
                icon: "person.2",
                title: "Small Safs",
                detail: "Private safs with family and close friends."
            )
            VaktDivider()
            PaywallFeatureRow(
                icon: "chart.bar",
                title: "Start Insights",
                detail: "Your weekly rhythm, prayer by prayer."
            )
        }
        .padding(.horizontal, VaktSpace.md)
        .background(Color.vaktSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.vaktBorder, lineWidth: 0.5)
        )
    }

    private var planCards: some View {
        VStack(spacing: VaktSpace.sm) {
            PaywallPlanCard(
                title: "Yearly",
                price: paywallStore.displayPrice(for: .yearly),
                cadence: "per year",
                caption: "About $8.33 a month \u2014 two months on us",
                badge: "Best value",
                isSelected: paywallStore.selectedPlan == .yearly
            ) {
                select(.yearly)
            }

            PaywallPlanCard(
                title: "Monthly",
                price: paywallStore.displayPrice(for: .monthly),
                cadence: "per month",
                caption: "Pause or change anytime",
                badge: nil,
                isSelected: paywallStore.selectedPlan == .monthly
            ) {
                select(.monthly)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: VaktSpace.sm) {
            VaktButton(
                title: paywallStore.isPurchasing ? "One moment\u2026" : "Continue with Vakt+",
                style: .primary
            ) {
                Task {
                    if await paywallStore.purchaseSelectedPlan() {
                        onComplete()
                    }
                }
            }
            .disabled(paywallStore.isPurchasing)

            Button {
                onComplete()
            } label: {
                Text("Continue with the open Saf")
                    .font(VaktFont.body(14))
                    .foregroundStyle(Color.vaktMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(VaktPressStyle())

            HStack(spacing: VaktSpace.sm) {
                footerButton("Restore") {
                    Task {
                        if await paywallStore.restorePurchases() {
                            onComplete()
                        }
                    }
                }

                footerDot

                footerLink("Terms", url: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")

                footerDot

                footerLink("Privacy", url: "https://vakt.app/privacy")
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var footerDot: some View {
        Circle()
            .fill(Color.vaktShadow)
            .frame(width: 2.5, height: 2.5)
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(VaktFont.caption(11))
                .foregroundStyle(Color.vaktShadow)
        }
        .buttonStyle(VaktPressStyle())
    }

    @ViewBuilder
    private func footerLink(_ title: String, url: String) -> some View {
        if let destination = URL(string: url) {
            Link(title, destination: destination)
                .font(VaktFont.caption(11))
                .foregroundStyle(Color.vaktShadow)
        } else {
            Text(title)
                .font(VaktFont.caption(11))
                .foregroundStyle(Color.vaktShadow)
        }
    }

    private func select(_ plan: PaywallStore.Plan) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        withAnimation(VaktAnimation.fast) {
            paywallStore.selectedPlan = plan
        }
    }
}

private struct PaywallPlanCard: View {
    let title: String
    let price: String
    let cadence: String
    let caption: String
    let badge: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: VaktSpace.md) {
                selectionIndicator

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: VaktSpace.sm) {
                        Text(title)
                            .font(VaktFont.body(15))
                            .foregroundStyle(Color.vaktPrimary)

                        if let badge {
                            Text(badge.uppercased())
                                .font(VaktFont.eyebrow(9))
                                .tracking(0.8)
                                .foregroundStyle(Color.vaktBg)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.vaktGlow)
                                .clipShape(Capsule())
                        }
                    }

                    Text(caption)
                        .font(VaktFont.caption(11))
                        .foregroundStyle(Color.vaktMuted)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(price)
                        .font(VaktFont.timeDisplay(20))
                        .foregroundStyle(Color.vaktPrimary)
                        .monospacedDigit()

                    Text(cadence)
                        .font(VaktFont.caption(10))
                        .foregroundStyle(Color.vaktMuted)
                }
            }
            .padding(VaktSpace.md)
            .background(
                RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                    .fill(isSelected ? Color.vaktElevated.opacity(0.85) : Color.vaktSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.vaktAccent.opacity(0.7) : Color.vaktBorder,
                        lineWidth: isSelected ? 1 : 0.5
                    )
            )
            .shadow(color: Color.vaktAccent.opacity(isSelected ? 0.18 : 0), radius: 14, y: 4)
        }
        .buttonStyle(VaktPressStyle())
        .accessibilityLabel("\(title), \(price) \(cadence). \(caption)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .strokeBorder(isSelected ? Color.vaktAccent : Color.vaktBorderStrong, lineWidth: 1)
                .frame(width: 18, height: 18)

            if isSelected {
                Circle()
                    .fill(Color.vaktAccent)
                    .frame(width: 8, height: 8)
                    .vaktGlow(radius: 6)
            }
        }
    }
}

private struct PaywallFeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: VaktSpace.sm + 2) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.vaktAccent)
                .frame(width: 26, height: 26)
                .background(Color.vaktAccent.opacity(0.10))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(VaktFont.body(13))
                    .foregroundStyle(Color.vaktSecondary)

                Text(detail)
                    .font(VaktFont.caption(11))
                    .foregroundStyle(Color.vaktMuted)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

private struct PaywallSafScene: View {
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let breath = CGFloat((sin(time * 0.7) + 1) / 2)
                let lineY = size.height * 0.62

                drawSky(ctx: ctx, size: size, breath: breath)
                drawLightColumn(ctx: ctx, size: size, lineY: lineY, breath: breath)
                drawHorizon(ctx: ctx, size: size, lineY: lineY, time: time)
                drawBackRow(ctx: ctx, size: size, lineY: lineY, time: time)
                drawFrontRow(ctx: ctx, size: size, lineY: lineY, time: time)
                drawYou(ctx: ctx, size: size, lineY: lineY, time: time, breath: breath)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawSky(ctx: GraphicsContext, size: CGSize, breath: CGFloat) {
        let glowWidth = size.width * 0.86
        let glowRect = CGRect(
            x: (size.width - glowWidth) / 2,
            y: size.height * 0.10,
            width: glowWidth,
            height: size.height * 0.46
        )

        ctx.fill(
            Path(ellipseIn: glowRect),
            with: .color(.vaktAccent.opacity(0.07 + 0.03 * Double(breath)))
        )

        let lowerRect = CGRect(x: 0, y: size.height * 0.62, width: size.width, height: size.height * 0.38)
        ctx.fill(Path(lowerRect), with: .color(.vaktDeep.opacity(0.85)))
    }

    private func drawLightColumn(ctx: GraphicsContext, size: CGSize, lineY: CGFloat, breath: CGFloat) {
        let width = size.width * 0.15
        let rect = CGRect(
            x: size.width * 0.5 - width / 2,
            y: lineY - size.height * 0.44,
            width: width,
            height: size.height * 0.46
        )

        ctx.fill(
            Path(ellipseIn: rect),
            with: .color(.vaktPrimary.opacity(0.045 + 0.02 * Double(breath)))
        )
    }

    private func drawHorizon(ctx: GraphicsContext, size: CGSize, lineY: CGFloat, time: TimeInterval) {
        let shimmer = CGFloat((sin(time * 1.1) + 1) / 2)

        for index in 0..<3 {
            let inset = size.width * CGFloat(0.10 + Double(index) * 0.06)
            var path = Path()
            path.move(to: CGPoint(x: inset, y: lineY + CGFloat(index * 9)))
            path.addLine(to: CGPoint(x: size.width - inset, y: lineY + CGFloat(index * 9)))
            ctx.stroke(
                path,
                with: .color(.vaktAccent.opacity(0.16 + shimmer * 0.06 - CGFloat(index) * 0.03)),
                lineWidth: index == 0 ? 1.0 : 0.55
            )
        }
    }

    private func drawBackRow(ctx: GraphicsContext, size: CGSize, lineY: CGFloat, time: TimeInterval) {
        let count = 8

        for index in 0..<count {
            let xBase = CGFloat(index + 1) / CGFloat(count + 1)
            let sway = CGFloat(sin(time * 0.55 + Double(index) * 1.3)) * 0.008
            let x = size.width * (xBase + sway)
            let y = lineY - 15 + CGFloat(sin(Double(index) * 2.1)) * 3
            let radius: CGFloat = 1.9
            let opacity = 0.16 + Double(index % 3) * 0.05

            ctx.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                with: .color(.vaktAccent.opacity(opacity))
            )
        }
    }

    private func drawFrontRow(ctx: GraphicsContext, size: CGSize, lineY: CGFloat, time: TimeInterval) {
        let count = 11
        let centerIndex = count / 2

        for index in 0..<count {
            guard index != centerIndex else { continue }

            let xBase = CGFloat(index + 1) / CGFloat(count + 1)
            let sway = CGFloat(sin(time * 0.7 + Double(index) * 0.82)) * 0.010
            let x = size.width * min(0.94, max(0.06, xBase + sway))
            let y = lineY + CGFloat(index % 3 - 1) * 4 + CGFloat(sin(Double(index) * 1.7)) * 3
            let radius = CGFloat(2.4 + Double(index % 3) * 0.6)
            let opacity = 0.30 + Double(index % 4) * 0.10

            if index % 4 == 0 {
                let ringRadius = radius + 4
                ctx.stroke(
                    Path(ellipseIn: CGRect(
                        x: x - ringRadius,
                        y: y - ringRadius,
                        width: ringRadius * 2,
                        height: ringRadius * 2
                    )),
                    with: .color(.vaktAccent.opacity(0.18)),
                    lineWidth: 0.5
                )
            }

            ctx.fill(
                Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                with: .color(.vaktAccent.opacity(opacity))
            )
        }
    }

    private func drawYou(ctx: GraphicsContext, size: CGSize, lineY: CGFloat, time: TimeInterval, breath: CGFloat) {
        let center = CGPoint(x: size.width * 0.5, y: lineY)

        if !reduceMotion {
            let period: TimeInterval = 3.4
            let phase = CGFloat(time.truncatingRemainder(dividingBy: period) / period)
            let rippleRadius = 9 + phase * 30
            let rippleOpacity = Double((1 - phase) * 0.22)

            ctx.stroke(
                Path(ellipseIn: CGRect(
                    x: center.x - rippleRadius,
                    y: center.y - rippleRadius,
                    width: rippleRadius * 2,
                    height: rippleRadius * 2
                )),
                with: .color(.vaktPrimary.opacity(rippleOpacity)),
                lineWidth: 0.8
            )
        }

        let haloRadius = 15 + breath * 5
        ctx.fill(
            Path(ellipseIn: CGRect(
                x: center.x - haloRadius,
                y: center.y - haloRadius,
                width: haloRadius * 2,
                height: haloRadius * 2
            )),
            with: .color(.vaktPrimary.opacity(0.08 + 0.03 * Double(breath)))
        )

        let coreRadius: CGFloat = 4.6
        ctx.fill(
            Path(ellipseIn: CGRect(
                x: center.x - coreRadius,
                y: center.y - coreRadius,
                width: coreRadius * 2,
                height: coreRadius * 2
            )),
            with: .color(.vaktPrimary.opacity(0.95))
        )
    }
}
