#!/usr/bin/env bash

set -Eeuo pipefail

if (($# > 0)) && [[ "$1" == "--" ]]; then
  shift
fi

if (($# == 0)); then
  printf 'Usage: %s [--] command [args...]\n' "$0" >&2
  exit 64
fi

if [[ "$(uname -s)" == 'Darwin' ]]; then
  exec /usr/bin/caffeinate -is "$@"
fi

exec "$@"
