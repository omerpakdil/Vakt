import CoreLocation
import MapKit
import SwiftUI

struct NearbyMosquesView: View {
    @ObservedObject var store: MosqueFinderStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var searchText = ""
    @State private var searchVisible = false

    private var visiblePlaces: [MosquePlace] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return store.places
        }
        return store.places.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
                ($0.address?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                mosqueMap
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, VaktSpace.lg)
                        .padding(.top, max(10, geometry.safeAreaInsets.top + 6))

                    Spacer()

                    mapControls
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, VaktSpace.lg)
                        .padding(.bottom, 12)

                    let panelHeight = max(300, geometry.size.height * 0.43)
                    resultsPanel(bottomInset: geometry.safeAreaInsets.bottom)
                        .frame(height: panelHeight + geometry.safeAreaInsets.bottom)
                        .offset(y: geometry.safeAreaInsets.bottom)
                }
            }
        }
        .background(Color.vaktBg)
        .preferredColorScheme(.dark)
        .onAppear {
            store.start()
            focusOnResults(animated: false)
        }
        .onDisappear {
            store.stop()
        }
        .onChange(of: store.places.map(\.id)) { _, _ in
            focusOnResults(animated: true)
        }
        .onChange(of: store.userCoordinate?.latitude) { _, _ in
            focusOnResults(animated: true)
        }
        .onChange(of: store.selectedPlaceID) { _, newID in
            guard let newID,
                  let place = store.places.first(where: { $0.id == newID }) else { return }
            store.select(place)
            focus(on: place)
        }
    }

    private var mosqueMap: some View {
        Group {
            if store.userCoordinate != nil {
                Map(position: $cameraPosition, selection: $store.selectedPlaceID) {
                    if let coordinate = store.userCoordinate {
                        Annotation("", coordinate: coordinate, anchor: .center) {
                            MosqueCurrentLocationMarker()
                        }
                    }

                    ForEach(store.places) { place in
                        Annotation("", coordinate: place.coordinate, anchor: .bottom) {
                            MosqueMapMarker(isSelected: place.id == store.selectedPlaceID)
                        }
                        .tag(place.id)
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .mapControlVisibility(.hidden)
            } else {
                MosqueMapWaitingBackdrop()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                MosqueHeaderButton(icon: "xmark", action: { dismiss() })
                    .accessibilityLabel(L10n.string("common.close"))

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("mosques.title"))
                        .font(VaktFont.title(21))
                        .foregroundStyle(Color.vaktPrimary)

                    Text(L10n.string("mosques.subtitle"))
                        .font(VaktFont.caption(10))
                        .foregroundStyle(Color.vaktMuted)
                }

                Spacer()

                MosqueHeaderButton(icon: searchVisible ? "xmark" : "magnifyingglass") {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        searchVisible.toggle()
                        if !searchVisible { searchText = "" }
                    }
                }
                .accessibilityLabel(L10n.string("mosques.search"))
            }

            if searchVisible {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.vaktMuted)

                    TextField(L10n.string("mosques.search.placeholder"), text: $searchText)
                        .font(VaktFont.body(13))
                        .foregroundStyle(Color.vaktPrimary)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 13)
                .frame(height: 42)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                        .strokeBorder(Color.vaktBorder.opacity(0.7), lineWidth: 0.6)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(10)
        .background(Color.vaktDeep.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6)
        }
    }

    private var mapControls: some View {
        VStack(spacing: 0) {
            Button {
                focusOnResults(animated: true)
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.vaktPrimary)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(VaktPressStyle())
            .accessibilityLabel(L10n.string("mosques.recenter"))

            Rectangle()
                .fill(Color.vaktBorder.opacity(0.7))
                .frame(width: 22, height: 0.5)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.vaktPrimary)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(VaktPressStyle())
            .accessibilityLabel(L10n.string("mosques.refresh"))
        }
        .background(Color.vaktDeep.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6)
        }
    }

    private func resultsPanel(bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.vaktBorderStrong.opacity(0.7))
                .frame(width: 34, height: 3)
                .padding(.top, 9)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("mosques.results"))
                        .font(VaktFont.body(15))
                        .foregroundStyle(Color.vaktPrimary)

                    if !store.places.isEmpty {
                        Text(store.places.count, format: .number.locale(VaktLocalization.appLocale))
                            .font(VaktFont.caption(9))
                            .foregroundStyle(Color.vaktMuted)
                    }
                }

                Spacer()

                if store.state == .searching || store.state == .locating {
                    ProgressView()
                        .tint(Color.vaktGlow)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, VaktSpace.lg)
            .padding(.top, 10)
            .padding(.bottom, 8)

            resultContent
                .padding(.bottom, max(8, bottomInset))
        }
        .background(Color.vaktBg)
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 22,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 22,
            style: .continuous
        ))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.vaktGlow.opacity(0.16))
                .frame(height: 0.6)
        }
        .shadow(color: Color.black.opacity(0.24), radius: 22, y: -8)
    }

    @ViewBuilder
    private var resultContent: some View {
        switch store.state {
        case .idle, .locating, .searching:
            MosqueLoadingState()
        case .permissionNeeded:
            MosqueMessageState(
                icon: "location",
                title: L10n.string("mosques.permission.title"),
                message: L10n.string("mosques.permission.body"),
                actionTitle: L10n.string("action.use_location"),
                action: store.requestPermission
            )
        case .denied:
            MosqueMessageState(
                icon: "location.slash",
                title: L10n.string("mosques.denied.title"),
                message: L10n.string("mosques.denied.body"),
                actionTitle: L10n.string("common.settings"),
                action: openSettings
            )
        case .empty:
            MosqueMessageState(
                icon: "map",
                title: L10n.string("mosques.empty.title"),
                message: L10n.string("mosques.empty.body"),
                actionTitle: L10n.string("mosques.refresh"),
                action: store.refresh
            )
        case .failed:
            MosqueMessageState(
                icon: "wifi.exclamationmark",
                title: L10n.string("mosques.error.title"),
                message: L10n.string("mosques.error.body"),
                actionTitle: L10n.string("common.retry"),
                action: store.refresh
            )
        case .ready:
            if visiblePlaces.isEmpty {
                MosqueMessageState(
                    icon: "magnifyingglass",
                    title: L10n.string("mosques.search.empty"),
                    message: L10n.string("mosques.search.empty.body")
                )
            } else {
                mosqueList
            }
        }
    }

    private var mosqueList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 8) {
                    ForEach(visiblePlaces) { place in
                        MosqueResultRow(
                            place: place,
                            estimate: estimate(for: place),
                            isSelected: place.id == store.selectedPlaceID,
                            onSelect: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                store.select(place)
                            },
                            onDirections: {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                store.openDirections(to: place)
                            }
                        )
                        .id(place.id)
                    }
                }
                .padding(.horizontal, VaktSpace.lg)
                .padding(.bottom, 10)
            }
            .onChange(of: store.selectedPlaceID) { _, selectedID in
                guard let selectedID else { return }
                withAnimation(.easeInOut(duration: 0.28)) {
                    proxy.scrollTo(selectedID, anchor: .center)
                }
            }
        }
    }

    private func estimate(for place: MosquePlace) -> MosqueTravelEstimate {
        if let real = store.travelEstimates[place.id] { return real }
        return MosqueTravelEstimate(
            walking: place.distanceMeters / 1.25,
            driving: 120 + place.distanceMeters / 8.3
        )
    }

    private func focus(on place: MosquePlace) {
        withAnimation(.easeInOut(duration: 0.35)) {
            cameraPosition = .camera(MapCamera(
                centerCoordinate: place.coordinate,
                distance: 1_300,
                heading: 0,
                pitch: 0
            ))
        }
    }

    private func focusOnResults(animated: Bool) {
        guard let coordinate = store.userCoordinate else { return }
        let action = {
            cameraPosition = .region(MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 6_000,
                longitudinalMeters: 6_000
            ))
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.35), action)
        } else {
            action()
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
}

