#!/usr/bin/env bash
set -euo pipefail

PUSH_WORKER_URL="${PUSH_WORKER_URL:-http://127.0.0.1:54321/functions/v1/send-social-push}"
if [[ -z "${PUSH_WORKER_SECRET:-}" ]]; then
  printf '%s\n' "PUSH_WORKER_SECRET must be set" >&2
  exit 1
fi

TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

request_worker() {
  local url="$1"
  local response_file="$2"
  curl \
    --silent \
    --show-error \
    --request POST \
    --header 'content-type: application/json' \
    --data '{}' \
    --output "$response_file" \
    --write-out '%{http_code}' \
    --config <(printf 'header = "x-push-worker-secret: %s"\n' "$PUSH_WORKER_SECRET") \
    "$url"
}

HEALTH_RESPONSE="$TEMP_DIR/health.json"
if ! HEALTH_STATUS="$(request_worker "$PUSH_WORKER_URL?health=1" "$HEALTH_RESPONSE")"; then
  printf '%s\n' "Push worker health request failed" >&2
  exit 1
fi
if [[ "$HEALTH_STATUS" != "200" ]] || ! python3 - "$HEALTH_RESPONSE" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as response_file:
        payload = json.load(response_file)
except (json.JSONDecodeError, OSError, TypeError):
    raise SystemExit(1)

if not isinstance(payload, dict) or payload.get("status") != "ok":
    raise SystemExit(1)
PY
then
  printf '%s\n' "Push worker health check failed" >&2
  exit 1
fi

printf '%s\n' "Push worker check passed"
