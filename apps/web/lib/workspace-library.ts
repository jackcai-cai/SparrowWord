import type { ActivityItem, LookupKind, LookupResult } from "./mock-workspace";
import {
  createEditableEntry,
  finalizeEditableEntrySelection,
  inferLookupKindFromTerm,
  sanitizeInlineText,
  sanitizeParagraphText,
  selectedExamplesFromEntry,
  selectedMeaningsFromEntry,
  type WorkspaceEditableEntry,
} from "./workspace-entry";

export type LibraryEntry = WorkspaceEditableEntry & {
  id: string;
  context: string;
  favorite: boolean;
  savedAt: number;
  updatedAt: number;
};

export type LibraryEntrySeed = Pick<ActivityItem, "term" | "detail" | "savedAt"> & {
  context?: string;
  kind?: LookupKind;
  snapshot?: LookupResult | null;
  draft?: WorkspaceEditableEntry | null;
  favorite?: boolean;
};

function mergeUniqueStrings(...groups: Array<string[] | undefined>): string[] {
  const seen = new Set<string>();
  const merged: string[] = [];

  for (const group of groups) {
    for (const value of group ?? []) {
      const cleaned = sanitizeInlineText(value);
      const key = normalizedLibraryKey(cleaned);
      if (!cleaned || !key || seen.has(key)) {
        continue;
      }

      seen.add(key);
      merged.push(cleaned);
    }
  }

  return merged;
}

function mergeParagraphs(...parts: Array<string | undefined>): string {
  const seen = new Set<string>();
  const merged: string[] = [];

  for (const part of parts) {
    const chunks = sanitizeParagraphText(part)
      .split(/\n{2,}/)
      .map((chunk) => sanitizeParagraphText(chunk))
      .filter(Boolean);

    for (const chunk of chunks) {
      const key = normalizedLibraryKey(chunk);
      if (!key || seen.has(key)) {
        continue;
      }

      seen.add(key);
      merged.push(chunk);
    }
  }

  return merged.join("\n\n");
}

function selectedTextsToIndexes(choices: string[], selectedTexts: string[]): number[] {
  const indexes = selectedTexts
    .map((text) => choices.findIndex((choice) => normalizedLibraryKey(choice) === normalizedLibraryKey(text)))
    .filter((index) => index >= 0);

  return Array.from(new Set(indexes)).sort((left, right) => left - right);
}

function normalizedLibraryKey(text: string): string {
  return text
    .trim()
    .replace(/\s+/g, " ")
    .toLowerCase();
}

function fallbackLibraryId(term: string, now: number): string {
  const slug = normalizedLibraryKey(term).replace(/[^a-z0-9]+/g, "-");
  return `library-${slug || now}-${now}`;
}

export function libraryEntryFromActivity(seed: LibraryEntrySeed, existing?: LibraryEntry | null): LibraryEntry {
  const now = Date.now();
  const term = sanitizeInlineText(seed.term, sanitizeInlineText(existing?.term));
  const editable = finalizeEditableEntrySelection(createEditableEntry({
    term,
    kind: seed.kind ?? existing?.kind ?? inferLookupKindFromTerm(term, "word"),
    detail: seed.detail,
    context: seed.context ?? existing?.context ?? "",
    snapshot: seed.snapshot,
    notes: seed.draft?.notes ?? existing?.notes ?? "",
    existing: seed.draft ?? existing ?? null,
  }));

  return {
    ...editable,
    id: existing?.id ?? fallbackLibraryId(term, now),
    context: sanitizeParagraphText(seed.context ?? existing?.context ?? ""),
    favorite: seed.favorite ?? existing?.favorite ?? false,
    savedAt: existing?.savedAt ?? seed.savedAt ?? now,
    updatedAt: now,
  };
}

