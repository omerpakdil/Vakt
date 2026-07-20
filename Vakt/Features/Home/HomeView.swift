import SwiftUI

struct HomeView: View {
    @Binding var selectedTab: VaktTab
    @ObservedObject var prayerStore: PrayerScheduleStore
    @ObservedObject var sessionStore: PrayerSessionStore
    @ObservedObject var reflectionStore: PrayerReflectionStore
    @ObservedObject var socialPrayerStore: SocialPrayerStore

    @StateObject private var qiblaStore = QiblaCompassStore()
    @StateObject private var mosqueFinderStore = MosqueFinderStore()
    @State private var qiblaPresented = false
    @State private var mosquesPresented = false
    @State private var systemSurfacesPresented = false
    #if DEBUG
    @AppStorage(HomeAtmospherePhase.previewStorageKey)
    private var developerAtmosphereRawValue = HomeAtmospherePhase.automaticPreviewValue
    #endif

    var body: some View {
        let nextPrayer = prayerStore.nextPrayer
        let activeWindow = prayerStore.activePrayerWindow
        let currentPrayer = activeWindow?.prayerTime ?? prayerStore.latestStartedPrayer
        let selectedOutcome = currentPrayer.flatMap { reflectionStore.outcome(for: $0) } ?? .missed
        let trackingStatus = currentPrayer.map {
            reflectionStore.trackingStatus(
                for: $0,
                sessionStatus: sessionStore.status(for: $0)
            )
        }
        let atmosphere = HomeAtmosphereEngine.snapshot(
            at: prayerStore.now,
            prayers: prayerStore.prayersForDeadlineSync,
            forcedPhase: developerAtmospherePhase
        )

        GeometryReader { geometry in
            ZStack {
                HomeDayAtmosphere(
                    snapshot: atmosphere,
                    topBarTop: max(14, geometry.safeAreaInsets.top + 8)
                )

                VStack(spacing: 0) {
                    HomeTopBar(
                        now: prayerStore.now,
                        onSystemSurfaces: { systemSurfacesPresented = true },
                        onMosques: { mosquesPresented = true },
                        onQibla: { qiblaPresented = true }
                    )

                    HomePrayerFocus(
                        activeWindow: activeWindow,
                        latestPrayerTime: currentPrayer,
                        nextPrayerTime: nextPrayer,
                        now: prayerStore.now,
                        trackingStatus: trackingStatus
                    )
                    .padding(.top, 18)

                    Spacer(minLength: 14)

                    VStack(spacing: 0) {
                        if let currentPrayer, let trackingStatus {
                            HomePrayerActions(
                                prayer: currentPrayer.prayer,
                                selectedOutcome: selectedOutcome,
                                trackingStatus: trackingStatus,
                                onMark: { mark(currentPrayer, outcome: $0) },
                                onBegin: { selectedTab = .prayer }
                            )

                            HomeSocialLine(
                                prayer: currentPrayer.prayer,
                                summaries: socialPrayerStore.friendSummaries,
                                onOpen: { selectedTab = .circle }
                            )
                            .padding(.top, 18)
                        } else {
                            HomeBetweenPrayersNote()
                        }

                        HomePrayerTimeline(prayers: prayerStore.upcomingPrayers)
                            .padding(.top, 21)
                    }
                    .offset(y: 18)
                }
                .padding(.horizontal, VaktSpace.lg)
                .padding(.top, max(14, geometry.safeAreaInsets.top + 8))
                .padding(.bottom, max(4, geometry.safeAreaInsets.bottom - 4))
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
        }
        .sheet(isPresented: $qiblaPresented) {
            QiblaSheet(store: qiblaStore)
        }
        .fullScreenCover(isPresented: $mosquesPresented) {
            NearbyMosquesView(store: mosqueFinderStore)
        }
        .sheet(isPresented: $systemSurfacesPresented) {
            SystemSurfacesView()
                .presentationDetents([.fraction(0.84)])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
        }
        .onAppear {
            refreshSocialPrayer(for: currentPrayer)
        }
        .onChange(of: currentPrayer?.time) { _, _ in
            refreshSocialPrayer(for: currentPrayer)
        }
    }

    private var developerAtmospherePhase: HomeAtmospherePhase? {
        #if DEBUG
        HomeAtmospherePhase(rawValue: developerAtmosphereRawValue)
        #else
        nil
        #endif
    }

    private func refreshSocialPrayer(for prayerTime: PrayerTime?) {
        guard let prayerTime else { return }
        socialPrayerStore.refresh(for: prayerTime.time, timeZone: prayerTime.timeZone)
    }

    private func mark(_ prayerTime: PrayerTime, outcome: PrayerReflectionOutcome) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        if outcome == .prayed {
            sessionStore.markPrayerCompleted(for: prayerTime)
        }

        reflectionStore.mark(
            prayer: prayerTime.prayer,
            prayerDate: prayerTime.time,
            outcome: outcome
        )
        socialPrayerStore.mark(prayerTime, outcome: outcome)
    }
}

