-- Prevent an opt-out from allowing an already queued social push to be sent.

alter table public.push_notification_outbox
  add column if not exists suppressed_at timestamptz,
  add column if not exists lease_token uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.push_notification_outbox'::regclass
      and conname = 'push_notification_outbox_sent_or_suppressed_check'
  ) then
    alter table public.push_notification_outbox
      add constraint push_notification_outbox_sent_or_suppressed_check
      check (sent_at is null or suppressed_at is null);
  end if;
end;
$$;

drop index if exists public.push_notification_outbox_pending_idx;
create index push_notification_outbox_pending_idx
  on public.push_notification_outbox(created_at)
  where sent_at is null and suppressed_at is null;

drop index if exists public.push_notification_outbox_claim_idx;
create index push_notification_outbox_claim_idx
  on public.push_notification_outbox(processing_until, created_at)
  where sent_at is null and suppressed_at is null and attempt_count < 5;

create or replace function public.set_social_notifications_enabled(enabled boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare
  current_user_id uuid := (select auth.uid());
begin
  update public.profiles
  set social_notifications_enabled = enabled,
      updated_at = now()
  where id = current_user_id;

  if enabled is false then
    update public.push_notification_outbox
    set suppressed_at = now(),
        processing_until = null,
        lease_token = null,
        last_error = 'suppressed by user preference'
    where recipient_id = current_user_id
      and sent_at is null
      and suppressed_at is null;
  end if;
end;
$$;

create or replace function public.claim_push_notification_jobs(batch_limit integer default 50)
returns setof public.push_notification_outbox
language plpgsql security definer set search_path = '' as $$
begin
  return query
  with candidates as (
    select id
    from public.push_notification_outbox
    where sent_at is null
      and suppressed_at is null
      and attempt_count < 5
      and (processing_until is null or processing_until < now())
    order by created_at
    for update skip locked
    limit least(greatest(coalesce(batch_limit, 50), 1), 50)
  )
  update public.push_notification_outbox outbox
  set processing_until = now() + interval '10 minutes',
      lease_token = gen_random_uuid()
  from candidates
  where outbox.id = candidates.id
    and outbox.sent_at is null
    and outbox.suppressed_at is null
  returning outbox.*;
end;
$$;
