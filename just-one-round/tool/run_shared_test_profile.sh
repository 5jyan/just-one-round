#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
profile_file="$project_dir/.shared-test-profile.json"
device_id=''
game_id=''
gravity_switch_start_seconds="${JOR_GRAVITY_SWITCH_START_SECONDS:-0}"

usage() {
  printf 'Usage: %s [--game-id ID] <flutter-device-id>\n' "$0" >&2
}

while (($#)); do
  case "$1" in
    --game-id)
      game_id="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -* )
      printf 'Unknown option: %s\n' "$1" >&2
      usage
      exit 2
      ;;
    *)
      if [[ -n "$device_id" ]]; then
        printf 'Only one device ID may be supplied.\n' >&2
        usage
        exit 2
      fi
      device_id="$1"
      shift
      ;;
  esac
done

if [[ -z "$device_id" ]]; then
  usage
  exit 2
fi
if [[ ! "$gravity_switch_start_seconds" =~ ^[0-9]+$ ]]; then
  printf 'JOR_GRAVITY_SWITCH_START_SECONDS must be a non-negative integer.\n' >&2
  exit 2
fi
if [[ ! -f "$profile_file" ]]; then
  printf 'Missing local shared profile file: %s\n' "$profile_file" >&2
  exit 1
fi

JOR_TEST_GAME_ID="$game_id" "$project_dir/tool/ensure_shared_test_profile.sh"

api_url='https://jor-api.shook.party'
if xcrun simctl list devices booted | grep -Fq "$device_id"; then
  api_url='http://127.0.0.1:54321'
fi

cd "$project_dir"
exec flutter run -d "$device_id" \
  --dart-define-from-file="$profile_file" \
  --dart-define="SUPABASE_URL=$api_url" \
  --dart-define="GRAVITY_SWITCH_START_SECONDS=$gravity_switch_start_seconds"
