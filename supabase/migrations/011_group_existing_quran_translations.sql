begin;

update public.spiritual_reflections
set
    translation_group_id = 'quran-' || split_part(reference, ':', 1) || '-' || split_part(reference, ':', 2),
    translation_source = coalesce(translation_source, 'alquran.cloud'),
    translation_status = case
        when language_code = 'ar' then 'original'
        else 'human_reviewed'
    end,
    updated_at = now()
where content_type = 'quran'
  and reference ~ '^[0-9]{1,3}:[0-9]{1,3}$';

commit;
