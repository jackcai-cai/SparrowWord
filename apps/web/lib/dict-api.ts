import {
  type ActivityItem,
  type ActivityMeta,
  inferLookupKind,
  type LookupKind,
  type LookupResult,
  type ReverseLookupMatch,
  resolveWorkspaceState,
  type SuggestionItem,
  type WorkspaceState,
} from "./mock-workspace";
import { dictApiBaseUrl } from "./dict-api-base";

type ApiEnvelope<T> = {
  request_id: string;
  ok: boolean;
  data: T | null;
  error: {
    code: string;
    message: string;
  } | null;
};

type LookupApiData = {
  query: string;
  mode: "lookup" | "reverse" | "no-result";
  entry: {
    id: string;
    headword: string;
    lemma: string;
    phonetic: string;
    level: string;
    summary: string;
    source_tags: string[];
    meaning_groups: Array<{
      partOfSpeech: string;
      definitions: string[];
    }>;
    senses: Array<{
      sense_id: string;
      pos: string;
      gloss_zh: string;
    }>;
    english_definitions: string[];
    inflection_lines: string[];
    collocations: string[];
    related_terms: string[];
    examples: Array<{
      english: string;
      chinese: string;
    }>;
  } | null;
  reverse_items?: ReverseLookupApiData["items"];
};

type SuggestApiData = {
  query: string;
  items: Array<{
    id: string;
    headword: string;
    lemma: string;
    pos: "correction" | "related" | "phrase" | "starter";
    gloss_zh: string;
  }>;
};

type ReverseLookupApiData = {
  query: string;
  elapsed_ms?: number;
  cached?: boolean;
  items: Array<{
    id: string;
    headword: string;
    lemma: string;
    pos: string;
    gloss_zh: string;
    score: number;
    note: string;
  }>;
};

type SentenceStudyApiData = {
  sentence: string;
  token_count: number;
  candidate_count: number;
  matched_entry_count: number;
  elapsed_ms?: number;
  cached?: boolean;
  candidates: Array<{
    term: string;
    kind: "word" | "phrase";
    score: number;
    reason: string;
    summary: string;
  }>;
};

type ActivityApiData = {
  client_id: string;
  items: Array<{
    id: string;
    term: string;
    detail: string;
    context: string;
    saved_at: number;
    meta?: ActivityMeta | null;
  }>;
};

type WorkspaceStateApiData = {
  client_id: string;
  snapshot: unknown | null;
  updated_at: number | null;
};

function containsChineseCharacters(text: string): boolean {
  return /[\u3400-\u9fff]/u.test(text);
}

async function fetchDictApi<T>(
  path: string,
  params: Record<string, string>,
): Promise<ApiEnvelope<T> | null> {
  const url = new URL(path, dictApiBaseUrl());
  for (const [key, value] of Object.entries(params)) {
    if (value) {
      url.searchParams.set(key, value);
    }
  }

  try {
    const response = await fetch(url, {
      cache: "no-store",
      headers: {
        Accept: "application/json",
      },
    });

    if (!response.ok) {
      return null;
    }

    return (await response.json()) as ApiEnvelope<T>;
  } catch {
    return null;
  }
}

function sourceLabelFromFallback(source: string | null | undefined): string | null {
  return resolveWorkspaceState("", source).sourceLabel;
}

function mapLookupResult(entry: NonNullable<LookupApiData["entry"]>): LookupResult {
  return {
    headword: entry.headword,
    pronunciation: entry.phonetic,
    level: entry.level || "Dictionary",
    summary: entry.summary,
    sourceTags: entry.source_tags,
    meaningGroups:
      entry.meaning_groups.length > 0
        ? entry.meaning_groups
        : [
            {
              partOfSpeech: "sense",
              definitions: entry.senses.map((sense) => sense.gloss_zh),
            },
          ],
    examples: entry.examples,
    collocations: entry.collocations,
    relatedTerms:
      entry.related_terms.length > 0 ? entry.related_terms : entry.english_definitions.slice(0, 6),
    englishDefinitions: entry.english_definitions,
    inflectionLines: entry.inflection_lines,
    contextText: entry.examples[0]?.english ?? "",
  };
}

function mapSuggestions(items: SuggestApiData["items"]): SuggestionItem[] {
  return items.map((item) => ({
    term: item.headword,
    kind: item.pos,
    hint: item.gloss_zh,
  }));
}

function lookupDrivenSuggestions(lookup: LookupResult): SuggestionItem[] {
  const seen = new Set<string>();
  const suggestions: SuggestionItem[] = [];

  for (const item of lookup.collocations) {
    const [rawTerm, rawHint] = item.split("·").map((part) => part.trim());
    const term = rawTerm || item.trim();
    const hint = rawHint || item.trim();
    const key = term.toLowerCase();
    if (!term || seen.has(key)) {
      continue;
    }
    seen.add(key);
    suggestions.push({
      term,
      kind: term.includes(" ") || term.includes("-") ? "phrase" : "related",
      hint,
    });
  }

  for (const term of lookup.relatedTerms) {
    const key = term.toLowerCase();
    if (!term || seen.has(key)) {
      continue;
    }
    seen.add(key);
    suggestions.push({
      term,
      kind: term.includes(" ") || term.includes("-") ? "phrase" : "related",
      hint: term,
    });
  }

  return suggestions.slice(0, 8);
}

