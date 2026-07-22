import SwiftUI
import UIKit

struct QiblaSheet: View {
    @ObservedObject var store: QiblaCompassStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.vaktBg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, VaktSpace.lg)
                    .padding(.top, 18)

                Spacer(minLength: 20)

                contentArea
                    .padding(.horizontal, VaktSpace.lg)

                Spacer(minLength: 20)

                footer
                    .padding(.horizontal, VaktSpace.lg)
                    .padding(.bottom, 18)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .onAppear {
            #if DEBUG
            if StoreScreenshotRuntime.scene == .qibla {
                store.startDebugHeadingSimulation()
                store.setDebugHeading(142)
                return
            }
            #endif
            store.start()
        }
        .onDisappear {
            store.stop()
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                EyebrowLabel(text: L10n.text(.qibla))

                Text(L10n.text(.qiblaFaceDirectionTitle))
                    .font(VaktFont.title(22))
                    .foregroundStyle(Color.vaktPrimary)
                    .tracking(-0.2)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.vaktMuted)
                    .frame(width: 34, height: 34)
                    .background(Color.vaktSurface)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(Color.vaktBorder, lineWidth: 0.6)
                    )
            }
            .buttonStyle(VaktPressStyle())
            .accessibilityLabel(L10n.text(.closeQiblaFinder))
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        VStack(spacing: 16) {
            content
            simulatorDebugControls
        }
    }

    @ViewBuilder
    private var content: some View {
        if let reading = store.reading, store.status == .ready {
            QiblaCompassContent(reading: reading, reduceMotion: reduceMotion)
        } else {
            QiblaStateContent(
                status: store.status,
                requestPermission: {
                    store.requestLocationPermission()
                },
                openSettings: openSystemSettings
            )
        }
    }

    @ViewBuilder
    private var simulatorDebugControls: some View {
#if DEBUG
#if targetEnvironment(simulator)
        if StoreScreenshotRuntime.scene == nil {
            QiblaSimulatorControls(store: store)
        }
#else
        EmptyView()
#endif
#else
        EmptyView()
#endif
    }

    @ViewBuilder
    private var footer: some View {
        if let reading = store.reading, store.status == .ready {
            QiblaReadingFooter(reading: reading)
        } else {
            Text(L10n.text(.moveAwayFromMetal))
                .font(VaktFont.caption(11))
                .foregroundStyle(Color.vaktShadow)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

private struct QiblaCompassContent: View {
    let reading: QiblaCompassReading
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 24) {
            QiblaCompassDial(reading: reading, reduceMotion: reduceMotion)
                .frame(maxWidth: 315)
                .aspectRatio(1, contentMode: .fit)

            VStack(spacing: 8) {
                Text(reading.turnInstruction)
                    .font(VaktFont.title(25))
                    .foregroundStyle(reading.isAligned ? Color.vaktPrimary : Color.vaktSecondary)
                    .contentTransition(.opacity)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)

                Text(detailText)
                    .font(VaktFont.body(13))
                    .foregroundStyle(Color.vaktMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 300)
                    .contentTransition(.numericText())
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var detailText: String {
        if reading.isAligned {
            return L10n.text(.qiblaFacingSteady)
        }

        let degrees = Int(reading.absoluteAngle.rounded())
        return reading.angleToQibla > 0
            ? L10n.format(.qiblaDegreesRight, degrees)
            : L10n.format(.qiblaDegreesLeft, degrees)
    }

    private var accessibilityText: String {
        if reading.isAligned {
            return L10n.text(.qiblaAhead)
        }

        let degrees = Int(reading.absoluteAngle.rounded())
        return reading.angleToQibla > 0
            ? L10n.format(.qiblaIsDegreesRight, degrees)
            : L10n.format(.qiblaIsDegreesLeft, degrees)
    }
}

private struct QiblaCompassDial: View {
    let reading: QiblaCompassReading
    let reduceMotion: Bool

    private var normalizedAngle: Angle {
        .degrees(reading.angleToQibla)
    }

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let ringSize = size * 0.92
            let markerSize = size * 0.17

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.vaktSurface.opacity(reading.isAligned ? 0.96 : 0.78),
                                Color.vaktBg.opacity(0.2)
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: size * 0.48
                        )
                    )
                    .frame(width: ringSize, height: ringSize)
                    .shadow(
                        color: Color.vaktGlow.opacity(reading.isAligned ? 0.22 : 0.08),
                        radius: reading.isAligned ? 28 : 14
                    )

                QiblaTickRing()
                    .stroke(Color.vaktBorderStrong.opacity(0.7), lineWidth: 0.8)
                    .frame(width: ringSize, height: ringSize)

                ForEach(0..<72, id: \.self) { index in
                    QiblaTick(index: index)
                        .stroke(
                            index % 18 == 0 ? Color.vaktMuted.opacity(0.72) : Color.vaktBorderStrong.opacity(0.36),
                            lineWidth: index % 18 == 0 ? 1.3 : 0.7
                        )
                        .frame(width: ringSize, height: ringSize)
                }

                VStack(spacing: 5) {
                    Circle()
                        .fill(Color.vaktPrimary)
                        .frame(width: 9, height: 9)
                        .shadow(color: Color.vaktPrimary.opacity(0.5), radius: 10)

                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.vaktPrimary.opacity(0.72))
                        .frame(width: 2, height: size * 0.13)
                }
                .offset(y: -ringSize * 0.34)

                VStack(spacing: 5) {
                    Text(verbatim: "\(QiblaNumberFormatter.string(Int(reading.absoluteAngle.rounded())))°")
                        .font(VaktFont.timeDisplay(46))
                        .foregroundStyle(Color.vaktPrimary)
                        .monospacedDigit()

                    Text(reading.isAligned ? L10n.text(.qiblaDialSteady) : L10n.text(.qiblaDialToQibla))
                        .font(VaktFont.eyebrow(10))
                        .foregroundStyle(Color.vaktMuted)
                        .tracking(1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                QiblaMarker(isAligned: reading.isAligned)
                    .frame(width: markerSize, height: markerSize)
                    .offset(y: -ringSize * 0.39)
                    .rotationEffect(normalizedAngle)
                    .animation(reduceMotion ? .none : .spring(response: 0.42, dampingFraction: 0.78), value: reading.angleToQibla)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct QiblaMarker: View {
    let isAligned: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.vaktGlow.opacity(isAligned ? 0.26 : 0.14))

            Image(systemName: "location.north.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isAligned ? Color.vaktPrimary : Color.vaktGlow)
                .shadow(color: Color.vaktGlow.opacity(isAligned ? 0.45 : 0.2), radius: isAligned ? 12 : 7)
        }
    }
}

