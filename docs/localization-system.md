# Localization System

Vakt localization work is handled screen by screen, with a strict release/debug split.

## Supported Locales

Initial release locales:

- `en`
- `tr`
- `ar`
- `fr`
- `de`
- `es`
- `it`
- `nl`
- `pt`
- `ru`
- `id`
- `ur`

Arabic and Urdu must keep right-to-left layout enabled through `VaktLocalization.layoutDirection`.

## Definition Of Done

For each screen or surface:

- All user-facing strings are routed through `L10n.string(...)`, `L10n.formatString(...)`, `L10n.text(...)`, or a string catalog entry.
- Every new `L10n` key has translations for all supported release locales, not only `en`, `tr`, and `ar`.
- Dynamic strings are not hardcoded in Swift views or models.
- Accessibility labels and hints are localized when they describe user-visible behavior.
- Debug-only tools may remain English if they are inside `#if DEBUG` or otherwise simulator/developer-only.
- Prayer names come from `Prayer.displayName`, never manually typed as Fajr/Dhuhr/Asr/Maghrib/Isha in release copy.
- Build passes after the screen is completed.

## Screen Queue

| Priority | Surface | Files | Status |
| --- | --- | --- | --- |
| 1 | Onboarding shell | `OnboardingView.swift`, `VaktSplashView.swift` | Complete |
| 2 | Onboarding arrival | `OnboardingArrivalView.swift` | Complete |
| 3 | Onboarding Saf gathering | `OnboardingSafGatheringView.swift` | Complete |
| 4 | Onboarding Saf placement | `OnboardingSafPlacementView.swift` | Complete |
| 5 | Onboarding anonymous Saf | `OnboardingAnonymousSafView.swift` | Complete |
| 6 | Onboarding location | `OnboardingLocationView.swift` | Complete |
| 7 | Onboarding reminders | `OnboardingRemindersView.swift` | Complete |
| 8 | Insights / Moments | `InsightsView.swift` | Complete |
| 9 | Review prompt | `RateVaktView.swift` | Complete |
| 10 | Qibla release copy | `QiblaSheet.swift` | Complete |
| 11 | Shared accessibility | `HorizonView.swift`, tab labels | Complete |
| 12 | Developer-only profile copy | `ProfileView.swift` debug section | Deferred |

## Completed Surfaces

| Surface | Notes |
| --- | --- |
| Home | Primary titles, CTA, qibla chip, people count copy |
| Saf lobby | Header, helper text, hold/tap/completed button states |
| Quiet Salah | Quiet screen, presence events, check-in, completion fallback, spiritual source reference format |
| Saf placement | Header, footer, qibla label, slot accessibility |
| Paywall | Hero, plan rows, purchase states, footer links |
| Profile release view | Subscription, prayer times, notification, privacy, local data |
| Prayer settings models | Calculation method and Asr method titles/details |
| Notifications | Prayer reminder notification titles and bodies |
| Spiritual content kinds | Quran/Hadith/Dua/Reflection display names across all release locales |
| Onboarding shell | Splash subtitle/hold copy, onboarding progress accessibility, permission status copy |
| Onboarding arrival | Arrival title/body, demo prayer/time labels, micro-signals, continue/accessibility |
| Onboarding Saf gathering | Gathering copy, mini Saf scene labels, qibla label, status line, continue/accessibility |
| Onboarding Saf placement | Placement state copy, qibla label, slot hints/accessibility, next-step and continue states |
| Onboarding anonymous Saf | Privacy copy, anonymous trace labels, quiet line, progress and continue accessibility |
| Onboarding location | Location title/body, day arc labels, localized prayer marks, permission status copy, skip/primary actions |
| Onboarding reminders | Reminder title/body, signal accessibility, dial petal labels, whisper line, skip/primary actions |
| Insights / Moments | Period titles/subtitles, stat labels, latest entry format, private footer, companion count |
| Review prompt | Review title/body, rate/skip actions, completed prayer count |
| Qibla release copy | Compass state titles/messages, dial labels, metrics, signal quality, distance, helper guidance, qibla permission actions |
| Shared accessibility | Tab labels, profile title, Horizon legend labels, Horizon VoiceOver presence summary |

## Audit Command

Run:

```sh
scripts/localization-audit.sh
```

The command prints likely remaining Swift literals. Treat it as a review queue, not a perfect compiler. False positives include SF Symbol names, identifiers, numeric formatting, debug-only simulator tools, and intentionally branded words like `Vakt`.

Run:

```sh
scripts/localization-coverage.sh
```

This command fails when any supported locale is missing an `en` translation key. A screen can be marked `Complete` only when this passes for the keys it introduced.

Validate localized App Store metadata and Apple's field limits with:

```sh
scripts/app-store-metadata-audit.sh
```

Generate screenshots for the highest-risk release locales on an already booted
simulator with:

```sh
scripts/localization-visual-qa.sh
```

The matrix covers Arabic and Urdu RTL plus German, French, and Russian
long-copy layouts across splash, onboarding, sign-in, and paywall. Generated
screenshots live under `LocalizationQA/` and are not committed.

Remote APNs copy is localized independently from the iOS string catalog. The
app stores its current base language on each `device_tokens` row. Edge
Functions use `supabase/functions/_shared/push-localization.ts` to create a
separate payload for each recipient device, with English as the fallback.

For page-by-page work, pass key prefixes to verify only the current surface while older localization debt is still being cleared:

```sh
scripts/localization-coverage.sh onboarding.gathering placement.qibla action.continue onboarding.step_accessibility
```

## Recommended Work Order

1. Complete one row from the queue.
2. Add or reuse `L10n` keys.
3. Run `scripts/localization-audit.sh`.
4. Run an iOS simulator build.
5. Move the row to Completed Surfaces.
