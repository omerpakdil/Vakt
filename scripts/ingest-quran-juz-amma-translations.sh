#!/usr/bin/env sh
set -eu

references_seed="${1:-supabase/seeds/alquran-juz-amma.en.json}"

if [ ! -f "$references_seed" ]; then
  echo "Reference seed not found: $references_seed" >&2
  exit 1
fi

if [ -z "${SUPABASE_URL:-}" ]; then
  echo "SUPABASE_URL is required." >&2
  exit 1
fi

if [ -z "${SPIRITUAL_CONTENT_INGEST_SECRET:-}" ]; then
  echo "SPIRITUAL_CONTENT_INGEST_SECRET is required." >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

python3 - "$references_seed" "$tmpdir" <<'PY'
import json
import pathlib
import sys

seed_path = pathlib.Path(sys.argv[1])
out_dir = pathlib.Path(sys.argv[2])
seed = json.loads(seed_path.read_text(encoding="utf-8"))
references = seed["references"]

targets = [
    ("ar", "quran-uthmani", "alquran_cloud_juz_amma_ar_uthmani"),
    ("tr", "tr.diyanet", "alquran_cloud_juz_amma_tr_diyanet"),
    ("fr", "fr.hamidullah", "alquran_cloud_juz_amma_fr_hamidullah"),
    ("de", "de.bubenheim", "alquran_cloud_juz_amma_de_bubenheim"),
    ("es", "es.cortes", "alquran_cloud_juz_amma_es_cortes"),
    ("it", "it.piccardo", "alquran_cloud_juz_amma_it_piccardo"),
    ("nl", "nl.leemhuis", "alquran_cloud_juz_amma_nl_leemhuis"),
    ("pt", "pt.elhayek", "alquran_cloud_juz_amma_pt_elhayek"),
    ("ru", "ru.kuliev", "alquran_cloud_juz_amma_ru_kuliev"),
    ("id", "id.indonesian", "alquran_cloud_juz_amma_id_indonesian"),
    ("ur", "ur.jalandhry", "alquran_cloud_juz_amma_ur_jalandhry"),
]

for language_code, edition, source in targets:
    payload = {
        "source": source,
        "provider": "alquran_cloud",
        "edition": edition,
        "provider_language_code": language_code,
        "approve": True,
        "references": references,
    }
    (out_dir / f"{language_code}.json").write_text(
        json.dumps(payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
PY

for payload in "$tmpdir"/*.json; do
  language="$(basename "$payload" .json)"
  echo "Ingesting Quran translation: $language" >&2
  curl -sS -X POST "$SUPABASE_URL/functions/v1/ingest-spiritual-content" \
    -H "content-type: application/json" \
    -H "x-ingest-secret: $SPIRITUAL_CONTENT_INGEST_SECRET" \
    --data @"$payload"
  echo >&2
done
