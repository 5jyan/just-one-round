-- Store in-app support inquiries without exposing the operations table to clients.

create table public.support_inquiries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  message text not null check (char_length(message) between 5 and 1000),
  app_version text not null check (char_length(app_version) between 1 and 32),
  build_number integer not null check (build_number >= 0),
  status text not null default 'pending'
    check (status in ('pending', 'in_progress', 'answered', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index support_inquiries_user_created_idx
  on public.support_inquiries (user_id, created_at desc);
create index support_inquiries_pending_idx
  on public.support_inquiries (created_at)
  where status = 'pending';

alter table public.support_inquiries enable row level security;
revoke all on table public.support_inquiries
  from public, anon, authenticated;

create function public.submit_support_inquiry(
  inquiry_message text,
  client_app_version text,
  client_build_number integer
)
returns uuid
language plpgsql
security definer set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  normalized_message text := btrim(inquiry_message);
  normalized_version text := btrim(client_app_version);
  inquiry_id uuid;
begin
  if current_user_id is null then raise exception 'authentication required'; end if;
  if char_length(normalized_message) not between 5 and 1000 then
    raise exception 'inquiry must be between 5 and 1000 characters';
  end if;
  if char_length(normalized_version) not between 1 and 32 then
    raise exception 'app version is invalid';
  end if;
  if client_build_number is null or client_build_number < 0 then
    raise exception 'build number is invalid';
  end if;
  if (
    select count(*)
    from public.support_inquiries inquiry
    where inquiry.user_id = current_user_id
      and inquiry.created_at >= now() - interval '24 hours'
  ) >= 5 then
    raise exception 'daily inquiry limit reached';
  end if;

  insert into public.support_inquiries (
    user_id, message, app_version, build_number
  ) values (
    current_user_id,
    normalized_message,
    normalized_version,
    client_build_number
  ) returning id into inquiry_id;

  return inquiry_id;
end;
$$;

revoke all on function public.submit_support_inquiry(text, text, integer)
  from public, anon;
grant execute on function public.submit_support_inquiry(text, text, integer)
  to authenticated;

comment on table public.support_inquiries is
  'In-app support inquiries, readable only by trusted operations access.';
