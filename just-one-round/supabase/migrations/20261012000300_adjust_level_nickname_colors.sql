-- Adjust the level-earned nickname palette after 20261012000200.
--
-- The automatic palette is now yellow at level 5, mint at level 10, sky at
-- level 15, violet at level 20, pink at level 25, and gold at level 30.
-- Keep cyan (and the other historical tokens) in the profile constraint so
-- old rows and mixed-version clients remain readable.
--
-- Rollback is an explicit operator action: restore the 20261012000200
-- function body, backfill profiles again, then remove yellow from the
-- constraint only after no profile uses it. Do not reverse the historical
-- 300-coin refund ledger entries.

alter table public.profiles
  drop constraint if exists profiles_nickname_color_check;

alter table public.profiles
  add constraint profiles_nickname_color_check
  check (nickname_color in (
    'default',
    'coral',
    'mint',
    'cyan',
    'yellow',
    'sky',
    'violet',
    'pink',
    'gold'
  ));

create or replace function public.nickname_color_for_level(player_level integer)
returns text
language sql
immutable
strict
security definer set search_path = ''
as $$
  select case
    when player_level >= 30 then 'gold'
    when player_level >= 25 then 'pink'
    when player_level >= 20 then 'violet'
    when player_level >= 15 then 'sky'
    when player_level >= 10 then 'mint'
    when player_level >= 5 then 'yellow'
    else 'default'
  end;
$$;

revoke all on function public.nickname_color_for_level(integer)
  from public, anon, authenticated, service_role;

-- Re-apply the automatic mapping to profiles created by 20261012000200.
-- The existing before-insert/update trigger also prevents manual overrides.
update public.profiles profile
set nickname_color = public.nickname_color_for_level(
      public.experience_level(coalesce(profile.experience_points, 0))
    ),
    updated_at = now()
where profile.nickname_color is distinct from public.nickname_color_for_level(
  public.experience_level(coalesce(profile.experience_points, 0))
);

comment on function public.nickname_color_for_level(integer) is
  'Maps public.experience_level output to the automatic nickname color: yellow at level 5, mint at 10, sky at 15, violet at 20, pink at 25, and gold at 30.';