enum HomeAtmospherePhase: String, CaseIterable, Identifiable {
    case night
    case dawn
    case morning
    case midday
    case afternoon
    case sunset

    static let previewStorageKey = "vakt.developer.homeAtmospherePreview.v1"
    static let automaticPreviewValue = "automatic"

    var id: String { rawValue }

    var developerTitle: String {
        switch self {
        case .night: "Gece"
        case .dawn: "Sabah"
        case .morning: "Gündüz"
        case .midday: "Öğle"
        case .afternoon: "İkindi"
        case .sunset: "Akşam"
        }
    }

    var developerIcon: String {
        switch self {
        case .night: "moon.stars"
        case .dawn: "sunrise"
        case .morning: "sun.horizon"
        case .midday: "sun.max"
        case .afternoon: "sun.min"
        case .sunset: "sunset"
        }
    }
}

struct HomeAtmosphereSnapshot: Equatable {
    let phase: HomeAtmospherePhase
    let nextPhase: HomeAtmospherePhase
    let progress: Double

    var transitionProgress: Double {
        let normalized: Double
        if phase == .night {
            normalized = min(1, max(0, (progress - 0.72) / 0.28))
        } else {
            normalized = min(1, max(0, progress))
        }
        return normalized * normalized * (3 - 2 * normalized)
    }
}

enum HomeAtmosphereEngine {
    private struct Landmark {
        let date: Date
        let phase: HomeAtmospherePhase
    }

    static func snapshot(
        at date: Date,
        prayers: [PrayerTime],
        forcedPhase: HomeAtmospherePhase? = nil
    ) -> HomeAtmosphereSnapshot {
        if let forcedPhase {
            return HomeAtmosphereSnapshot(phase: forcedPhase, nextPhase: forcedPhase, progress: 0)
        }

        let landmarks = makeLandmarks(from: prayers)
        guard !landmarks.isEmpty else {
            let phase = fallbackPhase(at: date)
            return HomeAtmosphereSnapshot(phase: phase, nextPhase: phase, progress: 0)
        }

        guard let currentIndex = landmarks.lastIndex(where: { $0.date <= date }) else {
            let phase = landmarks[0].phase
            return HomeAtmosphereSnapshot(phase: phase, nextPhase: phase, progress: 0)
        }

        let current = landmarks[currentIndex]
        guard landmarks.indices.contains(currentIndex + 1) else {
            return HomeAtmosphereSnapshot(phase: current.phase, nextPhase: current.phase, progress: 0)
        }

        let next = landmarks[currentIndex + 1]
        let duration = next.date.timeIntervalSince(current.date)
        let progress = duration > 0 ? date.timeIntervalSince(current.date) / duration : 0
        return HomeAtmosphereSnapshot(
            phase: current.phase,
            nextPhase: next.phase,
            progress: min(1, max(0, progress))
        )
    }

    private static func makeLandmarks(from prayers: [PrayerTime]) -> [Landmark] {
        prayers
            .flatMap { prayerTime -> [Landmark] in
                switch prayerTime.prayer {
                case .fajr:
                    var values = [Landmark(date: prayerTime.time, phase: .dawn)]
                    if let sunrise = prayerTime.endsAt, sunrise > prayerTime.time {
                        values.append(Landmark(date: sunrise, phase: .morning))
                    }
                    return values
                case .dhuhr:
                    return [Landmark(date: prayerTime.time, phase: .midday)]
                case .asr:
                    return [Landmark(date: prayerTime.time, phase: .afternoon)]
                case .maghrib:
                    return [Landmark(date: prayerTime.time, phase: .sunset)]
                case .isha:
                    return [Landmark(date: prayerTime.time, phase: .night)]
                }
            }
            .sorted { $0.date < $1.date }
    }

    private static func fallbackPhase(at date: Date) -> HomeAtmospherePhase {
        switch Calendar.autoupdatingCurrent.component(.hour, from: date) {
        case 5..<7: .dawn
        case 7..<12: .morning
        case 12..<16: .midday
        case 16..<19: .afternoon
        case 19..<21: .sunset
        default: .night
        }
    }
}

