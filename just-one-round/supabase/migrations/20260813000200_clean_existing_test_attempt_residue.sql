-- Repair accounts that left test mode before the deactivation cleanup was
-- introduced. Normal ranked attempts are always linked from
-- daily_play_sessions in the current play-choice flow; tester attempts are
-- not. Restrict the one-time repair to today's normal-mode profiles and
-- preserve every linked ranked attempt.
delete from public.attempts attempt
using public.profiles profile
where profile.id = attempt.user_id
  and not coalesce(profile.is_test_account, false)
  and attempt.play_date = public.current_play_date()
  and not exists (
    select 1
    from public.daily_play_sessions session
    where session.attempt_id = attempt.id
  );
