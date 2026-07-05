import SwiftUI

struct PaywallView: View {
    @ObservedObject var store: SubscriptionStore

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @State private var selectedPlanID: String?
    @State private var sceneIsReady = false

    private var selectedPlan: SubscriptionStore.Plan? {
        store.plans.first { $0.id == selectedPlanID } ?? preferredPlan
    }

    private var preferredPlan: SubscriptionStore.Plan? {
        store.plans.first { $0.cadence == .yearly } ?? store.plans.first
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                PaywallCelestialScene(sceneIsReady: sceneIsReady, reduceMotion: reduceMotion)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        hero
                            .frame(minHeight: max(300, proxy.size.height * 0.43), alignment: .bottom)

                        purchaseArea
                    }
                    .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .background(Color.vaktDeep)
        .ignoresSafeArea(edges: .top)
        .onAppear {
            selectedPlanID = preferredPlan?.id
            withAnimation(reduceMotion ? .none : .easeOut(duration: 1.1)) {
                sceneIsReady = true
            }
        }
        .onChange(of: store.plans) { _, plans in
            guard selectedPlanID == nil || !plans.contains(where: { $0.id == selectedPlanID }) else {
                return
            }
            selectedPlanID = preferredPlan?.id
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: VaktSpace.md) {
            Text("VAKT PREMIUM")
                .font(VaktFont.eyebrow(11))
                .tracking(2.4)
                .foregroundStyle(Color.vaktPrimary.opacity(0.72))

            Text("Keep every salah\nwithin reach.")
                .font(VaktFont.title(36))
                .foregroundStyle(Color(hex: "#F4F1EA"))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Text("Local prayer times, a quiet Saf when it is time, and each moment kept with care.")
                .font(VaktFont.body(14))
                .foregroundStyle(Color.vaktPrimary.opacity(0.88))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 330, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, VaktSpace.lg)
        .padding(.bottom, 14)
        .opacity(sceneIsReady ? 1 : 0)
        .offset(y: sceneIsReady || reduceMotion ? 0 : 12)
    }

    private var purchaseArea: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.vaktBorderStrong.opacity(0.5))
                .frame(width: 36, height: 4)
                .padding(.top, 6)
                .padding(.bottom, 12)
                .accessibilityHidden(true)

            PaywallPromises()
                .padding(.bottom, 12)

            VStack(spacing: 8) {
                if store.isLoadingProducts && store.plans.isEmpty {
                    PaywallPlanLoading()
                } else {
                    ForEach(store.plans) { plan in
                        PaywallPlanRow(
                            plan: plan,
                            isSelected: selectedPlan?.id == plan.id
                        ) {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(reduceMotion ? .none : VaktAnimation.standard) {
                                selectedPlanID = plan.id
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 22)

            purchaseAction
                .padding(.bottom, 14)

            footer
        }
        .padding(.horizontal, VaktSpace.lg)
        .padding(.bottom, VaktSpace.sm)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 28,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 28,
                style: .continuous
            )
            .fill(
                LinearGradient(
                    colors: [Color.vaktDeep.opacity(0.94), Color.vaktDeep],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.22)
                )
            )
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: 28,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 28,
                    style: .continuous
                )
                .strokeBorder(Color.vaktBorder.opacity(0.4), lineWidth: 0.6)
            )
            .shadow(color: Color.vaktDeep.opacity(0.4), radius: 30, y: -12)
        )
    }

    @ViewBuilder
    private var purchaseAction: some View {
        VStack(spacing: 8) {
            if store.purchaseState == .pending {
                Text("Your purchase is waiting for approval. Vakt will open when the App Store confirms it.")
                    .font(VaktFont.caption(11))
                    .foregroundStyle(Color.vaktPrimary.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Button {
                guard let selectedPlan else { return }
                Task { await store.purchase(planID: selectedPlan.id) }
            } label: {
                HStack(spacing: 8) {
                    if store.purchaseState == .purchasing {
                        ProgressView()
                            .tint(Color.vaktDeep)
                    }

                    Text(primaryActionTitle)
                        .font(VaktFont.button())
                }
                .foregroundStyle(Color.vaktDeep)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color(hex: "#F4F1EA"))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: Color.vaktGlow.opacity(0.22), radius: 16, y: 6)
            }
            .buttonStyle(VaktPressStyle())
            .disabled(selectedPlan == nil || store.purchaseState == .purchasing)
            .opacity(selectedPlan == nil ? 0.45 : 1)

            Text("Renews automatically. Cancel anytime in your App Store settings.")
                .font(VaktFont.caption(9))
                .foregroundStyle(Color.vaktMuted)
                .multilineTextAlignment(.center)
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Button("Restore Purchases") {
                Task { await store.restorePurchases() }
            }
            .font(VaktFont.body(12))
            .foregroundStyle(Color.vaktSecondary)
            .disabled(store.purchaseState == .purchasing)

            HStack(spacing: VaktSpace.md) {
                Button("Terms") {
                    openURL(URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                }

                Rectangle()
                    .fill(Color.vaktBorderStrong)
                    .frame(width: 1, height: 10)

                Button("Privacy") {
                    openURL(URL(string: "https://vakt.app/privacy")!)
                }
            }
            .font(VaktFont.caption(9))
            .foregroundStyle(Color.vaktMuted)
        }
    }

    private var primaryActionTitle: String {
        guard let selectedPlan else { return "Continue" }
        return "Continue with \(selectedPlan.title)"
    }
}

