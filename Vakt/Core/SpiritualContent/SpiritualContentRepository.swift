import Foundation
import Supabase

protocol SpiritualContentRepository: Sendable {
    func contents(languageCode: String) async throws -> [SpiritualContent]
}

struct LocalSpiritualContentRepository: SpiritualContentRepository {
    func contents(languageCode: String) async throws -> [SpiritualContent] {
        Self.defaultContents.filter { $0.languageCode == languageCode }
    }
}

actor SupabaseSpiritualContentRepository: SpiritualContentRepository {
    private let client: SupabaseClient
    private let fallback: any SpiritualContentRepository

    init(
        client: SupabaseClient,
        fallback: any SpiritualContentRepository = LocalSpiritualContentRepository()
    ) {
        self.client = client
        self.fallback = fallback
    }

    func contents(languageCode: String) async throws -> [SpiritualContent] {
        do {
            let rows: [SupabaseSpiritualContentRow] = try await client
                .from("spiritual_reflections")
                .select("""
                    id,content_type,text,source_title,reference,grade,language_code,tags,weight
                    """)
                .eq("language_code", value: languageCode)
                .order("weight", ascending: false)
                .limit(180)
                .execute()
                .value

            let contents = rows.compactMap(SpiritualContent.init(row:))
            return contents.isEmpty ? try await fallback.contents(languageCode: languageCode) : contents
        } catch {
            return try await fallback.contents(languageCode: languageCode)
        }
    }
}

private struct SupabaseSpiritualContentRow: Decodable, Sendable {
    let id: UUID
    let contentType: String
    let text: String
    let sourceTitle: String
    let reference: String?
    let grade: String?
    let languageCode: String
    let tags: [String]
    let weight: Int

    enum CodingKeys: String, CodingKey {
        case id
        case contentType = "content_type"
        case text
        case sourceTitle = "source_title"
        case reference
        case grade
        case languageCode = "language_code"
        case tags
        case weight
    }
}

private extension SpiritualContent {
    init?(row: SupabaseSpiritualContentRow) {
        guard let kind = SpiritualContentKind(rawValue: row.contentType) else {
            return nil
        }

        self.init(
            id: row.id.uuidString,
            kind: kind,
            text: row.text,
            sourceTitle: row.sourceTitle,
            reference: row.reference,
            grade: row.grade,
            languageCode: row.languageCode,
            tags: Set(row.tags),
            weight: row.weight
        )
    }
}

extension LocalSpiritualContentRepository {
    static let defaultContents: [SpiritualContent] = defaultReflectionGroups.flatMap { group in
        group.translations.map { languageCode, text in
            SpiritualContent(
                id: "local-\(group.id)-\(languageCode)",
                kind: .reflection,
                text: text,
                sourceTitle: sourceTitle(languageCode: languageCode),
                languageCode: languageCode,
                tags: group.tags,
                weight: group.weight
            )
        }
    }

