export const supportedPushLanguages = [
  "en", "tr", "ar", "fr", "de", "es", "it", "nl", "pt", "ru", "id", "ur",
] as const;

export type PushLanguage = typeof supportedPushLanguages[number];
export type FriendEvent = "requested" | "accepted";

const supportedLanguageSet = new Set<string>(supportedPushLanguages);

export function normalizePushLanguage(value: string | null | undefined): PushLanguage {
  const language = (value ?? "en").trim().toLowerCase().split(/[-_]/)[0];
  return supportedLanguageSet.has(language) ? language as PushLanguage : "en";
}

export function friendEventCopy(
  language: PushLanguage,
  event: FriendEvent,
  actorName: string | null | undefined,
): { title: string; body: string } {
  const actor = cleanName(actorName) ?? friendFallback(language);

  if (event === "requested") {
    switch (language) {
      case "tr": return { title: "Yeni arkadaşlık isteği", body: `${actor} seni Vakt'te arkadaş olarak eklemek istiyor.` };
      case "ar": return { title: "طلب صداقة جديد", body: `${actor} يريد إضافتك صديقًا على Vakt.` };
      case "fr": return { title: "Nouvelle demande d’ami", body: `${actor} souhaite vous ajouter sur Vakt.` };
      case "de": return { title: "Neue Freundschaftsanfrage", body: `${actor} möchte dich auf Vakt hinzufügen.` };
      case "es": return { title: "Nueva solicitud de amistad", body: `${actor} quiere añadirte en Vakt.` };
      case "it": return { title: "Nuova richiesta di amicizia", body: `${actor} vuole aggiungerti su Vakt.` };
      case "nl": return { title: "Nieuw vriendschapsverzoek", body: `${actor} wil je toevoegen op Vakt.` };
      case "pt": return { title: "Novo pedido de amizade", body: `${actor} quer adicionar você no Vakt.` };
      case "ru": return { title: "Новый запрос в друзья", body: `${actor} хочет добавить вас в друзья в Vakt.` };
      case "id": return { title: "Permintaan pertemanan baru", body: `${actor} ingin menambahkanmu sebagai teman di Vakt.` };
      case "ur": return { title: "نئی دوستی کی درخواست", body: `${actor} آپ کو Vakt پر دوست بنانا چاہتے ہیں۔` };
      default: return { title: "New friend request", body: `${actor} wants to add you as a friend on Vakt.` };
    }
  }

  switch (language) {
    case "tr": return { title: "Arkadaşlık isteğin kabul edildi", body: `${actor} ile artık Vakt'te arkadaşsınız.` };
    case "ar": return { title: "تم قبول طلب الصداقة", body: `أصبحت أنت و${actor} صديقين على Vakt.` };
    case "fr": return { title: "Demande d’ami acceptée", body: `Vous êtes maintenant ami avec ${actor} sur Vakt.` };
    case "de": return { title: "Freundschaftsanfrage angenommen", body: `Du und ${actor} seid jetzt auf Vakt befreundet.` };
    case "es": return { title: "Solicitud de amistad aceptada", body: `Ahora tú y ${actor} son amigos en Vakt.` };
    case "it": return { title: "Richiesta di amicizia accettata", body: `Ora tu e ${actor} siete amici su Vakt.` };
    case "nl": return { title: "Vriendschapsverzoek geaccepteerd", body: `Jij en ${actor} zijn nu vrienden op Vakt.` };
    case "pt": return { title: "Pedido de amizade aceito", body: `Agora você e ${actor} são amigos no Vakt.` };
    case "ru": return { title: "Запрос в друзья принят", body: `Теперь вы и ${actor} друзья в Vakt.` };
    case "id": return { title: "Permintaan pertemanan diterima", body: `Kamu dan ${actor} sekarang berteman di Vakt.` };
    case "ur": return { title: "دوستی کی درخواست قبول ہوگئی", body: `اب آپ اور ${actor} Vakt پر دوست ہیں۔` };
    default: return { title: "Friend request accepted", body: `You and ${actor} are now friends on Vakt.` };
  }
}

export function nudgeCopy(
  language: PushLanguage,
  senderName: string | null | undefined,
  prayerKey: string,
): { title: string; body: string } {
  const sender = cleanName(senderName) ?? friendFallback(language);
  const prayer = prayerName(language, prayerKey);

  switch (language) {
    case "tr": return { title: `${sender}'den namaz hatırlatması`, body: `${sender}, ${prayer} namazını sana hatırlattı.` };
    case "ar": return { title: `تذكير بالصلاة من ${sender}`, body: `${sender} ذكّرك بصلاة ${prayer}.` };
    case "fr": return { title: `Rappel de prière de ${sender}`, body: `${sender} vous a rappelé la prière de ${prayer}.` };
    case "de": return { title: `Gebetserinnerung von ${sender}`, body: `${sender} hat dich an das ${prayer}-Gebet erinnert.` };
    case "es": return { title: `Recordatorio de oración de ${sender}`, body: `${sender} te recordó la oración de ${prayer}.` };
    case "it": return { title: `Promemoria di preghiera da ${sender}`, body: `${sender} ti ha ricordato la preghiera di ${prayer}.` };
    case "nl": return { title: `Gebedsherinnering van ${sender}`, body: `${sender} herinnerde je aan het ${prayer}-gebed.` };
    case "pt": return { title: `Lembrete de oração de ${sender}`, body: `${sender} lembrou você da oração de ${prayer}.` };
    case "ru": return { title: `Напоминание о намазе от ${sender}`, body: `${sender} напоминает вам о намазе ${prayer}.` };
    case "id": return { title: `Pengingat salat dari ${sender}`, body: `${sender} mengingatkanmu tentang salat ${prayer}.` };
    case "ur": return { title: `${sender} کی طرف سے نماز کی یاد دہانی`, body: `${sender} نے آپ کو نمازِ ${prayer} یاد دلائی۔` };
    default: return { title: `Prayer reminder from ${sender}`, body: `${sender} reminded you about ${prayer}.` };
  }
}

