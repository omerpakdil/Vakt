import SwiftUI

enum StoreScreenshotScene: String, CaseIterable {
    case home
    case circle
    case markPrayer = "mark-prayer"
    case quiet
    case makeup
    case systemSurfaces = "system-surfaces"
    case qibla
    case mosques
}

enum StoreScreenshotRuntime {
    static let readyDefaultsKey = "vakt.storeScreenshot.ready"

    static var scene: StoreScreenshotScene? {
        #if DEBUG
        guard let argument = ProcessInfo.processInfo.arguments.first(where: {
            $0.hasPrefix("--vakt-store-shot=")
        }) else { return nil }
        return StoreScreenshotScene(
            rawValue: String(argument.dropFirst("--vakt-store-shot=".count))
        )
        #else
        nil
        #endif
    }
}

#if DEBUG
@MainActor
struct StoreScreenshotPreviewRoot: View {
    let scene: StoreScreenshotScene

    @State private var selectedTab: VaktTab
    @State private var launchRequest: PrayerLaunchRequest?
    @State private var isConfigured = false

    @StateObject private var prayerStore: PrayerScheduleStore
    @StateObject private var sessionStore = PrayerSessionStore()
    @StateObject private var reflectionStore = PrayerReflectionStore()
    @StateObject private var socialPrayerStore = SocialPrayerStore(repositories: nil)
    @StateObject private var spiritualContentStore = SpiritualContentStore()
    @StateObject private var referralStore = ReferralStore(repository: nil)
    @StateObject private var subscriptionStore = SubscriptionStore()
    @StateObject private var mosqueStore = MosqueFinderStore()
    @StateObject private var qiblaStore = QiblaCompassStore()

    private let fixture: StoreScreenshotFixture

    init(scene: StoreScreenshotScene) {
        self.scene = scene
        let fixture = StoreScreenshotFixture(scene: scene)
        self.fixture = fixture
        _selectedTab = State(initialValue: scene == .circle ? .circle : .home)
        _prayerStore = StateObject(
            wrappedValue: PrayerScheduleStore(now: fixture.referenceDate)
        )
    }

    var body: some View {
        Group {
            if isConfigured {
                sceneContent
            } else {
                Color.vaktBg.ignoresSafeArea()
            }
        }
        .environment(\.locale, VaktLocalization.appLocale)
        .environment(\.layoutDirection, VaktLocalization.layoutDirection)
        .preferredColorScheme(.dark)
        .task {
            configureFixture()
            isConfigured = true

            let delay: Duration = scene == .mosques ? .milliseconds(1_800) : .milliseconds(900)
            try? await Task.sleep(for: delay)
            UserDefaults.standard.set(true, forKey: StoreScreenshotRuntime.readyDefaultsKey)
            UserDefaults.standard.synchronize()
            print("VAKT_STORE_SCREENSHOT_READY \(scene.rawValue)")
        }
    }

    @ViewBuilder
    private var sceneContent: some View {
        switch scene {
        case .home, .circle, .markPrayer:
            productionTabs
        case .quiet:
            NavigationStack {
                PrayerView(
                    prayerStore: prayerStore,
                    reflectionStore: reflectionStore,
                    sessionStore: sessionStore,
                    socialPrayerStore: socialPrayerStore,
                    spiritualContentStore: spiritualContentStore,
                    launchRequest: $launchRequest,
                    onReviewOpportunity: { _ in }
                )
            }
        case .makeup:
            NavigationStack {
                MakeupPrayerCenterView(
                    store: socialPrayerStore,
                    initialDate: fixture.referenceDate,
                    initialSelectedDay: fixture.makeupSelectedDay
                )
            }
        case .systemSurfaces:
            SystemSurfacesView()
        case .qibla:
            QiblaSheet(store: qiblaStore)
        case .mosques:
            NearbyMosquesView(store: mosqueStore)
        }
    }

    private var productionTabs: some View {
        TabView(selection: $selectedTab) {
            HomeView(
                selectedTab: $selectedTab,
                prayerStore: prayerStore,
                sessionStore: sessionStore,
                reflectionStore: reflectionStore,
                socialPrayerStore: socialPrayerStore
            )
            .tabItem { Label(L10n.text(.tabHome), systemImage: "line.3.horizontal") }
            .tag(VaktTab.home)

            NavigationStack {
                PrayerView(
                    prayerStore: prayerStore,
                    reflectionStore: reflectionStore,
                    sessionStore: sessionStore,
                    socialPrayerStore: socialPrayerStore,
                    spiritualContentStore: spiritualContentStore,
                    launchRequest: $launchRequest,
                    onReviewOpportunity: { _ in }
                )
            }
            .tabItem { Label(L10n.text(.tabPrayer), systemImage: "moon.stars") }
            .tag(VaktTab.prayer)

            SocialCircleView(
                socialPrayerStore: socialPrayerStore,
                prayerStore: prayerStore,
                referralStore: referralStore,
                subscriptionStore: subscriptionStore
            )
            .tabItem { Label(L10n.text(.tabCircle), systemImage: "person.2") }
            .tag(VaktTab.circle)

            Color.vaktBg
                .tabItem { Label(L10n.text(.tabProfile), systemImage: "smallcircle.filled.circle") }
                .tag(VaktTab.profile)
        }
        .tint(.vaktPrimary)
    }