private struct AtmosphereColor: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }

    func mixed(with other: AtmosphereColor, amount: Double) -> AtmosphereColor {
        AtmosphereColor(
            red: red + (other.red - red) * amount,
            green: green + (other.green - green) * amount,
            blue: blue + (other.blue - blue) * amount
        )
    }

    private init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}

private struct HomeAtmospherePalette {
    let top: AtmosphereColor
    let middle: AtmosphereColor
    let bottom: AtmosphereColor
    let glow: AtmosphereColor
    let horizon: AtmosphereColor
    let sunOpacity: Double
    let moonOpacity: Double
    let starOpacity: Double
    let celestialX: Double
    let celestialY: Double
    let moonX: Double
    let moonY: Double
    let horizonIntensity: Double

    static func palette(for phase: HomeAtmospherePhase) -> HomeAtmospherePalette {
        switch phase {
        case .night:
            HomeAtmospherePalette(
                top: .init(hex: 0x07101F), middle: .init(hex: 0x0A1222), bottom: .init(hex: 0x060810),
                glow: .init(hex: 0x7185B2), horizon: .init(hex: 0x344663),
                sunOpacity: 0, moonOpacity: 0.72, starOpacity: 0.52,
                celestialX: 0.79, celestialY: 0.14,
                moonX: 0.79, moonY: 0.14, horizonIntensity: 0.08
            )
        case .dawn:
            HomeAtmospherePalette(
                top: .init(hex: 0x172847), middle: .init(hex: 0x302C43), bottom: .init(hex: 0x111421),
                glow: .init(hex: 0xD2A19A), horizon: .init(hex: 0xC8897D),
                sunOpacity: 0.24, moonOpacity: 0.18, starOpacity: 0.16,
                celestialX: 0.81, celestialY: 0.34,
                moonX: 0.66, moonY: 0.14, horizonIntensity: 0.38
            )
        case .morning:
            HomeAtmospherePalette(
                top: .init(hex: 0x18354E), middle: .init(hex: 0x11283C), bottom: .init(hex: 0x08121F),
                glow: .init(hex: 0xD3C29E), horizon: .init(hex: 0x86A7B8),
                sunOpacity: 0.64, moonOpacity: 0, starOpacity: 0,
                celestialX: 0.80, celestialY: 0.21,
                moonX: 0.55, moonY: 0.10, horizonIntensity: 0.17
            )
        case .midday:
            HomeAtmospherePalette(
                top: .init(hex: 0x1C3C56), middle: .init(hex: 0x142C41), bottom: .init(hex: 0x091421),
                glow: .init(hex: 0xD8D3B2), horizon: .init(hex: 0x91AFBD),
                sunOpacity: 0.56, moonOpacity: 0, starOpacity: 0,
                celestialX: 0.82, celestialY: 0.10,
                moonX: 0.45, moonY: 0.10, horizonIntensity: 0.12
            )
        case .afternoon:
            HomeAtmospherePalette(
                top: .init(hex: 0x344052), middle: .init(hex: 0x292D3A), bottom: .init(hex: 0x0E121C),
                glow: .init(hex: 0xD3A577), horizon: .init(hex: 0xB48269),
                sunOpacity: 0.58, moonOpacity: 0, starOpacity: 0,
                celestialX: 0.78, celestialY: 0.27,
                moonX: 0.72, moonY: 0.10, horizonIntensity: 0.25
            )
        case .sunset:
            HomeAtmospherePalette(
                top: .init(hex: 0x442B3A), middle: .init(hex: 0x29243A), bottom: .init(hex: 0x0B101B),
                glow: .init(hex: 0xD28B79), horizon: .init(hex: 0xC56E62),
                sunOpacity: 0.42, moonOpacity: 0.04, starOpacity: 0.04,
                celestialX: 0.75, celestialY: 0.40,
                moonX: 0.84, moonY: 0.15, horizonIntensity: 0.45
            )
        }
    }

    func mixed(with other: HomeAtmospherePalette, amount: Double) -> HomeAtmospherePalette {
        func value(_ first: Double, _ second: Double) -> Double {
            first + (second - first) * amount
        }

        return HomeAtmospherePalette(
            top: top.mixed(with: other.top, amount: amount),
            middle: middle.mixed(with: other.middle, amount: amount),
            bottom: bottom.mixed(with: other.bottom, amount: amount),
            glow: glow.mixed(with: other.glow, amount: amount),
            horizon: horizon.mixed(with: other.horizon, amount: amount),
            sunOpacity: value(sunOpacity, other.sunOpacity),
            moonOpacity: value(moonOpacity, other.moonOpacity),
            starOpacity: value(starOpacity, other.starOpacity),
            celestialX: value(celestialX, other.celestialX),
            celestialY: value(celestialY, other.celestialY),
            moonX: value(moonX, other.moonX),
            moonY: value(moonY, other.moonY),
            horizonIntensity: value(horizonIntensity, other.horizonIntensity)
        )
    }
}

