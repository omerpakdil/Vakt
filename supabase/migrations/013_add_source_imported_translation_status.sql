begin;

alter table public.spiritual_reflections
    drop constraint if exists spiritual_reflections_translation_status_check;

alter table public.spiritual_reflections
    add constraint spiritual_reflections_translation_status_check
        check (translation_status in ('original', 'machine', 'source_imported', 'human_reviewed'));

update public.spiritual_reflections
set
    translation_status = 'source_imported',
    updated_at = now()
where content_type = 'quran'
  and language_code <> 'ar'
  and external_source like 'alquran_cloud_%'
  and translation_status = 'human_reviewed';

commit;