private struct MosqueMapWaitingBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#172432"), Color.vaktDeep],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { context, size in
                let color = Color.vaktBorder.opacity(0.18)
                let spacing: CGFloat = 54
                stride(from: -size.height, through: size.width, by: spacing).forEach { offset in
                    var path = Path()
                    path.move(to: CGPoint(x: offset, y: 0))
                    path.addLine(to: CGPoint(x: offset + size.height, y: size.height))
                    context.stroke(path, with: .color(color), lineWidth: 0.5)
                }
            }

            Image(systemName: "location.circle")
                .font(.system(size: 42, weight: .ultraLight))
                .foregroundStyle(Color.vaktGlow.opacity(0.5))
                .offset(y: -90)
        }
    }
}

private struct MosqueCurrentLocationMarker: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "#4E9FE6").opacity(0.18))
                .frame(width: 34, height: 34)

            Circle()
                .fill(Color(hex: "#4E9FE6"))
                .frame(width: 16, height: 16)
                .overlay {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 3)
                }
                .shadow(color: Color.black.opacity(0.28), radius: 4, y: 2)
        }
        .accessibilityHidden(true)
    }
}

private struct MosqueMapMarker: View {
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.vaktGlow : Color.vaktDeep.opacity(0.92))
                    .frame(width: isSelected ? 38 : 30, height: isSelected ? 38 : 30)
                    .overlay {
                        Circle()
                            .strokeBorder(
                                isSelected ? Color.vaktPrimary.opacity(0.85) : Color.vaktGlow.opacity(0.65),
                                lineWidth: isSelected ? 1.4 : 0.8
                            )
                    }

                VaktMosqueArchGlyph()
                    .stroke(isSelected ? Color.vaktDeep : Color.vaktGlow, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                    .frame(width: isSelected ? 15 : 12, height: isSelected ? 18 : 14)
            }
            .shadow(color: Color.black.opacity(0.3), radius: 5, y: 3)

            Triangle()
                .fill(isSelected ? Color.vaktGlow : Color.vaktDeep.opacity(0.92))
                .frame(width: 8, height: 6)
                .rotationEffect(.degrees(180))
                .offset(y: -1)
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

