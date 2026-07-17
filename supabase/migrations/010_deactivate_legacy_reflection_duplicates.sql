begin;

update public.spiritual_reflections
set
    active = false,
    review_note = coalesce(review_note, 'Deactivated after migration to translated Vakt reflection groups.'),
    updated_at = now()
where content_type = 'reflection'
  and language_code = 'en'
  and external_source is null
  and active = true
  and text in (
      'May Allah accept this prayer and keep your heart close to Him.',
      'Every return to salah matters. Come back gently, and keep going.',
      'Every return to prayer matters. Come back gently, and keep going.',
      'Allah''s mercy is wider than a difficult day. Begin again with the next prayer.',
      'Fajr begins the day with remembrance before the world becomes loud.',
      'Dhuhr is a pause in the middle of the day, a quiet return to what matters.',
      'Asr asks for steadiness while the day is still moving.',
      'Maghrib closes the light of the day with gratitude.',
      'Isha leaves the night quieter, with your prayer kept before sleep.'
  );

commit;
