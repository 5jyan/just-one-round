-- Restore the unrelated device claim that was removed while diagnosing a
-- different account. Preserve a newer row if one has since been created.
insert into public.device_daily_claims (device_hash, play_date, claimed_at)
values (
  '6f6b79a1f976283cb15a818d7c9aa97f4fc7dd8f1e90c7bb59a321e8668782f1',
  '2026-08-13'::date,
  '2026-08-12 22:53:25.068059+00'::timestamptz
)
on conflict (device_hash, play_date) do nothing;
