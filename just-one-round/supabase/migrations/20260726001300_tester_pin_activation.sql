-- Tester activation remains server-authoritative. The app only sends the PIN;
-- clients cannot read its hash or update tester privileges directly.
alter table public.app_runtime_config
  add column tester_pin_hash text;

update public.app_runtime_config
set tester_pin_hash =
  '$2a$12$w4zt077Rw0noUPh9fw4BZeosumaDL/XjT.73mEaCW.Bo9stbKW8j.'
where id;

alter table public.app_runtime_config
  alter column tester_pin_hash set not null;

alter table public.profiles
  add column tester_pin_failures smallint not null default 0,
  add column tester_pin_locked_until timestamptz,
  add constraint profiles_tester_pin_failures_range
    check (tester_pin_failures between 0 and 4);

create function public.activate_test_mode(tester_pin text)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  current_profile public.profiles;
  stored_pin_hash text;
  next_failures smallint;
  lock_expires_at timestamptz;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  select * into current_profile
  from public.profiles
  where id = current_user_id
  for update;

  if current_profile is null then
    raise exception 'profile not found';
  end if;

  if current_profile.is_test_account then
    return jsonb_build_object('status', 'activated');
  end if;

  if current_profile.tester_pin_locked_until is not null
    and current_profile.tester_pin_locked_until > now() then
    return jsonb_build_object(
      'status', 'locked',
      'retry_after_seconds',
      ceil(extract(
        epoch from current_profile.tester_pin_locked_until - now()
      ))::integer
    );
  end if;

  select config.tester_pin_hash into stored_pin_hash
  from public.app_runtime_config config
  where config.id;

  if stored_pin_hash is null then
    raise exception 'tester activation unavailable';
  end if;

  if tester_pin is null
    or tester_pin !~ '^[0-9]{6}$'
    or extensions.crypt(tester_pin, stored_pin_hash) <> stored_pin_hash then
    next_failures := case
      when current_profile.tester_pin_locked_until <= now() then 1
      else current_profile.tester_pin_failures + 1
    end;

    if next_failures >= 5 then
      lock_expires_at := now() + interval '15 minutes';
      update public.profiles
      set
        tester_pin_failures = 0,
        tester_pin_locked_until = lock_expires_at,
        updated_at = now()
      where id = current_user_id;

      return jsonb_build_object(
        'status', 'locked',
        'retry_after_seconds', 900
      );
    end if;

    update public.profiles
    set
      tester_pin_failures = next_failures,
      tester_pin_locked_until = null,
      updated_at = now()
    where id = current_user_id;

    return jsonb_build_object(
      'status', 'invalid',
      'attempts_remaining', 5 - next_failures
    );
  end if;

  update public.profiles
  set
    is_test_account = true,
    tester_pin_failures = 0,
    tester_pin_locked_until = null,
    updated_at = now()
  where id = current_user_id;

  return jsonb_build_object('status', 'activated');
end;
$$;

revoke all on function public.activate_test_mode(text) from public;
grant execute on function public.activate_test_mode(text) to authenticated;

comment on column public.app_runtime_config.tester_pin_hash is
  'Private bcrypt hash used only by activate_test_mode().';