private struct HomeDayAtmosphere: View {
    let snapshot: HomeAtmosphereSnapshot
    let topBarTop: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let palette = currentPalette

        GeometryReader { geometry in
            ZStack {
                Color.vaktBg

                LinearGradient(
                    colors: [palette.top.color, palette.middle.color, palette.bottom.color],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [palette.glow.color.opacity(0.27), .clear],
                    center: UnitPoint(x: palette.celestialX, y: palette.celestialY),
                    startRadius: 0,
                    endRadius: min(geometry.size.width * 0.72, 280)
                )

                atmosphereCanvas(palette: palette)

                celestialBody(palette: palette, size: geometry.size)

                LinearGradient(
                    colors: [.clear, Color.vaktBg.opacity(0.58), Color.vaktDeep.opacity(0.96)],
                    startPoint: UnitPoint(x: 0.5, y: 0.28),
                    endPoint: .bottom
                )
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 2.4), value: snapshot.phase)
            .animation(reduceMotion ? nil : .easeInOut(duration: 2.4), value: snapshot.nextPhase)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var currentPalette: HomeAtmospherePalette {
        HomeAtmospherePalette.palette(for: snapshot.phase).mixed(
            with: HomeAtmospherePalette.palette(for: snapshot.nextPhase),
            amount: snapshot.transitionProgress
        )
    }

    private func atmosphereCanvas(palette: HomeAtmospherePalette) -> some View {
        Canvas { context, size in
            if palette.starOpacity > 0.001 {
                for index in 0..<18 {
                    let x = starCoordinate(seed: index * 37 + 11)
                    let y = starCoordinate(seed: index * 53 + 7) * 0.39 + 0.035
                    let radius = 0.45 + starCoordinate(seed: index * 29 + 3) * 0.75
                    let rect = CGRect(
                        x: size.width * x - radius,
                        y: size.height * y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    let opacity = palette.starOpacity * (0.28 + starCoordinate(seed: index * 71 + 5) * 0.54)
                    context.fill(Path(ellipseIn: rect), with: .color(Color.vaktPrimary.opacity(opacity)))
                }
            }

            let horizonY = size.height * 0.43
            var horizon = Path()
            horizon.move(to: CGPoint(x: 0, y: horizonY))
            horizon.addCurve(
                to: CGPoint(x: size.width, y: horizonY + 14),
                control1: CGPoint(x: size.width * 0.28, y: horizonY - 8),
                control2: CGPoint(x: size.width * 0.68, y: horizonY + 25)
            )
            context.stroke(
                horizon,
                with: .color(palette.horizon.color.opacity(palette.horizonIntensity)),
                lineWidth: 0.8
            )
        }
    }

    private func celestialBody(palette: HomeAtmospherePalette, size: CGSize) -> some View {
        let sunPosition = safeCelestialPosition(
            desired: CGPoint(
                x: size.width * palette.celestialX,
                y: size.height * palette.celestialY
            ),
            bodyRadius: 44,
            canvasSize: size
        )
        let moonPosition = safeCelestialPosition(
            desired: CGPoint(
                x: size.width * palette.moonX,
                y: size.height * palette.moonY - 12
            ),
            bodyRadius: 34,
            canvasSize: size
        )

        ZStack {
            ZStack {
                Circle()
                    .fill(palette.glow.color.opacity(0.14 * palette.sunOpacity))
                    .frame(width: 88, height: 88)
                    .blur(radius: 18)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.vaktPrimary.opacity(0.86), palette.glow.color.opacity(0.5)],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 24
                        )
                    )
                    .frame(width: 34, height: 34)
                    .opacity(palette.sunOpacity)
            }
            .position(sunPosition)