    private static func sourceTitle(languageCode: String) -> String {
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

    private static let defaultReflectionGroups: [DefaultReflectionGroup] = [
        DefaultReflectionGroup(
            id: "after-salah-acceptance",
            tags: ["salah", "after_salah", "acceptance", "gratitude"],
            weight: 90,
            translations: [
                "en": "May Allah accept this prayer and keep your heart close to Him.",
                "tr": "Allah namazını kabul etsin ve kalbini Kendisine yakın tutsun.",
                "ar": "تقبل الله صلاتك، وجعل قلبك قريباً منه.",
                "id": "Semoga Allah menerima salatmu dan menjaga hatimu dekat kepada-Nya.",
                "ur": "اللہ آپ کی نماز قبول فرمائے اور آپ کے دل کو اپنے قریب رکھے۔",
                "ru": "Пусть Аллах примет эту молитву и сохранит сердце близким к Нему.",
                "fr": "Qu'Allah accepte cette prière et garde ton coeur proche de Lui.",
                "de": "Möge Allah dieses Gebet annehmen und dein Herz nahe bei Ihm halten.",
                "es": "Que Allah acepte esta oración y mantenga tu corazón cerca de Él.",
                "it": "Che Allah accetti questa preghiera e tenga il tuo cuore vicino a Lui.",
                "nl": "Moge Allah dit gebed aanvaarden en je hart dicht bij Hem houden.",
                "pt": "Que Allah aceite esta oração e mantenha seu coração perto Dele."
            ]
        ),
        DefaultReflectionGroup(
            id: "after-salah-returning",
            tags: ["salah", "after_salah", "returning", "steadiness"],
            weight: 86,
            translations: [
                "en": "Every return to prayer matters. Come back gently, and keep going.",
                "tr": "Namaza her dönüş kıymetlidir. Sakince dön ve devam et.",
                "ar": "كل عودة إلى الصلاة لها قدرها. عُد برفق، وواصل الطريق.",
                "id": "Setiap kembali kepada salat itu berarti. Kembalilah dengan lembut, lalu teruskan.",
                "ur": "نماز کی طرف ہر واپسی قیمتی ہے۔ نرمی سے لوٹیں اور چلتے رہیں۔",
                "ru": "Каждое возвращение к молитве важно. Возвращайся мягко и продолжай.",
                "fr": "Chaque retour à la prière compte. Reviens doucement et continue.",
                "de": "Jede Rückkehr zum Gebet zählt. Komm sanft zurück und geh weiter.",
                "es": "Cada regreso a la oración importa. Vuelve con calma y sigue adelante.",
                "it": "Ogni ritorno alla preghiera conta. Torna con dolcezza e continua.",
                "nl": "Elke terugkeer naar het gebed telt. Keer rustig terug en ga verder.",
                "pt": "Cada retorno à oração importa. Volte com calma e continue."
            ]
        ),
        DefaultReflectionGroup(
            id: "after-salah-mercy",
            tags: ["salah", "after_salah", "mercy", "returning"],
            weight: 84,
            translations: [
                "en": "Allah's mercy is wider than a difficult day. Begin again with the next prayer.",
                "tr": "Allah'ın rahmeti zor bir günden daha geniştir. Bir sonraki namazla yeniden başla.",
                "ar": "رحمة الله أوسع من يوم صعب. ابدأ من جديد مع الصلاة القادمة.",
                "id": "Rahmat Allah lebih luas daripada hari yang berat. Mulailah lagi pada salat berikutnya.",
                "ur": "اللہ کی رحمت ایک مشکل دن سے کہیں وسیع ہے۔ اگلی نماز کے ساتھ دوبارہ شروع کریں۔",
                "ru": "Милость Аллаха шире трудного дня. Начни снова со следующей молитвы.",
                "fr": "La miséricorde d'Allah dépasse une journée difficile. Recommence avec la prochaine prière.",
                "de": "Allahs Barmherzigkeit ist weiter als ein schwerer Tag. Beginne mit dem nächsten Gebet neu.",
                "es": "La misericordia de Allah es más amplia que un día difícil. Empieza de nuevo con la próxima oración.",
                "it": "La misericordia di Allah è più ampia di una giornata difficile. Ricomincia con la prossima preghiera.",
                "nl": "Allahs barmhartigheid is ruimer dan een moeilijke dag. Begin opnieuw met het volgende gebed.",
                "pt": "A misericórdia de Allah é maior que um dia difícil. Recomece com a próxima oração."
            ]
        ),
        DefaultReflectionGroup(
            id: "fajr-light",
            tags: ["salah", "after_salah", "fajr", "remembrance"],
            weight: 78,
            translations: [
                "en": "Fajr begins the day with remembrance before the world becomes loud.",
                "tr": "Sabah namazı, dünya kalabalıklaşmadan günü zikirle başlatır.",
                "ar": "يفتتح الفجر اليوم بالذكر قبل أن يعلو ضجيج الدنيا.",
                "id": "Fajr memulai hari dengan zikir sebelum dunia menjadi ramai.",
                "ur": "فجر دنیا کے شور سے پہلے دن کو ذکر کے ساتھ شروع کرتی ہے۔",
                "ru": "Фаджр начинает день с поминания, прежде чем мир станет шумным.",
                "fr": "Fajr ouvre la journée par le rappel, avant que le monde ne devienne bruyant.",
                "de": "Fajr beginnt den Tag mit Gedenken, bevor die Welt laut wird.",
                "es": "Fajr comienza el día con recuerdo antes de que el mundo se vuelva ruidoso.",
                "it": "Fajr apre il giorno con il ricordo, prima che il mondo diventi rumoroso.",
                "nl": "Fajr begint de dag met gedenken voordat de wereld druk wordt.",
                "pt": "Fajr começa o dia com recordação antes que o mundo fique barulhento."
            ]
        ),
        DefaultReflectionGroup(
            id: "dhuhr-pause",
            tags: ["salah", "after_salah", "dhuhr", "steadiness"],
            weight: 78,
            translations: [
                "en": "Dhuhr is a pause in the middle of the day, a quiet return to what matters.",
                "tr": "Öğle namazı günün ortasında bir duruştur; önemli olana sessiz bir dönüş.",
                "ar": "الظهر وقفة في منتصف اليوم، وعودة هادئة إلى ما يهم.",
                "id": "Dhuhr adalah jeda di tengah hari, kembali dengan tenang kepada yang penting.",
                "ur": "ظہر دن کے بیچ ایک ٹھہراؤ ہے، اہم چیز کی طرف خاموش واپسی۔",
                "ru": "Зухр — пауза посреди дня, тихое возвращение к главному.",
                "fr": "Dhuhr est une pause au milieu du jour, un retour calme à l'essentiel.",
                "de": "Dhuhr ist eine Pause mitten am Tag, eine stille Rückkehr zu dem, was zählt.",
                "es": "Dhuhr es una pausa a mitad del día, un regreso tranquilo a lo que importa.",
                "it": "Dhuhr è una pausa nel mezzo della giornata, un ritorno quieto a ciò che conta.",
                "nl": "Dhuhr is een pauze midden op de dag, een stille terugkeer naar wat telt.",
                "pt": "Dhuhr é uma pausa no meio do dia, um retorno calmo ao que importa."
            ]
        ),
        DefaultReflectionGroup(
            id: "asr-steadiness",
            tags: ["salah", "after_salah", "asr", "steadiness"],
            weight: 78,
            translations: [
                "en": "Asr asks for steadiness while the day is still moving.",
                "tr": "İkindi, gün hâlâ akarken senden sebat ister.",
                "ar": "يدعوك العصر إلى الثبات والنهار لا يزال يمضي.",
                "id": "Asr mengajakmu tetap teguh saat hari masih berjalan.",
                "ur": "عصر دن کے چلتے رہنے میں ثابت قدمی کا تقاضا کرتی ہے۔",
                "ru": "Аср зовет к стойкости, пока день всё еще движется.",
                "fr": "Asr appelle à la constance tandis que la journée continue d'avancer.",
                "de": "Asr ruft zur Beständigkeit, während der Tag noch in Bewegung ist.",
                "es": "Asr pide firmeza mientras el día sigue avanzando.",
                "it": "Asr chiede fermezza mentre il giorno è ancora in movimento.",
                "nl": "Asr vraagt om standvastigheid terwijl de dag nog doorgaat.",
                "pt": "Asr pede firmeza enquanto o dia ainda está em movimento."
            ]
        ),
        DefaultReflectionGroup(
            id: "maghrib-gratitude",
            tags: ["salah", "after_salah", "maghrib", "gratitude"],
            weight: 78,
            translations: [
                "en": "Maghrib closes the light of the day with gratitude.",
                "tr": "Akşam namazı, günün ışığını şükürle kapatır.",
                "ar": "يغلق المغرب نور اليوم بالشكر.",
                "id": "Maghrib menutup cahaya hari dengan syukur.",
                "ur": "مغرب دن کی روشنی کو شکر کے ساتھ بند کرتی ہے۔",
                "ru": "Магриб закрывает свет дня благодарностью.",
                "fr": "Maghrib referme la lumière du jour avec gratitude.",
                "de": "Maghrib schließt das Licht des Tages mit Dankbarkeit.",
                "es": "Maghrib cierra la luz del día con gratitud.",
                "it": "Maghrib chiude la luce del giorno con gratitudine.",
                "nl": "Maghrib sluit het licht van de dag af met dankbaarheid.",
                "pt": "Maghrib encerra a luz do dia com gratidão."
            ]
        ),
        DefaultReflectionGroup(
            id: "isha-rest",
            tags: ["salah", "after_salah", "isha", "remembrance"],
            weight: 78,
            translations: [
                "en": "Isha leaves the night quieter, with your prayer kept before sleep.",
                "tr": "Yatsı, uykudan önce kılınan namazla geceyi daha sakin bırakır.",
                "ar": "تترك العشاء الليل أهدأ، وقد قُدمت صلاتك قبل النوم.",
                "id": "Isha membuat malam lebih tenang, dengan salatmu terjaga sebelum tidur.",
                "ur": "عشاء رات کو زیادہ پرسکون چھوڑتی ہے، نیند سے پہلے نماز کے ساتھ۔",
                "ru": "Иша делает ночь тише, когда молитва совершена перед сном.",
                "fr": "Isha rend la nuit plus paisible, avec ta prière gardée avant le sommeil.",
                "de": "Isha lässt die Nacht stiller werden, mit deinem Gebet vor dem Schlaf.",
                "es": "Isha deja la noche más tranquila, con tu oración antes del descanso.",
                "it": "Isha lascia la notte più quieta, con la tua preghiera prima del sonno.",
                "nl": "Isha maakt de nacht stiller, met je gebed voor het slapen.",
                "pt": "Isha deixa a noite mais tranquila, com sua oração antes do sono."
            ]
        )
    ]
}

private struct DefaultReflectionGroup {
    let id: String
    let tags: Set<String>
    let weight: Int
    let translations: [String: String]
}
