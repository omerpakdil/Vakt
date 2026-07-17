import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.48.1";
import { normalizeItem } from "../_shared/spiritual-content.ts";
import type { IngestItem } from "../_shared/spiritual-content.ts";

type IngestRequest = {
  source?: string;
  approve?: boolean;
  items?: IngestItem[];
  provider?: "alquran_cloud";
  edition?: string;
  provider_language_code?: string;
  references?: string[];
};

type RejectedItem = {
  index: number;
  reason: string;
};

const jsonHeaders = {
  "content-type": "application/json; charset=utf-8",
};

serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed." }, 405);
  }

  const ingestSecret = Deno.env.get("SPIRITUAL_CONTENT_INGEST_SECRET");
  if (!ingestSecret) {
    return json({ error: "Ingestion is not configured." }, 500);
  }

  const providedSecret = request.headers.get("x-ingest-secret") ??
    request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (providedSecret !== ingestSecret) {
    return json({ error: "Unauthorized." }, 401);
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseURL || !serviceRoleKey) {
    return json({ error: "Supabase service credentials are not configured." }, 500);
  }

  let payload: IngestRequest;
  try {
    payload = await request.json();
  } catch {
    return json({ error: "Request body must be JSON." }, 400);
  }

  let providerItems: IngestItem[] = [];
  try {
    providerItems = payload.provider === "alquran_cloud"
      ? await fetchAlQuranCloudItems(
        payload.edition ?? "en.pickthall",
        payload.references ?? [],
        payload.provider_language_code,
      )
      : [];
  } catch (error) {
    return json({
      error: "Provider ingestion failed.",
      detail: error instanceof Error ? error.message : "Unknown provider error.",
    }, 502);
  }
  const items = [...(payload.items ?? []), ...providerItems];
  if (!Array.isArray(items) || items.length === 0) {
    return json({ error: "items must contain at least one content item." }, 400);
  }
  if (items.length > 250) {
    return json({ error: "A single ingestion batch can include at most 250 items." }, 400);
  }

  const source = normalizeSource(payload.source ?? "manual");
  const approve = payload.approve === true;
  const accepted = [];
  const rejected: RejectedItem[] = [];

  for (const [index, item] of items.entries()) {
    try {
      const normalized = normalizeItem({
        ...item,
        external_source: item.external_source ?? source,
      });

      if (!normalized.external_source || !normalized.external_id) {
        throw new Error("external_id is required for ingestion.");
      }

      accepted.push({
        content_type: normalized.content_type,
        language_code: normalized.language_code,
        text: normalized.text,
        source_title: normalized.source_title,
        reference: normalized.reference ?? null,
        grade: normalized.grade ?? null,
        tags: normalized.tags,
        weight: normalized.weight,
        approved: approve,
        active: true,
        external_source: normalized.external_source,
        external_id: normalized.external_id,
        source_url: normalized.source_url ?? null,
        imported_at: new Date().toISOString(),
        reviewed_at: approve ? new Date().toISOString() : null,
        review_note: approve ? "Approved during trusted ingestion." : null,
        translation_group_id: normalized.translation_group_id,
        translation_source: normalized.translation_source ?? null,
        translation_status: normalized.translation_status,
      });
    } catch (error) {
      rejected.push({
        index,
        reason: error instanceof Error ? error.message : "Unknown validation error.",
      });
    }
  }

  const supabase = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false },
  });

  let errorMessage: string | null = null;
  if (accepted.length > 0) {
    const { error } = await supabase
      .from("spiritual_reflections")
      .upsert(accepted, { onConflict: "external_source,external_id" });

    if (error) {
      errorMessage = error.message;
    }
  }

  await supabase
    .from("spiritual_reflection_ingest_runs")
    .insert({
      source,
      requested_count: items.length,
      accepted_count: errorMessage ? 0 : accepted.length,
      rejected_count: rejected.length + (errorMessage ? accepted.length : 0),
      approved_by_default: approve,
      error_message: errorMessage,
    });

  if (errorMessage) {
    return json({
      error: "Database upsert failed.",
      detail: errorMessage,
      accepted: 0,
      rejected: items.length,
      rejected_items: rejected,
    }, 500);
  }

  return json({
    source,
    approved_by_default: approve,
    requested: items.length,
    accepted: accepted.length,
    rejected: rejected.length,
    rejected_items: rejected,
  });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: jsonHeaders,
  });
}

