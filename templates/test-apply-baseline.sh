#!/usr/bin/env bash
# Re-applying the baseline must keep a repo's own README and .gitignore lines.
set -uo pipefail
script="${1:?path to apply-baseline.sh}"
ws=$(mktemp -d)
while IFS='|' read -r name _ _; do git init -q "$ws/$name"; done < "$(dirname "$script")/repos.txt"
printf '# web\nService README written in M1.\n' > "$ws/web/README.md"
printf 'local.settings.json\n' > "$ws/web/.gitignore"
GITHUB_ORG=example-org "$script" "$ws" >/dev/null
fail=0
grep -q 'Service README written in M1.' "$ws/web/README.md" || { echo "FAIL: README overwritten"; fail=1; }
grep -qx 'local.settings.json' "$ws/web/.gitignore" || { echo "FAIL: repo-specific .gitignore line lost"; fail=1; }
grep -qx '.env' "$ws/web/.gitignore" || { echo "FAIL: baseline .gitignore lines missing"; fail=1; }
grep -q 'Margin Copilot: data-agent' "$ws/data-agent/README.md" || { echo "FAIL: missing README not created"; fail=1; }
grep -q 'example-org/docs' "$ws/data-agent/README.md" || { echo "FAIL: GITHUB_ORG not used in README links"; fail=1; }
grep -q '551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb  gitleaks_' "$ws/web/.github/workflows/ci.yml" || { echo "FAIL: ci.yml lacks the pinned gitleaks hash"; fail=1; }
grep -q 'checksums.txt' "$ws/web/.github/workflows/ci.yml" && { echo "FAIL: ci.yml still downloads checksums.txt"; fail=1; }
GITHUB_ORG=example-org "$script" "$ws" >/dev/null
[ "$(grep -cx '.env' "$ws/web/.gitignore")" = 1 ] || { echo "FAIL: second run duplicated .gitignore lines"; fail=1; }
rm -rf "$ws"
[ "$fail" -eq 0 ] && echo "PASS"
exit "$fail"
