# shellcheck shell=bash
# Sourced by scripts/release-extensions.sh and scripts/check-extension-pr.sh. The allowlist names which repository may
# publish each Duplo extension and which console extension record it registers under. ai-release's extension-publisher
# role trusts the same repositories, which is the boundary that matters. This file decides only whether a run tries.
#
# .github/extension-publishers.json ships empty: an entry is added once its extension's console record exists, and
# its repository must already be in ai-release's extension-publisher role trust list.

publishers_file=".github/extension-publishers.json"

# publisher_extension_uuid <manifest-id> <org/repo>: the console extension UUID when the allowlist maps the id to
# that repository, else nothing and exit 1.
publisher_extension_uuid() {
  [ -f "$publishers_file" ] || return 1
  jq -er --arg id "$1" --arg repo "$2" \
    '.publishers[] | select(.manifestId == $id and .repository == $repo) | .consoleExtension' "$publishers_file"
}
