#!/usr/bin/env sh
set -eu

seed_file="${1:-supabase/seeds/vakt-reflections.12-lang.json}"

if [ ! -f "$seed_file" ]; then
  echo "Seed file not found: $seed_file" >&2
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

curl -sS -X POST "$SUPABASE_URL/functions/v1/ingest-spiritual-content" \
  -H "content-type: application/json" \
  -H "x-ingest-secret: $SPIRITUAL_CONTENT_INGEST_SECRET" \
  --data @"$seed_file"