private struct QiblaTickRing: Shape {
    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: rect)
    }
}

private struct QiblaTick: Shape {
    let index: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let length = index % 18 == 0 ? radius * 0.09 : radius * 0.045
        let angle = Double(index) * 5 - 90
        let radians = CGFloat(angle * .pi / 180)
        let outer = CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y + sin(radians) * radius
        )
        let inner = CGPoint(
            x: center.x + cos(radians) * (radius - length),
            y: center.y + sin(radians) * (radius - length)
        )

        var path = Path()
        path.move(to: inner)
        path.addLine(to: outer)
        return path
    }
}

private struct QiblaStateContent: View {
    let status: QiblaCompassStatus
    let requestPermission: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(Color.vaktSurface)
                    .frame(width: 172, height: 172)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.vaktBorderStrong, lineWidth: 0.8)
                    )

                Image(systemName: iconName)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.vaktGlow)
            }

            VStack(spacing: 8) {
                Text(title)
                    .font(VaktFont.title(24))
                    .foregroundStyle(Color.vaktPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)

                Text(message)
                    .font(VaktFont.body(13))
                    .foregroundStyle(Color.vaktMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 310)
                    .lineLimit(4)
                    .minimumScaleFactor(0.76)
            }

            action
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var action: some View {
        switch status {
        case .permissionNeeded:
            VaktButton(title: L10n.text(.useLocation), style: .primary, action: requestPermission)
                .frame(maxWidth: 260)
        case .denied:
            VaktButton(title: L10n.text(.openSettings), style: .secondary, action: openSettings)
                .frame(maxWidth: 260)
        default:
            EmptyView()
        }
    }

    private var iconName: String {
        switch status {
        case .permissionNeeded, .denied:
            return "location"
        case .locating:
            return "location.viewfinder"
        case .calibrating:
            return "location.north.line"
        case .unavailable:
            return "safari"
        case .failed:
            return "exclamationmark"
        case .idle, .ready:
            return "location.north"
        }
    }

    private var title: String {
        switch status {
        case .permissionNeeded:
            return L10n.text(.qiblaFindTitle)
        case .locating:
            return L10n.text(.qiblaFindingTitle)
        case .calibrating:
            return L10n.text(.qiblaCalibratingTitle)
        case .denied:
            return L10n.text(.qiblaLocationOffTitle)
        case .unavailable:
            return L10n.text(.qiblaUnavailableTitle)
        case .failed:
            return L10n.text(.qiblaFailedTitle)
        case .idle:
            return L10n.text(.qiblaPreparingTitle)
        case .ready:
            return L10n.text(.qiblaReadyTitle)
        }
    }

    private var message: String {
        switch status {
        case .permissionNeeded:
            return L10n.text(.qiblaPermissionMessage)
        case .locating:
            return L10n.text(.qiblaLocatingMessage)
        case .calibrating:
            return L10n.text(.qiblaCalibratingMessage)
        case .denied:
            return L10n.text(.qiblaDeniedMessage)
        case .unavailable:
            return L10n.text(.qiblaUnavailableMessage)
        case .failed:
            return L10n.string("qibla_failed_message")
        case .idle:
            return L10n.text(.qiblaIdleMessage)
        case .ready:
            return L10n.text(.qiblaReadyMessage)
        }
    }
}

#if DEBUG
#if targetEnvironment(simulator)
private struct QiblaSimulatorControls: View {
    @ObservedObject var store: QiblaCompassStore

