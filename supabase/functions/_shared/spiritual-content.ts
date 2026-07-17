export type SpiritualContentType = "quran" | "hadith" | "dua" | "reflection";

export type IngestItem = {
  content_type: SpiritualContentType;
  language_code?: string;
  text: string;
  source_title: string;
  reference?: string;
  grade?: string;
  tags?: string[];
  weight?: number;
  external_source?: string;
  external_id?: string;
  source_url?: string;
  translation_group_id?: string;
  translation_source?: string;
  translation_status?: "original" | "machine" | "source_imported" | "human_reviewed";
};

export type NormalizedIngestItem = Required<
  Pick<
    IngestItem,
    | "content_type"
    | "language_code"
    | "text"
    | "source_title"
    | "tags"
    | "weight"
    | "translation_group_id"
    | "translation_status"
  >
> &
  Pick<
    IngestItem,
    | "reference"
    | "grade"
    | "external_source"
    | "external_id"
    | "source_url"
    | "translation_source"
  >;

const allowedTypes = new Set<SpiritualContentType>(["quran", "hadith", "dua", "reflection"]);
const allowedTranslationStatuses = new Set(["original", "machine", "source_imported", "human_reviewed"]);
const rejectedHadithGrades = new Set(["weak", "daif", "da'if", "fabricated", "mawdu", "mawdoo", "unknown"]);
const usefulTags = new Set([
  "acceptance",
  "after_salah",
  "asr",
  "dua",
  "dhuhr",
  "fajr",
  "gratitude",
  "isha",
  "jumuah",
  "maghrib",
  "mercy",
  "patience",
  "quran",
  "remembrance",
  "returning",
  "salah",
  "steadiness",
  "wudu",
]);

export function normalizeItem(item: IngestItem): NormalizedIngestItem {
  if (!allowedTypes.has(item.content_type)) {
    throw new Error(`Unsupported content_type: ${String(item.content_type)}`);
  }

  const text = normalizeWhitespace(item.text);
  const sourceTitle = normalizeWhitespace(item.source_title);
  const reference = normalizeOptional(item.reference);
  const grade = normalizeOptional(item.grade);
  const languageCode = normalizeLanguage(item.language_code ?? "en");
  const tags = normalizeTags(item.tags ?? []);
  const weight = normalizeWeight(item.weight ?? 100);
  const externalSource = normalizeOptional(item.external_source);
  const externalID = normalizeOptional(item.external_id);
  const sourceURL = normalizeOptional(item.source_url);
  const translationGroupID = normalizeIdentifier(item.translation_group_id ?? externalID ?? "");
  const translationSource = normalizeOptional(item.translation_source);
  const translationStatus = normalizeTranslationStatus(item.translation_status ?? "original");

  const minimumTextLength = item.content_type === "quran" ? 1 : 12;
  if (text.length < minimumTextLength || text.length > 520) {
    throw new Error(`Text must be between ${minimumTextLength} and 520 characters.`);
  }
  if (sourceTitle.length < 2 || sourceTitle.length > 120) {
    throw new Error("source_title must be between 2 and 120 characters.");
  }
  if ((externalSource && !externalID) || (!externalSource && externalID)) {
    throw new Error("external_source and external_id must be provided together.");
  }
  if (!translationGroupID) {
    throw new Error("translation_group_id or external_id is required.");
  }
  if ((item.content_type === "quran" || item.content_type === "hadith") && !reference) {
    throw new Error(`${item.content_type} content requires a reference.`);
  }
  if (item.content_type === "hadith") {
    if (!grade) {
      throw new Error("Hadith content requires a grade.");
    }
    if (rejectedHadithGrades.has(grade.toLowerCase())) {
      throw new Error(`Rejected hadith grade: ${grade}`);
    }
  }

  return {
    content_type: item.content_type,
    language_code: languageCode,
    text,
    source_title: sourceTitle,
    reference,
    grade,
    tags,
    weight,
    external_source: externalSource,
    external_id: externalID,
    source_url: sourceURL,
    translation_group_id: translationGroupID,
    translation_source: translationSource,
    translation_status: translationStatus,
  };
}

function normalizeWhitespace(value: string): string {
  return String(value ?? "").replace(/\s+/g, " ").trim();
}

function normalizeOptional(value?: string): string | undefined {
  const normalized = normalizeWhitespace(value ?? "");
  return normalized.length > 0 ? normalized : undefined;
}

function normalizeLanguage(value: string): string {
  const normalized = normalizeWhitespace(value);
  if (!/^[a-z]{2}(-[A-Z]{2})?$/.test(normalized)) {
    throw new Error(`Invalid language code: ${normalized}`);
  }
  return normalized;
}

function normalizeIdentifier(value: string): string | undefined {
  const normalized = normalizeWhitespace(value)
    .toLowerCase()
    .replace(/[^a-z0-9_-]/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");

  return normalized.length > 0 ? normalized : undefined;
}

function normalizeTranslationStatus(value: string): "original" | "machine" | "source_imported" | "human_reviewed" {
  const normalized = normalizeWhitespace(value).toLowerCase();
  if (!allowedTranslationStatuses.has(normalized)) {
    throw new Error(`Invalid translation_status: ${normalized}`);
  }

  return normalized as "original" | "machine" | "source_imported" | "human_reviewed";
}

function normalizeWeight(value: number): number {
  if (!Number.isFinite(value)) {
    return 100;
  }
  return Math.min(1000, Math.max(1, Math.round(value)));
}

function normalizeTags(tags: string[]): string[] {
  const normalized = new Set<string>(["salah", "after_salah"]);

  for (const tag of tags) {
    const clean = normalizeWhitespace(tag)
      .toLowerCase()
      .replace(/[^a-z0-9_]/g, "_")
      .replace(/_+/g, "_")
      .replace(/^_|_$/g, "");

    if (clean && usefulTags.has(clean)) {
      normalized.add(clean);
    }
  }

  return Array.from(normalized).sort();
}
