import SwiftUI

enum SafPresenceDisplayPolicy {
    static let ambientRange = 5...10
    static let realCountThreshold = 7
    static let initialAmbientCount = 7

    static func displayedCount(realCount: Int, ambientCount: Int) -> Int {
        let realCount = max(0, realCount)
        guard realCount <= realCountThreshold else { return realCount }
        return min(ambientRange.upperBound, max(ambientRange.lowerBound, ambientCount))
    }

    static func nextAmbientCount(from current: Int, roll: Int) -> Int {
        let current = min(ambientRange.upperBound, max(ambientRange.lowerBound, current))
        if current == ambientRange.lowerBound { return current + 1 }
        if current == ambientRange.upperBound { return current - 1 }

        let normalizedRoll = min(99, max(0, roll))
        if current < 7 {
            return current + (normalizedRoll < 68 ? 1 : -1)
        }
        if current > 8 {
            return current + (normalizedRoll < 68 ? -1 : 1)
        }
        return current + (normalizedRoll < 50 ? -1 : 1)
    }
}

struct PresenceHorizonLayout {
    static let minimumDisplayedCount = SafPresenceDisplayPolicy.ambientRange.lowerBound

    let rawCount: Int
    let displayedCount: Int
    let density: Double
    let dots: [PresenceHorizonDot]
    let bands: [PresenceHorizonBand]

    init(memberCount: Int) {
        self.rawCount = max(1, memberCount)
        self.displayedCount = max(Self.minimumDisplayedCount, rawCount)
        self.density = Self.density(for: displayedCount)

        let confirmedCompanions = max(0, rawCount - 1)
        let visualCompanions = Self.visualCompanionCount(for: displayedCount)
        self.dots = Self.makeDots(
            count: visualCompanions,
            confirmedCompanions: confirmedCompanions,
            density: density
        )
        self.bands = Self.makeBands(displayedCount: displayedCount, density: density)
    }

    private static func density(for displayedCount: Int) -> Double {
        guard displayedCount > minimumDisplayedCount else { return 0 }
        return min(1, log1p(Double(displayedCount - minimumDisplayedCount)) / log1p(593))
    }

    private static func visualCompanionCount(for displayedCount: Int) -> Int {
        switch displayedCount {
        case 0...12:
            return 6
        case 13...32:
            return 8
        case 33...120:
            return 12
        case 121...360:
            return 16
        default:
            return 20
        }
    }

    private static func makeDots(count: Int, confirmedCompanions: Int, density: Double) -> [PresenceHorizonDot] {
        guard count > 0 else { return [] }
        let pairCount = Int(ceil(Double(count) / 2))
        let spread = CGFloat(0.23 + density * 0.20)
        let centerGap = CGFloat(0.10 - density * 0.025)

        return (0..<count).map { index in
            let isAmbient = index >= confirmedCompanions
            let pairIndex = index / 2
            let side: CGFloat = index.isMultiple(of: 2) ? -1 : 1
            let step = pairCount == 1 ? 0 : CGFloat(pairIndex) / CGFloat(pairCount - 1)
            let jitter = CGFloat(seededUnit(index, salt: 11) - 0.5) * 0.018
            let distance = centerGap + spread * step + jitter
            let x = min(0.94, max(0.06, 0.5 + side * distance))
            let yOffset = CGFloat(seededUnit(index, salt: 23) - 0.5) * (5 + density * 8)
            let radiusScale: CGFloat = isAmbient ? 0.78 : 1
            let opacityScale = isAmbient ? 0.48 : 1

            return PresenceHorizonDot(
                x: x,
                yOffset: yOffset,
                radius: CGFloat(3.1 + seededUnit(index, salt: 31) * 1.6 + density * 0.65) * radiusScale,
                opacity: (0.20 + density * 0.13 + seededUnit(index, salt: 41) * 0.10) * opacityScale,
                pulse: CGFloat(0.55 + seededUnit(index, salt: 53) * 0.9),
                phase: seededUnit(index, salt: 61) * .pi * 2,
                speed: (0.62 + seededUnit(index, salt: 71) * 0.62) * (isAmbient ? 0.72 : 1),
                drift: CGFloat(0.28 + seededUnit(index, salt: 83) * (0.9 + density * 1.2)) * (isAmbient ? 0.65 : 1),
                glow: isAmbient ? 0 : CGFloat(density * (2.5 + seededUnit(index, salt: 97) * 5.5))
            )
        }
    }

    private static func makeBands(displayedCount: Int, density: Double) -> [PresenceHorizonBand] {
        guard displayedCount > 24 else { return [] }

        let bandCount: Int
        switch displayedCount {
        case 25...120:
            bandCount = 2
        case 121...360:
            bandCount = 3
        default:
            bandCount = 4
        }

        return (0..<bandCount).map { index in
            let layer = Double(index)
            let inset = CGFloat(0.18 - min(0.08, density * 0.06) + layer * 0.035)
            let yOffset = CGFloat((layer - Double(bandCount - 1) / 2) * 4.2)

            return PresenceHorizonBand(
                start: inset,
                end: 1 - inset,
                yOffset: yOffset,
                opacity: 0.032 + density * 0.052 - layer * 0.006,
                width: CGFloat(1.0 + density * 2.0 - layer * 0.16),
                drift: CGFloat(1.2 + layer * 0.65)
            )
        }
    }

    private static func seededUnit(_ index: Int, salt: Int) -> Double {
        let value = sin(Double(index * 127 + salt * 311) * 12.9898) * 43_758.5453
        return value - floor(value)
    }
}

struct PresenceHorizonDot {
    let x: CGFloat
    let yOffset: CGFloat
    let radius: CGFloat
    let opacity: Double
    let pulse: CGFloat
    let phase: Double
    let speed: Double
    let drift: CGFloat
    let glow: CGFloat
}

struct PresenceHorizonBand {
    let start: CGFloat
    let end: CGFloat
    let yOffset: CGFloat
    let opacity: Double
    let width: CGFloat
    let drift: CGFloat
}
