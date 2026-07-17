import Foundation

@MainActor
final class SpiritualContentStore: ObservableObject {
    @Published private(set) var status: SpiritualContentStatus = .idle

    private static let recentIDsKey = "vakt.spiritualContent.recentIDs.v1"
    private static let cachedContentsKey = "vakt.spiritualContent.cachedContents.v1"
    private static let refreshInterval: TimeInterval = 60 * 60 * 12

    private let repository: any SpiritualContentRepository
    private let selector: SpiritualContentSelector
    private let defaults: UserDefaults
    private var contents: [SpiritualContent]
    private var lastRefresh: Date?
    private var isRefreshing = false

    init(
        repository: any SpiritualContentRepository = LocalSpiritualContentRepository(),
        selector: SpiritualContentSelector = SpiritualContentSelector(),
        defaults: UserDefaults = .standard
    ) {
        self.repository = repository
        self.selector = selector
        self.defaults = defaults
        self.contents = Self.restoreCachedContents(from: defaults)
        if contents.isEmpty {
            self.contents = LocalSpiritualContentRepository.defaultContents
        }
    }

    func prepare(languageCode: String = "en") {
        guard shouldRefresh else { return }
        Task {
            await refresh(languageCode: languageCode)
        }
    }

    func content(
        for prayer: Prayer,
        outcome: PrayerReflectionOutcome?,
        at date: Date = Date(),
        languageCode: String = "en"
    ) -> SpiritualContent {
        let request = SpiritualContentRequest(
            prayer: prayer,
            outcome: outcome,
            date: date,
            languageCode: languageCode
        )
        let selected = selector.select(
            from: contents,
            request: request,
            recentIDs: recentIDs
        ) ?? englishFallbackContent(for: request)
            ?? Self.fallbackContent(for: request)

        remember(contentID: selected.id)
        prepare(languageCode: languageCode)
        return selected
    }

    func refresh(languageCode: String = "en") async {
        guard !isRefreshing else { return }
        isRefreshing = true
        status = .loading

        do {
            let fetched = try await repository.contents(languageCode: languageCode)
            if !fetched.isEmpty {
                contents = fetched
                cache(contents: fetched)
            }
            lastRefresh = Date()
            status = .ready(count: contents.count)
        } catch {
            status = .ready(count: contents.count)
        }

        isRefreshing = false
    }

    private var shouldRefresh: Bool {
        guard !isRefreshing else { return false }
        guard let lastRefresh else { return true }
        return Date().timeIntervalSince(lastRefresh) > Self.refreshInterval
    }

    private var recentIDs: [String] {
        defaults.stringArray(forKey: Self.recentIDsKey) ?? []
    }

    private func remember(contentID: String) {
        var ids = recentIDs.filter { $0 != contentID }
        ids.append(contentID)

        if ids.count > 40 {
            ids = Array(ids.suffix(40))
        }

        defaults.set(ids, forKey: Self.recentIDsKey)
    }

    private func cache(contents: [SpiritualContent]) {
        guard let data = try? JSONEncoder().encode(contents) else { return }
        defaults.set(data, forKey: Self.cachedContentsKey)
    }

    private func englishFallbackContent(for request: SpiritualContentRequest) -> SpiritualContent? {
        guard request.languageCode != "en" else { return nil }
        let englishRequest = SpiritualContentRequest(
            prayer: request.prayer,
            outcome: request.outcome,
            date: request.date,
            languageCode: "en"
        )
        return selector.select(
            from: contents,
            request: englishRequest,
            recentIDs: recentIDs
        )
    }

    private static func restoreCachedContents(from defaults: UserDefaults) -> [SpiritualContent] {
        guard let data = defaults.data(forKey: cachedContentsKey),
              let decoded = try? JSONDecoder().decode([SpiritualContent].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func fallbackContent(for request: SpiritualContentRequest) -> SpiritualContent {
        SpiritualContent(
            id: "fallback-\(request.prayer.rawValue.lowercased())",
            kind: .reflection,
            text: Self.localizedFallbackText(languageCode: request.languageCode),
            sourceTitle: Self.localizedSourceTitle(languageCode: request.languageCode),
            languageCode: request.languageCode,
            tags: request.preferredTags,
            weight: 1
        )
    }

    private static func localizedFallbackText(languageCode: String) -> String {
        switch languageCode {
        case "tr":
            return "Allah namazını kabul etsin ve kalbini bir sonraki vakte yakın tutsun."
        case "ar":
            return "تقبل الله صلاتك، وجعل قلبك قريباً من الصلاة القادمة."
        case "id":
            return "Semoga Allah menerima salatmu dan menjaga hatimu dekat dengan salat berikutnya."
        case "ur":
            return "اللہ آپ کی نماز قبول فرمائے اور آپ کے دل کو اگلی نماز کے قریب رکھے۔"
        case "ru":
            return "Пусть Аллах примет эту молитву и сохранит сердце близким к следующей."
        case "fr":
            return "Qu'Allah accepte cette prière et garde ton coeur proche de la prochaine."
        case "de":
            return "Möge Allah dieses Gebet annehmen und dein Herz nahe beim nächsten halten."
        case "es":
            return "Que Allah acepte esta oración y mantenga tu corazón cerca de la próxima."
        case "it":
            return "Che Allah accetti questa preghiera e tenga il tuo cuore vicino alla prossima."
        case "nl":
            return "Moge Allah dit gebed aanvaarden en je hart dicht bij het volgende houden."
        case "pt":
            return "Que Allah aceite esta oração e mantenha seu coração perto da próxima."
        default:
            return "May Allah accept this prayer and keep you close to the next one."
        }
    }

    private static func localizedSourceTitle(languageCode: String) -> String {
        switch languageCode {
        case "tr":
            return "Vakt tefekkürü"
        case "ar":
            return "تأمل من Vakt"
        case "id":
            return "Renungan Vakt"
        case "ur":
            return "Vakt تأمل"
        case "ru":
            return "Размышление Vakt"
        case "fr":
            return "Réflexion Vakt"
        case "de":
            return "Vakt-Reflexion"
        case "es":
            return "Reflexión de Vakt"
        case "it":
            return "Riflessione Vakt"
        case "nl":
            return "Vakt-reflectie"
        case "pt":
            return "Reflexão Vakt"
        default:
            return "Vakt reflection"
        }
    }
}

enum SpiritualContentStatus: Equatable {
    case idle
    case loading
    case ready(count: Int)
}
