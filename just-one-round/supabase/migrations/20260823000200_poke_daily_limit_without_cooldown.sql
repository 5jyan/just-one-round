-- A poke may be sent up to three times per Seoul calendar day.
-- Do not impose a per-recipient cooldown: the product rule is the daily
-- allowance, and the client only provides the immediate affordance/feedback.

create or replace function public.send_social_action(
  target_user_id uuid,
  social_action text,
  action_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  created public.social_notifications;
  current_rank integer;
  current_score integer;
  current_game_id text;
  today_seoul date := (now() at time zone 'Asia/Seoul')::date;
begin
  if current_user_id is null then
    raise exception 'authentication required';
  end if;
  if target_user_id is null or target_user_id = current_user_id then
    raise exception 'invalid recipient';
  end if;
  if social_action not in ('poke', 'boast') then
    raise exception 'invalid social action';
  end if;
  if exists (
    select 1
    from public.social_notifications
    where sender_id = current_user_id
      and request_id = action_request_id
  ) then
    return (
      select id
      from public.social_notifications
      where sender_id = current_user_id
        and request_id = action_request_id
    );
  end if;
  if not exists (
    select 1
    from public.profiles
    where id = target_user_id
      and not is_test_account
  ) then
    raise exception 'recipient unavailable';
  end if;
  if (
    select count(*)
    from public.social_notifications
    where sender_id = current_user_id
      and created_at >= now() - interval '24 hours'
  ) >= 10 then
    raise exception 'daily social action limit reached';
  end if;
  if (
    select count(*)
    from public.social_notifications
    where sender_id = current_user_id
      and action_type = social_action
      and (created_at at time zone 'Asia/Seoul')::date = today_seoul
  ) >= 3 then
    if social_action = 'poke' then
      raise exception 'daily poke limit reached';
    else
      raise exception 'daily boast limit reached';
    end if;
  end if;
  if social_action = 'boast' then
    select ranked.rank, ranked.raw_score, ranked.game_id
      into current_rank, current_score, current_game_id
    from (
      select best.user_id, best.raw_score, best.game_id,
        row_number() over (
          order by best.raw_score desc, best.submitted_at asc, best.user_id
        )::integer rank
      from (
        select distinct on (score.user_id)
          score.user_id, score.raw_score, score.game_id, score.submitted_at
        from public.scores score
        join public.profiles profile on profile.id = score.user_id
        where score.play_date = public.current_play_date()
          and not profile.is_test_account
        order by score.user_id, score.raw_score desc, score.submitted_at asc
      ) best
    ) ranked
    where ranked.user_id = current_user_id;
    if current_rank is null then
      raise exception 'today rank is not available';
    end if;
  end if;
  insert into public.social_notifications(
    sender_id,
    recipient_id,
    action_type,
    sender_rank,
    sender_score,
    sender_game_id,
    request_id
  )
  values (
    current_user_id,
    target_user_id,
    social_action,
    current_rank,
    current_score,
    current_game_id,
    action_request_id
  )
  on conflict(sender_id, request_id)
  do update set request_id = excluded.request_id
  returning * into created;
  perform public.enqueue_social_push(created);
  return created.id;
end;
$$;
