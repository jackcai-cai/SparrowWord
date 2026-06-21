import type { LookupKind, LookupResult } from "./mock-workspace";
import type { ReviewLevel } from "./review";
import {
  createEditableEntry,
  editableExampleChoiceCount,
  editableMeaningChoiceCount,
  finalizeEditableEntrySelection,
  inferLookupKindFromTerm,
  meaningCandidatesFromChoices,
  parseStoredEditableEntryMap,
  sanitizeInlineText,
  sanitizeParagraphText,
  selectedExamplesFromEntry,
  selectedMeaningsFromEntry,
  type MeaningCandidate,
  type WorkspaceEditableEntry,
} from "./workspace-entry";

export type QuickCaptureDraftRecord = {
  term: string;
  kind: LookupKind;
  context: string;
  reviewLevel: ReviewLevel;
  savedAt: number;
  entry: WorkspaceEditableEntry;
};

export type QuickCaptureDraftMap = Record<string, QuickCaptureDraftRecord>;

export type QuickCaptureFormState = {
  term: string;
  kind: LookupKind;
  context: string;
  reviewLevel: ReviewLevel;
  meaningCandidates: MeaningCandidate[];
  exampleChoices: string[];
  selectedExampleIndexes: number[];
  notes: string;
};

type QuickCaptureEditableEntryOptions = {
  term: string;
  kind?: LookupKind;
  context?: string;
  reviewLevel?: ReviewLevel;
  meaningCandidates?: MeaningCandidate[];
  meaning?: string;
  exampleChoices?: string[];
  selectedExampleIndexes?: number[];
  example?: string;
  partOfSpeech?: string;
  notes?: string;
  snapshot?: LookupResult | null;
  existing?: WorkspaceEditableEntry | null;
};

function normalizedQuickCaptureKey(text: string): string {
  return text
    .trim()
    .replace(/\s+/g, " ")
    .toLowerCase();
}

function insertSelectedChoiceAtFront(
  choices: string[],
  labels: string[] | null,
  value: string,
  label: string,
  limit: number,
): {
  choices: string[];
  labels: string[] | null;
  selectedIndex: number;
} {
  const cleaned = sanitizeInlineText(value);
  if (!cleaned) {
    return {
      choices,
      labels,
      selectedIndex: 0,
    };
  }

  const existingIndex = choices.findIndex(
    (choice) => normalizedQuickCaptureKey(choice) === normalizedQuickCaptureKey(cleaned),
  );
  if (existingIndex >= 0) {
    const nextLabels = labels ? [...labels] : null;
    if (nextLabels && label) {
      nextLabels[existingIndex] = sanitizeInlineText(label, nextLabels[existingIndex] ?? "");
    }

    return {
      choices,
      labels: nextLabels,
      selectedIndex: existingIndex,
    };
  }

  const nextChoices = [cleaned, ...choices].slice(0, limit);
  const nextLabels = labels
    ? [sanitizeInlineText(label), ...labels].slice(0, limit)
    : null;

  return {
    choices: nextChoices,
    labels: nextLabels,
    selectedIndex: 0,
  };
}

function detailFromMeaningCandidates(
  candidates: MeaningCandidate[] | undefined,
  fallbackDetail: string,
): string {
  const selectedMeanings = (candidates ?? [])
    .filter((candidate) => candidate.selected)
    .map((candidate) => sanitizeInlineText(candidate.meaning))
    .filter(Boolean);

  if (selectedMeanings.length > 0) {
    return selectedMeanings.join(" / ");
  }

  const firstMeaning = (candidates ?? [])
    .map((candidate) => sanitizeInlineText(candidate.meaning))
    .find(Boolean);

  return sanitizeInlineText(fallbackDetail, firstMeaning ?? "");
}

function normalizeSelectedIndexes(indexes: number[] | undefined, upperBound: number): number[] {
  if (!Array.isArray(indexes)) {
    return [];
  }

  return Array.from(
    new Set(
      indexes.filter((index) => Number.isInteger(index) && index >= 0 && index < upperBound),
    ),
  );
}

