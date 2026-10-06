alter table public.profiles
  add column if not exists first_challenge_nickname_prompted_at timestamptz;

create or replace function public.claim_first_challenge_nickname_prompt()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  affected_rows integer := 0;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;

  update public.profiles profile
  set first_challenge_nickname_prompted_at = now(),
      updated_at = now()
  where profile.id = current_user_id
    and profile.first_challenge_nickname_prompted_at is null
    and profile.nickname ~ '^신원미상#[0-9]+$'
    and (
      select count(*)
      from public.scores score
      where score.user_id = current_user_id
    ) = 1;

  get diagnostics affected_rows = row_count;
  return affected_rows = 1;
end;
$$;

revoke all on function public.claim_first_challenge_nickname_prompt()
  from public, anon;
grant execute on function public.claim_first_challenge_nickname_prompt()
  to authenticated;

comment on function public.claim_first_challenge_nickname_prompt() is
  'Atomically claims the one-time nickname prompt after a user''s first ranked challenge.';
