# Vakt Backend Architecture

## Scope of the first backend

The first backend exists to support anonymous Saf presence. It does not store:

- precise or approximate user location
- prayer reflections
- prayer completion history
- selected Saf placement
- names, avatars, contacts, or social graphs

Those features remain on-device unless a later product decision introduces an explicit sync option.

## Trust boundary

Views never talk to Supabase directly. The dependency direction is:

`Feature -> Store/Coordinator -> Repository protocol -> Supabase adapter`

The domain layer contains no Supabase types. A local adapter can therefore drive previews, tests, offline behavior, and the existing simulation without changing feature code.

## Identity

Vakt creates a Supabase anonymous auth user on first network participation. Anonymous users receive the `authenticated` database role, so every exposed table must still use RLS. The app does not create a public profile row for the initial MVP.

The Keychain-backed Supabase session is the user identity. A separate random client instance ID distinguishes two installations or concurrent connections without exposing it to other clients.

## Prayer session identity

A session is resolved from:

- prayer name
- the prayer's local calendar day
- IANA time-zone identifier

The server owns session IDs and timestamps. Clients do not decide whether a session is open using their device clock alone.

## Presence lifecycle

1. Observing Home resolves the current prayer session and opens the aggregate snapshot stream. It does not create a presence lease.
2. Entering the Saf upserts one presence lease for the authenticated user and client instance.
3. Status changes update the existing lease rather than inserting another row.
4. Refresh the lease every five minutes and on status changes.
5. Treat leases older than fifteen minutes as expired.
6. Leaving the Saf tab removes the lease but keeps session observation available to Home.
7. A prayer-session change cancels the old stream and lease before resolving the next session.
8. Reconnect with bounded exponential backoff and jitter.

Commands carry a unique command ID. The remote adapter must make retries idempotent.

## Privacy of realtime data

Feature code receives `PresenceSnapshot`, which contains counts only. It must never receive user IDs or raw presence rows. The Supabase adapter may temporarily aggregate anonymous Realtime Presence payloads internally, but those payloads must contain only a status and server timestamp.

The app keeps these values separate:

- `participantCount`: observed backend participants
- `displayPresence`: ambient visual representation

Simulated visual activity must not be presented as an exact live participant count.

## Failure behavior

- Cached snapshots are marked `isStale` and retain their original observation time.
- Offline mode does not fabricate a realtime count.
- A failed heartbeat retries without creating a second lease.
- An expired or missing lease is recreated with an idempotent upsert.
- Prayer and session changes cancel the previous stream before joining the next one.

## Planned Supabase objects

The first migration should contain only:

- `prayer_sessions`
- `session_presence`
- aggregate RPCs for session resolution and counts
- RLS policies tied to `auth.uid()`
- indexes supporting session lookup and lease expiry

Profiles, prayer logs, and Small Saf tables are intentionally deferred.
