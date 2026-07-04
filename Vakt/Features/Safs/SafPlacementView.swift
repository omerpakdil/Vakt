import SwiftUI

struct SafPlacementView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let prayer: Prayer
    let memberCount: Int
    let onCancel: () -> Void
    let onSelect: (SafPlacement) -> Void

    @State private var selectedPlacement: SafPlacement?
    @State private var occupiedPlacements: Set<SafPlacement> = []
    @State private var didSettle = false
    @State private var appeared = false
    @State private var settleTask: Task<Void, Never>?
    @State private var presenceTask: Task<Void, Never>?

    private var layout: SafPlacementLayout {
        SafPlacementLayout(memberCount: memberCount)
    }

    var body: some View {
        ZStack {
            placementBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, VaktSpace.lg)
                    .padding(.top, VaktSpace.xl)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 8)

                Spacer(minLength: VaktSpace.lg)

                SafPlacementSectionView(
                    slots: layout.slots(occupiedPlacements: occupiedPlacements),
                    selectedPlacement: selectedPlacement,
                    onSelect: selectPlacement
                )
                .padding(.horizontal, VaktSpace.lg)
                .frame(height: 355)
                .disabled(selectedPlacement != nil)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.985)

                Spacer(minLength: VaktSpace.lg)

                footer
                    .padding(.horizontal, VaktSpace.lg)
                    .padding(.bottom, VaktSpace.xl)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : -6)
            }
        }
        .onAppear {
            if occupiedPlacements.isEmpty {
                occupiedPlacements = layout.initialOccupiedPlacements()
            }

            withAnimation(reduceMotion ? .none : .easeOut(duration: 0.58)) {
                appeared = true
            }

            startPresenceSimulation()
        }
        .onDisappear {
            settleTask?.cancel()
            presenceTask?.cancel()
        }
        .onChange(of: memberCount) { _, _ in
            presenceTask?.cancel()
            presenceTask = nil
            withAnimation(.easeInOut(duration: 0.9)) {
                reconcileOccupancyWithMemberCount()
            }
            startPresenceSimulation()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                EyebrowLabel(text: prayer.displayName)

                Spacer()

                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.vaktMuted)
                        .frame(width: 34, height: 34)
                        .background(Color.vaktSurface.opacity(0.72))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(Color.vaktBorder, lineWidth: 0.5)
                        )
                }
                .buttonStyle(VaktPressStyle())
                .accessibilityLabel("Close")
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Step into the Saf")
                    .font(VaktFont.timeDisplay(34))
                    .foregroundStyle(Color.vaktPrimary)
                    .tracking(-0.8)

                Text("A quiet cue before you put the phone away.")
                    .font(VaktFont.body(14))
                    .foregroundStyle(Color.vaktMuted)
                    .lineSpacing(4)
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Text(didSettle ? "You have joined" : "Tap an open mark")
                .font(VaktFont.body(15))
                .foregroundStyle(didSettle ? Color.vaktPrimary.opacity(0.88) : Color.vaktMuted)
                .contentTransition(.opacity)

            Text(didSettle ? "May Allah make it easy" : "This only begins your salah screen.")
                .font(VaktFont.caption(11))
                .foregroundStyle(Color.vaktShadow)
                .tracking(0.35)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? .none : .easeInOut(duration: 0.24), value: didSettle)
    }

    private var placementBackground: some View {
        ZStack {
            Color.vaktDeep

            RadialGradient(
                colors: [
                    Color.vaktElevated.opacity(0.54),
                    Color.vaktBg.opacity(0.20),
                    Color.vaktDeep.opacity(0)
                ],
                center: .center,
                startRadius: 30,
                endRadius: 420
            )
            .scaleEffect(1.18)

            LinearGradient(
                colors: [
                    Color.vaktDeep.opacity(0.94),
                    Color.vaktBg.opacity(0.68),
                    Color.vaktDeep
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func selectPlacement(_ placement: SafPlacement) {
        guard selectedPlacement == nil else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        presenceTask?.cancel()

        withAnimation(reduceMotion ? .none : .spring(response: 0.42, dampingFraction: 0.86)) {
            selectedPlacement = placement
            didSettle = true
        }

        settleTask?.cancel()
        settleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: reduceMotion ? 520_000_000 : 1_050_000_000)
            onSelect(placement)
        }
    }

    private func startPresenceSimulation() {
        guard !reduceMotion, presenceTask == nil else { return }

        presenceTask = Task {
            var isFirstPresenceShift = true

            while !Task.isCancelled {
                let delay = isFirstPresenceShift
                    ? UInt64.random(in: 800_000_000...2_800_000_000)
                    : UInt64.random(in: 3_500_000_000...6_500_000_000)
                try? await Task.sleep(nanoseconds: delay)
                isFirstPresenceShift = false

                await MainActor.run {
                    guard selectedPlacement == nil else {
                        presenceTask?.cancel()
                        presenceTask = nil
                        return
                    }

                    withAnimation(.easeInOut(duration: 0.9)) {
                        updatePresenceSimulation()
                    }
                }
            }
        }
    }

    private func updatePresenceSimulation() {
        let targetRange = layout.occupiedCountRange

        if occupiedPlacements.count < targetRange.lowerBound {
            if let placement = layout.nextOpenPlacement(excluding: occupiedPlacements) {
                occupiedPlacements.insert(placement)
            }
            return
        }

        if occupiedPlacements.count > targetRange.upperBound {
            if let placement = layout.nextOccupiedPlacement(in: occupiedPlacements) {
                occupiedPlacements.remove(placement)
            }
            return
        }

    }

    private func reconcileOccupancyWithMemberCount() {
        let target = layout.occupiedCountRange.lowerBound

        while occupiedPlacements.count < target {
            guard let placement = layout.nextOpenPlacement(excluding: occupiedPlacements) else { break }
            occupiedPlacements.insert(placement)
        }

        while occupiedPlacements.count > target {
            guard let placement = layout.nextOccupiedPlacement(in: occupiedPlacements) else { break }
            occupiedPlacements.remove(placement)
        }
    }
}

private struct SafPlacementSectionView: View {
    let slots: [SafPlacementSlot]
    let selectedPlacement: SafPlacement?
    let onSelect: (SafPlacement) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: SafPlacementLayout.columns)

    var body: some View {
        VStack(spacing: 16) {
            qiblaLine

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(slots) { slot in
                    SafPlacementSlotButton(
                        slot: slot,
                        isSelected: selectedPlacement == slot.placement,
                        isDisabled: selectedPlacement != nil,
                        onSelect: onSelect
                    )
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(.horizontal, VaktSpace.sm)
        .padding(.vertical, VaktSpace.lg)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: VaktRadius.xl, style: .continuous)
                    .fill(Color.vaktSurface.opacity(0.24))

                SafPlacementRowGuides()
                    .padding(.horizontal, VaktSpace.lg)
                    .padding(.top, 56)
                    .padding(.bottom, 28)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: VaktRadius.xl, style: .continuous)
                .strokeBorder(Color.vaktPrimary.opacity(0.035), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
    }

    private var qiblaLine: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.vaktAccent.opacity(0.20))
                .frame(height: 0.6)

            Text("QIBLA")
                .font(VaktFont.eyebrow(9))
                .foregroundStyle(Color.vaktAccent.opacity(0.44))
                .tracking(1.6)

            Rectangle()
                .fill(Color.vaktAccent.opacity(0.20))
                .frame(height: 0.6)
        }
        .padding(.horizontal, VaktSpace.sm)
    }
}

