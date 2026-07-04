# Vakt Supabase Setup

## Current scope

These migrations provide only anonymous prayer-session presence:

1. `001_presence_schema.sql` creates the two protected tables.
2. `002_presence_rpc.sql` exposes the minimal authenticated RPC surface.
3. `003_realtime_authorization.sql` authorizes private Presence channels.
4. `004_fix_rpc_conflict_targets.sql` makes presence upserts idempotent against the intended unique keys.
5. `005_realtime_channel_read_authorization.sql` permits the private-channel Broadcast read handshake while keeping client writes Presence-only.

No location, reflection, prayer log, profile, or Saf placement is uploaded.

## Required dashboard settings

- Enable Anonymous Sign-Ins under Authentication providers.
- Configure CAPTCHA before production to limit anonymous-account abuse.
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

## Lease rules

- One authenticated user contributes at most one row per prayer session.
- Status changes update that row.
- Heartbeats extend the lease by 15 minutes.
- Expired rows remain harmless because snapshot queries ignore them.
- A later maintenance migration can physically delete expired rows without affecting correctness.
