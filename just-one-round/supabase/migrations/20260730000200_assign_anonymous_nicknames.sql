create sequence public.anonymous_nickname_seq
  as bigint
  minvalue 1
  maxvalue 9999999
  no cycle;

select setval(
  'public.anonymous_nickname_seq',
  greatest(
    coalesce(
      (
        select max(
          substring(p.nickname from '^신원미상#([0-9]+)$')::bigint
        )
        from public.profiles p
        where p.nickname ~ '^신원미상#[0-9]+$'
      ),
      0
    ) + 1,
    1
  ),
  false
);

revoke all on sequence public.anonymous_nickname_seq from public;
revoke all on sequence public.anonymous_nickname_seq from anon, authenticated;

create or replace function public.assign_anonymous_nickname()
returns trigger
language plpgsql
security definer set search_path = ''
as $$
begin
  if new.nickname is null then
    new.nickname :=
      '신원미상#' || nextval('public.anonymous_nickname_seq')::text;
  end if;
  return new;
end;
$$;

revoke all on function public.assign_anonymous_nickname() from public;

create trigger assign_anonymous_nickname_before_write
  before insert or update of nickname on public.profiles
  for each row
  when (new.nickname is null)
  execute function public.assign_anonymous_nickname();

update public.profiles
set nickname = null
where nickname is null;

create or replace function public.set_my_nickname(new_nickname text)
returns public.profiles
language plpgsql
security definer set search_path = ''
as $$
declare
  normalized_nickname text := btrim(new_nickname);
  compact_nickname text;
  updated_profile public.profiles;
begin
  if (select auth.uid()) is null then
    raise exception 'authentication required';
  end if;

  if char_length(normalized_nickname) not between 2 and 12 then
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

  begin
    update public.profiles
    set nickname = normalized_nickname, updated_at = now()
    where id = (select auth.uid())
    returning * into updated_profile;
  exception when unique_violation then
    raise exception 'nickname already taken' using errcode = '23505';
  end;

  return updated_profile;
end;
$$;
