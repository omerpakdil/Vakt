#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METADATA="$ROOT_DIR/AppStoreMetadata/locales.json"

python3 - "$METADATA" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
supported = ["en", "tr", "ar", "fr", "de", "es", "it", "nl", "pt", "ru", "id", "ur"]
locales = data.get("locales", {})
fields = ["name", "subtitle", "keywords", "promotionalText", "description"]
limits = {"name": 30, "subtitle": 30, "keywords": 100, "promotionalText": 170, "description": 4000}
legacy_terms = ["join the saf", "saf presence", "anonymous saf", "safa katıl", "saf varlığı"]
failures = []

if sorted(locales) != sorted(supported):
    failures.append(f"Locales must be exactly: {', '.join(supported)}")

for locale in supported:
    values = locales.get(locale, {})
    for field in fields:
        value = values.get(field)
        if not isinstance(value, str) or not value.strip():
            failures.append(f"{locale}.{field} is missing")
            continue
        if len(value) > limits[field]:
            failures.append(f"{locale}.{field} is {len(value)} characters; limit is {limits[field]}")
        lowered = value.lower()
        for term in legacy_terms:
            if term in lowered:
                failures.append(f"{locale}.{field} contains legacy product copy: {term}")

if failures:
    print("App Store metadata audit failed")
    print("===============================")
    for failure in failures:
        print(f"- {failure}")
    raise SystemExit(1)

print(f"App Store metadata: {len(supported)} locales complete")
for locale in supported:
    values = locales[locale]
    print(
        f"{locale}: name {len(values['name'])}/30, "
        f"subtitle {len(values['subtitle'])}/30, "
        f"keywords {len(values['keywords'])}/100, "
        f"promo {len(values['promotionalText'])}/170, "
        f"description {len(values['description'])}/4000"
    )
PY