            ZStack {
                Circle()
                    .fill(palette.glow.color.opacity(0.16))
                    .frame(width: 58, height: 58)
                    .blur(radius: 16)

                Image(systemName: "moon.fill")
                    .font(.system(size: 29, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Color.vaktPrimary.opacity(0.9))
                    .shadow(color: palette.glow.color.opacity(0.36), radius: 8)
            }
            .opacity(palette.moonOpacity)
            .position(moonPosition)
        }
    }

    private func safeCelestialPosition(
        desired: CGPoint,
        bodyRadius: CGFloat,
        canvasSize: CGSize
    ) -> CGPoint {
        let utilityGroupWidth: CGFloat = 139
        let utilityGroupHeight: CGFloat = 50
        let clearance: CGFloat = 12
        let protectedFrame = CGRect(
            x: canvasSize.width - VaktSpace.lg - utilityGroupWidth,
            y: topBarTop,
            width: utilityGroupWidth,
            height: utilityGroupHeight
        ).insetBy(dx: -clearance, dy: -clearance)
        let celestialFrame = CGRect(
            x: desired.x - bodyRadius,
            y: desired.y - bodyRadius,
            width: bodyRadius * 2,
            height: bodyRadius * 2
        )

        guard celestialFrame.intersects(protectedFrame) else { return desired }

        let leadingPosition = protectedFrame.minX - bodyRadius - clearance
        if leadingPosition - bodyRadius >= VaktSpace.lg {
            return CGPoint(x: leadingPosition, y: desired.y)
        }

        return CGPoint(
            x: min(max(desired.x, bodyRadius + VaktSpace.lg), canvasSize.width - bodyRadius - VaktSpace.lg),
            y: protectedFrame.maxY + bodyRadius + clearance
        )
    }

    private func starCoordinate(seed: Int) -> Double {
        let value = sin(Double(seed) * 12.9898) * 43_758.5453
        return abs(value - floor(value))
    }
}

private struct HomeTopBar: View {
    let now: Date
    let onSystemSurfaces: () -> Void
    let onMosques: () -> Void
    let onQibla: () -> Void

