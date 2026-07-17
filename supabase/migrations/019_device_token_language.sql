alter table public.device_tokens
    add column if not exists language_code text not null default 'en';

alter table public.device_tokens
    drop constraint if exists device_tokens_language_code_check;

alter table public.device_tokens
    add constraint device_tokens_language_code_check
        check (language_code in ('en', 'tr', 'ar', 'fr', 'de', 'es', 'it', 'nl', 'pt', 'ru', 'id', 'ur'));

comment on column public.device_tokens.language_code is
    'BCP-47 base language used to localize pushes sent to this device.';
