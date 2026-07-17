begin;

update public.spiritual_reflections
set text = 'May Allah accept this prayer and keep your heart close to Him.'
where content_type = 'reflection'
  and language_code = 'en'
  and text = 'May Allah accept this salah and keep your heart close to Him.';

update public.spiritual_reflections
set text = 'Allah''s mercy is wider than a difficult day. Begin again with the next prayer.'
where content_type = 'reflection'
  and language_code = 'en'
  and text = 'Allah''s mercy is wider than a difficult day. Begin again with the next salah.';

update public.spiritual_reflections
set text = 'Isha leaves the night quieter, with your prayer kept before sleep.'
where content_type = 'reflection'
  and language_code = 'en'
  and text = 'Isha leaves the night quieter, with this salah kept before sleep.';

commit;
