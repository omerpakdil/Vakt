# Vakt Localization v2

## Scope

Vakt ships in English plus 11 translated languages:

- English (`en`)
- Turkish (`tr`)
- Arabic (`ar`)
- French (`fr`)
- German (`de`)
- Spanish (`es`)
- Italian (`it`)
- Dutch (`nl`)
- Portuguese (`pt`)
- Russian (`ru`)
- Indonesian (`id`)
- Urdu (`ur`)

Release UI, accessibility text, local and remote notifications, errors, sharing,
dates, counts, prayer terminology, subscription content, and remote spiritual
content are all part of localization. Developer-only controls are excluded.

## Principles

1. `Localizable.xcstrings` is the single source of truth for app copy.
2. `InfoPlist.xcstrings` is the source of truth for permission descriptions.
3. Copy is adapted to natural religious usage in each language, not translated
   word for word.
4. English is the fallback language.
5. Arabic and Urdu are first-class RTL layouts.
6. Counts use locale-aware plural rules; dates, times, and numbers use the
   recipient's locale.
7. User-facing strings must not be embedded directly in release Swift code or
   Supabase Edge Functions.

## Delivery Order

1. Foundation: consolidate catalogs, add coverage and hardcoded-copy audits.
2. Splash, onboarding, Sign in with Apple.
3. Paywall and referral entry.
4. Home.
5. Prayer and Quiet Mode.
6. Friends, nudges, and referrals.
7. My Vakt, makeup calendar, and insights.
8. Profile, reminders, account, Qibla, modals, and secondary screens.
9. Recipient-locale push notifications and remote spiritual content validation.
10. LTR, RTL, long-copy, small-screen, and accessibility QA.

## Completion Gate

An iteration is complete only when:

- every new key has English and all 11 target translations;
- format placeholders match in every language;
- no release-facing hardcoded copy remains in the completed surface;
- Arabic and Urdu render correctly in RTL;
- the app builds and localization audits pass for that surface.
