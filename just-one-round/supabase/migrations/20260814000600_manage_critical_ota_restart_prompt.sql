-- Keep the runtime-config table private while giving trusted operations a
-- single audited RPC for enabling, changing, or clearing the OTA prompt.

create function public.set_critical_ota_directive(
  enabled boolean,
  message text default null
)
returns jsonb
language plpgsql
security definer set search_path = ''
as $$
declare
  updated_config public.app_runtime_config;
begin
  update public.app_runtime_config
  set
    critical_ota_prompt_enabled = enabled,
    critical_ota_prompt_message = case
      when message is null or trim(message) = ''
        then critical_ota_prompt_message
      else trim(message)
    end,
    updated_at = now()
  where id
  returning * into updated_config;

  return jsonb_build_object(
    'enabled', updated_config.critical_ota_prompt_enabled,
    'message', updated_config.critical_ota_prompt_message,
    'updated_at', updated_config.updated_at
  );
end;
$$;

revoke all on function public.set_critical_ota_directive(boolean, text)
  from public, anon, authenticated;
grant execute on function public.set_critical_ota_directive(boolean, text)
  to service_role;
