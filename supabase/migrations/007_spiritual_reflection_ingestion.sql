begin;

alter table public.spiritual_reflections
    add column if not exists external_source text,
    add column if not exists external_id text,
    add column if not exists source_url text,
    add column if not exists imported_at timestamptz,
    add column if not exists reviewed_at timestamptz,
    add column if not exists review_note text;

alter table public.spiritual_reflections
    add constraint spiritual_reflections_external_pair_check
        check (
            (external_source is null and external_id is null)
            or
            (external_source is not null and external_id is not null)
        );

create unique index if not exists spiritual_reflections_external_unique
    on public.spiritual_reflections (external_source, external_id);

create table if not exists public.spiritual_reflection_ingest_runs (
    id uuid primary key default gen_random_uuid(),
    source text not null,
    requested_count integer not null default 0,
    accepted_count integer not null default 0,
    rejected_count integer not null default 0,
    approved_by_default boolean not null default false,
    error_message text,
    created_at timestamptz not null default now(),

    constraint spiritual_reflection_ingest_runs_counts_check
        check (requested_count >= 0 and accepted_count >= 0 and rejected_count >= 0)
);

alter table public.spiritual_reflection_ingest_runs enable row level security;
alter table public.spiritual_reflection_ingest_runs force row level security;

revoke all on table public.spiritual_reflection_ingest_runs from anon, authenticated;

commit;
