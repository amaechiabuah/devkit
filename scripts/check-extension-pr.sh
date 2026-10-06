#!/usr/bin/env bash
# Warn on a pull request about what each changed extension's release will need — the PR step of
# .github/workflows/extension-ci.yml. Warnings only, never a failure: authors should learn what shipping needs as
# early as possible without being blocked mid-development. scripts/release-extensions.sh is what refuses a release
# that cannot ship.
#
# For each extension the PR changes (anything under its directory since the merge base):
#   - manifest.version is unchanged, so the release job will refuse to publish the new content at the old version.
#   - a directory under skills/ has no matching skills[].folder in the manifest, so the host never registers it.
#   - the built bundle's frontend is webpack (fe/remoteEntry.js, no fe/remoteEntry.json), whose pages do not open on
#     hosts that load Native Federation remotes. Checked only when dist/extension.zip exists, i.e. after a build.
#   - the manifest id or version cannot form a bucket key, which scripts/_publish.sh's publish_build refuses.
#   - the manifest declares no resources, which the host refuses to install.
#   - the built bundle is over 268435456 bytes, which the release job refuses to publish. Checked only after a build.
#   - in one of Duplo's organizations, the manifest id is not in the extension publisher allowlist
#     (scripts/_publishers.sh) for this repository, so the release ships but the license server never gets it.
#
# Usage: ./scripts/check-extension-pr.sh <base-ref>   # e.g. origin/main; defaults to origin/$GITHUB_BASE_REF
set -euo pipefail
cd "$(dirname "$0")/.."
shopt -s nullglob

# shellcheck source=scripts/_publishers.sh
. "$(dirname "$0")/_publishers.sh"
# shellcheck source=scripts/_publish.sh
. "$(dirname "$0")/_publish.sh"
publishers_file="${PUBLISHERS_FILE:-$publishers_file}"

base_ref="${1:-origin/${GITHUB_BASE_REF:?usage: check-extension-pr.sh <base-ref>}}"
base="$(git merge-base "$base_ref" HEAD)"
warned=0
warn() { echo "::warning file=$1::$2"; warned=$((warned+1)); }

for m in extensions/*/manifest.json extension/*/manifest.json extension/manifest.json; do
  [ -f "$m" ] || continue
  dir="$(dirname "$m")"
  git diff --quiet "$base" HEAD -- "$dir" && continue

  version="$(jq -r '.version' "$m")"
  base_version="$(git show "$base:$m" 2>/dev/null | jq -r '.version // empty' 2>/dev/null || true)"
  if [ -n "$base_version" ] && [ "$base_version" = "$version" ]; then
    warn "$m" "$dir changed but manifest.version is still $version. Bump it, or the release job refuses to publish this content."
  fi

  for v in "$(jq -r '.id' "$m")" "$version"; do
    [[ "$v" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || warn "$m" "$dir — '$v' cannot form a bucket key, so the release job refuses to publish it."
  done
  jq -e '(.resources // []) | length > 0' "$m" >/dev/null \
    || warn "$m" "$dir declares no resource, so the host refuses the bundle."
  if duplo_org && ! publisher_extension_uuid "$(jq -r '.id' "$m")" "${GITHUB_REPOSITORY:-}" >/dev/null; then
    warn "$m" "$dir — $(jq -r '.id' "$m") is not in the extension publisher allowlist for ${GITHUB_REPOSITORY:-this repository}, so a release is not published to the license server."
  fi

  for s in "$dir"/skills/*/; do
    s="$(basename "$s")"
    jq -e --arg s "$s" 'any(.skills[]?.folder // ""; endswith("/skills/" + $s))' "$m" >/dev/null \
      || warn "$m" "$dir ships skills/$s but the manifest declares no skills[].folder for it, so the host never registers it."
  done

  zip="$dir/dist/extension.zip"
  if [ -f "$zip" ]; then
    [ "$(wc -c < "$zip")" -le 268435456 ] || warn "$m" "$dir builds a bundle over 268435456 bytes, which the release job refuses."
    entries="$(unzip -Z1 "$zip")"
    if grep -qx 'fe/remoteEntry.js' <<<"$entries" && ! grep -qx 'fe/remoteEntry.json' <<<"$entries"; then
      warn "$m" "$dir builds a webpack frontend (fe/remoteEntry.js). Its pages do not open on hosts that load Native Federation remotes. Migrate with the duplo-extension-ng22-migration skill."
    fi
  fi
done

echo "==> $warned release warning(s)."
