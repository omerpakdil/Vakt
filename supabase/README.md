# Vakt Supabase Setup

## Current scope

The backend now covers authenticated social prayer activity, reminders, spiritual content, and referral rewards.

1. `001_presence_schema.sql` creates the two protected tables.
2. `002_presence_rpc.sql` exposes the minimal authenticated RPC surface.
3. `003_realtime_authorization.sql` authorizes private Presence channels.
4. `004_fix_rpc_conflict_targets.sql` makes presence upserts idempotent against the intended unique keys.
5. `005_realtime_channel_read_authorization.sql` permits the private-channel Broadcast read handshake while keeping client writes Presence-only.
6. `006_spiritual_reflections.sql` creates approved read-only post-prayer content.
7. `007_spiritual_reflection_ingestion.sql` adds source metadata and ingestion logs.
8. `009_spiritual_reflection_translations.sql` adds translation grouping and review metadata for localized post-prayer content.

Migration `017_referral_rewards.sql` adds referral campaigns, one-time invite claims, subscription snapshots, idempotent RevenueCat webhook events, and promotional-offer rewards.

## Required dashboard settings

- Enable Sign in with Apple and disable anonymous sign-ins for production.
- Disable public Realtime channel access.
- Use private channel topics formatted as `saf:<prayer-session-uuid>`.
- Put only `status` and a server-compatible timestamp in Presence payloads.
- Use the project publishable key in the iOS app. Never ship a secret or service-role key.

## iOS configuration

1. Duplicate `Vakt/Resources/Backend.xcconfig.example` as `Backend.xcconfig`.
2. Set the project URL and publishable key from the Supabase Connect dialog.

`Vakt.xcconfig` includes this file automatically for Debug and Release. `Backend.xcconfig` is ignored by git. An absent configuration is handled as `.notConfigured`; the app can continue using its local presence adapter during development.

## Session grouping

The resolver validates the prayer name, IANA time zone, local prayer date, and expected prayer time. It groups expected times into 15-minute buckets. This avoids storing coordinates or city names while preventing one worldwide session from mixing unrelated prayer windows.

## API surface

Authenticated clients may execute only:

- `resolve_prayer_session`
- `upsert_session_presence`
- `refresh_session_presence`
- `leave_session_presence`
- `get_session_presence_snapshot`

Direct table reads are revoked. Snapshot responses contain aggregate counts only.

The iOS app may read only `approved = true and active = true` rows from `spiritual_reflections`.
It never writes religious content and never sends a user's post-prayer reflection outcome to Supabase.

## Referral rewards

Referral codes last 30 days and can be used by multiple new customers. Claiming a code connects the two accounts as friends. A qualifying first paid subscription creates one pending reward for the inviter. The reward becomes available after 7 days, expires after 24 months, and is limited to 6 issued rewards per calendar year.

Create these App Store Connect promotional offers on the existing subscription products:

- `vakt_referral_monthly_1m` on `vakt_premium_monthly`
- `vakt_referral_yearly_1m` on `vakt_premium_yearly`

Each offer must grant one free month and be available to existing subscribers. RevenueCat must be configured to sign promotional offers.

Set Edge Function secrets without committing their values:

```sh
supabase secrets set REVENUECAT_SECRET_API_KEY=... \
  REVENUECAT_WEBHOOK_AUTH=... \
  REFERRAL_CRON_SECRET=... \
  APNS_PRIVATE_KEY=... \
  APNS_KEY_ID=... \
  APNS_TEAM_ID=... \
  APNS_TOPIC=com.callousity.vakt \
  APNS_ENVIRONMENT=production
```

Deploy the referral functions:

```sh
supabase functions deploy sync-referral-subscription
supabase functions deploy revenuecat-webhook --no-verify-jwt
supabase functions deploy finalize-referral-rewards --no-verify-jwt
```

In RevenueCat, send production webhook events to:

`https://<project-ref>.supabase.co/functions/v1/revenuecat-webhook`

Use the exact `REVENUECAT_WEBHOOK_AUTH` value as the webhook authorization header. Schedule `finalize-referral-rewards` hourly and send `Authorization: Bearer <REFERRAL_CRON_SECRET>`.

Set `VAKT_APP_STORE_ID` in the ignored `Vakt/Resources/Backend.xcconfig` so shared invitations include the final App Store URL.

## Spiritual content ingestion

Use the `ingest-spiritual-content` Edge Function to import reviewed batches into `spiritual_reflections`.
The function validates length, source metadata, references, tags, hadith grade, and external IDs before upserting.
Localized rows should share a `translation_group_id`, with one row per `language_code`.

Required function secrets:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SPIRITUAL_CONTENT_INGEST_SECRET`

Deploy:

```sh
supabase functions deploy ingest-spiritual-content
```

Import the Vakt post-prayer reflection seed in 12 languages:

```sh
export SUPABASE_URL="https://your-project-ref.supabase.co"
export SPIRITUAL_CONTENT_INGEST_SECRET="your-ingest-secret"
scripts/ingest-vakt-reflections.sh
```

The Vakt seed contains 8 reflection groups across `en`, `tr`, `ar`, `fr`, `de`, `es`, `it`, `nl`, `pt`, `ru`, `id`, and `ur`.
It is idempotent: rows are upserted by `external_source,external_id`, and translations are grouped by `translation_group_id`.
These are Vakt-authored reflection lines, not Quran or Hadith translations.

Call:

```sh
curl -X POST "$SUPABASE_URL/functions/v1/ingest-spiritual-content" \
  -H "content-type: application/json" \
  -H "x-ingest-secret: $SPIRITUAL_CONTENT_INGEST_SECRET" \
  --data @supabase/seeds/spiritual-content.sample.json
```

Import the keyless Al Quran Cloud Juz Amma bootstrap batch:

```sh
curl -X POST "$SUPABASE_URL/functions/v1/ingest-spiritual-content" \
  -H "content-type: application/json" \
  -H "x-ingest-secret: $SPIRITUAL_CONTENT_INGEST_SECRET" \
  --data @supabase/seeds/alquran-juz-amma.en.json
```

The bootstrap file stores references only. The Edge Function fetches the selected translation at ingestion time,
adds source attribution, and upserts by `external_source,external_id`.

Import the same Juz Amma reference set across the app's 11 additional languages:

```sh
export SUPABASE_URL="https://your-project-ref.supabase.co"
export SPIRITUAL_CONTENT_INGEST_SECRET="your-ingest-secret"
scripts/ingest-quran-juz-amma-translations.sh
```

The script imports Arabic Uthmani text plus Turkish, French, German, Spanish, Italian, Dutch, Portuguese,
Russian, Indonesian, and Urdu translations from Al Quran Cloud. Each verse shares a stable
`translation_group_id` formatted as `quran-<surah>-<ayah>`.

Keep `approve` as `false` for imported Quran or Hadith batches until they are manually reviewed.
Only set `approved = true` after the translation, reference, grade, and license/source are verified.
The checked-in Al Quran Cloud bootstrap is intentionally marked `approve: true` so a reviewed first batch can be
made visible immediately after ingestion. Change it to `false` if you want a manual database review step first.

Quran Foundation Content APIs are intended to be called from a backend with app credentials. Sunnah.com also requires an API key. Do not call either directly from the iOS app.
Al Quran Cloud is keyless, but keep ingestion backend-only so the app never depends on a third-party content API at runtime.

## Lease rules

- One authenticated user contributes at most one row per prayer session.
- Status changes update that row.
- Heartbeats extend the lease by 15 minutes.
- Expired rows remain harmless because snapshot queries ignore them.
- A later maintenance migration can physically delete expired rows without affecting correctness.
