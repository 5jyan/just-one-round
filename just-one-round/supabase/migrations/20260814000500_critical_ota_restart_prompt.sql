-- Allow operations to request a restart prompt only when a Shorebird patch has
-- actually been downloaded. Clients already running the latest patch ignore
-- the directive even while it remains enabled.

alter table public.app_runtime_config
add column critical_ota_prompt_enabled boolean not null default false,
add column critical_ota_prompt_message text not null default
  '중요한 업데이트가 준비됐어요. 앱을 완전히 종료한 뒤 다시 열어주세요.';

comment on column public.app_runtime_config.critical_ota_prompt_enabled is
  'When true, clients download an available Shorebird patch and prompt for restart.';
comment on column public.app_runtime_config.critical_ota_prompt_message is
  'Operator-controlled message shown after the Shorebird patch is ready.';

create function public.get_critical_ota_directive()
returns jsonb
language sql
stable
security definer set search_path = ''
as $$
  select jsonb_build_object(
    'enabled', coalesce(config.critical_ota_prompt_enabled, false),
    'message', coalesce(
      nullif(trim(config.critical_ota_prompt_message), ''),
      '중요한 업데이트가 준비됐어요. 앱을 완전히 종료한 뒤 다시 열어주세요.'
    )
  )
  from public.app_runtime_config config
  where config.id;
$$;

revoke all on function public.get_critical_ota_directive() from public;
grant execute on function public.get_critical_ota_directive()
  to anon, authenticated;
