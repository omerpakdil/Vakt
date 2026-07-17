begin;

create table public.spiritual_reflections (
    id uuid primary key default gen_random_uuid(),
    content_type text not null,
    language_code text not null default 'en',
    text text not null,
    source_title text not null,
    reference text,
    grade text,
    tags text[] not null default '{}',
    weight integer not null default 100,
    approved boolean not null default false,
    active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),

    constraint spiritual_reflections_type_check
        check (content_type in ('quran', 'hadith', 'dua', 'reflection')),
    constraint spiritual_reflections_language_check
        check (language_code ~ '^[a-z]{2}(-[A-Z]{2})?$'),
    constraint spiritual_reflections_text_check
        check (length(trim(text)) between 12 and 520),
    constraint spiritual_reflections_source_check
        check (length(trim(source_title)) between 2 and 120),
    constraint spiritual_reflections_weight_check
        check (weight between 1 and 1000),
    constraint spiritual_reflections_quran_reference_check
        check (content_type <> 'quran' or reference is not null),
    constraint spiritual_reflections_hadith_reference_check
        check (content_type <> 'hadith' or reference is not null)
);

create index spiritual_reflections_read_idx
    on public.spiritual_reflections (language_code, approved, active, weight desc);

create index spiritual_reflections_tags_idx
    on public.spiritual_reflections using gin (tags);

alter table public.spiritual_reflections enable row level security;
alter table public.spiritual_reflections force row level security;

revoke all on table public.spiritual_reflections from anon, authenticated;
grant select on table public.spiritual_reflections to anon, authenticated;

create policy "approved active spiritual reflections are readable"
on public.spiritual_reflections
for select
to anon, authenticated
using (approved = true and active = true);

insert into public.spiritual_reflections
    (content_type, language_code, text, source_title, reference, tags, weight, approved)
values
    (
        'reflection',
        'en',
        'May Allah accept this prayer and keep your heart close to Him.',
        'Vakt reflection',
        null,
        array['salah', 'after_salah', 'acceptance', 'gratitude'],
        90,
        true
    ),
    (
        'reflection',
        'en',
        'Every return to prayer matters. Come back gently, and keep going.',
        'Vakt reflection',
        null,
        array['salah', 'after_salah', 'returning', 'steadiness'],
        86,
        true
    ),
    (
        'reflection',
        'en',
        'Allah''s mercy is wider than a difficult day. Begin again with the next prayer.',
        'Vakt reflection',
        null,
        array['salah', 'after_salah', 'mercy', 'returning'],
        84,
        true
    ),
    (
        'reflection',
        'en',
        'Fajr begins the day with remembrance before the world becomes loud.',
        'Vakt reflection',
        null,
        array['salah', 'after_salah', 'fajr', 'remembrance'],
        78,
        true
    ),
    (
        'reflection',
        'en',
        'Dhuhr is a pause in the middle of the day, a quiet return to what matters.',
        'Vakt reflection',
        null,
        array['salah', 'after_salah', 'dhuhr', 'steadiness'],
        78,
        true
    ),
    (
        'reflection',
        'en',
        'Asr asks for steadiness while the day is still moving.',
        'Vakt reflection',
        null,
        array['salah', 'after_salah', 'asr', 'steadiness'],
        78,
        true
    ),
    (
        'reflection',
        'en',
        'Maghrib closes the light of the day with gratitude.',
        'Vakt reflection',
        null,
        array['salah', 'after_salah', 'maghrib', 'gratitude'],
        78,
        true
    ),
    (
        'reflection',
        'en',
        'Isha leaves the night quieter, with your prayer kept before sleep.',
        'Vakt reflection',
        null,
        array['salah', 'after_salah', 'isha', 'remembrance'],
        78,
        true
    );

commit;
