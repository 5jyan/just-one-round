#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  echo "Usage: $0 -- shorebird patch --platforms=android [options]" >&2
}

fail() {
  echo "with_shorebird_ota_signing: $*" >&2
  exit 1
}

if (($# > 0)) && [[ "$1" == "--" ]]; then
  shift
fi

if (($# < 3)); then
  usage
  exit 64
fi

if [[ "$(basename "$1")" != "shorebird" || "$2" != "patch" ]]; then
  fail "이 fallback은 shorebird patch에만 사용할 수 있습니다."
fi

android_platform_requested=false
previous_arg=""
for arg in "$@"; do
  if [[ "$arg" == "--platforms=android" || ( "$previous_arg" == "--platforms" && "$arg" == "android" ) ]]; then
    android_platform_requested=true
    break
  fi
  previous_arg="$arg"
done

if [[ "$android_platform_requested" != true ]]; then
  fail "Android OTA만 임시 서명 fallback을 사용할 수 있습니다."
fi

command -v openssl >/dev/null 2>&1 || fail "openssl을 찾을 수 없습니다."

keytool_bin=""
if [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/keytool" ]]; then
  keytool_bin="${JAVA_HOME}/bin/keytool"
elif [[ -x "/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home/bin/keytool" ]]; then
  keytool_bin="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home/bin/keytool"
elif command -v keytool >/dev/null 2>&1; then
  keytool_bin="$(command -v keytool)"
else
  fail "keytool을 찾을 수 없습니다."
fi

umask 077
tmp_dir="$(mktemp -d /tmp/just-one-round-shorebird-signing.XXXXXX)"

cleanup() {
  if [[ -f "$tmp_dir/upload-keystore.jks" ]]; then
    unlink "$tmp_dir/upload-keystore.jks" 2>/dev/null || true
  fi
  rmdir "$tmp_dir" 2>/dev/null || true
}
trap cleanup EXIT

store_password="$(openssl rand -hex 32)"
if ! "$keytool_bin" -genkeypair \
  -keystore "$tmp_dir/upload-keystore.jks" \
  -storetype PKCS12 \
  -storepass "$store_password" \
  -keypass "$store_password" \
  -alias upload \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -dname 'CN=Just One Round OTA Temporary, OU=Mobile, O=Just One Round, L=Seoul, ST=Seoul, C=KR' \
  >/dev/null 2>&1; then
  fail "사용 가능한 JDK keytool로 임시 keystore를 만들지 못했습니다."
fi

export ANDROID_UPLOAD_KEYSTORE="$tmp_dir/upload-keystore.jks"
export ANDROID_UPLOAD_KEY_ALIAS=upload
export ANDROID_UPLOAD_STORE_PASSWORD="$store_password"

"$@"
