import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import Database from "better-sqlite3";

type SuggestionKind = "correction" | "related" | "phrase" | "starter";

type ECDICTRow = {
  word: string;
  phonetic: string | null;
  pos: string | null;
  translation: string | null;
  definition: string | null;
  exchange: string | null;
  collins: number | null;
  oxford: number | null;
  tag: string | null;
  bnc: number | null;
  frq: number | null;
  audio: string | null;
};

type CedictRow = {
  simplified: string;
  traditional: string;
  pinyin: string;
  english: string;
};

type OewnEntryRow = {
  lemma: string;
  part_of_speech: string;
  pronunciations_json: string;
  forms_json: string;
  synsets_json: string;
};

type OewnSynsetRow = {
  synset_id: string;
  part_of_speech: string;
  definitions_json: string;
  members_json: string;
};

export type DictionaryHealth = {
  ecdict: boolean;
  cedict: boolean;
  oewn: boolean;
  tatoeba: boolean;
  paths: {
    ecdict: string;
    cedict: string;
    oewn: string;
    tatoeba: string;
  };
};

export type DictionaryLookup = {
  headword: string;
  phonetic: string;
  level: string;
  summary: string;
  sourceTags: string[];
  meaningGroups: Array<{
    partOfSpeech: string;
    definitions: string[];
  }>;
  senses: Array<{
    sense_id: string;
    pos: string;
    gloss_zh: string;
  }>;
  englishDefinitions: string[];
  inflectionLines: string[];
  collocations: string[];
  relatedTerms: string[];
  examples: Array<{
    english: string;
    chinese: string;
  }>;
};

export type DictionarySuggestion = {
  term: string;
  kind: SuggestionKind;
  hint: string;
};

export type ReverseLookupCandidate = {
  term: string;
  pos: string;
  gloss_zh: string;
  note: string;
  score: number;
};

export type SentenceStudyCandidate = {
  term: string;
  kind: "word" | "phrase";
  score: number;
  reason: string;
  summary: string;
};

export type SentenceStudyResult = {
  sentence: string;
  token_count: number;
  candidate_count: number;
  matched_entry_count: number;
  candidates: SentenceStudyCandidate[];
};

const englishSentenceStopwords = new Set([
  "a",
  "an",
  "and",
  "are",
  "as",
  "at",
  "be",
  "been",
  "being",
  "but",
  "by",
  "for",
  "from",
  "had",
  "has",
  "have",
  "he",
  "her",
  "his",
  "i",
  "in",
  "is",
  "it",
  "its",
  "me",
  "my",
  "of",
  "on",
  "or",
  "our",
  "she",
  "so",
  "than",
  "that",
  "the",
  "their",
  "them",
  "there",
  "they",
  "this",
  "to",
  "us",
  "was",
  "we",
  "were",
  "will",
  "with",
  "you",
  "your",
]);

const sentenceStudyMetadataTokens = new Set([
  "audit",
  "id",
  "marker",
  "sample",
  "tag",
  "test",
]);

const learnerPhraseConnectorTokens = new Set([
  "about",
  "across",
  "after",
  "against",
  "around",
  "at",
  "before",
  "between",
  "by",
  "doing",
  "few",
  "for",
  "from",
  "in",
  "into",
  "itself",
  "oneself",
  "on",
  "onto",
  "over",
  "through",
  "to",
  "toward",
  "towards",
  "under",
  "with",
]);

const offlineResourcesRoot =
  process.env.SPARROWWORD_OFFLINE_RESOURCES_DIR?.trim() ||
  join(homedir(), "Library", "Application Support", "SparrowWord", "OfflineResources");

const resourcePaths = {
  ecdict:
    process.env.SPARROWWORD_ECDICT_DB?.trim() ||
    join(offlineResourcesRoot, "ecdict", "stardict.db"),
  cedict:
    process.env.SPARROWWORD_CEDICT_DB?.trim() ||
    join(offlineResourcesRoot, "cedict", "cedict.sqlite"),
  oewn:
    process.env.SPARROWWORD_OEWN_DB?.trim() ||
    join(offlineResourcesRoot, "oewn", "oewn.sqlite"),
  tatoeba:
    process.env.SPARROWWORD_TATOEBA_DB?.trim() ||
    join(offlineResourcesRoot, "tatoeba", "tatoeba.sqlite"),
};

type SQLiteDatabase = Database.Database;

let ecdictDb: SQLiteDatabase | null | undefined;
let cedictDb: SQLiteDatabase | null | undefined;
let oewnDb: SQLiteDatabase | null | undefined;
let tatoebaDb: SQLiteDatabase | null | undefined;

function uniq<T>(values: T[]): T[] {
  return Array.from(new Set(values));
}

function uniqBy<T>(values: T[], key: (value: T) => string): T[] {
  const seen = new Set<string>();
  return values.filter((value) => {
    const normalized = key(value);
    if (seen.has(normalized)) {
      return false;
    }

    seen.add(normalized);
    return true;
  });
}

function normalizeQuery(query: string): string {
  return query
    .trim()
    .replace(/\s+/g, " ")
    .replace(/[–—‑]/g, "-")
    .toLowerCase();
}

function containsChineseCharacters(text: string): boolean {
  return /[\u3400-\u9fff]/u.test(text);
}

