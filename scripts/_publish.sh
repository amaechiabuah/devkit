# shellcheck shell=bash
# Sourced by scripts/release-extensions.sh. Signing is mandatory in Duplo's two organizations and skipped anywhere
# else, so a customer copy of the release workflow behaves as before with no Duplo credential. Upload and registration
# run only in Duplo's organizations, for a manifest id the allowlist maps to this repository.

# duplo_org: exit 0 when this run belongs to one of Duplo's organizations.
duplo_org() { case "${GITHUB_REPOSITORY_OWNER:-}" in duplocloud|duplocloud-internal) return 0 ;; *) return 1 ;; esac; }

# publish_build <tag> <id> <version> <sdk> <dir>: upload and register one released build (Task 8).
publish_build() { echo "==> would publish $1"; }