private struct SafPlacementSlotButton: View {
    let slot: SafPlacementSlot
    let isSelected: Bool
    let isDisabled: Bool
    let onSelect: (SafPlacement) -> Void

    var body: some View {
        Button {
            guard slot.state == .open else { return }
            onSelect(slot.placement)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor)
                    .frame(height: 42)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: isSelected ? 0.9 : 0.5)
                    )

                slotMark
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(VaktPressStyle())
        .disabled(slot.state == .occupied || isDisabled)
        .opacity(isDisabled && !isSelected ? 0.44 : 1)
        .scaleEffect(isSelected ? 1.08 : 1)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: isSelected)
        .animation(.easeInOut(duration: 0.22), value: isDisabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(slot.state == .open ? "Select this open mark to join the Saf." : "This mark is already filled.")
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.vaktPrimary.opacity(0.11)
        }

        switch slot.state {
        case .open:
            return Color.vaktGlow.opacity(0.07)
        case .occupied:
            return Color.vaktSurface.opacity(0.20)
        }
    }

    private var borderColor: Color {
        if isSelected {
            return Color.vaktPrimary.opacity(0.54)
        }

        switch slot.state {
        case .open:
            return Color.vaktPrimary.opacity(0.26)
        case .occupied:
            return Color.vaktBorder.opacity(0.34)
        }
    }

    @ViewBuilder
    private var slotMark: some View {
        if isSelected {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.vaktPrimary.opacity(0.92))
                    .frame(width: 23, height: 30)
                    .shadow(color: Color.vaktPrimary.opacity(0.42), radius: 14)

                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.vaktGlow.opacity(0.38))
                    .frame(width: 11, height: 17)
                    .offset(y: -1)

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.vaktGlow.opacity(0.62), lineWidth: 0.75)
                    .frame(width: 23, height: 30)
            }
        } else {
            switch slot.state {
            case .open:
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.vaktPrimary.opacity(0.12))
                        .frame(width: 27, height: 34)
                        .shadow(color: Color.vaktGlow.opacity(0.28), radius: 11)

                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.vaktGlow.opacity(0.62),
                                    Color.vaktPrimary.opacity(0.30)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 19, height: 27)
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(Color.vaktPrimary.opacity(0.34), lineWidth: 0.7)
                        )

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.vaktPrimary.opacity(0.22))
                        .frame(width: 8, height: 14)
                        .offset(y: -2)
                }
            case .occupied:
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.vaktAccent.opacity(0.22))
                    .frame(width: 11, height: 21)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.vaktBorder.opacity(0.20), lineWidth: 0.45)
                    )
            }
        }
    }

    private var accessibilityLabel: String {
        switch slot.state {
        case .open:
            return "Open mark, row \(slot.placement.row + 1), position \(slot.placement.column + 1)"
        case .occupied:
            return "Filled mark, row \(slot.placement.row + 1), position \(slot.placement.column + 1)"
        }
    }
}