/// Procedurally drawn night scene: gradient sky, twinkling stars, a crescent moon,
/// rising warm light motes, and an abstract dome/minaret skyline silhouette.
private struct PaywallCelestialScene: View {
    let sceneIsReady: Bool
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                Canvas { ctx, size in
                    let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    let breath = CGFloat((sin(time * 0.5) + 1) / 2)

                    drawSky(ctx: ctx, size: size)
                    drawStars(ctx: ctx, size: size, time: time)
                    drawMoon(ctx: ctx, size: size, breath: breath)
                    drawEmbers(ctx: ctx, size: size, time: time)
                    drawSkyline(ctx: ctx, size: size, breath: breath)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .scaleEffect(sceneIsReady || reduceMotion ? 1 : 1.035)
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [Color.vaktDeep.opacity(0.24), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: proxy.size.height * 0.3)
            }
            .overlay(Color.vaktDeep.opacity(0.1))
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func drawSky(ctx: GraphicsContext, size: CGSize) {
        ctx.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(
                Gradient(colors: [Color.vaktBg, Color.vaktDeep]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)
            )
        )
    }

    private func drawStars(ctx: GraphicsContext, size: CGSize, time: TimeInterval) {
        for star in Self.starField {
            let twinkle = (sin(time * 0.8 + star.phase) + 1) / 2
            let x = size.width * star.x
            let y = size.height * star.y

            ctx.fill(
                Path(ellipseIn: CGRect(x: x - star.radius, y: y - star.radius, width: star.radius * 2, height: star.radius * 2)),
                with: .color(.vaktPrimary.opacity(0.16 + twinkle * 0.4))
            )
        }
    }

    private func drawMoon(ctx: GraphicsContext, size: CGSize, breath: CGFloat) {
        let radius = size.width * 0.075
        let center = CGPoint(x: size.width * 0.74, y: size.height * 0.2)
        let haloRadius = radius * (2.7 + breath * 0.35)

        ctx.fill(
            Path(ellipseIn: CGRect(x: center.x - haloRadius, y: center.y - haloRadius, width: haloRadius * 2, height: haloRadius * 2)),
            with: .color(.vaktGlow.opacity(0.10 + Double(breath) * 0.05))
        )

        ctx.fill(
            Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
            with: .color(Color(hex: "#F4F1EA").opacity(0.92))
        )

        let cutOffset = radius * 0.42
        ctx.fill(
            Path(ellipseIn: CGRect(
                x: center.x - radius + cutOffset,
                y: center.y - radius - radius * 0.12,
                width: radius * 2,
                height: radius * 2
            )),
            with: .color(.vaktBg)
        )
    }

    private func drawEmbers(ctx: GraphicsContext, size: CGSize, time: TimeInterval) {
        for ember in Self.embers {
            let t = (CGFloat(time) * ember.speed + ember.phase).truncatingRemainder(dividingBy: 1)
            let y = size.height * (0.94 - t * 0.62)
            let drift = sin(Double(t) * .pi * 2 + Double(ember.phase) * 6) * 7
            let x = size.width * ember.x + drift
            let opacity = max(0, sin(Double(t) * .pi))

            ctx.fill(
                Path(ellipseIn: CGRect(x: x - ember.radius, y: y - ember.radius, width: ember.radius * 2, height: ember.radius * 2)),
                with: .color(.vaktGlow.opacity(opacity * 0.5))
            )
        }
    }

    private func drawSkyline(ctx: GraphicsContext, size: CGSize, breath: CGFloat) {
        let horizonY = size.height * 0.62

        var glowLine = Path()
        glowLine.move(to: CGPoint(x: 0, y: horizonY))
        glowLine.addLine(to: CGPoint(x: size.width, y: horizonY))
        ctx.stroke(
            glowLine,
            with: .color(.vaktAccent.opacity(0.14 + Double(breath) * 0.03)),
            lineWidth: 0.7
        )

        var silhouette = Path()
        silhouette.move(to: CGPoint(x: 0, y: size.height))
        silhouette.addLine(to: CGPoint(x: 0, y: horizonY + 10))

        silhouette.addLine(to: CGPoint(x: size.width * 0.14, y: horizonY + 10))
        silhouette.addLine(to: CGPoint(x: size.width * 0.14, y: horizonY - 46))
        silhouette.addLine(to: CGPoint(x: size.width * 0.145, y: horizonY - 55))
        silhouette.addLine(to: CGPoint(x: size.width * 0.15, y: horizonY - 46))
        silhouette.addLine(to: CGPoint(x: size.width * 0.15, y: horizonY + 10))

        silhouette.addLine(to: CGPoint(x: size.width * 0.32, y: horizonY + 10))
        silhouette.addLine(to: CGPoint(x: size.width * 0.32, y: horizonY - 12))
        silhouette.addCurve(
            to: CGPoint(x: size.width * 0.5, y: horizonY - 58),
            control1: CGPoint(x: size.width * 0.34, y: horizonY - 46),
            control2: CGPoint(x: size.width * 0.40, y: horizonY - 58)
        )
        silhouette.addCurve(
            to: CGPoint(x: size.width * 0.68, y: horizonY - 12),
            control1: CGPoint(x: size.width * 0.60, y: horizonY - 58),
            control2: CGPoint(x: size.width * 0.66, y: horizonY - 46)
        )
        silhouette.addLine(to: CGPoint(x: size.width * 0.68, y: horizonY + 10))

        silhouette.addLine(to: CGPoint(x: size.width * 0.85, y: horizonY + 10))
        silhouette.addLine(to: CGPoint(x: size.width * 0.85, y: horizonY - 46))
        silhouette.addLine(to: CGPoint(x: size.width * 0.855, y: horizonY - 55))
        silhouette.addLine(to: CGPoint(x: size.width * 0.86, y: horizonY - 46))
        silhouette.addLine(to: CGPoint(x: size.width * 0.86, y: horizonY + 10))

        silhouette.addLine(to: CGPoint(x: size.width, y: horizonY + 10))
        silhouette.addLine(to: CGPoint(x: size.width, y: size.height))
        silhouette.closeSubpath()

        ctx.fill(silhouette, with: .color(.vaktDeep))
    }

    private static let starField: [(x: CGFloat, y: CGFloat, phase: Double, radius: CGFloat)] = (0..<46).map { _ in
        (
            x: CGFloat.random(in: 0.02...0.98),
            y: CGFloat.random(in: 0.04...0.58),
            phase: Double.random(in: 0...(2 * .pi)),
            radius: CGFloat.random(in: 0.6...1.8)
        )
    }

    private static let embers: [(x: CGFloat, speed: CGFloat, phase: CGFloat, radius: CGFloat)] = (0..<14).map { _ in
        (
            x: CGFloat.random(in: 0.08...0.92),
            speed: CGFloat.random(in: 0.03...0.07),
            phase: CGFloat.random(in: 0...1),
            radius: CGFloat.random(in: 1.2...2.6)
        )
    }
}