    private var headingBinding: Binding<Double> {
        Binding(
            get: { store.debugHeading },
            set: { store.setDebugHeading($0) }
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.vaktGlow)
                    .frame(width: 22, height: 22)
                    .background(Color.vaktGlow.opacity(0.11))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Simulator heading")
                        .font(VaktFont.caption(11))
                        .foregroundStyle(Color.vaktSecondary)

                    Text(store.isUsingDebugHeading ? "Move the slider to test the compass UI." : "Use this when the simulator has no real compass.")
                        .font(VaktFont.caption(10))
                        .foregroundStyle(Color.vaktShadow)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: 8)

                Text(verbatim: "\(Int(store.debugHeading.rounded()))°")
                    .font(VaktFont.caption(11))
                    .foregroundStyle(Color.vaktGlow)
                    .monospacedDigit()
                    .frame(width: 42, alignment: .trailing)
            }

            if store.isUsingDebugHeading {
                Slider(value: headingBinding, in: 0...359, step: 1)
                    .tint(Color.vaktGlow)

                HStack(spacing: 8) {
                    QiblaDebugStepButton(title: "-15") {
                        store.setDebugHeading(store.debugHeading - 15)
                    }

                    QiblaDebugStepButton(title: "+15") {
                        store.setDebugHeading(store.debugHeading + 15)
                    }

                    if let reading = store.reading {
                        QiblaDebugStepButton(title: "Face") {
                            store.setDebugHeading(reading.qiblaBearing)
                        }

                        QiblaDebugStepButton(title: "Away") {
                            store.setDebugHeading(reading.qiblaBearing + 180)
                        }
                    }

                    Button("Stop") {
                        store.stopDebugHeadingSimulation()
                    }
                    .font(VaktFont.caption(11))
                    .foregroundStyle(Color.vaktMuted)
                    .buttonStyle(VaktPressStyle())
                    .frame(maxWidth: .infinity)
                }
            } else {
                Button {
                    store.startDebugHeadingSimulation()
                } label: {
                    Text(verbatim: "Run heading demo")
                        .font(VaktFont.caption(11))
                        .foregroundStyle(Color.vaktBg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(Color.vaktPrimary)
                        .clipShape(Capsule())
                }
                .buttonStyle(VaktPressStyle())
            }
        }
        .padding(12)
        .background(Color.vaktSurface.opacity(0.64))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.vaktBorder.opacity(0.7), lineWidth: 0.6)
        )
    }
}

private struct QiblaDebugStepButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(VaktFont.caption(11))
                .foregroundStyle(Color.vaktSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(Color.vaktBg.opacity(0.58))
                .clipShape(Capsule())
        }
        .buttonStyle(VaktPressStyle())
    }
}
#endif
#endif

private struct QiblaReadingFooter: View {
    let reading: QiblaCompassReading

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                QiblaFooterMetric(
                    title: L10n.text(.qiblaMetricBearing),
                    value: "\(QiblaNumberFormatter.string(Int(reading.qiblaBearing.rounded())))°"
                )
                QiblaFooterMetric(title: L10n.text(.qiblaMetricDistance), value: distanceText)
                QiblaFooterMetric(title: L10n.text(.qiblaMetricSignal), value: qualityText)
            }

            Text(helperText)
                .font(VaktFont.caption(11))
                .foregroundStyle(Color.vaktShadow)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .lineLimit(3)
                .minimumScaleFactor(0.75)
        }
    }

    private var distanceText: String {
        if reading.distanceKilometers >= 1_000 {
            return L10n.format(.qiblaDistanceThousandsKm, Int((reading.distanceKilometers / 1_000).rounded()))
        }

        return L10n.format(.qiblaDistanceKm, Int(reading.distanceKilometers.rounded()))
    }

    private var qualityText: String {
        switch reading.headingQuality {
        case .good:
            return L10n.text(.qiblaSignalGood)
        case .fair:
            return L10n.text(.qiblaSignalFair)
        case .poor:
            return L10n.text(.qiblaSignalLow)
        case .unknown:
            return L10n.text(.qiblaSignalCalm)
        }
    }

    private var helperText: String {
        if reading.usesSavedLocation {
            return L10n.text(.qiblaSavedLocationHelper)
        }

        if reading.headingQuality == .poor {
            return L10n.text(.qiblaPoorSignalHelper)
        }

        return L10n.text(.qiblaDefaultHelper)
    }
}

private struct QiblaFooterMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(VaktFont.body(13))
                .foregroundStyle(Color.vaktSecondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(title.uppercased(with: VaktLocalization.appLocale))
                .font(VaktFont.eyebrow(8))
                .foregroundStyle(Color.vaktShadow)
                .tracking(0.7)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(Color.vaktSurface.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.vaktBorder.opacity(0.72), lineWidth: 0.6)
        )
    }
}

private enum QiblaNumberFormatter {
    static func string(_ value: Int) -> String {
        value.formatted(.number.locale(VaktLocalization.appLocale))
    }
}
