#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

if [[ -n "${PUSH_WORKER_ENV_FILE:-}" ]]; then
  ENV_FILE="$PUSH_WORKER_ENV_FILE"
elif [[ $# -ge 1 ]]; then
  ENV_FILE="$1"
else
  ENV_FILE="$REPO_DIR/.env.push-worker.local"
fi

if [[ ! -f "$ENV_FILE" ]]; then
  printf '%s\n' "Push worker env file not found: $ENV_FILE" >&2
  exit 1
fi

has_non_empty_assignment() {
  local key="$1"
  awk -v key="$key" '
    /^[[:space:]]*#/ { next }
    {
      line = $0
      sub(/^[[:space:]]*/, "", line)
      if (line !~ ("^" key "[[:space:]]*=")) next
      sub(("^" key "[[:space:]]*=[[:space:]]*"), "", line)
      sub(/[[:space:]]*$/, "", line)
      first = substr(line, 1, 1)
      last = substr(line, length(line), 1)
      single_quote = sprintf("%c", 39)
      if ((first == "\"" && last == "\"") ||
          (first == single_quote && last == single_quote)) {
        line = substr(line, 2, length(line) - 2)
        sub(/^[[:space:]]*/, "", line)
        sub(/[[:space:]]*$/, "", line)
      }
      if (line != "") found = 1
    }
    END { exit(found ? 0 : 1) }
  ' "$ENV_FILE"
}

for required_key in \
  SUPABASE_URL \
  SUPABASE_SERVICE_ROLE_KEY \
  PUSH_WORKER_SECRET \
  FIREBASE_SERVICE_ACCOUNT_JSON; do
  if ! has_non_empty_assignment "$required_key"; then
    printf '%s\n' "Push worker env file is missing a non-empty $required_key" >&2
    exit 1
  fi
done

NETWORK_ID="${SUPABASE_NETWORK_ID:-supabase_network_just-one-round}"

exec npx supabase@latest functions serve send-social-push \
  --no-verify-jwt \
  --env-file "$ENV_FILE" \
  --network-id "$NETWORK_ID"
