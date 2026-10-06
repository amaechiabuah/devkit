# shellcheck shell=bash
# Fakes for publish_build's dependencies (scripts/_publish.sh), shared by test-publish.sh and the resume tests in
# test-release-extensions.sh. Source this after creating "$TMP/bin" and putting it on PATH. It writes gh, aws and
# curl there and makes them executable. The caller exports ASSETS (a directory holding extension.zip and
# extension.zip.sig), S3 and CONSOLE (scratch directories standing in for the bucket and the console's records),
# and LOG (where every stubbed call is appended).
#
# gh also answers the release-lifecycle calls scripts/release-extensions.sh itself makes (create/view, and the
# immutable-flag api lookup), so one gh stub serves both test files. It tells that lookup apart from publish_build's
# digest lookup, which hits the same `gh api repos/{owner}/{repo}/releases/tags/<tag>` shape with a different --jq.

cat > "$TMP/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$LOG"
case "$1 $2" in
  "release download") while [ $# -gt 0 ]; do [ "$1" = -D ] && cp "$ASSETS"/* "$2"/; shift; done ;;
  "release create") exit "${GH_CREATE_RC:-0}" ;;
  "release view") [ "${GH_VIEW_RC:-0}" = 0 ] || exit "${GH_VIEW_RC}"
                   printf '%s\n' "${GH_ASSETS:-extension.zip,extension.zip.sig}" ;;
  "api repos/{owner}/{repo}/releases/tags/"*)
    if [[ "$*" == *'assets[]'* ]]; then printf '%s\n' "${GH_DIGEST-sha256:$ZSHA}"
    else printf '%s\n' "${GH_IMMUTABLE:-true}"; fi ;;
esac
EOF

cat > "$TMP/bin/aws" <<'EOF'
#!/usr/bin/env bash
echo "aws $*" >> "$LOG"
key=""; body=""; out=""; while [ $# -gt 0 ]; do case "$1" in --key) key=$2 ;; --body) body=$2 ;; esac; out=$1; shift; done
obj="$S3/$(echo "$key" | tr / _)"
if grep -q put-object <<<"$(tail -1 "$LOG")"; then
  [ -f "$obj" ] && { echo "An error occurred (PreconditionFailed) when calling the PutObject operation" >&2; exit 254; }
  cp "$body" "$obj"; echo '{}'
else cp "$obj" "$out"; fi
EOF

cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
# Console stub: versions and artifacts live as files under $CONSOLE. Prints body then a final line with the code.
echo "curl $*" | sed -E 's/Api-Key [^ ]+/Api-Key ***/' >> "$LOG"
url=""; data=""; method=GET
while [ $# -gt 0 ]; do case "$1" in -X) method=$2; shift ;; --data|-d) data=$2; method=${method/GET/POST}; shift ;; http*) url=$1 ;; esac; shift; done
case "$method $url" in
  "GET "*"/versions/?version="*) cat "$CONSOLE/versions.json" 2>/dev/null || echo '[]' ;;
  "POST "*"/versions/") [ -n "${RACE:-}" ] && [ ! -f "$CONSOLE/raced" ] && { touch "$CONSOLE/raced"; echo '[{"uuid":"v-1"}]' > "$CONSOLE/versions.json"; echo '{"version":["1.0.0 already exists for this extension."]}'; exit 22; }
                         echo '[{"uuid":"v-1"}]' > "$CONSOLE/versions.json"; echo '{"uuid":"v-1"}' ;;
  "GET "*"/artifacts/?sdk_version="*) cat "$CONSOLE/artifacts.json" 2>/dev/null || echo '[]' ;;
  "POST "*"/artifacts/") echo "[$data]" > "$CONSOLE/artifacts.json"; echo "$data" ;;
esac
EOF

chmod +x "$TMP/bin/gh" "$TMP/bin/aws" "$TMP/bin/curl"
