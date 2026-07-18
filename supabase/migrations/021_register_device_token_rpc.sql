begin;

create or replace function public.register_device_token(
    p_token text,
    p_platform text default 'ios',
    p_language_code text default 'en'
)
returns public.device_tokens
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller_id uuid := auth.uid();
    normalized_token text := lower(trim(p_token));
    normalized_language text := lower(split_part(trim(p_language_code), '-', 1));
    registered_token public.device_tokens;
begin
    if caller_id is null then
        raise exception 'authentication required' using errcode = '42501';
    end if;

    if normalized_token = '' or length(normalized_token) > 512 then
        raise exception 'invalid device token' using errcode = '22023';
    end if;

    if p_platform <> 'ios' then
        raise exception 'unsupported device platform' using errcode = '22023';
    end if;

    if normalized_language not in ('en', 'tr', 'ar', 'fr', 'de', 'es', 'it', 'nl', 'pt', 'ru', 'id', 'ur') then
        normalized_language := 'en';
    end if;

    insert into public.device_tokens (
        user_id,
        token,
        platform,
        language_code,
        updated_at
    )
    values (
        caller_id,
        normalized_token,
        p_platform,
        normalized_language,
        now()
    )
    on conflict (token) do update
    set user_id = caller_id,
        platform = excluded.platform,
        language_code = excluded.language_code,
        updated_at = now()
    returning * into registered_token;

    return registered_token;
end;
$$;

revoke all on function public.register_device_token(text, text, text) from public, anon;
grant execute on function public.register_device_token(text, text, text) to authenticated;

commit;
