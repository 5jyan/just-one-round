-- Build 10 is the first release that all supported clients must run.
-- Apply this migration only after the 1.0.5 (build 10) release is installable
-- from both Google Play and the App Store.

-- The compatibility RPC is intentionally callable before authentication and
-- gameplay. Older clients may register their device before calling it, so
-- device registration must not invoke current_play_date(), which rejects
-- unsupported app builds before the client can render the update screen.
create or replace function public.register_device_installation(device_hash text)
returns void
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  normalized_hash text := lower(btrim(device_hash));
  play_day date := (
    (now() at time zone 'Asia/Seoul') - interval '6 hours'
  )::date;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if normalized_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid device hash';
  end if;

  -- Do not call public.current_play_date() here: it enforces the minimum
  -- client build and would hide the required-update response from legacy apps.
  delete from public.device_daily_claims
  where play_date < play_day;

  -- An anonymous account belongs to one active installation. Detach any stale
  -- mapping while retaining its anonymous daily-claim ledger.
  update public.device_installations installation
  set user_id = null, last_seen_at = now()
  where installation.user_id = current_user_id
    and installation.device_hash <> normalized_hash;

  insert into public.device_installations (
    device_hash,
    user_id,
    last_seen_at
  ) values (
    normalized_hash,
    current_user_id,
    now()
  )
  on conflict on constraint device_installations_pkey do update
  set user_id = excluded.user_id,
      last_seen_at = excluded.last_seen_at;

  -- Deploying this protection must also cover attempts made earlier today
  -- before the app first registered its installation.
  insert into public.device_daily_claims (device_hash, play_date, claimed_at)
  select normalized_hash, attempt.play_date, min(attempt.issued_at)
  from public.attempts attempt
  where attempt.user_id = current_user_id
    and attempt.play_date = play_day
  group by attempt.play_date
  on conflict on constraint device_daily_claims_pkey do nothing;
end;
$$;

update public.app_runtime_config
set minimum_supported_build = greatest(minimum_supported_build, 10)
where id;