function normalizeSource(source: string): string {
  const normalized = source
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_-]/g, "_")
    .replace(/_+/g, "_")
    .replace(/^_|_$/g, "");

  return normalized || "manual";
}

async function fetchAlQuranCloudItems(
  edition: string,
  references: string[],
  languageCode?: string,
): Promise<IngestItem[]> {
  const cleanEdition = edition.trim() || "en.pickthall";
  const cleanLanguageCode = normalizeProviderLanguageCode(languageCode, cleanEdition);
  const uniqueReferences = Array.from(new Set(references.map((reference) => reference.trim()).filter(Boolean)));

  if (uniqueReferences.length === 0) {
    throw new Error("references are required when provider is alquran_cloud.");
  }
  if (uniqueReferences.length > 220) {
    throw new Error("A single Al Quran Cloud batch can include at most 220 references.");
  }

  const parsedReferences: Array<{ reference: string; surah: number; ayah: number }> = [];
  for (const reference of uniqueReferences) {
    const match = reference.match(/^(\d{1,3}):(\d{1,3})$/);
    if (!match) {
      throw new Error(`Invalid Quran reference: ${reference}`);
    }

    const surah = Number(match[1]);
    const ayah = Number(match[2]);
    if (surah < 1 || surah > 114 || ayah < 1) {
      throw new Error(`Invalid Quran reference: ${reference}`);
    }

    parsedReferences.push({ reference, surah, ayah });
  }

  const referencesBySurah = new Map<number, Set<number>>();
  for (const parsed of parsedReferences) {
    const ayahs = referencesBySurah.get(parsed.surah) ?? new Set<number>();
    ayahs.add(parsed.ayah);
    referencesBySurah.set(parsed.surah, ayahs);
  }

  const verseLookup = parsedReferences.every((parsed) => parsed.surah >= 78 && parsed.surah <= 114)
    ? await fetchAlQuranCloudJuz30(cleanEdition)
    : await fetchAlQuranCloudSurahs(cleanEdition, referencesBySurah);

  const items: IngestItem[] = [];
  for (const parsed of parsedReferences) {
    const resolvedReference = `${parsed.surah}:${parsed.ayah}`;
    const verse = verseLookup.get(resolvedReference);
    if (!verse) {
      throw new Error(`Al Quran Cloud did not return ${resolvedReference}.`);
    }

    items.push({
      content_type: "quran",
      language_code: cleanLanguageCode,
      text: verse.text,
      source_title: quranSourceTitle(cleanLanguageCode, verse.editionName),
      reference: resolvedReference,
      tags: tagsForQuranReference(resolvedReference),
      weight: 170,
      external_source: `alquran_cloud_${cleanEdition}`,
      external_id: `${cleanEdition}_${resolvedReference}`,
      source_url: `https://api.alquran.cloud/v1/ayah/${resolvedReference}/${cleanEdition}`,
      translation_group_id: `quran-${parsed.surah}-${parsed.ayah}`,
      translation_source: "alquran.cloud",
      translation_status: cleanLanguageCode === "ar" ? "original" : "source_imported",
    });
  }

  return items;
}

function normalizeProviderLanguageCode(languageCode: string | undefined, edition: string): string {
  if (languageCode?.trim()) {
    return languageCode.trim().toLowerCase();
  }

  if (edition === "quran-uthmani" || edition === "quran-simple" || edition === "quran-simple-clean") {
    return "ar";
  }

  const prefix = edition.split(".")[0]?.toLowerCase();
  return /^[a-z]{2}$/.test(prefix) ? prefix : "en";
}