export function buildQuickCaptureEditableEntry(
  options: QuickCaptureEditableEntryOptions,
): WorkspaceEditableEntry {
  const term = sanitizeInlineText(options.term);
  const context = sanitizeParagraphText(options.context);
  const meaning = sanitizeInlineText(options.meaning);
  const example = sanitizeInlineText(options.example);
  const partOfSpeech = sanitizeInlineText(options.partOfSpeech);
  const notes = sanitizeParagraphText(options.notes);
  const kind = options.kind ?? inferLookupKindFromTerm(term, "word");

  const base = createEditableEntry({
    term,
    kind,
    detail: meaning || options.snapshot?.summary || term,
    context,
    notes,
    snapshot: options.snapshot,
    existing: {
      ...(options.existing ?? null),
      meaningCandidates:
        options.meaningCandidates ??
        options.existing?.meaningCandidates ??
        undefined,
    },
  });

  const meaningSelection = options.meaningCandidates?.length
    ? {
        choices: options.meaningCandidates.map((candidate) => candidate.meaning).slice(0, editableMeaningChoiceCount),
        labels: options.meaningCandidates.map((candidate) => candidate.partOfSpeech).slice(0, editableMeaningChoiceCount),
        selectedIndexes: options.meaningCandidates
          .map((candidate, index) => (candidate.selected ? index : -1))
          .filter((index) => index >= 0),
      }
    : (() => {
        const inserted = insertSelectedChoiceAtFront(
          base.meaningChoices,
          base.meaningChoicePartOfSpeechLabels,
          meaning || base.detail,
          partOfSpeech,
          editableMeaningChoiceCount,
        );
        return {
          choices: inserted.choices,
          labels: inserted.labels ?? [],
          selectedIndexes: inserted.choices.length > 0 ? [inserted.selectedIndex] : [],
        };
      })();

  const explicitExampleChoices = options.exampleChoices
    ?.map((choice) => sanitizeInlineText(choice))
    .filter(Boolean)
    .slice(0, editableExampleChoiceCount);

  const exampleSelection = explicitExampleChoices && explicitExampleChoices.length > 0
    ? {
        choices: explicitExampleChoices,
        labels: null,
        selectedIndexes:
          normalizeSelectedIndexes(options.selectedExampleIndexes, explicitExampleChoices.length).length > 0
            ? normalizeSelectedIndexes(options.selectedExampleIndexes, explicitExampleChoices.length)
            : [0],
      }
    : example
      ? (() => {
          const inserted = insertSelectedChoiceAtFront(base.exampleChoices, null, example, "", editableExampleChoiceCount);
          return {
            choices: inserted.choices,
            labels: null,
            selectedIndexes: inserted.choices.length > 0 ? [inserted.selectedIndex] : [],
          };
        })()
      : {
          choices: base.exampleChoices,
          labels: null,
          selectedIndexes:
            normalizeSelectedIndexes(base.selectedExampleIndexes, base.exampleChoices.length).length > 0
              ? normalizeSelectedIndexes(base.selectedExampleIndexes, base.exampleChoices.length)
              : base.exampleChoices.length > 0
                ? [0]
                : [],
        };

  const nextEntry: WorkspaceEditableEntry = {
    ...base,
    kind,
    partOfSpeech: sanitizeInlineText(
      partOfSpeech,
      meaningSelection.labels[meaningSelection.selectedIndexes[0] ?? 0] ?? base.partOfSpeech,
    ),
    meaningCandidates: meaningCandidatesFromChoices(
      meaningSelection.choices,
      meaningSelection.labels,
      meaningSelection.selectedIndexes,
    ),
    meaningChoices: meaningSelection.choices,
    meaningChoicePartOfSpeechLabels: meaningSelection.labels,
    selectedMeaningIndexes: meaningSelection.selectedIndexes,
    exampleChoices: exampleSelection.choices,
    selectedExampleIndexes: exampleSelection.selectedIndexes,
    notes,
  };

  return {
    ...nextEntry,
    detail: detailFromMeaningCandidates(nextEntry.meaningCandidates, meaning || base.detail),
  };
}

