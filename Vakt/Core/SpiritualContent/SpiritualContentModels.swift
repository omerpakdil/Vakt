import Foundation

enum SpiritualContentKind: String, Codable, CaseIterable, Sendable {
    case quran
    case hadith
    case dua
    case reflection

    var displayName: String {
        switch self {
        case .quran:
            return L10n.string("spiritual.kind.quran")
        case .hadith:
            return L10n.string("spiritual.kind.hadith")
        case .dua:
            return L10n.string("spiritual.kind.dua")
        case .reflection:
            return L10n.string("spiritual.kind.reflection")
        }
    }
}

struct SpiritualContent: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let kind: SpiritualContentKind
    let text: String
    let sourceTitle: String
    let reference: String?
    let grade: String?
    let languageCode: String
    let tags: Set<String>
    let weight: Int

    init(
        id: String,
        kind: SpiritualContentKind,
        text: String,
        sourceTitle: String,
        reference: String? = nil,
        grade: String? = nil,
        languageCode: String = "en",
        tags: Set<String>,
        weight: Int = 100
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.sourceTitle = sourceTitle
        self.reference = reference
        self.grade = grade
        self.languageCode = languageCode
        self.tags = tags.map { $0.lowercased() }.reduce(into: Set<String>()) { $0.insert($1) }
        self.weight = max(1, weight)
    }

    var sourceLine: String {
        let displayedReference = kind == .quran
            ? QuranReferenceFormatter.displayReference(reference)
            : reference

        return [kind.displayName, displayedReference ?? sourceTitle]
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
    }
}

enum QuranReferenceFormatter {
    static func displayReference(_ reference: String?, languageCode: String = VaktLocalization.languageCode) -> String? {
        guard let reference, !reference.isEmpty else { return nil }
        let parts = reference.split(separator: ":")
        guard parts.count == 2,
              let surah = Int(parts[0]),
              let ayah = Int(parts[1]),
              let surahName = surahName(surah, languageCode: languageCode) else {
            return reference
        }

        return "\(surahName), \(ayah)"
    }

    private static func surahName(_ surah: Int, languageCode: String) -> String? {
        switch languageCode {
        case "tr":
            return turkishSurahName(surah)
        case "ar", "ur":
            return arabicSurahName(surah)
        default:
            return transliteratedSurahName(surah)
        }
    }

    private static func turkishSurahName(_ surah: Int) -> String? {
        switch surah {
        case 93: return "Duha"
        case 94: return "İnşirah"
        case 95: return "Tin"
        case 96: return "Alak"
        case 97: return "Kadir"
        case 98: return "Beyyine"
        case 99: return "Zilzal"
        case 100: return "Adiyat"
        case 101: return "Karia"
        case 102: return "Tekasür"
        case 103: return "Asr"
        case 104: return "Hümeze"
        case 105: return "Fil"
        case 106: return "Kureyş"
        case 107: return "Maun"
        case 108: return "Kevser"
        case 109: return "Kafirun"
        case 110: return "Nasr"
        case 111: return "Tebbet"
        case 112: return "İhlas"
        case 113: return "Felak"
        case 114: return "Nas"
        default: return nil
        }
    }

    private static func arabicSurahName(_ surah: Int) -> String? {
        switch surah {
        case 93: return "الضحى"
        case 94: return "الشرح"
        case 95: return "التين"
        case 96: return "العلق"
        case 97: return "القدر"
        case 98: return "البينة"
        case 99: return "الزلزلة"
        case 100: return "العاديات"
        case 101: return "القارعة"
        case 102: return "التكاثر"
        case 103: return "العصر"
        case 104: return "الهمزة"
        case 105: return "الفيل"
        case 106: return "قريش"
        case 107: return "الماعون"
        case 108: return "الكوثر"
        case 109: return "الكافرون"
        case 110: return "النصر"
        case 111: return "المسد"
        case 112: return "الإخلاص"
        case 113: return "الفلق"
        case 114: return "الناس"
        default: return nil
        }
    }

    private static func transliteratedSurahName(_ surah: Int) -> String? {
        switch surah {
        case 93: return "Ad-Duha"
        case 94: return "Ash-Sharh"
        case 95: return "At-Tin"
        case 96: return "Al-Alaq"
        case 97: return "Al-Qadr"
        case 98: return "Al-Bayyinah"
        case 99: return "Az-Zalzalah"
        case 100: return "Al-Adiyat"
        case 101: return "Al-Qariah"
        case 102: return "At-Takathur"
        case 103: return "Al-Asr"
        case 104: return "Al-Humazah"
        case 105: return "Al-Fil"
        case 106: return "Quraysh"
        case 107: return "Al-Ma'un"
        case 108: return "Al-Kawthar"
        case 109: return "Al-Kafirun"
        case 110: return "An-Nasr"
        case 111: return "Al-Masad"
        case 112: return "Al-Ikhlas"
        case 113: return "Al-Falaq"
        case 114: return "An-Nas"
        default: return nil
        }
    }
}

struct SpiritualContentRequest: Equatable, Sendable {
    let prayer: Prayer
    let outcome: PrayerReflectionOutcome?
    let date: Date
    let languageCode: String

    init(
        prayer: Prayer,
        outcome: PrayerReflectionOutcome? = nil,
        date: Date = Date(),
        languageCode: String = "en"
    ) {
        self.prayer = prayer
        self.outcome = outcome
        self.date = date
        self.languageCode = languageCode
    }

    var preferredTags: Set<String> {
        var tags: Set<String> = ["salah", "after_salah", prayer.rawValue.lowercased()]

        switch outcome {
        case .prayed:
            tags.formUnion(["gratitude", "acceptance"])
        case .later:
            tags.formUnion(["returning", "steadiness"])
        case .missed:
            tags.formUnion(["mercy", "returning"])
        case nil:
            tags.formUnion(["acceptance", "remembrance"])
        }

        if Calendar.current.component(.weekday, from: date) == 6 {
            tags.insert("jumuah")
        }

        return tags
    }

    var selectionKey: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let day = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        return [day, prayer.rawValue, outcome?.rawValue ?? "none", languageCode].joined(separator: "|")
    }
}