    @AppStorage("vakt.surfaces.discovery-dismissed.v1")
    private var hasSeenSystemSurfaces = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting)
                    .font(VaktFont.body(14))
                    .foregroundStyle(Color.vaktPrimary)

                Text(dateText)
                    .font(VaktFont.caption(10))
                    .foregroundStyle(Color.vaktMuted)
            }

            Spacer()

            HStack(spacing: 0) {
                utilityButton(
                    accessibilityLabel: L10n.string("surfaces.title"),
                    showsDiscoveryDot: !hasSeenSystemSurfaces,
                    action: onSystemSurfaces
                ) {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 12, weight: .medium))
                }

                utilityDivider

                utilityButton(
                    accessibilityLabel: L10n.string("mosques.title"),
                    action: onMosques
                ) {
                    VaktMosqueGlyph()
                        .stroke(
                            Color.vaktPrimary.opacity(0.92),
                            style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: 17, height: 15)
                }

                utilityDivider

                utilityButton(
                    accessibilityLabel: L10n.string("home.open_qibla"),
                    action: onQibla
                ) {
                    Image(systemName: "location.north.line")
                        .font(.system(size: 13, weight: .medium))
                }
            }
            .padding(3)
            .foregroundStyle(Color.vaktPrimary.opacity(0.92))
            .background(Color.vaktSurface.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.vaktBorderStrong.opacity(0.6), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
        }
    }

    private var utilityDivider: some View {
        Rectangle()
            .fill(Color.vaktBorderStrong.opacity(0.52))
            .frame(width: 0.5, height: 20)
            .allowsHitTesting(false)
    }

    private func utilityButton<Icon: View>(
        accessibilityLabel: String,
        showsDiscoveryDot: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            ZStack(alignment: .topTrailing) {
                icon()

                if showsDiscoveryDot {
                    Circle()
                        .fill(Color.vaktGlow)
                        .frame(width: 5, height: 5)
                        .overlay(Circle().stroke(Color.vaktBg.opacity(0.8), lineWidth: 1))
                        .offset(x: -2, y: 2)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(VaktPressStyle())
        .accessibilityLabel(accessibilityLabel)
    }

    private var greeting: String {
        let hour = Calendar.autoupdatingCurrent.component(.hour, from: now)
        return switch hour {
        case 5..<12: L10n.string("home.greeting.morning")
        case 12..<18: L10n.string("home.greeting.day")
        case 18..<22: L10n.string("home.greeting.evening")
        default: L10n.string("home.greeting.night")
        }
    }

    private var dateText: String {
        now.formatted(
            .dateTime
                .weekday(.wide)
                .day()
                .month(.wide)
                .locale(VaktLocalization.appLocale)
        )
    }
}

private struct HomePrayerFocus: View {
    let activeWindow: ActivePrayerWindow?
    let latestPrayerTime: PrayerTime?
    let nextPrayerTime: PrayerTime
    let now: Date
    let trackingStatus: PrayerTrackingStatus?

    var body: some View {
        if let activeWindow, let trackingStatus {
            activePrayerFocus(activeWindow, trackingStatus: trackingStatus)
        } else if let latestPrayerTime, let trackingStatus {
            latestPrayerFocus(latestPrayerTime, trackingStatus: trackingStatus)
        } else {
            upcomingPrayerFocus
        }
    }

    private func latestPrayerFocus(
        _ prayerTime: PrayerTime,
        trackingStatus: PrayerTrackingStatus
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(L10n.string("home.last_prayer")
                    .uppercased(with: VaktLocalization.appLocale))
                    .font(VaktFont.eyebrow(9))
                    .foregroundStyle(Color.vaktMuted)
                    .tracking(1.8)

                Spacer()

                HomeQuietStatus(status: trackingStatus)
            }

            Text(prayerTime.prayer.displayName)
                .font(VaktFont.prayerDisplay(64))
                .foregroundStyle(Color.vaktPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.opacity)

            HomePrayerWindowRail(
                window: ActivePrayerWindow(
                    prayerTime: prayerTime,
                    endsAt: nextPrayerTime.time,
                    endingPrayer: nextPrayerTime.prayer
                ),
                now: now
            )
            .padding(.top, 10)
        }
        .accessibilityElement(children: .combine)
    }

    private func activePrayerFocus(
        _ window: ActivePrayerWindow,
        trackingStatus: PrayerTrackingStatus
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(L10n.string("home.current_prayer")
                    .uppercased(with: VaktLocalization.appLocale))
                    .font(VaktFont.eyebrow(9))
                    .foregroundStyle(Color.vaktMuted)
                    .tracking(1.8)

                Spacer()

                HomeQuietStatus(status: trackingStatus)
            }

            Text(window.prayerTime.prayer.displayName)
                .font(VaktFont.prayerDisplay(64))
                .foregroundStyle(Color.vaktPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.opacity)

            HomePrayerWindowRail(
                window: window,
                now: now
            )
            .padding(.top, 10)
        }
    }

    private var upcomingPrayerFocus: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L10n.string("home.next_prayer")
                .uppercased(with: VaktLocalization.appLocale))
                .font(VaktFont.eyebrow(9))
                .foregroundStyle(Color.vaktMuted)
                .tracking(1.8)

            Text(nextPrayerTime.prayer.displayName)
                .font(VaktFont.prayerDisplay(64))
                .foregroundStyle(Color.vaktPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.opacity)

            Text(VaktTimeFormatter.string(from: nextPrayerTime.time, timeZone: nextPrayerTime.timeZone))
                .font(VaktFont.timeDisplay(20))
                .foregroundStyle(Color.vaktGlow)
                .monospacedDigit()

            CountdownLabel(
                seconds: max(0, nextPrayerTime.time.timeIntervalSince(now)),
                fontSize: 12,
                digitWidth: 7.5,
                digitHeight: 16
            )
            .padding(.top, 7)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct HomePrayerWindowRail: View {
    let window: ActivePrayerWindow
    let now: Date

    var body: some View {
        VStack(spacing: 9) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.vaktBorderStrong.opacity(0.72))

                    Capsule()
                        .fill(Color.vaktGlow.opacity(0.76))
                        .frame(width: proxy.size.width * CGFloat(window.progress(at: now)))
                }
            }
            .frame(height: 2)

            HStack(alignment: .top, spacing: 18) {
                Text(VaktTimeFormatter.string(
                    from: window.prayerTime.time,
                    timeZone: window.prayerTime.timeZone
                ))
                .font(VaktFont.body(13))
                .foregroundStyle(Color.vaktGlow)
                .monospacedDigit()

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(endingTitle)
                            .font(VaktFont.body(13))
                            .foregroundStyle(Color.vaktSecondary)

                        Text(VaktTimeFormatter.string(
                            from: window.endsAt,
                            timeZone: window.prayerTime.timeZone
                        ))
                        .font(VaktFont.body(13))
                        .foregroundStyle(Color.vaktGlow)
                        .monospacedDigit()
                    }

                    CountdownLabel(
                        seconds: window.remaining(at: now),
                        fontSize: 10,
                        digitWidth: 6.5,
                        digitHeight: 14
                    )
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var endingTitle: String {
        window.endingPrayer?.displayName ?? L10n.string("home.sunrise")
    }
}

private struct HomeBetweenPrayersNote: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.horizon")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(Color.vaktGlow)

            Text(L10n.string("schedule.refreshing"))
                .font(VaktFont.body(12))
                .foregroundStyle(Color.vaktSecondary)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.vaktBorder.opacity(0.62))
                .frame(height: 0.5)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.vaktBorder.opacity(0.62))
                .frame(height: 0.5)
        }
    }
}