struct VaktMosqueArchGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let bottom = rect.maxY
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.15, y: bottom))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.15, y: rect.minY + rect.height * 0.43))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.15, y: rect.minY + rect.height * 0.43),
            control: CGPoint(x: rect.midX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.15, y: bottom))
        return path
    }
}

struct VaktMosqueGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let minX = rect.minX
        let maxX = rect.maxX
        let minY = rect.minY
        let width = rect.width
        let height = rect.height
        let baseline = minY + height * 0.88

        path.move(to: CGPoint(x: minX + width * 0.06, y: baseline))
        path.addLine(to: CGPoint(x: maxX - width * 0.06, y: baseline))

        path.move(to: CGPoint(x: minX + width * 0.27, y: baseline))
        path.addLine(to: CGPoint(x: minX + width * 0.27, y: minY + height * 0.52))
        path.addQuadCurve(
            to: CGPoint(x: maxX - width * 0.27, y: minY + height * 0.52),
            control: CGPoint(x: rect.midX, y: minY + height * 0.12)
        )
        path.addLine(to: CGPoint(x: maxX - width * 0.27, y: baseline))

        path.move(to: CGPoint(x: minX + width * 0.12, y: baseline))
        path.addLine(to: CGPoint(x: minX + width * 0.12, y: minY + height * 0.34))
        path.move(to: CGPoint(x: minX + width * 0.07, y: minY + height * 0.34))
        path.addLine(to: CGPoint(x: minX + width * 0.12, y: minY + height * 0.20))
        path.addLine(to: CGPoint(x: minX + width * 0.17, y: minY + height * 0.34))

        path.move(to: CGPoint(x: maxX - width * 0.12, y: baseline))
        path.addLine(to: CGPoint(x: maxX - width * 0.12, y: minY + height * 0.34))
        path.move(to: CGPoint(x: maxX - width * 0.17, y: minY + height * 0.34))
        path.addLine(to: CGPoint(x: maxX - width * 0.12, y: minY + height * 0.20))
        path.addLine(to: CGPoint(x: maxX - width * 0.07, y: minY + height * 0.34))

        return path
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct MosqueHeaderButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.vaktPrimary)
                .frame(width: 38, height: 38)
                .background(Color.vaktSurface.opacity(0.72))
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.vaktBorder.opacity(0.7), lineWidth: 0.5))
        }
        .buttonStyle(VaktPressStyle())
    }
}

