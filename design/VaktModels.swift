// VaktModels.swift
// Vakt — Veri Modelleri

import Foundation
import SwiftUI

// MARK: - Prayer

enum Prayer: String, CaseIterable, Identifiable {
    case fajr    = "Sabah"
    case dhuhr   = "Öğle"
    case asr     = "İkindi"
    case maghrib = "Akşam"
    case isha    = "Yatsı"

    var id: String { rawValue }

    var arabicName: String {
        switch self {
        case .fajr:    return "Fajr"
        case .dhuhr:   return "Dhuhr"
        case .asr:     return "Asr"
        case .maghrib: return "Maghrib"
        case .isha:    return "Isha"
        }
    }
}

// MARK: - PrepStatus

enum PrepStatus: String, CaseIterable, Identifiable, Codable {
    case gettingUp  = "Kalkıyorum"
    case wudu       = "Abdest alıyorum"
    case findingPlace = "Yer arıyorum"
    case ready      = "Hazırım"
    case praying    = "Namaz kılıyorum"

    var id: String { rawValue }

    // Ufuk noktasının boyutu — hazır olana yakın = büyük
    var dotRadius: CGFloat {
        switch self {
        case .gettingUp:    return 4
        case .wudu:         return 5
        case .findingPlace: return 5
        case .ready:        return 6
        case .praying:      return 7
        }
    }

    // Ufuk noktasının rengi
    var dotColor: Color {
        switch self {
        case .gettingUp:    return .vaktSurface
        case .wudu:         return .vaktElevated
        case .findingPlace: return .vaktElevated
        case .ready:        return .vaktAccent
        case .praying:      return .vaktPrimary
        }
    }

    // Kenarlık — hazır olmayanlar için çerçeve
    var borderColor: Color? {
        switch self {
        case .gettingUp:    return .vaktAccent
        case .wudu:         return .vaktGlow
        case .findingPlace: return .vaktGlow
        case .ready:        return nil
        case .praying:      return nil
        }
    }

    var accessibilityLabel: String {
        "Durumu: \(rawValue)"
    }
}

// MARK: - SafMember (Anonim)

struct SafMember: Identifiable {
    let id: UUID
    let normalizedPosition: CGFloat   // 0.0 — 1.0, yatay konum
    let status: PrepStatus
    let isCurrentUser: Bool

    var dotRadius: CGFloat {
        isCurrentUser ? 6 : status.dotRadius
    }

    var dotColor: Color {
        isCurrentUser ? .vaktPrimary : status.dotColor
    }

    var glowEnabled: Bool {
        isCurrentUser
    }
}

// MARK: - Saf

struct Saf: Identifiable {
    let id: UUID
    let name: String               // "Küresel Saf" / "Küçük Saf" vb.
    let prayer: Prayer
    let members: [SafMember]
    let isSmall: Bool              // Küçük saf = özel grup

    var memberCount: Int { members.count }

    var readyCount: Int {
        members.filter { $0.status == .ready || $0.status == .praying }.count
    }
}

// MARK: - PrayerTime

struct PrayerTime: Identifiable {
    let id = UUID()
    let prayer: Prayer
    let time: Date
    let countdown: TimeInterval    // saniye cinsinden
}

// MARK: - WeeklyInsight

struct DayInsight: Identifiable {
    let id = UUID()
    let weekday: String            // "Pzt", "Sal" vb.
    let onTimeCount: Int           // Zamanında başlanan vakit sayısı
    let maxPossible: Int = 5

    var fillRatio: CGFloat {
        guard maxPossible > 0 else { return 0 }
        return CGFloat(onTimeCount) / CGFloat(maxPossible)
    }
}

// MARK: - Mock Data

enum VaktMockData {
    static let nextPrayer = PrayerTime(
        prayer: .asr,
        time: Date().addingTimeInterval(12 * 60),
        countdown: 12 * 60
    )

    static let globalSaf = Saf(
        id: UUID(),
        name: "Küresel Saf",
        prayer: .asr,
        members: [
            SafMember(id: UUID(), normalizedPosition: 0.10, status: .gettingUp,    isCurrentUser: false),
            SafMember(id: UUID(), normalizedPosition: 0.22, status: .wudu,         isCurrentUser: false),
            SafMember(id: UUID(), normalizedPosition: 0.34, status: .wudu,         isCurrentUser: false),
            SafMember(id: UUID(), normalizedPosition: 0.46, status: .findingPlace, isCurrentUser: false),
            SafMember(id: UUID(), normalizedPosition: 0.55, status: .ready,        isCurrentUser: true),
            SafMember(id: UUID(), normalizedPosition: 0.64, status: .ready,        isCurrentUser: false),
            SafMember(id: UUID(), normalizedPosition: 0.76, status: .gettingUp,    isCurrentUser: false),
            SafMember(id: UUID(), normalizedPosition: 0.87, status: .wudu,         isCurrentUser: false),
        ],
        isSmall: false
    )

    static let weeklyInsights: [DayInsight] = [
        DayInsight(weekday: "Pzt", onTimeCount: 5),
        DayInsight(weekday: "Sal", onTimeCount: 3),
        DayInsight(weekday: "Çar", onTimeCount: 5),
        DayInsight(weekday: "Per", onTimeCount: 2),
        DayInsight(weekday: "Cum", onTimeCount: 4),
        DayInsight(weekday: "Cmt", onTimeCount: 5),
        DayInsight(weekday: "Paz", onTimeCount: 0),
    ]

    static let upcomingPrayers: [PrayerTime] = [
        PrayerTime(prayer: .asr,     time: Date().addingTimeInterval(12 * 60),    countdown: 12 * 60),
        PrayerTime(prayer: .maghrib, time: Date().addingTimeInterval(114 * 60),   countdown: 114 * 60),
        PrayerTime(prayer: .isha,    time: Date().addingTimeInterval(208 * 60),   countdown: 208 * 60),
        PrayerTime(prayer: .fajr,    time: Date().addingTimeInterval(610 * 60),   countdown: 610 * 60),
    ]
}
