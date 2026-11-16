#!/usr/bin/env bash
# Copies the shared baseline into every Margin Copilot repo and installs the pre-commit hook.
# Safe to re-run: LICENSE, the hook config and ci.yml are baseline-owned and overwritten
# (put a repo's own CI jobs in another workflow file); README.md is only created if missing;
# missing baseline lines are appended to .gitignore.
# Usage: [GITHUB_ORG=<org>] docs/templates/apply-baseline.sh <workspace-dir>   (GITHUB_ORG defaults to margin-copilot)
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
workspace="${1:?usage: apply-baseline.sh <workspace-dir>}"
org="${GITHUB_ORG:-margin-copilot}"
license_body="$(gh api licenses/mit --jq .body | sed -e 's/\[year\]/2026/' -e 's/\[fullname\]/Margin Copilot contributors/')"

while IFS='|' read -r name visibility description; do
  repo="$workspace/$name"
  [ "$visibility" = public ] && printf '%s\n' "$license_body" > "$repo/LICENSE"
  cp "$here/repo-baseline/.pre-commit-config.yaml" "$repo/.pre-commit-config.yaml"
  mkdir -p "$repo/.github/workflows"
  cp "$here/repo-baseline/ci.yml" "$repo/.github/workflows/ci.yml"
  touch "$repo/.gitignore"
  while IFS= read -r line; do
    grep -qxF -- "$line" "$repo/.gitignore" || printf '%s\n' "$line" >> "$repo/.gitignore"
  done < "$here/repo-baseline/gitignore"
  if [ "$name" != docs ] && [ ! -e "$repo/README.md" ]; then
    template="$here/repo-baseline/README.md"
    [ "$visibility" = private ] && template="$here/repo-baseline/README.private.md"
    sed -e "s|{{NAME}}|$name|g" -e "s|{{ORG}}|$org|g" -e "s|{{DESCRIPTION}}|$description|g" "$template" > "$repo/README.md"
  fi
  (cd "$repo" && pre-commit install >/dev/null)
  echo "baseline applied: $name"
done < "$here/repos.txt"
