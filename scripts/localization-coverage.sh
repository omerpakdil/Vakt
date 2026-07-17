#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG="$ROOT_DIR/Vakt/Core/Localization/Localizable.xcstrings"

python3 - "$CATALOG" "$@" <<'PY'
import json
import re
import sys
from collections import Counter
from pathlib import Path

catalog_path = Path(sys.argv[1])
filters = sys.argv[2:]
supported = ["en", "tr", "ar", "fr", "de", "es", "it", "nl", "pt", "ru", "id", "ur"]
catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
strings = catalog.get("strings", {})

keys = sorted(
    key for key in strings
    if not filters or any(key == prefix or key.startswith(prefix) for prefix in filters)
)

placeholder_pattern = re.compile(
    r"%(?!%)(?:\d+\$)?[-+0 #'I]*(?:\d+|\*)?(?:\.\d+|\.\*)?(?:hh|h|ll|l|L|z|j|t|q)?([@diuoxXfFeEgGaAcCsSp])"
)

def value_for(key, language):
    unit = strings.get(key, {}).get("localizations", {}).get(language, {}).get("stringUnit", {})
    if unit.get("state") in {"translated", "new", "needs_review"}:
        return unit.get("value")
    return None

def placeholders(value):
    return Counter(match.group(1) for match in placeholder_pattern.finditer(value or ""))

failed = False
print("Localization catalog coverage")
print("=============================")
if filters:
    print("Filters: " + ", ".join(filters))
print(f"Catalog keys: {len(keys)}")
print()

for language in supported:
    missing = [key for key in keys if value_for(key, language) is None]
    print(f"{language}: {len(keys) - len(missing)}/{len(keys)} keys", end="")
    if missing:
        failed = True
        print(f" - missing {len(missing)}")
        for key in missing[:30]:
            print(f"  - {key}")
        if len(missing) > 30:
            print(f"  ... and {len(missing) - 30} more")
    else:
        print(" - complete")

print()
print("Placeholder parity")
print("------------------")
placeholder_failures = []
for key in keys:
    source = value_for(key, "en")
    if source is None:
        continue
    expected = placeholders(source)
    for language in supported[1:]:
        translated = value_for(key, language)
        if translated is None:
            continue
        actual = placeholders(translated)
        if actual != expected:
            placeholder_failures.append((key, language, expected, actual))

if placeholder_failures:
    failed = True
    for key, language, expected, actual in placeholder_failures:
        print(f"{language} · {key}: expected {dict(expected)}, found {dict(actual)}")
else:
    print("All available translations preserve source placeholders.")

if failed:
    sys.exit(1)
PY