export function upsertLibraryEntry(entries: LibraryEntry[], seed: LibraryEntrySeed): LibraryEntry[] {
  const key = normalizedLibraryKey(seed.term);
  const existing = entries.find((entry) => normalizedLibraryKey(entry.term) === key) ?? null;
  const next = libraryEntryFromActivity(seed, existing);

  return [next, ...entries.filter((entry) => entry.id !== next.id)].sort(
    (left, right) => right.updatedAt - left.updatedAt,
  );
}

export function restoreLibraryEntry(entries: LibraryEntry[], seed: LibraryEntry): LibraryEntry[] {
  const key = normalizedLibraryKey(seed.term);
  const existing = entries.find(
    (entry) => entry.id === seed.id || normalizedLibraryKey(entry.term) === key,
  );
  const restored = libraryEntryFromActivity(
    {
      term: seed.term,
      detail: seed.detail,
      context: seed.context,
      savedAt: seed.savedAt,
      kind: seed.kind,
      draft: seed,
      favorite: seed.favorite,
    },
    existing ?? seed,
  );

  return [restored, ...entries.filter((entry) => entry.id !== restored.id)].sort(
    (left, right) => right.updatedAt - left.updatedAt,
  );
}

export function updateLibraryEntry(
  entries: LibraryEntry[],
  entryId: string,
  updates: Partial<
    Pick<
      LibraryEntry,
      | "context"
      | "favorite"
      | "term"
      | "kind"
      | "detail"
      | "notes"
      | "partOfSpeech"
      | "meaningCandidates"
      | "meaningChoices"
      | "meaningChoicePartOfSpeechLabels"
      | "selectedMeaningIndexes"
      | "exampleChoices"
      | "selectedExampleIndexes"
      | "englishDefinitions"
      | "inflectionLines"
      | "referenceTags"
    >
  >,
): LibraryEntry[] {
  return entries
    .map((entry) => {
      if (entry.id !== entryId) {
        return entry;
      }

      const editable = finalizeEditableEntrySelection(createEditableEntry({
        term: updates.term ?? entry.term,
        kind: updates.kind ?? entry.kind,
        detail: updates.detail ?? entry.detail,
        context: updates.context ?? entry.context,
        notes: updates.notes ?? entry.notes,
        existing: {
          ...entry,
          ...updates,
          meaningCandidates: updates.meaningCandidates ?? entry.meaningCandidates,
          meaningChoices: updates.meaningChoices ?? entry.meaningChoices,
          meaningChoicePartOfSpeechLabels:
            updates.meaningChoicePartOfSpeechLabels ?? entry.meaningChoicePartOfSpeechLabels,
          selectedMeaningIndexes: updates.selectedMeaningIndexes ?? entry.selectedMeaningIndexes,
          exampleChoices: updates.exampleChoices ?? entry.exampleChoices,
          selectedExampleIndexes: updates.selectedExampleIndexes ?? entry.selectedExampleIndexes,
          englishDefinitions: updates.englishDefinitions ?? entry.englishDefinitions,
          inflectionLines: updates.inflectionLines ?? entry.inflectionLines,
          referenceTags: updates.referenceTags ?? entry.referenceTags,
        },
      }));

      return {
        ...entry,
        ...editable,
        context: sanitizeParagraphText(updates.context ?? entry.context),
        favorite: updates.favorite ?? entry.favorite,
        updatedAt: Date.now(),
      };
    })
    .sort((left, right) => right.updatedAt - left.updatedAt);
}

export function removeLibraryEntry(entries: LibraryEntry[], entryId: string): LibraryEntry[] {
  return entries.filter((entry) => entry.id !== entryId);
}

export function duplicateLibraryEntries(entries: LibraryEntry[], entryId: string): LibraryEntry[] {
  const primary = entries.find((entry) => entry.id === entryId);
  if (!primary) {
    return [];
  }

  const key = normalizedLibraryKey(primary.term);
  return entries.filter((entry) => entry.id !== entryId && normalizedLibraryKey(entry.term) === key);
}

