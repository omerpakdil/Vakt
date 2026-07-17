begin;

alter table public.spiritual_reflections
    add column if not exists translation_group_id text,
    add column if not exists translation_source text,
    add column if not exists translation_status text not null default 'original';

alter table public.spiritual_reflections
    add constraint spiritual_reflections_translation_status_check
        check (translation_status in ('original', 'machine', 'human_reviewed'));

update public.spiritual_reflections
set translation_group_id = coalesce(
    translation_group_id,
    external_id,
    lower(regexp_replace(left(text, 64), '[^a-zA-Z0-9]+', '-', 'g'))
)
where translation_group_id is null;

alter table public.spiritual_reflections
    alter column translation_group_id set not null;

create unique index if not exists spiritual_reflections_translation_language_unique
    on public.spiritual_reflections (translation_group_id, language_code);

create index if not exists spiritual_reflections_translation_group_idx
    on public.spiritual_reflections (translation_group_id);

comment on column public.spiritual_reflections.translation_group_id is
    'Stable id shared by translations of the same spiritual content item.';

comment on column public.spiritual_reflections.translation_status is
    'Translation quality state: original, machine, or human_reviewed.';

comment on column public.spiritual_reflections.translation_source is
    'Optional tool, provider, or editor that produced the translation.';

commit;
