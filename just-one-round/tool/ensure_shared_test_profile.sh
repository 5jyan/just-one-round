#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
profile_file="${JOR_SHARED_TEST_PROFILE_FILE:-$project_dir/.shared-test-profile.json}"
profile_id='b732c7b5-5f66-4c84-8740-8726a59719cd'
identity_id='38ed0930-09a2-4a1d-94ff-9694a86b7281'
game_id="${JOR_TEST_GAME_ID:-}"
production_profile="${JOR_PRODUCTION_PROFILE:-0}"

if [[ ! -f "$profile_file" ]]; then
  printf 'Missing local shared profile file: %s\n' "$profile_file" >&2
  exit 1
fi
if ! docker ps --format '{{.Names}}' | grep -qx 'supabase_db_just-one-round'; then
  printf 'Local Supabase database is not running.\n' >&2
  exit 1
fi

profile_email="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["SHARED_TEST_PROFILE_EMAIL"])' "$profile_file")"
profile_password="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["SHARED_TEST_PROFILE_PASSWORD"])' "$profile_file")"

if [[ "$production_profile" == '1' ]]; then
  game_id=''
fi
if [[ -n "$game_id" && ! "$game_id" =~ ^[a-z0-9_]+$ ]]; then
  printf 'Invalid test game ID: %s\n' "$game_id" >&2
  exit 2
fi
if [[ -n "$game_id" ]]; then
  game_exists="$(
    docker exec -i supabase_db_just-one-round \
      psql -U postgres -d postgres -At -v game_id="$game_id" <<'SQL'
select exists(select 1 from public.games where id = :'game_id');
SQL
  )"
  if [[ "$game_exists" != t ]]; then
    printf 'Requested test game does not exist: %s\n' "$game_id" >&2
    exit 3
  fi
fi

docker exec -i supabase_db_just-one-round psql -U postgres -d postgres \
  -v ON_ERROR_STOP=1 \
  -v profile_id="$profile_id" \
  -v identity_id="$identity_id" \
  -v profile_email="$profile_email" \
  -v profile_password="$profile_password" \
  -v production_profile="$production_profile" \
  -v game_id="$game_id" <<'SQL'
insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  is_anonymous
) values (
  '00000000-0000-0000-0000-000000000000'::uuid,
  :'profile_id'::uuid,
  'authenticated',
  'authenticated',
  :'profile_email',
  extensions.crypt(:'profile_password', extensions.gen_salt('bf')),
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"display_name":"공용테스트","email_verified":true}'::jsonb,
  now(),
  now(),
  false
) on conflict (id) do update set
  email = excluded.email,
  encrypted_password = excluded.encrypted_password,
  email_confirmed_at = excluded.email_confirmed_at,
  raw_app_meta_data = excluded.raw_app_meta_data,
  raw_user_meta_data = excluded.raw_user_meta_data,
  updated_at = now(),
  is_anonymous = false;

insert into auth.identities (
  id,
  provider_id,
  user_id,
  identity_data,
  provider,
  created_at,
  updated_at
) values (
  :'identity_id'::uuid,
  :'profile_id',
  :'profile_id'::uuid,
  jsonb_build_object(
    'sub', :'profile_id',
    'email', :'profile_email',
    'email_verified', true,
    'phone_verified', false
  ),
  'email',
  now(),
  now()
) on conflict (provider_id, provider) do update set
  user_id = excluded.user_id,
  identity_data = excluded.identity_data,
  updated_at = now();

insert into public.profiles (id, nickname, is_test_account, test_game_id)
values (
  :'profile_id'::uuid,
  '공용테스트',
  :'production_profile' <> '1',
  case when :'production_profile' = '1' then null else nullif(:'game_id', '') end
)
on conflict (id) do update set
  nickname = excluded.nickname,
  is_test_account = excluded.is_test_account,
  test_game_id = case
    when :'production_profile' = '1' then null
    when :'game_id' = '' then public.profiles.test_game_id
    else excluded.test_game_id
  end,
  updated_at = now();

-- Developer-only games stay inactive in migrations so they cannot enter the
-- public daily rotation. The local shared profile still needs to open its
-- explicitly selected game, so enable that one in the local database only.
update public.games
set is_active = true
where id = nullif(:'game_id', '');
SQL

if [[ "$production_profile" == '1' ]]; then
  printf 'Production-like local profile ready: %s\n' "$profile_id"
elif [[ -n "$game_id" ]]; then
  printf 'Shared test profile ready: %s (%s)\n' "$profile_id" "$game_id"
else
  printf 'Shared test profile ready: %s (game selection preserved)\n' "$profile_id"
fi
