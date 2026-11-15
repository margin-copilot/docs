#!/usr/bin/env bash
# Copies the shared baseline into every Margin Copilot repo and installs the pre-commit hook.
# Usage: docs/templates/apply-baseline.sh <workspace-dir>
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
workspace="${1:?usage: apply-baseline.sh <workspace-dir>}"
license_body="$(gh api licenses/mit --jq .body | sed -e 's/\[year\]/2026/' -e 's/\[fullname\]/Margin Copilot contributors/')"

while IFS='|' read -r name visibility description; do
  repo="$workspace/$name"
  [ "$visibility" = public ] && printf '%s\n' "$license_body" > "$repo/LICENSE"
  cp "$here/repo-baseline/.pre-commit-config.yaml" "$repo/.pre-commit-config.yaml"
  mkdir -p "$repo/.github/workflows"
  cp "$here/repo-baseline/ci.yml" "$repo/.github/workflows/ci.yml"
  cp "$here/repo-baseline/gitignore" "$repo/.gitignore"
  if [ "$name" != docs ]; then
    template="$here/repo-baseline/README.md"
    [ "$visibility" = private ] && template="$here/repo-baseline/README.private.md"
    sed -e "s|{{NAME}}|$name|g" -e "s|{{DESCRIPTION}}|$description|g" "$template" > "$repo/README.md"
  fi
  (cd "$repo" && pre-commit install >/dev/null)
  echo "baseline applied: $name"
done < "$here/repos.txt"
