#!/usr/bin/env bash
# Tests for .github/extension-publishers.json and scripts/_publishers.sh. Usage: ./tests/test-extension-publishers.sh
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
t()   { printf '  %s … ' "$1"; }
ok()  { echo "ok"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
. ./scripts/_publishers.sh
REAL=.github/extension-publishers.json
FIXTURE=tests/fixtures/extension-publishers.json
echo "extension-publishers:"

# Structural checks run against both files: the real allowlist can never gain a malformed entry either.
for F in "$REAL" "$FIXTURE"; do
  t "$F parses with schemaVersion 1"
  [ "$(jq -r .schemaVersion "$F")" = 1 ] && ok || bad "schemaVersion"
  t "$F: each manifest id appears once"
  [ "$(jq '[.publishers[].manifestId] | length == (unique | length)' "$F")" = true ] && ok || bad "duplicate id"
  t "$F: each entry names one repository and a console UUID"
  jq -e 'all(.publishers[]; (.repository | test("^[^/]+/[^/]+$")) and (.consoleExtension | test("^[0-9a-f-]{36}$")))' \
    "$F" >/dev/null && ok || bad "shape"
done

t "the real file is empty or every entry passes the shape check"
jq -e '(.publishers | length == 0) or
  all(.publishers[]; (.repository | test("^[^/]+/[^/]+$")) and (.consoleExtension | test("^[0-9a-f-]{36}$")))' \
  "$REAL" >/dev/null && ok || bad "placeholder in the real file"

publishers_file="$FIXTURE"
t "a mapped id and repository yield the UUID"
id=$(jq -r '.publishers[0].manifestId' "$FIXTURE"); repo=$(jq -r '.publishers[0].repository' "$FIXTURE")
[ "$(publisher_extension_uuid "$id" "$repo")" = "$(jq -r '.publishers[0].consoleExtension' "$FIXTURE")" ] && ok || bad "lookup"
t "an id mapped to another repository is refused"
! publisher_extension_uuid "$id" "someone/else" >/dev/null && ok || bad "accepted another repo"
t "an unknown id is refused"
! publisher_extension_uuid "duplo.nope" "$repo" >/dev/null && ok || bad "accepted unknown id"

echo; echo "passed $PASS, failed $FAIL"; [ "$FAIL" -eq 0 ]
