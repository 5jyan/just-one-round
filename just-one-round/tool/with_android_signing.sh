#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: tool/with_android_signing.sh [--] command [args...]

Run an Android signing or release command with the Just One Round upload
keystore settings. A complete android/key.properties is used without reading
the macOS Keychain; otherwise the project-specific Keychain item supplies the
store password without printing it.
USAGE
}

fail() {
  printf 'with_android_signing.sh: %s\n' "$*" >&2
  exit 1
}

if (($# == 0)); then
  usage
  exit 64
fi

if [[ "${1:-}" == "--" ]]; then
  shift
fi

if (($# == 0)); then
  usage
  exit 64
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
ANDROID_DIR="${PROJECT_ROOT}/android"
KEY_PROPERTIES="${ANDROID_DIR}/key.properties"
DEFAULT_KEYSTORE="${ANDROID_DIR}/app/upload-keystore.jks"
KEYCHAIN_SERVICE='just-one-round-android-upload-key-20260731'
KEYCHAIN_ACCOUNT='upload'

has_nonblank_property() {
  local property_name="$1"

  awk -v wanted="$property_name" '
    /^[[:space:]]*[#!]/ { next }
    {
      separator = index($0, "=")
      if (separator == 0) next
      name = substr($0, 1, separator - 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
      if (name != wanted) next
      value = substr($0, separator + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      if (value != "") found = 1
    }
    END { exit(found ? 0 : 1) }
  ' "${KEY_PROPERTIES}"
}

property_value() {
  local property_name="$1"

  awk -v wanted="$property_name" '
    /^[[:space:]]*[#!]/ { next }
    {
      separator = index($0, "=")
      if (separator == 0) next
      name = substr($0, 1, separator - 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
      if (name != wanted) next
      value = substr($0, separator + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      found = 1
    }
    END { if (found) print value }
  ' "${KEY_PROPERTIES}"
}

key_properties_is_valid() {
  [[ -f "${KEY_PROPERTIES}" ]] || return 1
  has_nonblank_property storeFile || return 1
  has_nonblank_property storePassword || return 1
  has_nonblank_property keyAlias || return 1
  has_nonblank_property keyPassword || return 1

  local store_file
  store_file="$(property_value storeFile)"
  if [[ "${store_file}" = /* ]]; then
    [[ -f "${store_file}" ]]
  else
    [[ -f "${ANDROID_DIR}/app/${store_file}" ]]
  fi
}

keystore_override="${ANDROID_UPLOAD_KEYSTORE:-}"
if [[ -n "${keystore_override//[[:space:]]/}" ]]; then
  if [[ "${keystore_override}" = /* ]]; then
    upload_keystore="${keystore_override}"
  elif [[ "${keystore_override}" == android/* ]]; then
    upload_keystore="${PROJECT_ROOT}/${keystore_override}"
  elif [[ "${keystore_override}" == app/* ]]; then
    upload_keystore="${ANDROID_DIR}/${keystore_override}"
  else
    upload_keystore="${ANDROID_DIR}/app/${keystore_override}"
  fi
else
  upload_keystore="${DEFAULT_KEYSTORE}"
fi

key_alias="${ANDROID_UPLOAD_KEY_ALIAS:-}"
if [[ -z "${key_alias//[[:space:]]/}" ]]; then
  key_alias='upload'
fi

export ANDROID_UPLOAD_KEYSTORE="${upload_keystore}"
export ANDROID_UPLOAD_KEY_ALIAS="${key_alias}"

if ! key_properties_is_valid; then
  [[ -f "${upload_keystore}" ]] || \
    fail "upload keystore was not found at ${upload_keystore}; provide a valid ANDROID_UPLOAD_KEYSTORE or restore the project upload keystore."

  store_password="${ANDROID_UPLOAD_STORE_PASSWORD:-}"
  if [[ -z "${store_password//[[:space:]]/}" ]]; then
    [[ "$(uname -s)" == 'Darwin' ]] || \
      fail "macOS Keychain fallback is unavailable on this operating system; set a non-blank ANDROID_UPLOAD_STORE_PASSWORD or provide a complete android/key.properties."
    [[ -x /usr/bin/security ]] || \
      fail "macOS security command was not found; set a non-blank ANDROID_UPLOAD_STORE_PASSWORD or provide a complete android/key.properties."

    keychain_path="$(
      /usr/bin/security list-keychains -d user 2>/dev/null \
        | sed -n 's/^[[:space:]]*"\(.*\/login\.keychain-db\)"[[:space:]]*$/\1/p' \
        | head -n 1
    )" || keychain_path=''
    security_args=(
      find-generic-password
      -s "${KEYCHAIN_SERVICE}"
      -a "${KEYCHAIN_ACCOUNT}"
      -w
    )
    if [[ -n "${keychain_path}" ]]; then
      security_args+=("${keychain_path}")
    fi

    if ! store_password="$(
      /usr/bin/security "${security_args[@]}" 2>/dev/null
    )" || [[ -z "${store_password//[[:space:]]/}" ]]; then
      fail "Keychain lookup failed for service ${KEYCHAIN_SERVICE} and account ${KEYCHAIN_ACCOUNT}; verify the item without printing its value, or provide a non-blank ANDROID_UPLOAD_STORE_PASSWORD."
    fi
  fi
  export ANDROID_UPLOAD_STORE_PASSWORD="${store_password}"
fi

exec "$@"