private struct MosqueResultRow: View {
    let place: MosquePlace
    let estimate: MosqueTravelEstimate
    let isSelected: Bool
    let onSelect: () -> Void
    let onDirections: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.vaktGlow.opacity(0.14) : Color.vaktSurface.opacity(0.7))
                        .frame(width: 42, height: 42)

                    VaktMosqueArchGlyph()
                        .stroke(Color.vaktGlow, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                        .frame(width: 16, height: 20)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(place.name)
                        .font(VaktFont.body(14))
                        .foregroundStyle(Color.vaktPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    HStack(spacing: 6) {
                        Text(MosqueDisplayFormatter.distance(place.distanceMeters))

                        if let address = place.address, !address.isEmpty {
                            Text(verbatim: "·")
                            Text(address)
                                .lineLimit(1)
                        }
                    }
                    .font(VaktFont.caption(9))
                    .foregroundStyle(Color.vaktMuted)

                    HStack(spacing: 12) {
                        travelMetric(icon: "figure.walk", value: MosqueDisplayFormatter.duration(estimate.walking))
                        travelMetric(icon: "car.fill", value: MosqueDisplayFormatter.duration(estimate.driving))
                    }
                }

                Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onDirections) {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.vaktGlow)
                    .frame(width: 38, height: 38)
                    .background(Color.vaktGlow.opacity(0.09))
                    .clipShape(Circle())
            }
            .buttonStyle(VaktPressStyle())
            .accessibilityLabel(L10n.string("mosques.directions"))
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 86)
        .background(isSelected ? Color.vaktElevated.opacity(0.74) : Color.vaktSurface.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VaktRadius.md, style: .continuous)
                .strokeBorder(
                    isSelected ? Color.vaktGlow.opacity(0.65) : Color.vaktBorder.opacity(0.55),
                    lineWidth: isSelected ? 1 : 0.5
                )
        }
        .accessibilityHint(L10n.string("mosques.select.hint"))
    }

    @ViewBuilder
    private func travelMetric(icon: String, value: String?) -> some View {
        if let value {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.vaktGlow)
                Text(value)
                    .font(VaktFont.caption(9))
                    .foregroundStyle(Color.vaktSecondary)
            }
        }
    }
}

private struct MosqueLoadingState: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Color.vaktGlow)
            Text(L10n.string("mosques.loading"))
                .font(VaktFont.body(12))
                .foregroundStyle(Color.vaktMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MosqueMessageState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Color.vaktGlow)

            Text(title)
                .font(VaktFont.body(14))
                .foregroundStyle(Color.vaktPrimary)

            Text(message)
                .font(VaktFont.caption(10))
                .foregroundStyle(Color.vaktMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(VaktFont.button(11))
                    .foregroundStyle(Color.vaktDeep)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(Color.vaktGlow)
                    .clipShape(RoundedRectangle(cornerRadius: VaktRadius.sm, style: .continuous))
                    .buttonStyle(VaktPressStyle())
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, VaktSpace.lg)
    }
}