function parseJSONArray(value: string): string[] {
  try {
    const parsed = JSON.parse(value) as string[];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function openReadonlyDatabase(path: string): SQLiteDatabase | null {
  if (!existsSync(path)) {
    return null;
  }

  return new Database(path, {
    readonly: true,
    fileMustExist: true,
  });
}

function getECDICTDb(): SQLiteDatabase | null {
  if (ecdictDb !== undefined) {
    return ecdictDb;
  }

  ecdictDb = openReadonlyDatabase(resourcePaths.ecdict);
  return ecdictDb;
}

function getCedictDb(): SQLiteDatabase | null {
  if (cedictDb !== undefined) {
    return cedictDb;
  }

  cedictDb = openReadonlyDatabase(resourcePaths.cedict);
  return cedictDb;
}

function getOewnDb(): SQLiteDatabase | null {
  if (oewnDb !== undefined) {
    return oewnDb;
  }

  oewnDb = openReadonlyDatabase(resourcePaths.oewn);
  return oewnDb;
}

function getTatoebaDb(): SQLiteDatabase | null {
  if (tatoebaDb !== undefined) {
    return tatoebaDb;
  }

  tatoebaDb = openReadonlyDatabase(resourcePaths.tatoeba);
  return tatoebaDb;
}

export function getDictionaryHealth(): DictionaryHealth {
  return {
    ecdict: existsSync(resourcePaths.ecdict),
    cedict: existsSync(resourcePaths.cedict),
    oewn: existsSync(resourcePaths.oewn),
    tatoeba: existsSync(resourcePaths.tatoeba),
    paths: resourcePaths,
  };
}

function englishLookupCandidates(term: string): string[] {
  const trimmed = term.trim();
  if (!trimmed) {
    return [];
  }

  const normalizedSpacing = trimmed.replace(/\s+/g, " ");
  const normalizedHyphen = normalizedSpacing.replace(/[–—‑]/g, "-");
  const candidates: string[] = [trimmed];

  if (normalizedSpacing !== trimmed) {
    candidates.push(normalizedSpacing);
  }

  if (normalizedHyphen !== normalizedSpacing) {
    candidates.push(normalizedHyphen);
  }

  if (normalizedHyphen.includes(" ") || normalizedHyphen.includes("-")) {
    candidates.push(normalizedHyphen.replace(/-/g, " "));
    candidates.push(normalizedHyphen.replace(/ /g, "-"));
  } else {
    candidates.push(...inflectedEnglishCandidates(normalizedHyphen));
    candidates.push(...adjacentTranspositionCandidates(normalizedHyphen));
  }

  return uniq(
    candidates
      .map((candidate) => candidate.trim())
      .filter(Boolean),
  );
}

function inflectedEnglishCandidates(term: string): string[] {
  const value = normalizeQuery(term);
  if (!value) {
    return [];
  }

  const candidates: string[] = [];
  const irregulars: Record<string, string[]> = {
    better: ["good"],
    best: ["good"],
    worse: ["bad"],
    worst: ["bad"],
    went: ["go"],
    gone: ["go"],
    done: ["do"],
    did: ["do"],
    taken: ["take"],
    took: ["take"],
    made: ["make"],
    bought: ["buy"],
    brought: ["bring"],
    saw: ["see"],
    seen: ["see"],
    ran: ["run"],
    written: ["write"],
    wrote: ["write"],
  };

  candidates.push(...(irregulars[value] ?? []));

  if (value.endsWith("ies") && value.length > 4) {
    candidates.push(`${value.slice(0, -3)}y`);
  }

  if (value.endsWith("es") && value.length > 3) {
    candidates.push(value.slice(0, -2));
  }

  if (value.endsWith("s") && value.length > 2) {
    candidates.push(value.slice(0, -1));
  }

  if (value.endsWith("ied") && value.length > 4) {
    candidates.push(`${value.slice(0, -3)}y`);
  }

  if (value.endsWith("ed") && value.length > 3) {
    const stem = value.slice(0, -2);
    candidates.push(stem, `${stem}e`);
    const simplified = droppingTrailingDoubledConsonant(stem);
    if (simplified) {
      candidates.push(simplified);
    }
  }

  if (value.endsWith("ing") && value.length > 5) {
    const stem = value.slice(0, -3);
    candidates.push(stem, `${stem}e`);
    const simplified = droppingTrailingDoubledConsonant(stem);
    if (simplified) {
      candidates.push(simplified);
    }
  }

  if (value.endsWith("er") && value.length > 4) {
    const stem = value.slice(0, -2);
    candidates.push(stem, `${stem}e`);
    if (stem.endsWith("i")) {
      candidates.push(`${stem.slice(0, -1)}y`);
    }
  }

  if (value.endsWith("est") && value.length > 5) {
    const stem = value.slice(0, -3);
    candidates.push(stem, `${stem}e`);
    if (stem.endsWith("i")) {
      candidates.push(`${stem.slice(0, -1)}y`);
    }
  }

  return uniq(candidates.filter(Boolean));
}

function droppingTrailingDoubledConsonant(stem: string): string | null {
  if (stem.length < 2) {
    return null;
  }

  const last = stem.at(-1);
  const previous = stem.at(-2);
  if (!last || last !== previous || !"bcdfghjklmnpqrstvwxyz".includes(last)) {
    return null;
  }

  return stem.slice(0, -1);
}

function adjacentTranspositionCandidates(term: string): string[] {
  const chars = Array.from(term);
  const candidates: string[] = [];

  for (let index = 0; index < chars.length - 1; index += 1) {
    const swapped = [...chars];
    [swapped[index], swapped[index + 1]] = [swapped[index + 1]!, swapped[index]!];
    candidates.push(swapped.join(""));
  }

  return uniq(candidates.filter((candidate) => candidate !== term));
}

function lookupECDICTRow(term: string): ECDICTRow | null {
  const database = getECDICTDb();
  if (!database) {
    return null;
  }

  const statement = database.prepare(`
    SELECT word, phonetic, pos, translation, definition, exchange, collins, oxford, tag, bnc, frq, audio
    FROM stardict
    WHERE lower(word) = lower(?)
    LIMIT 1
  `);

  return (statement.get(term) as ECDICTRow | undefined) ?? null;
}

function firstECDICTMatch(term: string): ECDICTRow | null {
  for (const candidate of englishLookupCandidates(term)) {
    const row = lookupECDICTRow(candidate);
    if (row) {
      return row;
    }
  }

  return null;
}

function lookupECDICTPrefixMatches(prefix: string, limit: number): ECDICTRow[] {
  const database = getECDICTDb();
  if (!database) {
    return [];
  }

  const statement = database.prepare(`
    SELECT word, phonetic, pos, translation, definition, exchange, collins, oxford, tag, bnc, frq, audio
    FROM stardict
    WHERE word LIKE ? COLLATE NOCASE
    ORDER BY
      CASE
        WHEN lower(word) = lower(?) THEN 0
        WHEN lower(word) LIKE lower(?) || ' %' THEN 1
        WHEN lower(word) LIKE lower(?) || '-%' THEN 1
        ELSE 2
      END,
      CASE WHEN frq IS NULL OR frq = 0 THEN 1 ELSE 0 END,
      frq ASC,
      length(word) ASC
    LIMIT ?
  `);

  return statement.all(`${prefix}%`, prefix, prefix, prefix, limit) as ECDICTRow[];
}

function lookupECDICTPhraseMatches(baseTerm: string, limit: number): ECDICTRow[] {
  const database = getECDICTDb();
  if (!database) {
    return [];
  }

  const statement = database.prepare(`
    SELECT word, phonetic, pos, translation, definition, exchange, collins, oxford, tag, bnc, frq, audio
    FROM stardict
    WHERE word LIKE ? COLLATE NOCASE OR word LIKE ? COLLATE NOCASE
    ORDER BY
      CASE WHEN frq IS NULL OR frq = 0 THEN 1 ELSE 0 END,
      frq ASC,
      length(word) ASC
    LIMIT ?
  `);

  return statement.all(`${baseTerm} %`, `${baseTerm}-%`, limit) as ECDICTRow[];
}

function primaryPOSCode(rawValue: string | null | undefined): string {
  if (!rawValue) {
    return "";
  }

  let bestCode = "";
  let bestScore = Number.NEGATIVE_INFINITY;

  for (const part of rawValue.split("/")) {
    const [code, rawScore] = part.split(":");
    if (!code) {
      continue;
    }

    const score = rawScore ? Number(rawScore) : 0;
    if (score > bestScore) {
      bestScore = score;
      bestCode = code;
    }
  }

  return bestCode;
}

function mapPOSCodeToLabel(code: string): string {
  const normalized = code.toLowerCase().replace(/\.$/, "");

  switch (normalized) {
    case "v":
    case "vt":
    case "vi":
      return "verb";
    case "n":
      return "noun";
    case "adj":
    case "a":
      return "adjective";
    case "adv":
    case "ad":
      return "adverb";
    case "prep":
      return "preposition";
    case "pron":
      return "pronoun";
    case "conj":
      return "conjunction";
    case "int":
      return "interjection";
    default:
      return "sense";
  }
}

function sanitizeTranslationText(text: string): string {
  return text
    .replace(/\[[^\]]+\]/g, "")
    .replace(/[（）]/g, (value) => (value === "（" ? "(" : ")"))
    .replace(/\s+/g, " ")
    .trim();
}

function splitMeaningSegments(text: string): string[] {
  return text
    .split(/[;,，；]/)
    .map((segment) => sanitizeTranslationText(segment))
    .filter(Boolean);
}

function parseMeaningGroups(rawTranslation: string | null | undefined, rawPOS: string | null | undefined): Array<{
  pos: string;
  definitions: string[];
}> {
  const translation = rawTranslation ?? "";

  const lines = translation
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .split("\n")
    .map((line) => sanitizeTranslationText(line))
    .filter(Boolean);

  const fallbackPOS = mapPOSCodeToLabel(primaryPOSCode(rawPOS));
  const groups = lines
    .map((line) => {
      const match = line.match(
        /^(transitive verb\.|intransitive verb\.|adjective\.|adverb\.|preposition\.|pronoun\.|conjunction\.|interjection\.|auxiliary verb\.|vt\.|vi\.|verb\.|v\.|noun\.|n\.|adj\.|a\.|adv\.|ad\.)\s*/i,
      );

      const pos = match ? mapPOSCodeToLabel(match[1] ?? fallbackPOS) : fallbackPOS;
      const stripped = match ? line.slice(match[0].length) : line;
      const definitions = splitMeaningSegments(stripped);
      return definitions.length > 0 ? { pos, definitions } : null;
    })
    .filter((value): value is { pos: string; definitions: string[] } => value !== null);

  return groups.length > 0 ? groups : [{ pos: fallbackPOS, definitions: splitMeaningSegments(translation) }];
}

function preferredChineseMeaning(row: ECDICTRow): string {
  const groups = parseMeaningGroups(row.translation, row.pos);
  return groups.flatMap((group) => group.definitions)[0] ?? "";
}

function parseExchange(exchange: string | null | undefined, query: string): string[] {
  if (!exchange?.trim()) {
    return [];
  }

  const mapping: Record<string, string> = {
    d: "Past",
    p: "Past participle",
    i: "Present participle",
    "3": "Third-person singular",
    s: "Plural",
    r: "Comparative",
    t: "Superlative",
  };

  return uniq(
    exchange
      .split("/")
      .map((segment) => segment.trim())
      .filter(Boolean)
      .map((segment) => {
        const [code, value] = segment.split(":");
        const cleaned = value?.trim() ?? "";
        if (!cleaned || cleaned.toLowerCase() === query.toLowerCase()) {
          return "";
        }

        const label = mapping[code ?? ""] ?? "Form";
        return `${label}: ${cleaned}`;
      })
      .filter(Boolean),
  ).slice(0, 5);
}

function parseECDICTDefinitions(rawDefinition: string | null | undefined): string[] {
  if (!rawDefinition?.trim()) {
    return [];
  }

  return uniq(
    rawDefinition
      .replace(/\r\n/g, "\n")
      .replace(/\r/g, "\n")
      .split("\n")
      .map((line) =>
        line
          .replace(
            /^(transitive verb\.|intransitive verb\.|adjective\.|adverb\.|preposition\.|pronoun\.|conjunction\.|interjection\.|auxiliary verb\.|vt\.|vi\.|verb\.|v\.|noun\.|n\.|adj\.|a\.|adv\.|ad\.|s\.|r\.)\s*/i,
            "",
          )
          .trim(),
      )
      .filter(Boolean),
  ).slice(0, 6);
}

function learnerEnglishDefinitionScore(definition: string): number {
  const normalized = definition.trim().toLowerCase();
  if (!normalized) {
    return Number.NEGATIVE_INFINITY;
  }

  const words = normalized.split(/\s+/).filter(Boolean);
  let score = 0;

  if (words.length >= 5 && words.length <= 12) {
    score += 3;
  } else if (words.length > 16) {
    score -= 4;
  }

  if (
    normalized.startsWith("to ") ||
    normalized.startsWith("able to ") ||
    normalized.startsWith("something that ") ||
    normalized.startsWith("a ") ||
    normalized.startsWith("an ")
  ) {
    score += 2;
  }

  const negativePatterns = [
    "the right to buy or sell",
    "any maneuver made as part of progress",
    "process or result of",
    "a facility where",
    "used to give emphasis",
    "musical notation",
    "a statute in draft before it becomes law",
    "technology",
    "taxable",
    "forfeited",
    "property at an agreed price",
  ];

  for (const pattern of negativePatterns) {
    if (normalized.includes(pattern)) {
      score -= 5;
    }
  }

  if (normalized.includes(";")) {
    score -= 1;
  }

  const positivePatterns = [
    "how much there is or how many there are",
    "one of a number of things from which only one can be chosen",
    "a document (or organization) from which information is obtained",
  ];

  for (const pattern of positivePatterns) {
    if (normalized.includes(pattern)) {
      score += 5;
    }
  }

  return score;
}

function resolveLevel(tag: string | null | undefined): string {
  const lowered = (tag ?? "").toLowerCase();
  if (lowered.includes("gre")) {
    return "GRE";
  }
  if (lowered.includes("toefl")) {
    return "TOEFL";
  }
  if (lowered.includes("cet6")) {
    return "CET6";
  }
  if (lowered.includes("cet4")) {
    return "CET4";
  }
  if (lowered.includes("gk")) {
    return "GK";
  }

  return "";
}

function lookupOewnRows(term: string): OewnEntryRow[] {
  const database = getOewnDb();
  if (!database) {
    return [];
  }

  const exactRows = database
    .prepare(`
      SELECT lemma, part_of_speech, pronunciations_json, forms_json, synsets_json
      FROM oewn_entries
      WHERE lower(lemma) = lower(?)
      ORDER BY lemma ASC
      LIMIT 8
    `)
    .all(term) as OewnEntryRow[];

  if (exactRows.length > 0) {
    return exactRows;
  }

  const lemmas = (
    database
      .prepare(`
        SELECT lemma
        FROM oewn_forms
        WHERE lower(form) = lower(?)
        ORDER BY lemma ASC
        LIMIT 8
      `)
      .all(term) as Array<{ lemma: string }>
  ).map((row) => row.lemma);

  const rows = lemmas.flatMap((lemma) =>
    database
      .prepare(`
        SELECT lemma, part_of_speech, pronunciations_json, forms_json, synsets_json
        FROM oewn_entries
        WHERE lower(lemma) = lower(?)
        ORDER BY lemma ASC
      `)
      .all(lemma) as OewnEntryRow[],
  );

  return uniqBy(rows, (row) => `${row.lemma.toLowerCase()}::${row.part_of_speech}`);
}

function lookupOewnDefinitions(term: string): string[] {
  return lookupOewnEnrichment(term).definitions;
}

function lookupOewnEnrichment(term: string): {
  definitions: string[];
  relatedTerms: string[];
} {
  const database = getOewnDb();
  if (!database) {
    return {
      definitions: [],
      relatedTerms: [],
    };
  }

  const rows = lookupOewnRows(term);
  if (rows.length === 0) {
    return {
      definitions: [],
      relatedTerms: [],
    };
  }

  const synsetIds = uniq(rows.flatMap((row) => parseJSONArray(row.synsets_json))).slice(0, 8);
  if (synsetIds.length === 0) {
    return {
      definitions: [],
      relatedTerms: [],
    };
  }

  const placeholders = synsetIds.map(() => "?").join(", ");
  const synsets = database
    .prepare(`
      SELECT synset_id, part_of_speech, definitions_json, members_json
      FROM oewn_synsets
      WHERE synset_id IN (${placeholders})
    `)
    .all(...synsetIds) as OewnSynsetRow[];

  const definitions: string[] = [];
  const relatedTerms: string[] = [];
  for (const row of synsets) {
    definitions.push(...parseJSONArray(row.definitions_json));
    relatedTerms.push(...parseJSONArray(row.members_json));
  }

  return {
    definitions: uniq(
      definitions
        .map((definition) => definition.trim())
        .filter(Boolean),
    ).slice(0, 6),
    relatedTerms: uniq(
      relatedTerms
        .map((item) => item.trim())
        .filter((item) => item && item.toLowerCase() !== term.toLowerCase()),
    ).slice(0, 8),
  };
}

function collocationHints(term: string, limit = 5): string[] {
  return uniq(
    lookupECDICTPhraseMatches(term, Math.max(limit * 3, 12))
      .filter((row) => shouldKeepLearnerSuggestion(row, term))
      .map((row) => {
        const hint = preferredChineseMeaning(row);
        return hint ? `${row.word} · ${hint}` : row.word;
      })
      .filter(Boolean),
  ).slice(0, limit);
}

function lookupTatoebaExamples(term: string, limit = 3): Array<{
  english: string;
  chinese: string;
}> {
  const database = getTatoebaDb();
  if (!database) {
    return [];
  }

  const quotedTerm = `"${term.replaceAll('"', '""')}"`;
  try {
    const rows = database
      .prepare(`
        SELECT eng.text AS english, cmn.text AS chinese
        FROM english_sentences_fts AS fts
        JOIN sentences AS eng ON eng.id = fts.rowid
        JOIN bilingual_links AS links ON links.eng_id = eng.id
        JOIN sentences AS cmn ON cmn.id = links.cmn_id
        WHERE fts.text MATCH ?
        ORDER BY length(eng.text) ASC
        LIMIT ?
      `)
      .all(quotedTerm, limit) as Array<{ english: string; chinese: string }>;

    return rows.filter((row) => row.english && row.chinese);
  } catch {
    const rows = database
      .prepare(`
        SELECT eng.text AS english, cmn.text AS chinese
        FROM sentences AS eng
        JOIN bilingual_links AS links ON links.eng_id = eng.id
        JOIN sentences AS cmn ON cmn.id = links.cmn_id
        WHERE eng.lang = 'eng'
          AND cmn.lang = 'cmn'
          AND eng.text LIKE ? COLLATE NOCASE
        ORDER BY length(eng.text) ASC
        LIMIT ?
      `)
      .all(`%${term}%`, limit) as Array<{ english: string; chinese: string }>;

    return uniqBy(
      rows.filter((row) => row.english && row.chinese),
      (row) => `${row.english}::${row.chinese}`,
    );
  }
}

function hintFromRow(row: ECDICTRow): string {
  return (
    preferredChineseMeaning(row) ||
    row.definition?.split("\n")[0]?.trim() ||
    "dictionary suggestion"
  );
}

function reverseLookupGlossFromRow(row: ECDICTRow, query: string): string {
  const meanings = parseMeaningGroups(row.translation, row.pos).flatMap((group) => group.definitions);
  return (
    meanings.find((definition) => definition.includes(query)) ??
    preferredChineseMeaning(row) ??
    query
  );
}

function reverseLookupNoteFromRow(row: ECDICTRow): string {
  const hint = hintFromRow(row);
  if (hint && hint !== preferredChineseMeaning(row)) {
    return hint;
  }

  const pos = mapPOSCodeToLabel(primaryPOSCode(row.pos));
  return pos === "sense" ? "dictionary translation match" : `${pos} translation match`;
}

function isLearnerFriendlyReverseHeadword(row: ECDICTRow): boolean {
  const word = row.word.trim();
  if (!word || word.length > 32) {
    return false;
  }

  if (!/^[A-Za-z]+(?:[ -][A-Za-z]+){0,2}$/.test(word)) {
    return false;
  }

  if (/\d/.test(word) || word.includes(".")) {
    return false;
  }

  const tokens = word.split(/[\s-]+/).filter(Boolean);
  if (tokens.length === 0 || tokens.some((token) => token.length <= 1)) {
    return false;
  }

  if (/[A-Z]/.test(word) && word !== word.toLowerCase() && word !== word.toUpperCase()) {
    return false;
  }

  if (!row.definition?.trim() && !row.frq && !row.oxford && !row.collins) {
    return false;
  }

  const translation = row.translation ?? "";
  return !translation.includes("[网络]");
}

function learnerSuggestionQuality(row: ECDICTRow, query: string): number {
  const lowerWord = row.word.toLowerCase();
  const lowerQuery = query.toLowerCase();
  const tokens = lowerWord.split(/[\s-]+/).filter(Boolean);
  const hasMetadata = Boolean(row.definition?.trim()) || Boolean(row.frq) || Boolean(row.oxford) || Boolean(row.collins);
  const translation = row.translation ?? "";
  let score = 0;

  if (row.frq && row.frq > 0) {
    score += Math.max(0, 6 - Math.min(5, row.frq / 5000));
  }
  if (row.oxford) {
    score += 4;
  }
  if (row.collins) {
    score += Math.min(row.collins, 5);
  }
  if (row.definition?.trim()) {
    score += 3;
  }
  if (lowerWord === lowerQuery) {
    score += 10;
  }
  if (row.word.includes(".") || /\d/.test(row.word)) {
    score -= 8;
  }
  if (/[A-Z]/.test(row.word) && row.word !== row.word.toLowerCase()) {
    score -= 4;
  }
  if (translation.includes("[网络]")) {
    score -= 5;
  }
  if (translation.includes("[计]")) {
    score -= 2;
  }
  if (tokens.length > 1) {
    const connectorHits = tokens.filter((token) => learnerPhraseConnectorTokens.has(token)).length;
    if (connectorHits > 0) {
      score += 3;
    } else {
      score -= 3;
    }
  }
  if (tokens.some((token) => token.length === 1)) {
    score -= 6;
  }
  if (tokens.some((token) => token.length <= 2) && !tokens.some((token) => learnerPhraseConnectorTokens.has(token))) {
    score -= 2;
  }
  if (row.word.includes("-") && tokens.some((token) => token.length < 3)) {
    score -= 4;
  }
  if (!hasMetadata && tokens.length > 1) {
    score -= 4;
  }

  return score;
}

function shouldKeepLearnerSuggestion(row: ECDICTRow, query: string): boolean {
  if (row.word.toLowerCase() === query.toLowerCase()) {
    return false;
  }

  const score = learnerSuggestionQuality(row, query);
  if (score >= 0) {
    return true;
  }

  return Boolean(row.frq && row.frq > 0) || Boolean(row.oxford) || Boolean(row.collins);
}

export function lookupDictionaryEntry(query: string): DictionaryLookup | null {
  if (containsChineseCharacters(query)) {
    return null;
  }

  const row = firstECDICTMatch(query);
  if (!row) {
    return null;
  }

  const meaningGroups = parseMeaningGroups(row.translation, row.pos);
  const senses = meaningGroups.flatMap((group, groupIndex) =>
    group.definitions.map((definition, definitionIndex) => ({
      sense_id: `sense-${groupIndex + 1}-${definitionIndex + 1}`,
      pos: group.pos,
      gloss_zh: definition,
    })),
  );

  const oewn = lookupOewnEnrichment(row.word);
  const ecdictDefinitions = parseECDICTDefinitions(row.definition);
  const englishDefinitions = uniq(
    [...ecdictDefinitions, ...oewn.definitions]
      .map((definition) => definition.trim())
      .filter(Boolean),
  )
    .sort((left, right) => {
      const scoreDelta = learnerEnglishDefinitionScore(right) - learnerEnglishDefinitionScore(left);
      if (scoreDelta !== 0) {
        return scoreDelta;
      }

      return left.length - right.length;
    })
    .slice(0, 6);
  const summary =
    preferredChineseMeaning(row) ||
    (senses[0]?.gloss_zh ??
    englishDefinitions[0] ??
    row.word);

  const sourceTags = ["ECDICT"];
  if (englishDefinitions.length > 0) {
    sourceTags.push("OEWN");
  }
  if (row.oxford) {
    sourceTags.push("Oxford");
  }
  if (row.collins) {
    sourceTags.push("Collins");
  }

  return {
    headword: row.word,
    phonetic: row.phonetic ?? "",
    level: resolveLevel(row.tag),
    summary,
    sourceTags,
    meaningGroups: meaningGroups.map((group) => ({
      partOfSpeech: group.pos,
      definitions: group.definitions,
    })),
    senses,
    englishDefinitions,
    inflectionLines: parseExchange(row.exchange, query),
    collocations: collocationHints(row.word),
    relatedTerms: oewn.relatedTerms,
    examples: lookupTatoebaExamples(row.word),
  };
}

export function suggestDictionaryEntries(query: string, limit = 8): DictionarySuggestion[] {
  const cleanedQuery = query.trim();
  if (cleanedQuery.length < 2 || /[\u3400-\u9fff]/u.test(cleanedQuery)) {
    return [];
  }

  const suggestions: DictionarySuggestion[] = [];
  const prefixRows = lookupECDICTPrefixMatches(cleanedQuery, Math.max(limit * 3, 18));

  const correctionCandidates =
    cleanedQuery.length >= 4 && prefixRows.length === 0
      ? englishLookupCandidates(cleanedQuery).slice(1)
      : [];

  for (const candidate of correctionCandidates) {
    const row = lookupECDICTRow(candidate);
    if (!row) {
      continue;
    }

    suggestions.push({
      term: row.word,
      kind: row.word.includes(" ") || row.word.includes("-") ? "phrase" : "correction",
      hint: hintFromRow(row),
    });
  }

  for (const row of prefixRows) {
    if (row.word.toLowerCase() === cleanedQuery.toLowerCase()) {
      continue;
    }

    if (!shouldKeepLearnerSuggestion(row, cleanedQuery)) {
      continue;
    }

    suggestions.push({
      term: row.word,
      kind: row.word.includes(" ") || row.word.includes("-") ? "phrase" : "related",
      hint: hintFromRow(row),
    });
  }

  return uniqBy(suggestions, (item) => `${item.kind}::${item.term.toLowerCase()}`).slice(0, limit);
}

function normalizeSentenceStudyToken(token: string): string {
  return token.trim().replace(/\s+/g, " ").toLowerCase();
}

function trimSentenceStudyToken(token: string): string {
  return token
    .trim()
    .replace(/^[^A-Za-z]+/, "")
    .replace(/[^A-Za-z]+$/, "");
}

function isSentenceMetadataToken(token: string): boolean {
  const trimmed = trimSentenceStudyToken(token);
  if (!trimmed) {
    return false;
  }

  const normalized = normalizeSentenceStudyToken(trimmed);
  return (
    sentenceStudyMetadataTokens.has(normalized) ||
    /\d/.test(trimmed) ||
    /^[A-Z]{2,}(?:-[A-Z0-9]+)*$/.test(trimmed)
  );
}

function shouldKeepSentenceStudyToken(token: string): boolean {
  const trimmed = trimSentenceStudyToken(token);
  if (!trimmed) {
    return false;
  }

  if (!/[A-Za-z]/.test(trimmed) || /\d/.test(trimmed)) {
    return false;
  }

  if (/^[A-Z]{2,}(?:-[A-Z]+)*$/.test(trimmed)) {
    return false;
  }

  return true;
}

function stripSentenceStudyMetadataSuffix(sentence: string): string {
  const trimmed = sentence.trim();
  if (!trimmed) {
    return trimmed;
  }

  const boundary = trimmed.search(/[.!?。！？]\s+/u);
  if (boundary < 0) {
    return trimmed;
  }

  const lastBoundaryMatch = [...trimmed.matchAll(/[.!?。！？]\s+/gu)].at(-1);
  if (!lastBoundaryMatch || typeof lastBoundaryMatch.index !== "number") {
    return trimmed;
  }

  const suffixStart = lastBoundaryMatch.index + lastBoundaryMatch[0].length;
  const suffix = trimmed.slice(suffixStart).trim();
  if (!suffix) {
    return trimmed;
  }

  const suffixTokens = suffix.split(/\s+/).filter(Boolean);
  if (
    suffixTokens.length === 0 ||
    suffixTokens.length > 4 ||
    suffixTokens.some((token) => !isSentenceMetadataToken(token))
  ) {
    return trimmed;
  }

  return trimmed.slice(0, suffixStart).trim();
}

function tokenizeSentenceForStudy(sentence: string): string[] {
  return sentence
    .split(/[^A-Za-z'-]+/)
    .map((token) => trimSentenceStudyToken(token))
    .filter((token) => shouldKeepSentenceStudyToken(token));
}

function sentenceNgramCandidates(tokens: string[]): Array<{ term: string; kind: "word" | "phrase"; weight: number }> {
  const seen = new Set<string>();
  const candidates: Array<{ term: string; kind: "word" | "phrase"; weight: number }> = [];

  function pushCandidate(term: string, kind: "word" | "phrase", weight: number) {
    const cleaned = term.trim().replace(/\s+/g, " ");
    const normalized = normalizeSentenceStudyToken(cleaned);
    if (!cleaned || !normalized || seen.has(`${kind}:${normalized}`)) {
      return;
    }

    seen.add(`${kind}:${normalized}`);
    candidates.push({ term: cleaned, kind, weight });
  }

  for (const token of tokens) {
    const normalized = normalizeSentenceStudyToken(token);
    if (!normalized || englishSentenceStopwords.has(normalized)) {
      continue;
    }

    pushCandidate(token, "word", token.length >= 8 ? 10 : 6);
  }

  for (let start = 0; start < tokens.length; start += 1) {
    for (let size = 2; size <= 3; size += 1) {
      const slice = tokens.slice(start, start + size);
      if (slice.length !== size) {
        continue;
      }

      const firstNormalized = normalizeSentenceStudyToken(slice[0] ?? "");
      const lastNormalized = normalizeSentenceStudyToken(slice[slice.length - 1] ?? "");
      if (!firstNormalized || !lastNormalized) {
        continue;
      }

      if (englishSentenceStopwords.has(firstNormalized) || englishSentenceStopwords.has(lastNormalized)) {
        continue;
      }

      const hasDisallowedStopword = slice.some((token) => {
        const normalized = normalizeSentenceStudyToken(token);
        return englishSentenceStopwords.has(normalized) && !learnerPhraseConnectorTokens.has(normalized);
      });
      if (hasDisallowedStopword) {
        continue;
      }

      const filtered = slice.filter((token) => {
        const normalized = normalizeSentenceStudyToken(token);
        return !englishSentenceStopwords.has(normalized) || token.length >= 6;
      });

      if (filtered.length < Math.max(1, size - 1)) {
        continue;
      }

      pushCandidate(slice.join(" "), "phrase", size === 3 ? 16 : 12);
    }
  }

  return candidates;
}

export function studySentenceCandidates(sentence: string, limit = 10): SentenceStudyResult {
  const cleanedSentence = sentence.trim().replace(/\s+/g, " ");
  if (!cleanedSentence || /[\u3400-\u9fff]/u.test(cleanedSentence)) {
    return {
      sentence: cleanedSentence,
      token_count: 0,
      candidate_count: 0,
      matched_entry_count: 0,
      candidates: [],
    };
  }

  const normalizedStudySentence = stripSentenceStudyMetadataSuffix(cleanedSentence);
  const tokens = tokenizeSentenceForStudy(normalizedStudySentence);
  if (tokens.length === 0) {
    return {
      sentence: cleanedSentence,
      token_count: 0,
      candidate_count: 0,
      matched_entry_count: 0,
      candidates: [],
    };
  }

  const scored = new Map<string, SentenceStudyCandidate & { matched: boolean }>();

  for (const candidate of sentenceNgramCandidates(tokens)) {
    const normalized = normalizeSentenceStudyToken(candidate.term);
    const entry = lookupDictionaryEntry(candidate.term);
    const suggestion = !entry ? suggestDictionaryEntries(candidate.term, 3)[0] ?? null : null;
    const resolvedTerm =
      entry?.headword ??
      (suggestion && normalizeSentenceStudyToken(suggestion.term) === normalized ? suggestion.term : candidate.term);
    const matched = Boolean(entry) || Boolean(suggestion && normalizeSentenceStudyToken(suggestion.term) === normalized);
    const summary = entry?.summary ?? suggestion?.hint ?? `${candidate.kind === "phrase" ? "phrase" : "word"} from sentence`;

    let score = candidate.weight;
    if (entry) {
      score += candidate.kind === "phrase" ? 20 : 14;
      score += Math.min(entry.collocations.length, 4);
      score += entry.examples.length > 0 ? 3 : 0;
      score += entry.level ? 2 : 0;
    } else if (suggestion) {
      score += suggestion.kind === "phrase" ? 12 : 7;
    }

    if (candidate.kind === "phrase") {
      score += 4;
    }

    const reason = entry
      ? candidate.kind === "phrase"
        ? "live phrase match"
        : "live dictionary match"
      : suggestion
        ? `supported by ${suggestion.kind} suggestion`
        : candidate.kind === "phrase"
          ? "phrase from sentence"
          : "content word";

    const existing = scored.get(normalized);
    if (!existing || score > existing.score) {
      scored.set(normalized, {
        term: resolvedTerm,
        kind: candidate.kind,
        score,
        reason,
        summary,
        matched,
      });
    }
  }

  const candidates = Array.from(scored.values())
    .sort((left, right) => {
      if (left.score !== right.score) {
        return right.score - left.score;
      }

      if (left.kind !== right.kind) {
        return left.kind === "phrase" ? -1 : 1;
      }

      return left.term.localeCompare(right.term);
    })
    .slice(0, limit);

  return {
    sentence: cleanedSentence,
    token_count: tokens.length,
    candidate_count: candidates.length,
    matched_entry_count: candidates.filter((candidate) => candidate.matched).length,
    candidates: candidates.map(({ matched: _matched, ...candidate }) => candidate),
  };
}

function extractEnglishCandidates(english: string): string[] {
  return uniq(
    english
      .split("/")
      .flatMap((part) =>
        part
          .replaceAll("(fig.)", "")
          .replaceAll("(lit.)", "")
          .split(/[;,，；]/),
      )
      .flatMap((part) => normalizedEnglishCandidateVariants(part)),
  );
}

function normalizedEnglishCandidateVariants(rawValue: string): string[] {
  const cleaned = rawValue
    .replace(/\(.*?\)/g, "")
    .replace(/^fig\.\s*/i, "")
    .replace(/^lit\.\s*/i, "")
    .replace(/^fig\s+/i, "")
    .replace(/^lit\s+/i, "")
    .replace(/\s+/g, " ")
    .trim();

  if (!cleaned || cleaned.length > 40) {
    return [];
  }

  const lower = cleaned.toLowerCase();
  const blockedPrefixes = [
    "cl:",
    "variant of ",
    "old variant of ",
    "used in ",
    "classifier for ",
    "surname ",
    "abbr. ",
    "abbreviation for ",
    "see also ",
  ];

  if (
    blockedPrefixes.some((prefix) => lower.startsWith(prefix)) ||
    lower === "sb" ||
    lower === "sth"
  ) {
    return [];
  }

  const variants = [cleaned];
  for (const prefix of ["to ", "a ", "an ", "the "]) {
    if (lower.startsWith(prefix) && cleaned.length > prefix.length) {
      variants.push(cleaned.slice(prefix.length));
    }
  }

  return uniq(
    variants
      .map((value) => value.trim())
      .filter(Boolean),
  );
}

function canonicalEnglishCandidate(term: string): string {
  return term
    .trim()
    .replace(/^(to|a|an|the)\s+/i, "")
    .toLowerCase();
}

function reverseLookupPreferenceFromRows(rows: CedictRow[]): "verb" | null {
  const verbVotes = rows
    .flatMap((row) => row.english.split("/"))
    .map((part) => part.trim().toLowerCase())
    .filter(Boolean)
    .filter((part) => part.startsWith("to ")).length;

  return verbVotes > 0 ? "verb" : null;
}

function reverseLookupRank(term: string, extractionScore: number): number {
  const baseTerm = canonicalEnglishCandidate(term);
  const row = lookupECDICTRow(baseTerm);

  let rank = extractionScore * 0.2;

  if (row) {
    rank += 0.3;

    if (row.oxford) {
      rank += 0.15;
    }

    if (row.collins) {
      rank += Math.min(row.collins, 5) / 5 * 0.1;
    }

    if (row.frq && row.frq > 0) {
      rank += (1 - Math.min(row.frq, 20000) / 20000) * 0.35;
    }
  }

  if (term.includes(" ")) {
    rank -= 0.05;
  }

  return rank;
}

function reverseLookupTranslationRank(
  row: ECDICTRow,
  query: string,
  preferredPos: "verb" | null,
): number {
  const pos = mapPOSCodeToLabel(primaryPOSCode(row.pos));
  let rank = reverseLookupRank(row.word, 1);
  const primaryMeaning = preferredChineseMeaning(row);
  const translation = row.translation ?? "";

  if (primaryMeaning === query) {
    rank += 0.42;
  } else if (primaryMeaning.includes(query)) {
    rank += 0.26;
  }

  if (translation.includes(query)) {
    rank += 0.16;
  }

  if (preferredPos === "verb") {
    if (pos === "verb") {
      rank += 0.18;
    } else {
      rank -= 0.2;
    }
  } else if (pos === "verb") {
    rank += 0.08;
  }

  if (pos === "adjective") {
    rank -= 0.08;
  }

  if (pos === "noun") {
    rank -= 0.04;
  }

  return rank;
}

export function reverseLookupDictionaryEntries(
  query: string,
  limit = 8,
): ReverseLookupCandidate[] {
  const database = getCedictDb();
  const cleanedQuery = query.trim();
  if (!database || !cleanedQuery) {
    return [];
  }

  const exactRows = database
    .prepare(`
      SELECT simplified, traditional, pinyin, english
      FROM cedict_entries
      WHERE simplified = ? OR traditional = ?
      ORDER BY length(simplified) ASC
      LIMIT 24
    `)
    .all(cleanedQuery, cleanedQuery) as CedictRow[];

  const prefixRows =
    exactRows.length === 0
      ? (database
          .prepare(`
            SELECT simplified, traditional, pinyin, english
            FROM cedict_entries
            WHERE simplified LIKE ? OR traditional LIKE ?
            ORDER BY length(simplified) ASC
            LIMIT 24
          `)
          .all(`${cleanedQuery}%`, `${cleanedQuery}%`) as CedictRow[])
      : [];

  const containsRows =
    exactRows.length === 0 && prefixRows.length === 0 && cleanedQuery.length >= 2
      ? (database
          .prepare(`
            SELECT simplified, traditional, pinyin, english
            FROM cedict_entries
            WHERE simplified LIKE ? OR traditional LIKE ?
            ORDER BY length(simplified) ASC
            LIMIT 32
          `)
          .all(`%${cleanedQuery}%`, `%${cleanedQuery}%`) as CedictRow[])
      : [];

  const rows =
    exactRows.length > 0 ? exactRows : prefixRows.length > 0 ? prefixRows : containsRows;
  const preferredPos = reverseLookupPreferenceFromRows(rows);

  const cedictCandidates = rows.flatMap((row) =>
    extractEnglishCandidates(row.english).map((english, index) => ({
      term: english,
      pos: english.includes(" ") ? "phrase" : "word",
      gloss_zh: row.simplified === cleanedQuery ? row.simplified : `${row.simplified} / ${row.traditional}`,
      note: row.pinyin,
      score: reverseLookupRank(english, 1 - index * 0.08),
    })),
  );

  const ecdictTranslationRows = getECDICTDb()
    ?.prepare(`
      SELECT word, phonetic, pos, translation, definition, exchange, collins, oxford, tag, bnc, frq, audio
      FROM stardict
      WHERE translation LIKE ?
      ORDER BY
        CASE WHEN translation LIKE ? THEN 0 ELSE 1 END,
        CASE WHEN oxford IS NULL OR oxford = 0 THEN 1 ELSE 0 END,
        oxford DESC,
        CASE WHEN collins IS NULL OR collins = 0 THEN 1 ELSE 0 END,
        collins DESC,
        CASE WHEN frq IS NULL OR frq = 0 THEN 1 ELSE 0 END,
        frq ASC,
        length(word) ASC
      LIMIT 80
    `)
    .all(`%${cleanedQuery}%`, `${cleanedQuery}%`) as ECDICTRow[] | undefined;

  const ecdictCandidates = (ecdictTranslationRows ?? [])
    .filter((row) => isLearnerFriendlyReverseHeadword(row))
    .filter((row) => preferredPos !== "verb" || mapPOSCodeToLabel(primaryPOSCode(row.pos)) === "verb")
    .map((row) => ({
      term: row.word,
      pos: mapPOSCodeToLabel(primaryPOSCode(row.pos)),
      gloss_zh: reverseLookupGlossFromRow(row, cleanedQuery),
      note: reverseLookupNoteFromRow(row),
      score: reverseLookupTranslationRank(row, cleanedQuery, preferredPos),
    }));

  const candidates = [...cedictCandidates, ...ecdictCandidates];

  const normalizedCandidates = [...candidates].sort((left, right) => {
    if (left.term.length !== right.term.length) {
      return left.term.length - right.term.length;
    }

    return right.score - left.score;
  });

  return uniqBy(
    normalizedCandidates,
    (item) => canonicalEnglishCandidate(item.term),
  )
    .sort((left, right) => {
      if (right.score !== left.score) {
        return right.score - left.score;
      }
      if (left.gloss_zh.length !== right.gloss_zh.length) {
        return left.gloss_zh.length - right.gloss_zh.length;
      }
      if (left.term.length !== right.term.length) {
        return left.term.length - right.term.length;
      }
      return left.note.localeCompare(right.note);
    })
    .slice(0, limit);
}
