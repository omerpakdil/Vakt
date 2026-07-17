begin;

alter table public.spiritual_reflections
    drop constraint if exists spiritual_reflections_text_check;

alter table public.spiritual_reflections
    add constraint spiritual_reflections_text_check
        check (
            (
                content_type = 'quran'
                and length(trim(text)) between 1 and 520
            )
            or
            (
                content_type <> 'quran'
                and length(trim(text)) between 12 and 520
            )
        );

commit;