export function quickCaptureFormStateFromEntry(
  entry: WorkspaceEditableEntry,
  options?: {
    term?: string;
    kind?: LookupKind;
    context?: string;
    reviewLevel?: ReviewLevel;
  },
): QuickCaptureFormState {
  return {
    term: sanitizeInlineText(options?.term, entry.term),
    kind: options?.kind ?? entry.kind,
    context: sanitizeParagraphText(options?.context),
    reviewLevel: options?.reviewLevel ?? 0,
    meaningCandidates:
      entry.meaningCandidates?.length
        ? entry.meaningCandidates
        : meaningCandidatesFromChoices(
            entry.meaningChoices,
            entry.meaningChoicePartOfSpeechLabels,
            entry.selectedMeaningIndexes,
          ),
    exampleChoices: entry.exampleChoices,
    selectedExampleIndexes: entry.selectedExampleIndexes,
    notes: entry.notes,
  };
}

export function createQuickCaptureDraftRecord(
  options: QuickCaptureEditableEntryOptions & {
    reviewLevel: ReviewLevel;
    savedAt?: number;
  },
): QuickCaptureDraftRecord | null {
  const term = sanitizeInlineText(options.term);
  if (!term) {
    return null;
  }

  return {
    term,
    kind: options.kind ?? inferLookupKindFromTerm(term, "word"),
    context: sanitizeParagraphText(options.context),
    reviewLevel: options.reviewLevel,
    savedAt: options.savedAt ?? Date.now(),
    entry: buildQuickCaptureEditableEntry(options),
  };
}

export function upsertQuickCaptureDraft(
  current: QuickCaptureDraftMap,
  draft: QuickCaptureDraftRecord,
): QuickCaptureDraftMap {
  return {
    ...current,
    [normalizedQuickCaptureKey(draft.term)]: draft,
  };
}

export function removeQuickCaptureDraft(
  current: QuickCaptureDraftMap,
  term: string,
): QuickCaptureDraftMap {
  const key = normalizedQuickCaptureKey(term);
  if (!key || !current[key]) {
    return current;
  }

  const next = { ...current };
  delete next[key];
  return next;
}

export function parseStoredQuickCaptureDraftMap(value: unknown): QuickCaptureDraftMap {
  if (!value || typeof value !== "object") {
    return {};
  }

  const next: QuickCaptureDraftMap = {};

  for (const rawRecord of Object.values(value as Record<string, unknown>)) {
    if (!rawRecord || typeof rawRecord !== "object") {
      continue;
    }

    const record = rawRecord as Record<string, unknown>;
    const term = sanitizeInlineText(typeof record.term === "string" ? record.term : "");
    if (!term) {
      continue;
    }

    const entry = parseStoredEditableEntryMap({
      restored: record.entry,
    }).restored;
    if (!entry) {
      continue;
    }

    const kind =
      record.kind === "word" || record.kind === "phrase" || record.kind === "sentence"
        ? record.kind
        : inferLookupKindFromTerm(term, entry.kind);
    const reviewLevel =
      record.reviewLevel === 0 ||
      record.reviewLevel === 1 ||
      record.reviewLevel === 2 ||
      record.reviewLevel === 3 ||
      record.reviewLevel === 4
        ? record.reviewLevel
        : 0;
    const savedAt = typeof record.savedAt === "number" && Number.isFinite(record.savedAt)
      ? record.savedAt
      : Date.now();

    next[normalizedQuickCaptureKey(term)] = {
      term,
      kind,
      context: sanitizeParagraphText(typeof record.context === "string" ? record.context : ""),
      reviewLevel,
      savedAt,
      entry,
    };
  }

  return next;
}
