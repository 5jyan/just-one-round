-- Prevent a webhook retry and the periodic retry worker from sending the same
-- outbox item concurrently.

alter table public.push_notification_outbox
  add column if not exists processing_until timestamptz;

create index if not exists push_notification_outbox_claim_idx
  on public.push_notification_outbox(processing_until, created_at)
  where sent_at is null and attempt_count < 5;

create or replace function public.claim_push_notification_jobs(batch_limit integer default 50)
returns setof public.push_notification_outbox
language plpgsql security definer set search_path = '' as $$
begin
  return query
  with candidates as (
    select id
    from public.push_notification_outbox
    where sent_at is null
      and attempt_count < 5
      and (processing_until is null or processing_until < now())
    order by created_at
    for update skip locked
    limit least(greatest(coalesce(batch_limit, 50), 1), 50)
  )
  update public.push_notification_outbox outbox
  set processing_until = now() + interval '2 minutes'
  from candidates
  where outbox.id = candidates.id
  returning outbox.*;
end; $$;

revoke all on function public.claim_push_notification_jobs(integer) from public, anon, authenticated;
grant execute on function public.claim_push_notification_jobs(integer) to service_role;
