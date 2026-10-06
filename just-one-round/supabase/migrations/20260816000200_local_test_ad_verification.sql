-- Google test ad units cannot send AdMob SSV callbacks. Allow a local
-- validation database to emulate only that callback after the client reports
-- an earned test ad. The switch defaults off in every environment.

alter table public.app_runtime_config
  add column if not exists local_test_ad_verification_enabled boolean
  not null default false;

create or replace function public.verify_local_practice_ad_for_development(
  reward_session_id uuid
)
returns void
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  target_grant public.rewarded_ad_grants;
  bypass_enabled boolean := false;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  select config.local_test_ad_verification_enabled
  into bypass_enabled
  from public.app_runtime_config config
  where config.id;
  if not coalesce(bypass_enabled, false) then
    raise exception 'local test ad verification disabled';
  end if;

  select grant_row.* into target_grant
  from public.rewarded_ad_grants grant_row
  where grant_row.id = reward_session_id
    and grant_row.user_id = current_user_id
    and grant_row.play_date = public.current_play_date()
    and grant_row.grant_purpose = 'practice'
  for update;

  if target_grant.id is null then
    raise exception 'practice reward session not found';
  end if;
  if target_grant.status in ('verified', 'consumed') then
    return;
  end if;
  if target_grant.status <> 'prepared' or target_grant.expires_at <= now() then
    raise exception 'practice reward session unavailable';
  end if;

  update public.rewarded_ad_grants
  set
    status = 'verified',
    provider_transaction_id = coalesce(
      provider_transaction_id,
      'local-test-' || id::text
    ),
    reward_item = 'practice_ticket',
    reward_amount = 2,
    verified_at = coalesce(verified_at, now())
  where id = target_grant.id;
end;
$$;

revoke all on function public.verify_local_practice_ad_for_development(uuid)
  from public, anon;
grant execute on function public.verify_local_practice_ad_for_development(uuid)
  to authenticated;

comment on column public.app_runtime_config.local_test_ad_verification_enabled
  is 'Local validation only: emulate AdMob SSV after an earned Google test ad.';
comment on function public.verify_local_practice_ad_for_development(uuid)
  is 'Verifies a prepared practice ad only when the server-side local test switch is enabled.';