private struct HomeQuietStatus: View {
    let status: PrayerTrackingStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)

            Text(title)
            .font(VaktFont.caption(10))
            .foregroundStyle(Color.vaktMuted)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
    }

    private var title: String {
        switch status {
        case .ready: L10n.string("home.status.unmarked")
        case .inProgress: L10n.string("home.status.in_prayer")
        case .prayed, .later: L10n.string("home.status.prayed")
        case .missed: L10n.string("home.status.missed")
        }
    }

    private var color: Color {
        switch status {
        case .prayed, .later: Color.vaktPrimary
        case .inProgress: Color.vaktGlow
        case .ready, .missed: Color.vaktMuted
        }
    }
}

private struct HomePrayerActions: View {
    let prayer: Prayer
    let selectedOutcome: PrayerReflectionOutcome
    let trackingStatus: PrayerTrackingStatus
    let onMark: (PrayerReflectionOutcome) -> Void
    let onBegin: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 0) {
                outcomeButton(
                    title: L10n.string("home.action.prayed"),
                    icon: "checkmark",
                    outcome: .prayed
                )

                Rectangle()
                    .fill(Color.vaktBorderStrong.opacity(0.7))
                    .frame(width: 0.5, height: 24)

                outcomeButton(
                    title: L10n.string("home.action.missed"),
                    icon: "minus",
                    outcome: .missed
                )
            }
            .frame(height: 49)
            .background(Color.vaktSurface.opacity(0.48))
            .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                    .strokeBorder(Color.vaktBorder.opacity(0.7), lineWidth: 0.5)
            )

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onBegin()
            } label: {
                HStack(spacing: 12) {
                    Group {
                        if isOpen {
                            Image(systemName: "arrow.uturn.forward")
                                .font(.system(size: 15, weight: .medium))
                        } else {
                            VaktPrayerEntryGlyph()
                        }
                    }
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(actionTitle)
                            .font(VaktFont.button(16))

                        Text(actionSubtitle)
                            .font(VaktFont.caption(10))
                            .foregroundStyle(Color.vaktBg.opacity(0.58))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }

                    Spacer()

                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Color.vaktBg)
                .padding(.horizontal, 17)
                .frame(height: 60)
                .background(Color.vaktPrimary)
                .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
            }
            .buttonStyle(VaktPressStyle())
            .accessibilityLabel(actionTitle)
            .accessibilityHint(actionSubtitle)
        }
    }

    private func outcomeButton(title: String, icon: String, outcome: PrayerReflectionOutcome) -> some View {
        let isSelected = selectedOutcome == outcome

        return Button {
            onMark(outcome)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : icon)
                    .font(.system(size: 12, weight: .medium))

                Text(title)
                    .font(VaktFont.body(13))
            }
            .foregroundStyle(isSelected ? Color.vaktPrimary : Color.vaktMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(isSelected ? Color.vaktElevated.opacity(0.48) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(VaktPressStyle())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var isOpen: Bool {
        if case .inProgress = trackingStatus { return true }
        return false
    }

    private var actionTitle: String {
        L10n.string(isOpen ? "home.action.return" : "home.action.begin")
    }

    private var actionSubtitle: String {
        if isOpen {
            return L10n.string("home.action.return.subtitle")
        }
        return L10n.formatString("home.action.begin.subtitle", prayer.displayName)
    }
}

private struct VaktPrayerEntryGlyph: View {
    var body: some View {
        ZStack {
            VaktMihrabOutline()
                .stroke(
                    Color.vaktBg.opacity(0.88),
                    style: StrokeStyle(lineWidth: 1.65, lineCap: .round, lineJoin: .round)
                )

            Capsule()
                .fill(Color.vaktBg.opacity(0.3))
                .frame(width: 18, height: 1.2)
                .offset(y: 8.6)
        }
        .frame(width: 22, height: 22)
    }
}

private struct VaktMihrabOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let left = rect.minX + rect.width * 0.21
        let right = rect.maxX - rect.width * 0.21
        let centerX = rect.midX
        let top = rect.minY + rect.height * 0.09
        let shoulderY = rect.minY + rect.height * 0.34
        let bottom = rect.maxY - rect.height * 0.16

        var path = Path()
        path.move(to: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: left, y: shoulderY))
        path.addCurve(
            to: CGPoint(x: centerX, y: top),
            control1: CGPoint(x: left, y: rect.height * 0.23),
            control2: CGPoint(x: centerX - rect.width * 0.08, y: top + rect.height * 0.025)
        )
        path.addCurve(
            to: CGPoint(x: right, y: shoulderY),
            control1: CGPoint(x: centerX + rect.width * 0.08, y: top + rect.height * 0.025),
            control2: CGPoint(x: right, y: rect.height * 0.23)
        )
        path.addLine(to: CGPoint(x: right, y: bottom))
        return path
    }
}