    private func configureFixture() {
        UserDefaults.standard.set(false, forKey: StoreScreenshotRuntime.readyDefaultsKey)
        UserDefaults.standard.synchronize()
        sessionStore.clear()
        reflectionStore.clear()
        prayerStore.configureStoreScreenshotPreview(
            now: fixture.referenceDate,
            prayers: fixture.prayerSchedule
        )
        socialPrayerStore.configureStoreScreenshotPreview(
            referenceDate: fixture.referenceDate,
            calendar: StoreScreenshotFixture.calendar,
            friendNames: StoreScreenshotFixture.friendNames
        )
        mosqueStore.configureStoreScreenshotPreview()

        if scene == .markPrayer, let currentPrayer = prayerStore.activePrayer {
            sessionStore.markPrayerCompleted(for: currentPrayer, at: fixture.referenceDate)
            reflectionStore.mark(
                prayer: currentPrayer.prayer,
                prayerDate: currentPrayer.time,
                outcome: .prayed,
                markedAt: fixture.referenceDate
            )
        }

        if scene == .qibla {
            qiblaStore.configureStoreScreenshotPreview()
        }
    }
}

private struct StoreScreenshotFixture {
    let scene: StoreScreenshotScene

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        calendar.locale = VaktLocalization.appLocale
        return calendar
    }

    var referenceDate: Date {
        var components = DateComponents()
        components.calendar = Self.calendar
        components.timeZone = Self.calendar.timeZone
        components.year = 2026
        components.month = 7
        components.day = 20
        components.hour = scene == .markPrayer ? 22 : 17
        components.minute = 18
        return components.date!
    }

    var prayerSchedule: [PrayerTime] {
        let times: [(Prayer, Int, Int)] = [
            (.fajr, 4, 42),
            (.dhuhr, 12, 58),
            (.asr, 16, 56),
            (.maghrib, 20, 14),
            (.isha, 21, 48)
        ]
        var prayers = times.map { prayer, hour, minute in
            prayerTime(prayer, dayOffset: 0, hour: hour, minute: minute)
        }
        prayers.append(prayerTime(.fajr, dayOffset: 1, hour: 4, minute: 44))
        prayers.append(prayerTime(.dhuhr, dayOffset: 1, hour: 12, minute: 58))
        prayers.append(prayerTime(.asr, dayOffset: 1, hour: 16, minute: 55))
        prayers.append(prayerTime(.maghrib, dayOffset: 1, hour: 20, minute: 13))
        prayers.append(prayerTime(.isha, dayOffset: 1, hour: 21, minute: 47))
        return prayers.map { prayer in
            PrayerTime(
                prayer: prayer.prayer,
                time: prayer.time,
                countdown: max(0, prayer.time.timeIntervalSince(referenceDate)),
                timeZoneIdentifier: Self.calendar.timeZone.identifier,
                endsAt: nil
            )
        }
    }

    var quietSession: PrayerQuietSession {
        PrayerQuietSession(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000301")!,
            prayer: .asr,
            prayerDate: prayerTime(.asr, dayOffset: 0, hour: 16, minute: 56).time,
            startedAt: referenceDate.addingTimeInterval(-4 * 60),
            companionCount: 0,
            role: .primary
        )
    }

    var makeupSelectedDay: LocalPrayerDay {
        let date = Self.calendar.date(byAdding: .day, value: -1, to: referenceDate)!
        return LocalPrayerDay(date: date, calendar: Self.calendar)
    }

    private func prayerTime(
        _ prayer: Prayer,
        dayOffset: Int,
        hour: Int,
        minute: Int
    ) -> PrayerTime {
        let day = Self.calendar.date(byAdding: .day, value: dayOffset, to: referenceDate)!
        let date = Self.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        return PrayerTime(
            prayer: prayer,
            time: date,
            countdown: max(0, date.timeIntervalSince(referenceDate)),
            timeZoneIdentifier: Self.calendar.timeZone.identifier
        )
    }

    static var friendNames: [(displayName: String, username: String)] {
        switch VaktLocalization.languageCode {
        case "tr": [("Ayşe", "ayse"), ("Yusuf", "yusuf"), ("Meryem", "meryem")]
        case "ar": [("مريم", "maryam"), ("يوسف", "yusuf"), ("ليان", "layan")]
        case "fr": [("Inès", "ines"), ("Yanis", "yanis"), ("Mariam", "mariam")]
        case "de": [("Amina", "amina"), ("Yusuf", "yusuf"), ("Meryem", "meryem")]
        case "es": [("Amina", "amina"), ("Yusef", "yusef"), ("Mariam", "mariam")]
        case "it": [("Amina", "amina"), ("Yusuf", "yusuf"), ("Maryam", "maryam")]
        case "nl": [("Amina", "amina"), ("Youssef", "youssef"), ("Maryam", "maryam")]
        case "pt": [("Amina", "amina"), ("Yusuf", "yusuf"), ("Mariam", "mariam")]
        case "ru": [("Амина", "amina"), ("Юсуф", "yusuf"), ("Марьям", "maryam")]
        case "id": [("Aisyah", "aisyah"), ("Yusuf", "yusuf"), ("Maryam", "maryam")]
        case "ur": [("مریم", "maryam"), ("یوسف", "yusuf"), ("عائشہ", "aisha")]
        default: [("Amina", "amina"), ("Yusuf", "yusuf"), ("Maryam", "maryam")]
        }
    }
}
#endif

#if !DEBUG
struct StoreScreenshotPreviewRoot: View {
    let scene: StoreScreenshotScene

    var body: some View {
        EmptyView()
    }
}
#endif