function quranSourceTitle(languageCode: string, editionName: string): string {
  if (languageCode === "ar") {
    return `Qur'an Arabic text - ${editionName}`;
  }

  return `Qur'an translation - ${editionName}`;
}

async function fetchAlQuranCloudJuz30(edition: string): Promise<Map<string, { text: string; editionName: string }>> {
  const url = `https://api.alquran.cloud/v1/juz/30/${encodeURIComponent(edition)}`;
  const payload = await fetchAlQuranCloudJSON(url, "juz 30");
  if (!Array.isArray(payload?.data?.ayahs)) {
    throw new Error("Al Quran Cloud returned an invalid response for juz 30.");
  }

  const editionName = payload.data.edition?.englishName ?? payload.data.edition?.name ?? edition;
  const verseLookup = new Map<string, { text: string; editionName: string }>();
  for (const ayah of payload.data.ayahs) {
    const surahNumber = Number(ayah?.surah?.number);
    const ayahNumber = Number(ayah?.numberInSurah);
    if (surahNumber >= 1 && ayahNumber >= 1 && typeof ayah?.text === "string") {
      verseLookup.set(`${surahNumber}:${ayahNumber}`, {
        text: ayah.text,
        editionName,
      });
    }
  }

  return verseLookup;
}

async function fetchAlQuranCloudSurahs(
  edition: string,
  referencesBySurah: Map<number, Set<number>>,
): Promise<Map<string, { text: string; editionName: string }>> {
  const verseLookup = new Map<string, { text: string; editionName: string }>();
  let requestIndex = 0;

  for (const [surah, ayahs] of referencesBySurah) {
    if (requestIndex > 0) {
      await delay(350);
    }
    requestIndex += 1;

    const url = `https://api.alquran.cloud/v1/surah/${surah}/${encodeURIComponent(edition)}`;
    const payload = await fetchAlQuranCloudJSON(url, `surah ${surah}`);
    if (!Array.isArray(payload?.data?.ayahs)) {
      throw new Error(`Al Quran Cloud returned an invalid response for surah ${surah}.`);
    }

    const editionName = payload.data.edition?.englishName ?? payload.data.edition?.name ?? edition;
    for (const ayah of payload.data.ayahs) {
      const ayahNumber = Number(ayah?.numberInSurah);
      if (ayahs.has(ayahNumber) && typeof ayah?.text === "string") {
        verseLookup.set(`${surah}:${ayahNumber}`, {
          text: ayah.text,
          editionName,
        });
      }
    }
  }

  return verseLookup;
}

async function fetchAlQuranCloudJSON(url: string, label: string): Promise<any> {
  let lastStatus = 0;

  for (let attempt = 0; attempt < 4; attempt += 1) {
    if (attempt > 0) {
      await delay(900 * attempt);
    }

    const response = await fetch(url);
    lastStatus = response.status;
    if (response.ok) {
      const payload = await response.json();
      if (payload?.code === 200) {
        return payload;
      }
      throw new Error(`Al Quran Cloud returned an invalid response for ${label}.`);
    }

    if (response.status !== 429 && response.status < 500) {
      break;
    }
  }

  throw new Error(`Al Quran Cloud request failed for ${label}: ${lastStatus}`);
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function tagsForQuranReference(reference: string): string[] {
  const tags = new Set(["quran", "salah", "after_salah", "remembrance"]);
  const [surahText] = reference.split(":");
  const surah = Number(surahText);

  if ([93, 94, 95, 99, 103, 108, 110].includes(surah)) {
    tags.add("gratitude");
  }
  if ([94, 103, 109, 112, 113, 114].includes(surah)) {
    tags.add("steadiness");
  }
  if ([93, 97, 107, 113, 114].includes(surah)) {
    tags.add("mercy");
  }
  if ([96, 97, 98].includes(surah)) {
    tags.add("patience");
  }

  return Array.from(tags).sort();
}