export function mergeDuplicateLibraryEntries(entries: LibraryEntry[], primaryEntryId: string): LibraryEntry[] {
  const primary = entries.find((entry) => entry.id === primaryEntryId);
  if (!primary) {
    return entries;
  }

  const duplicates = duplicateLibraryEntries(entries, primaryEntryId);
  if (duplicates.length === 0) {
    return entries;
  }

  const mergedMeaningChoices = mergeUniqueStrings(
    primary.meaningChoices,
    ...duplicates.map((entry) => entry.meaningChoices),
  );
  const mergedLabels = mergedMeaningChoices.map((choice) => {
    const primaryIndex = primary.meaningChoices.findIndex(
      (item) => normalizedLibraryKey(item) === normalizedLibraryKey(choice),
    );
    if (primaryIndex >= 0) {
      return primary.meaningChoicePartOfSpeechLabels[primaryIndex] ?? "";
    }

    for (const duplicate of duplicates) {
      const index = duplicate.meaningChoices.findIndex(
        (item) => normalizedLibraryKey(item) === normalizedLibraryKey(choice),
      );
      if (index >= 0) {
        return duplicate.meaningChoicePartOfSpeechLabels[index] ?? "";
      }
    }

    return "";
  });
  const mergedSelectedMeaningIndexes = selectedTextsToIndexes(
    mergedMeaningChoices,
    mergeUniqueStrings(
      selectedMeaningsFromEntry(primary),
      ...duplicates.map((entry) => selectedMeaningsFromEntry(entry)),
    ),
  );
  const mergedExampleChoices = mergeUniqueStrings(
    primary.exampleChoices,
    ...duplicates.map((entry) => entry.exampleChoices),
  );
  const mergedSelectedExampleIndexes = selectedTextsToIndexes(
    mergedExampleChoices,
    mergeUniqueStrings(
      selectedExamplesFromEntry(primary),
      ...duplicates.map((entry) => selectedExamplesFromEntry(entry)),
    ),
  );

  const merged = updateLibraryEntry(entries, primaryEntryId, {
    kind: primary.kind,
    term: primary.term,
    partOfSpeech: primary.partOfSpeech,
    detail: primary.detail,
    context: mergeParagraphs(primary.context, ...duplicates.map((entry) => entry.context)),
    notes: mergeParagraphs(primary.notes, ...duplicates.map((entry) => entry.notes)),
    favorite: primary.favorite || duplicates.some((entry) => entry.favorite),
    meaningChoices: mergedMeaningChoices,
    meaningChoicePartOfSpeechLabels: mergedLabels,
    selectedMeaningIndexes:
      mergedSelectedMeaningIndexes.length > 0
        ? mergedSelectedMeaningIndexes
        : mergedMeaningChoices.length > 0
          ? [0]
          : [],
    exampleChoices: mergedExampleChoices,
    selectedExampleIndexes:
      mergedSelectedExampleIndexes.length > 0
        ? mergedSelectedExampleIndexes
        : mergedExampleChoices.length > 0
          ? [0]
          : [],
    englishDefinitions: mergeUniqueStrings(
      primary.englishDefinitions,
      ...duplicates.map((entry) => entry.englishDefinitions),
    ),
    inflectionLines: mergeUniqueStrings(
      primary.inflectionLines,
      ...duplicates.map((entry) => entry.inflectionLines),
    ),
    referenceTags: mergeUniqueStrings(
      primary.referenceTags,
      ...duplicates.map((entry) => entry.referenceTags),
    ),
  }).map((entry) => {
    if (entry.id !== primaryEntryId) {
      return entry;
    }

    return {
      ...entry,
      savedAt: Math.min(primary.savedAt, ...duplicates.map((item) => item.savedAt)),
    };
  });

  const duplicateIds = new Set(duplicates.map((entry) => entry.id));
  return merged.filter((entry) => !duplicateIds.has(entry.id));
}

