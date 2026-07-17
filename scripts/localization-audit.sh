#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

strict=false
if [[ "${1:-}" == "--strict" ]]; then
  strict=true
  shift
fi

paths=("$@")
if [[ ${#paths[@]} -eq 0 ]]; then
  paths=(Vakt)
fi

matches="$({
  rg -n \
    'Text\("|Button\("|Label\("|TextField\("|alert\("|navigationTitle\("|accessibility(Label|Hint)\("' \
    "${paths[@]}" \
    --glob '*.swift' \
    || true
} | rg -v 'Image\(systemName:' \
  | rg -v 'L10n\.' \
  | rg -v 'String\(localized:' \
  | rg -v 'Text\("\\\(' \
  | rg -v 'Text\("[0-9]' \
  | rg -v 'Text\("Vakt"\)' \
  | rg -v 'Text\("@\\\(' \
  || true)"

echo "Likely hardcoded user-facing Swift copy"
echo "======================================="
echo "Paths: ${paths[*]}"
echo

if [[ -z "$matches" ]]; then
  echo "No likely hardcoded release copy found."
  exit 0
fi

printf '%s\n' "$matches"
count="$(printf '%s\n' "$matches" | wc -l | tr -d ' ')"
echo
echo "$count likely hardcoded strings found."

if [[ "$strict" == true ]]; then
  exit 1
fi

echo "Report-only mode. Pass --strict and completed feature paths to enforce the gate."