function mapReverseMatches(items: ReverseLookupApiData["items"]): ReverseLookupMatch[] {
  return items.map((item) => ({
    term: item.headword,
    partOfSpeech: item.pos,
    gloss: item.gloss_zh,
    note: item.note,
  }));
}

function mapActivityItems(items: ActivityApiData["items"]): ActivityItem[] {
  return items
    .filter(
      (item) =>
        typeof item.id === "string" &&
        typeof item.term === "string" &&
        typeof item.detail === "string" &&
        typeof item.context === "string" &&
        typeof item.saved_at === "number",
    )
    .map((item) => ({
      id: item.id,
      term: item.term,
      detail: item.detail,
      context: item.context,
      savedAt: item.saved_at,
      meta: item.meta ?? null,
    }));
}

export async function loadActivityItems(
  kind: "history" | "inbox",
  clientId: string | null | undefined,
): Promise<ActivityItem[]> {
  if (!clientId) {
    return [];
  }

  const envelope = await fetchDictApi<ActivityApiData>(`/${kind}`, {
    client_id: clientId,
  });
  if (!envelope?.data) {
    return [];
  }

  return mapActivityItems(envelope.data.items);
}

export async function loadWorkspacePersistenceState(
  clientId: string | null | undefined,
): Promise<unknown | null> {
  if (!clientId) {
    return null;
  }

  const envelope = await fetchDictApi<WorkspaceStateApiData>("/workspace-state", {
    client_id: clientId,
  });

  return envelope?.data?.snapshot ?? null;
}

export async function loadSentenceStudy(
  sentence: string,
): Promise<SentenceStudyApiData | null> {
  const query = sentence.trim();
  if (!query) {
    return null;
  }

  const envelope = await fetchDictApi<SentenceStudyApiData>("/sentence-study", {
    q: query,
  });

  return envelope?.data ?? null;
}

export async function loadWorkspaceState(
  rawQuery: string | null | undefined,
  source: string | null | undefined,
  rawKind?: string | null | undefined,
): Promise<WorkspaceState> {
  const fallback = resolveWorkspaceState(rawQuery, source, rawKind);
  const query = rawQuery?.trim() ?? "";
  const kind = inferLookupKind(rawKind, rawQuery);

  if (!query) {
    return fallback;
  }

  if (kind === "sentence") {
    return {
      ...fallback,
      kind,
      mode: "no-result",
      suggestions: [],
      reverseMatches: [],
      statusTitle: "Sentence mode",
      statusBody: "Extract study candidates or capture the whole sentence.",
    };
  }

  const isChineseQuery = containsChineseCharacters(query);
  const [lookupEnvelope, suggestEnvelope, reverseEnvelope] = await Promise.all([
    isChineseQuery
      ? Promise.resolve(null)
      : fetchDictApi<LookupApiData>("/lookup", { q: query }),
    fetchDictApi<SuggestApiData>("/suggest", { q: query }),
    isChineseQuery
      ? fetchDictApi<ReverseLookupApiData>("/reverse-lookup", { q: query })
      : Promise.resolve(null),
  ]);

  if (!lookupEnvelope && !suggestEnvelope && !reverseEnvelope) {
    return {
      ...fallback,
      mode: "no-result",
      kind,
      query,
      sourceLabel: sourceLabelFromFallback(source),
      lookup: null,
      suggestions: [],
      reverseMatches: [],
      statusTitle: "Dictionary service offline.",
      statusBody: "Start the dict-api alongside the web app so lookup can read ECDICT, CEDICT, OEWN, and Tatoeba.",
    };
  }

  const sourceLabel = sourceLabelFromFallback(source);
  const lookup = lookupEnvelope?.data?.entry ? mapLookupResult(lookupEnvelope.data.entry) : null;
  const suggestions = suggestEnvelope?.data ? mapSuggestions(suggestEnvelope.data.items) : [];
  const reverseMatches = reverseEnvelope?.data
    ? mapReverseMatches(reverseEnvelope.data.items)
    : [];

  if (reverseMatches.length > 0) {
    let previewLookup = lookup;
    if (!previewLookup && reverseMatches[0]) {
      const previewEnvelope = await fetchDictApi<LookupApiData>("/lookup", {
        q: reverseMatches[0].term,
      });
      if (previewEnvelope?.data?.entry) {
        previewLookup = mapLookupResult(previewEnvelope.data.entry);
      }
    }

    return {
      mode: "reverse",
      kind,
      query,
      sourceLabel,
      lookup: previewLookup,
      suggestions: suggestions.length > 0 ? suggestions : fallback.suggestions.slice(0, 2),
      reverseMatches,
      statusTitle: `Reverse lookup found ${reverseMatches.length} English options.`,
      statusBody: "Select an English candidate to inspect or save.",
    };
  }

  if (lookup) {
    const lookupSuggestions = lookupDrivenSuggestions(lookup);
    return {
      mode: "lookup",
      kind,
      query,
      sourceLabel,
      lookup,
      suggestions: lookupSuggestions.length > 0 ? lookupSuggestions : suggestions,
      reverseMatches: fallback.reverseMatches,
      statusTitle: `Showing ${lookup.headword}.`,
      statusBody: "Live dictionary result.",
    };
  }

  return {
    mode: "no-result",
    kind,
    query,
    sourceLabel,
    lookup: null,
    suggestions: suggestions.length > 0 ? suggestions : fallback.suggestions.slice(0, 3),
    reverseMatches: [],
    statusTitle: `No direct match for “${query}” yet.`,
    statusBody: "Try a suggestion or capture it manually.",
  };
}
