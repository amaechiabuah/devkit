#!/usr/bin/env bash
# Tests for publish_build in scripts/_publish.sh. Usage: ./tests/test-publish.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
t()   { printf '  %s … ' "$1"; }
ok()  { echo "ok"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/s3" "$TMP/assets"; export PATH="$TMP/bin:$PATH" LOG="$TMP/log"
printf 'ZIPBYTES' > "$TMP/assets/extension.zip"; printf 'SIGBYTES' > "$TMP/assets/extension.zip.sig"
ZSHA=$(shasum -a 256 "$TMP/assets/extension.zip" | cut -d' ' -f1)

# shellcheck source=tests/_publish_stubs.sh
. "$(dirname "$0")/_publish_stubs.sh"
export S3="$TMP/s3" ASSETS="$TMP/assets" ZSHA CONSOLE="$TMP/console" CONSOLE_API_KEY=secret-key uuid=ext-1
. ./scripts/_publish.sh
fresh() { rm -rf "$S3"/* "$CONSOLE"; mkdir -p "$CONSOLE"; : > "$LOG"; }

echo "publish:"

t "uploads both objects create-only and registers version and artifact with the signature"
fresh; OUT=$(publish_build demo-v1.0.0-sdk-1.0.6 duplo.demo 1.0.0 1.0.6 extensions/demo 2>&1); RC=$?
if [ $RC = 0 ] && [ "$(grep -c "put-object.*--if-none-match \*" "$LOG")" = 2 ] \
   && jq -e --arg s "$ZSHA" '.[0] | .sha256 == $s and .signature == "SIGBYTES" and (.s3_path | endswith("bundles/duplo.demo/1.0.0/sdk-1.0.6/extension.zip"))' "$CONSOLE/artifacts.json" >/dev/null
then ok; else bad "rc=$RC out=$OUT"; fi

t "never sets is_published and never logs the key"
grep -q is_published "$LOG" && bad "is_published sent" || { grep -q secret-key "$LOG" "$TMP"/console/* 2>/dev/null && bad "key logged" || ok; }

t "a re-run of a finished build changes nothing"
: > "$LOG"  # Keep S3/CONSOLE state from the prior run. Clear only the log, so this run's own curls are what we check.
OUT=$(publish_build demo-v1.0.0-sdk-1.0.6 duplo.demo 1.0.0 1.0.6 extensions/demo 2>&1); RC=$?
[ $RC = 0 ] && grep -q "already uploaded" <<<"$OUT" && ! grep -q "POST" <<<"$(grep curl "$LOG")" && ok || bad "rc=$RC out=$OUT"

t "a re-run after only the zip uploaded uploads the signature"
fresh; cp "$ASSETS/extension.zip" "$S3/bundles_duplo.demo_1.0.0_sdk-1.0.6_extension.zip"
OUT=$(publish_build demo-v1.0.0-sdk-1.0.6 duplo.demo 1.0.0 1.0.6 extensions/demo 2>&1); RC=$?
[ $RC = 0 ] && [ -f "$S3/bundles_duplo.demo_1.0.0_sdk-1.0.6_extension.zip.sig" ] && ok || bad "rc=$RC out=$OUT"

t "different bytes already at a key fail the job"
fresh; printf 'OTHER' > "$S3/bundles_duplo.demo_1.0.0_sdk-1.0.6_extension.zip"
OUT=$(publish_build demo-v1.0.0-sdk-1.0.6 duplo.demo 1.0.0 1.0.6 extensions/demo 2>&1); RC=$?
[ $RC != 0 ] && grep -q "different bytes" <<<"$OUT" && ok || bad "rc=$RC out=$OUT"

t "a version created by a concurrent run is looked up again"
fresh; OUT=$(RACE=1 publish_build demo-v1.0.0-sdk-1.0.6 duplo.demo 1.0.0 1.0.6 extensions/demo 2>&1); RC=$?
[ $RC = 0 ] && [ -f "$CONSOLE/artifacts.json" ] && ok || bad "rc=$RC out=$OUT"

t "an existing artifact with a different sha256 fails the job"
fresh; echo '[{"uuid":"v-1"}]' > "$CONSOLE/versions.json"; echo '[{"sdk_version":"1.0.6","s3_path":"x","sha256":"0000","signature":"y"}]' > "$CONSOLE/artifacts.json"
OUT=$(publish_build demo-v1.0.0-sdk-1.0.6 duplo.demo 1.0.0 1.0.6 extensions/demo 2>&1); RC=$?
[ $RC != 0 ] && grep -q "differs" <<<"$OUT" && ok || bad "rc=$RC out=$OUT"

t "a missing GitHub digest falls back to hashing the downloaded asset"
fresh; OUT=$(GH_DIGEST="" publish_build demo-v1.0.0-sdk-1.0.6 duplo.demo 1.0.0 1.0.6 extensions/demo 2>&1); RC=$?
[ $RC = 0 ] && jq -e --arg s "$ZSHA" '.[0].sha256 == $s' "$CONSOLE/artifacts.json" >/dev/null && ok || bad "rc=$RC out=$OUT"

echo; echo "passed $PASS, failed $FAIL"; [ "$FAIL" -eq 0 ]