function parseStoredLibraryEntry(item: unknown): LibraryEntry | null {
  if (!item || typeof item !== "object") {
    return null;
  }

  const record = item as Record<string, unknown>;
  const id = typeof record.id === "string" ? record.id : "";
  const term = typeof record.term === "string" ? record.term : "";
  const detail = typeof record.detail === "string" ? record.detail : "";
  const context = typeof record.context === "string" ? record.context : "";
  const notes = typeof record.notes === "string" ? record.notes : "";
  const favorite = typeof record.favorite === "boolean" ? record.favorite : false;
  const savedAt = typeof record.savedAt === "number" && Number.isFinite(record.savedAt) ? record.savedAt : Date.now();
  const updatedAt =
    typeof record.updatedAt === "number" && Number.isFinite(record.updatedAt) ? record.updatedAt : savedAt;
  const rawMeaningCandidatesValue = (record as { meaningCandidates?: unknown[] }).meaningCandidates;
  const rawMeaningCandidates: unknown[] = Array.isArray(rawMeaningCandidatesValue)
    ? rawMeaningCandidatesValue
    : [];

  if (!id || !term.trim()) {
    return null;
  }

  const editable = finalizeEditableEntrySelection(createEditableEntry({
    term,
    kind:
      record.kind === "word" || record.kind === "phrase" || record.kind === "sentence"
        ? record.kind
        : inferLookupKindFromTerm(term, "word"),
    detail,
    context,
    notes,
    existing: {
      kind:
        record.kind === "word" || record.kind === "phrase" || record.kind === "sentence"
          ? record.kind
          : undefined,
      partOfSpeech: typeof record.partOfSpeech === "string" ? record.partOfSpeech : "",
      detail,
      notes,
      meaningCandidates: rawMeaningCandidates
        .map((candidate) => {
          if (!candidate || typeof candidate !== "object") {
            return null;
          }

          const recordCandidate = candidate as Record<string, unknown>;
          const meaning = typeof recordCandidate.meaning === "string" ? recordCandidate.meaning : "";
          if (!meaning.trim()) {
            return null;
          }

          return {
            id:
              typeof recordCandidate.id === "string" && recordCandidate.id.trim()
                ? recordCandidate.id
                : `sense:${meaning}`,
            partOfSpeech:
              typeof recordCandidate.partOfSpeech === "string" ? recordCandidate.partOfSpeech : "",
            meaning,
            selected: recordCandidate.selected === true,
          };
        })
        .filter((candidate): candidate is NonNullable<typeof candidate> => candidate !== null),
      meaningChoices: Array.isArray(record.meaningChoices)
        ? record.meaningChoices.filter((value): value is string => typeof value === "string")
        : [],
      meaningChoicePartOfSpeechLabels: Array.isArray(record.meaningChoicePartOfSpeechLabels)
        ? record.meaningChoicePartOfSpeechLabels.filter((value): value is string => typeof value === "string")
        : [],
      selectedMeaningIndexes: Array.isArray(record.selectedMeaningIndexes)
        ? record.selectedMeaningIndexes.filter((value): value is number => typeof value === "number")
        : [],
      exampleChoices: Array.isArray(record.exampleChoices)
        ? record.exampleChoices.filter((value): value is string => typeof value === "string")
        : [],
      selectedExampleIndexes: Array.isArray(record.selectedExampleIndexes)
        ? record.selectedExampleIndexes.filter((value): value is number => typeof value === "number")
        : [],
      englishDefinitions: Array.isArray(record.englishDefinitions)
        ? record.englishDefinitions.filter((value): value is string => typeof value === "string")
        : [],
      inflectionLines: Array.isArray(record.inflectionLines)
        ? record.inflectionLines.filter((value): value is string => typeof value === "string")
        : [],
      referenceTags: Array.isArray(record.referenceTags)
        ? record.referenceTags.filter((value): value is string => typeof value === "string")
        : [],
    },
  }));

  return {
    ...editable,
    id,
    context,
    favorite,
    savedAt,
    updatedAt,
  };
}

export function parseStoredLibraryEntries(value: unknown): LibraryEntry[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .map(parseStoredLibraryEntry)
    .filter((item): item is LibraryEntry => item !== null)
    .sort((left, right) => right.updatedAt - left.updatedAt);
}