private struct SafPlacementRowGuides: View {
    var body: some View {
        VStack(spacing: 31) {
            ForEach(0..<SafPlacementLayout.rows, id: \.self) { row in
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.vaktAccent.opacity(0),
                                Color.vaktAccent.opacity(row == 0 ? 0.09 : 0.055),
                                Color.vaktAccent.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct SafPlacementSlot: Identifiable {
    let placement: SafPlacement
    let state: SafPlacementSlotState

    var id: SafPlacement {
        placement
    }
}

private enum SafPlacementSlotState {
    case open
    case occupied
}

private struct SafPlacementLayout {
    static let rows = 5
    static let columns = 7

    let memberCount: Int

    var occupiedCountRange: ClosedRange<Int> {
        let target = initialOccupiedCount()
        return target...target
    }

    func initialOccupiedPlacements() -> Set<SafPlacement> {
        Set(allPlacements().prefix(initialOccupiedCount()))
    }

    func slots(occupiedPlacements: Set<SafPlacement>) -> [SafPlacementSlot] {
        return (0..<Self.rows).flatMap { row in
            (0..<Self.columns).map { column in
                let placement = SafPlacement(sectionIndex: 0, row: row, column: column)
                let isOccupied = occupiedPlacements.contains(placement)

                return SafPlacementSlot(
                    placement: placement,
                    state: isOccupied ? .occupied : .open
                )
            }
        }
    }

    func nextOpenPlacement(excluding occupiedPlacements: Set<SafPlacement>) -> SafPlacement? {
        allPlacements()
            .filter { !occupiedPlacements.contains($0) }
            .prefix(8)
            .randomElement()
    }

    func nextOccupiedPlacement(in occupiedPlacements: Set<SafPlacement>) -> SafPlacement? {
        allPlacements()
            .reversed()
            .filter { occupiedPlacements.contains($0) }
            .prefix(8)
            .randomElement()
    }

    private func initialOccupiedCount() -> Int {
        SafPlacementOccupancyPolicy.occupiedCount(for: memberCount)
    }

    private func allPlacements() -> [SafPlacement] {
        (0..<Self.rows).flatMap { row in
            (0..<Self.columns)
                .map { column in
                    SafPlacement(sectionIndex: 0, row: row, column: column)
                }
        }
        .sorted {
            occupancyRank(row: $0.row, column: $0.column) < occupancyRank(row: $1.row, column: $1.column)
        }
    }

    private func occupancyRank(row: Int, column: Int) -> Int {
        let centerColumn = (Self.columns - 1) / 2
        let distanceFromCenter = abs(column - centerColumn)
        let rowWeight = row * 5
        let centerWeight = distanceFromCenter * 3
        let noise = abs((row + 1) * 11 + (column + 2) * 7) % 5
        return rowWeight + centerWeight + noise
    }
}

enum SafPlacementOccupancyPolicy {
    static func occupiedCount(for memberCount: Int) -> Int {
        let count = max(0, memberCount)

        switch count {
        case 0...20:
            return count
        case 21...60:
            let progress = Double(count - 20) / 40
            return 20 + Int(ceil(progress * 6))
        case 61...150:
            let progress = Double(count - 60) / 90
            return 26 + Int(ceil(progress * 3))
        default:
            return 30
        }
    }
}