private struct PaywallPromises: View {
    private let promises: [(icon: String, title: String)] = [
        ("clock", "Prayer times for where you are"),
        ("circle.grid.3x3.fill", "Join the Saf as salah draws near"),
        ("hand.raised", "Private moments, held on your device")
    ]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(promises, id: \.title) { promise in
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.vaktGlow.opacity(0.12))
                            .frame(width: 26, height: 26)

                        Image(systemName: promise.icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.vaktGlow)
                    }

                    Text(promise.title)
                        .font(VaktFont.body(12))
                        .foregroundStyle(Color.vaktPrimary.opacity(0.86))

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.vaktSurface.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PaywallPlanRow: View {
    let plan: SubscriptionStore.Plan
    let isSelected: Bool
    let action: () -> Void

    private var isBestValue: Bool { plan.cadence == .yearly }
    private var campaignLabel: String? {
        isBestValue ? "LAUNCH OFFER" : nil
    }

    private var originalPrice: String {
        switch plan.cadence {
        case .monthly: "$29.99"
        case .yearly: "$249.99"
        }
    }

    private var detailText: String {
        guard isBestValue else { return plan.billingDescription }
        return "\(plan.billingDescription) · about $8.33/month"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: VaktSpace.md) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.vaktPrimary : Color.vaktMuted, lineWidth: 1)
                        .frame(width: 22, height: 22)

                    if isSelected {
                        Circle()
                            .fill(Color.vaktPrimary)
                            .frame(width: 11, height: 11)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(plan.title)
                            .font(VaktFont.button(16))
                            .foregroundStyle(Color.vaktPrimary)

                        if let campaignLabel {
                            Text(campaignLabel)
                                .font(VaktFont.eyebrow(8))
                                .tracking(0.6)
                                .foregroundStyle(Color.vaktDeep)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.vaktGlow)
                                .clipShape(Capsule())
                        }
                    }

                    Text(detailText)
                        .font(VaktFont.caption(10))
                        .foregroundStyle(Color.vaktMuted)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(originalPrice)
                        .font(VaktFont.caption(10))
                        .foregroundStyle(Color.vaktMuted.opacity(0.74))
                        .strikethrough(true, color: Color.vaktMuted.opacity(0.72))

                    Text(plan.displayPrice)
                        .font(VaktFont.button(16))
                        .foregroundStyle(isSelected ? Color.vaktPrimary : Color.vaktSecondary)
                }
            }
            .padding(.horizontal, VaktSpace.md)
            .frame(height: 64)
            .background(isSelected ? Color.vaktSurface.opacity(0.92) : Color.vaktDeep.opacity(0.56))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.vaktGlow.opacity(0.62) : Color.vaktBorder,
                        lineWidth: isSelected ? 1 : 0.6
                    )
            )
            .shadow(color: Color.vaktGlow.opacity(isSelected ? 0.18 : 0), radius: 16, y: 6)
        }
        .buttonStyle(VaktPressStyle())
        .scaleEffect(isSelected ? 1.01 : 1)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: isSelected)
        .accessibilityLabel("\(plan.title), \(plan.displayPrice), \(plan.billingDescription)\(isBestValue ? ", best value" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PaywallPlanLoading: View {
    var body: some View {
        HStack(spacing: VaktSpace.md) {
            ProgressView()
                .tint(Color.vaktGlow)

            Text("Checking plans with the App Store…")
                .font(VaktFont.body(13))
                .foregroundStyle(Color.vaktSecondary)

            Spacer()
        }
        .padding(.horizontal, VaktSpace.md)
        .frame(height: 64)
        .background(Color.vaktSurface.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.vaktBorder, lineWidth: 0.6)
        )
    }
}
