-- The restart instruction is now the fixed primary heading in the client.
-- Keep the operator-controlled message concise so it does not repeat it.

alter table public.app_runtime_config
alter column critical_ota_prompt_message set default
  '중요한 업데이트가 준비됐어요.';

update public.app_runtime_config
set
  critical_ota_prompt_message = '중요한 업데이트가 준비됐어요.',
  updated_at = now()
where id
  and critical_ota_prompt_message =
    '중요한 업데이트가 준비됐어요. 앱을 완전히 종료한 뒤 다시 열어주세요.';
