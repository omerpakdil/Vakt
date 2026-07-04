import SwiftUI

extension Color {
    static let vaktBg = Color(hex: "#0A0E1A")
    static let vaktSurface = Color(hex: "#0F1826")
    static let vaktElevated = Color(hex: "#1A2840")
    static let vaktDeep = Color(hex: "#060810")

    static let vaktAccent = Color(hex: "#648CC8")
    static let vaktGlow = Color(hex: "#8AAAD0")

    static let vaktPrimary = Color(hex: "#DCE4F0")
    static let vaktSecondary = Color(hex: "#8AAAD0")
    static let vaktMuted = Color(hex: "#4A6080")
    static let vaktShadow = Color(hex: "#2A3A50")

    static let vaktBorder = Color(hex: "#1A2840")
    static let vaktBorderStrong = Color(hex: "#2A3A50")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct VaktFont {
    static func prayerDisplay(_ size: CGFloat = 42) -> Font {
        .system(size: size, weight: .ultraLight, design: .default)
    }

    static func timeDisplay(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .thin, design: .default)
    }

    static func title(_ size: CGFloat = 22) -> Font {
        .system(size: size, weight: .light, design: .default)
    }

    static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    static func button(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }

    static func caption(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    static func eyebrow(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .semibold, design: .default)
    }
}

enum VaktSpace {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 44
    static let xxxl: CGFloat = 60
}

enum VaktRadius {
    static let sm: CGFloat = 10
    static let md: CGFloat = 14
    static let lg: CGFloat = 18
    static let xl: CGFloat = 22
    static let pill: CGFloat = 999
}

enum VaktAnimation {
    static let standard = Animation.easeInOut(duration: 0.3)
    static let slow = Animation.easeInOut(duration: 0.6)
    static let fast = Animation.easeOut(duration: 0.15)
    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.8)
}

extension View {
    func vaktGlow(color: Color = .vaktAccent, radius: CGFloat = 8) -> some View {
        shadow(color: color.opacity(0.35), radius: radius, x: 0, y: 0)
    }
}