private struct HomeSocialLine: View {
    let prayer: Prayer
    let summaries: [FriendPrayerSummary]
    let onOpen: () -> Void

    private var prayedFriends: [FriendPrayerSummary] {
        summaries.filter { summary in
            switch summary.statuses[PrayerKey(prayer)] {
            case .prayedOnTime, .prayedLater, .madeUp: true
            case .preparing, .notMarked, nil: false
            }
        }
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onOpen()
        } label: {
            HStack(spacing: 12) {
                HomeAvatarStack(friends: Array(prayedFriends.prefix(3)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("home.social.title"))
                        .font(VaktFont.body(13))
                        .foregroundStyle(Color.vaktPrimary)

                    Text(summary)
                        .font(VaktFont.caption(10))
                        .foregroundStyle(Color.vaktMuted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.vaktMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(VaktPressStyle())
    }

    private var summary: String {
        if summaries.isEmpty { return L10n.string("home.social.no_friends") }
        if prayedFriends.isEmpty { return L10n.string("home.social.no_signal") }
        if prayedFriends.count == 1 {
            return L10n.formatString("home.social.one_prayed", prayer.displayName)
        }
        return L10n.formatString(
            "home.social.many_prayed",
            HomeNumberFormatter.string(prayedFriends.count),
            prayer.displayName
        )
    }
}

private struct HomeAvatarStack: View {
    let friends: [FriendPrayerSummary]

    var body: some View {
        HStack(spacing: -8) {
            if friends.isEmpty {
                Image(systemName: "person.2")
                    .font(.system(size: 13, weight: .light))
                    .foregroundStyle(Color.vaktMuted)
                    .frame(width: 34, height: 34)
                    .background(Color.vaktSurface)
                    .clipShape(Circle())
            } else {
                ForEach(friends) { friend in
                    Text(initials(friend.profile.displayName))
                        .font(VaktFont.eyebrow(8))
                        .foregroundStyle(Color.vaktPrimary)
                        .frame(width: 32, height: 32)
                        .background(Color.vaktElevated)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.vaktBg, lineWidth: 2))
                }
            }
        }
        .frame(minWidth: 34, alignment: .leading)
    }

    private func initials(_ name: String) -> String {
        name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased(with: VaktLocalization.appLocale)
    }
}

private struct HomePrayerTimeline: View {
    let prayers: [PrayerTime]

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(L10n.string("home.timeline.title")
                    .uppercased(with: VaktLocalization.appLocale))
                    .font(VaktFont.eyebrow(9))
                    .foregroundStyle(Color.vaktMuted)
                    .tracking(1.5)

                Spacer()

                Text(L10n.string("home.timeline.local_time"))
                    .font(VaktFont.caption(9))
                    .foregroundStyle(Color.vaktMuted.opacity(0.7))
            }

            HStack(spacing: 5) {
                ForEach(Array(prayers.prefix(5).enumerated()), id: \.element.id) { index, prayer in
                    HomePrayerTimelineItem(
                        prayer: prayer,
                        isCurrent: index == 0
                    )
                }
            }
            .padding(5)
            .background(Color.vaktSurface.opacity(0.34))
            .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                    .strokeBorder(Color.vaktBorder.opacity(0.55), lineWidth: 0.5)
            )
        }
    }
}

private enum HomeNumberFormatter {
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = VaktLocalization.appLocale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    static func string(_ value: Int) -> String {
        formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

private struct HomePrayerTimelineItem: View {
    let prayer: PrayerTime
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Rectangle()
                .fill(isCurrent ? Color.vaktPrimary : Color.clear)
                .frame(width: isCurrent ? 25 : 0, height: 1.5)

            Text(prayer.prayer.displayName)
                .font(VaktFont.body(isCurrent ? 11 : 10))
                .foregroundStyle(isCurrent ? Color.vaktPrimary : Color.vaktMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.68)

            Text(VaktTimeFormatter.string(from: prayer.time, timeZone: prayer.timeZone))
                .font(VaktFont.timeDisplay(isCurrent ? 14 : 12))
                .foregroundStyle(Color.vaktPrimary.opacity(isCurrent ? 0.94 : 0.58))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.74)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(isCurrent ? Color.vaktElevated.opacity(0.58) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
