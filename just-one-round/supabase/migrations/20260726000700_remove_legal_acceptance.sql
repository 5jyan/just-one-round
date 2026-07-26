drop function if exists public.accept_legal_documents(text, text);

alter table public.profiles
  drop column if exists terms_version,
  drop column if exists privacy_version,
  drop column if exists age_confirmed_at,
  drop column if exists legal_accepted_at;
