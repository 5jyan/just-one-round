#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_SCRIPT="$SCRIPT_DIR/check_push_worker.sh"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

MOCK_BIN="$TEMP_DIR/bin"
mkdir -p "$MOCK_BIN"
CALL_LOG="$TEMP_DIR/calls.log"

cat > "$MOCK_BIN/curl" <<'MOCK_CURL'
#!/usr/bin/env bash
set -euo pipefail

output_file=""
request_url=""
args=("$@")
for ((index = 0; index < ${#args[@]}; index++)); do
  case "${args[$index]}" in
    --output)
      index=$((index + 1))
      output_file="${args[$index]}"
      ;;
    http://*|https://*)
      request_url="${args[$index]}"
      ;;
  esac
done

printf '%s\n' "$request_url" >> "$MOCK_CURL_CALL_LOG"
printf '%s\n' '{"status":"ok"}' > "$output_file"
printf '%s' '200'
MOCK_CURL
chmod +x "$MOCK_BIN/curl"

if ! output="$({
  PATH="$MOCK_BIN:$PATH" \
    MOCK_CURL_CALL_LOG="$CALL_LOG" \
    PUSH_WORKER_SECRET='test-only-secret' \
    PUSH_WORKER_URL='http://mock.local/functions/v1/send-social-push' \
    "$CHECK_SCRIPT"
} 2>&1)"; then
  printf '%s\n' "$output" >&2
  printf '%s\n' 'check_push_worker.sh mock health check failed' >&2
  exit 1
fi

if [[ "$output" != *'Push worker check passed'* ]]; then
  printf '%s\n' "$output" >&2
  printf '%s\n' 'check_push_worker.sh did not report success' >&2
  exit 1
fi

if [[ "$(wc -l < "$CALL_LOG" | tr -d ' ')" != '1' ]]; then
  printf '%s\n' 'check_push_worker.sh made more than one worker request' >&2
  exit 1
fi

if [[ "$(sed -n '1p' "$CALL_LOG")" != 'http://mock.local/functions/v1/send-social-push?health=1' ]]; then
  printf '%s\n' 'check_push_worker.sh did not use the non-claiming health endpoint' >&2
  exit 1
fi

printf '%s\n' 'check_push_worker.sh health-only regression passed'
