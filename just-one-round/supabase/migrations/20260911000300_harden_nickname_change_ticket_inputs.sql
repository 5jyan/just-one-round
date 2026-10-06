-- Reject a null nickname before the anonymous-name trigger can replace it.
-- The mobile form never sends null, but RPC callers can still invoke the
-- function directly and must not be able to reset a custom nickname for free.

create or replace function public.set_my_nickname(new_nickname text)
returns public.profiles
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  normalized_nickname text := btrim(new_nickname);
  compact_nickname text;
  current_profile public.profiles;
  updated_profile public.profiles;
  requires_change_ticket boolean;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  if normalized_nickname is null
     or char_length(normalized_nickname) not between 2 and 12 then
    raise exception 'nickname must be between 2 and 12 characters';
  end if;
  if normalized_nickname ~ '[[:cntrl:]]' then
    raise exception 'nickname contains invalid characters';
  end if;
  if normalized_nickname ~ '^신원미상#[0-9]+$' then
    raise exception 'nickname is reserved';
  end if;

  compact_nickname := lower(
    regexp_replace(normalized_nickname, '[[:space:]._-]+', '', 'g')
  );
  if compact_nickname ~ '(시발|씨발|ㅅㅂ|병신|개새끼|좆|섹스|sex|fuck|nigger)' then
    raise exception 'nickname contains blocked language';
  end if;
  if normalized_nickname ~* '(https?://|www\.|@)'
     or normalized_nickname ~ '01[016789][[:space:]-]?[0-9]{3,4}[[:space:]-]?[0-9]{4}'
     or normalized_nickname ~ '(.)\1{4,}' then
    raise exception 'nickname contains contact or spam content';
  end if;

  select * into current_profile
  from public.profiles profile
  where profile.id = current_user_id
  for update;
  if current_profile.id is null then raise exception 'profile not found'; end if;

  requires_change_ticket := current_profile.nickname is not null
    and current_profile.nickname !~ '^신원미상#[0-9]+$'
    and current_profile.nickname <> normalized_nickname;

  begin
    if requires_change_ticket then
      update public.profiles profile
      set
        nickname = normalized_nickname,
        store_nickname_change_tickets =
          profile.store_nickname_change_tickets - 1,
        updated_at = now()
      where profile.id = current_user_id
        and profile.store_nickname_change_tickets > 0
      returning * into updated_profile;
      if updated_profile.id is null then
        raise exception 'nickname change ticket is not available';
      end if;
    else
      update public.profiles profile
      set nickname = normalized_nickname, updated_at = now()
      where profile.id = current_user_id
      returning * into updated_profile;
    end if;
  exception when unique_violation then
    raise exception 'nickname already taken' using errcode = '23505';
  end;

  return updated_profile;
end;
$$;

revoke all on function public.set_my_nickname(text) from public, anon;
grant execute on function public.set_my_nickname(text) to authenticated;