export function referralRewardCopy(language: PushLanguage): { title: string; body: string } {
  switch (language) {
    case "tr": return { title: "Bir ücretsiz ayın hazır", body: "Davet ödülünü Vakt’imden kullanabilirsin." };
    case "ar": return { title: "شهرك المجاني جاهز", body: "يمكنك استخدام مكافأة الدعوة من صفحة حسابك في Vakt." };
    case "fr": return { title: "Votre mois offert est prêt", body: "Utilisez votre récompense d’invitation depuis votre profil Vakt." };
    case "de": return { title: "Dein kostenloser Monat ist bereit", body: "Löse deine Einladungsprämie in deinem Vakt-Profil ein." };
    case "es": return { title: "Tu mes gratis está listo", body: "Canjea tu recompensa por invitación desde tu perfil de Vakt." };
    case "it": return { title: "Il tuo mese gratuito è pronto", body: "Riscatta il premio invito dal tuo profilo Vakt." };
    case "nl": return { title: "Je gratis maand staat klaar", body: "Gebruik je uitnodigingsbeloning via je Vakt-profiel." };
    case "pt": return { title: "Seu mês grátis está pronto", body: "Resgate sua recompensa de convite no seu perfil do Vakt." };
    case "ru": return { title: "Ваш бесплатный месяц готов", body: "Активируйте награду за приглашение в профиле Vakt." };
    case "id": return { title: "Bulan gratismu sudah siap", body: "Gunakan hadiah undangan dari profil Vakt-mu." };
    case "ur": return { title: "آپ کا مفت مہینہ تیار ہے", body: "اپنے Vakt پروفائل سے دعوتی انعام استعمال کریں۔" };
    default: return { title: "Your free month is ready", body: "Redeem your referral reward from your Vakt profile." };
  }
}

function prayerName(language: PushLanguage, prayerKey: string): string {
  const names: Record<PushLanguage, Record<string, string>> = {
    en: { fajr: "Fajr", dhuhr: "Dhuhr", asr: "Asr", maghrib: "Maghrib", isha: "Isha" },
    tr: { fajr: "Sabah", dhuhr: "Öğle", asr: "İkindi", maghrib: "Akşam", isha: "Yatsı" },
    ar: { fajr: "الفجر", dhuhr: "الظهر", asr: "العصر", maghrib: "المغرب", isha: "العشاء" },
    fr: { fajr: "Fajr", dhuhr: "Dhuhr", asr: "Asr", maghrib: "Maghrib", isha: "Isha" },
    de: { fajr: "Fadschr", dhuhr: "Dhuhr", asr: "Asr", maghrib: "Maghrib", isha: "Ischa" },
    es: { fajr: "Fajr", dhuhr: "Dhuhr", asr: "Asr", maghrib: "Maghrib", isha: "Isha" },
    it: { fajr: "Fajr", dhuhr: "Dhuhr", asr: "Asr", maghrib: "Maghrib", isha: "Isha" },
    nl: { fajr: "Fajr", dhuhr: "Dhuhr", asr: "Asr", maghrib: "Maghrib", isha: "Isha" },
    pt: { fajr: "Fajr", dhuhr: "Dhuhr", asr: "Asr", maghrib: "Maghrib", isha: "Isha" },
    ru: { fajr: "Фаджр", dhuhr: "Зухр", asr: "Аср", maghrib: "Магриб", isha: "Иша" },
    id: { fajr: "Subuh", dhuhr: "Zuhur", asr: "Asar", maghrib: "Magrib", isha: "Isya" },
    ur: { fajr: "فجر", dhuhr: "ظہر", asr: "عصر", maghrib: "مغرب", isha: "عشاء" },
  };
  return names[language][prayerKey] ?? names[language].dhuhr;
}

function friendFallback(language: PushLanguage): string {
  switch (language) {
    case "tr": return "Bir arkadaşın";
    case "ar": return "أحد أصدقائك";
    case "fr": return "Un ami";
    case "de": return "Ein Freund";
    case "es": return "Un amigo";
    case "it": return "Un amico";
    case "nl": return "Een vriend";
    case "pt": return "Um amigo";
    case "ru": return "Ваш друг";
    case "id": return "Seorang teman";
    case "ur": return "آپ کے ایک دوست";
    default: return "A friend";
  }
}

function cleanName(value: string | null | undefined): string | null {
  const name = value?.trim();
  return name ? name.slice(0, 80) : null;
}
