import Foundation

struct SpiritualContentSelector: Sendable {
    var recentWindow: Int = 18
    var prayerSpecificInterval: UInt64 = 4

    private static let prayerTags: Set<String> = ["fajr", "dhuhr", "asr", "maghrib", "isha"]

    func select(
        from contents: [SpiritualContent],
        request: SpiritualContentRequest,
        recentIDs: [String]
    ) -> SpiritualContent? {
        let normalizedRecentIDs = Array(recentIDs.suffix(recentWindow))
        let eligible = contents.filter { content in
            content.languageCode == request.languageCode && !content.text.isEmpty
        }

        guard !eligible.isEmpty else { return nil }

        let compatible = eligible.filter { content in
            isCompatible(content, request: request)
        }
        let compatiblePool = compatible.isEmpty ? eligible : compatible

        let unseen = compatiblePool.filter { !normalizedRecentIDs.contains($0.id) }
        let pool = unseen.isEmpty ? compatiblePool : unseen
        let preferredPool = preferredPool(from: pool, request: request)
        let selectionPool = preferredPool.isEmpty ? pool : preferredPool

        return selectionPool.max { lhs, rhs in
            score(lhs, request: request) < score(rhs, request: request)
        }
    }

    private func score(_ content: SpiritualContent, request: SpiritualContentRequest) -> UInt64 {
        let requestTags = request.preferredTags.subtracting(Self.prayerTags)
        let tagScore = UInt64(content.tags.intersection(requestTags).count * 7_500)
        let prayerScore = UInt64(prayerSpecificBonus(content, request: request))
        let typeScore = UInt64(typeWeight(content.kind))
        let sourceScore = UInt64(sourceCompletenessWeight(content))
        let weightScore = UInt64(content.weight * 16)
        let stableNoise = Self.stableHash("\(request.selectionKey)|\(content.id)") % 5_000

        return tagScore + prayerScore + typeScore + sourceScore + weightScore + stableNoise
    }

    private func isCompatible(_ content: SpiritualContent, request: SpiritualContentRequest) -> Bool {
        let prayerTags = content.tags.intersection(Self.prayerTags)
        return prayerTags.isEmpty || prayerTags.contains(request.prayer.rawValue.lowercased())
    }

    private func preferredPool(from contents: [SpiritualContent], request: SpiritualContentRequest) -> [SpiritualContent] {
        let shouldUsePrayerSpecific = shouldUsePrayerSpecificContent(request)
        let requestPrayerTag = request.prayer.rawValue.lowercased()

        return contents.filter { content in
            let prayerTags = content.tags.intersection(Self.prayerTags)
            if prayerTags.isEmpty {
                return true
            }

            return shouldUsePrayerSpecific && prayerTags.contains(requestPrayerTag)
        }
    }

    private func shouldUsePrayerSpecificContent(_ request: SpiritualContentRequest) -> Bool {
        guard prayerSpecificInterval > 1 else { return true }
        return Self.stableHash("prayer-specific|\(request.selectionKey)") % prayerSpecificInterval == 0
    }

    private func prayerSpecificBonus(_ content: SpiritualContent, request: SpiritualContentRequest) -> Int {
        guard shouldUsePrayerSpecificContent(request) else { return 0 }
        let requestPrayerTag = request.prayer.rawValue.lowercased()
        return content.tags.contains(requestPrayerTag) ? 2_400 : 0
    }

    private func typeWeight(_ kind: SpiritualContentKind) -> Int {
        switch kind {
        case .quran:
            return 4_000
        case .hadith:
            return 3_000
        case .dua:
            return 2_200
        case .reflection:
            return 1_000
        }
    }

    private func sourceCompletenessWeight(_ content: SpiritualContent) -> Int {
        switch content.kind {
        case .quran:
            return content.reference == nil ? -5_000 : 1_400
        case .hadith:
            guard content.reference != nil else { return -5_000 }
            return content.grade == nil ? 400 : 1_200
        case .dua, .reflection:
            return content.sourceTitle.isEmpty ? 0 : 300
        }
    }

    static func stableHash(_ value: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037

        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }

        return hash
    }
}
