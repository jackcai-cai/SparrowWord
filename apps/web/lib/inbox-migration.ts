import type { ActivityItem } from "./mock-workspace";
import { reviewStateForTerm, type ReviewStateMap } from "./review";
import {
  createQuickCaptureDraftRecord,
  upsertQuickCaptureDraft,
  type QuickCaptureDraftMap,
} from "./quick-capture";
import {
  upsertLibraryEntry,
  type LibraryEntry,
} from "./workspace-library";
import {
  inferLookupKindFromTerm,
  selectedExamplesFromEntry,
  selectedMeaningsFromEntry,
  type WorkspaceEditableEntry,
} from "./workspace-entry";

export type InboxMigrationInput = {
  inboxItems: ActivityItem[];
  inboxEntryDrafts: Record<string, WorkspaceEditableEntry>;
  quickCaptureDrafts: QuickCaptureDraftMap;
  libraryEntries: LibraryEntry[];
  reviewStateMap: ReviewStateMap;
};

export type InboxMigrationResult = {
  inboxItems: ActivityItem[];
  inboxEntryDrafts: Record<string, WorkspaceEditableEntry>;
  quickCaptureDrafts: QuickCaptureDraftMap;
  libraryEntries: LibraryEntry[];
  migratedToLibrary: string[];
  migratedToDrafts: string[];
  hasChanges: boolean;
};

function normalizedMigrationKey(text: string): string {
  return text
    .trim()
    .replace(/\s+/g, " ")
    .toLowerCase();
}

function containsChineseCharacters(text: string | undefined): boolean {
  return /[\u3400-\u9FFF]/u.test(text ?? "");
}

function looksLikeLegacyCandidateDetail(detail: string): boolean {
  const normalized = normalizedMigrationKey(detail);
  return (
    normalized.includes("sentence captured for study") ||
    normalized.includes("captured from sentence") ||
    normalized.includes("reverse lookup from") ||
    normalized.includes("saved after reverse lookup")
  );
}

function shouldKeepAsDraft(
  item: ActivityItem,
  draft: WorkspaceEditableEntry | null,
): boolean {
  const kind = draft?.kind ?? inferLookupKindFromTerm(item.term, "word");
  if (kind === "sentence") {
    return true;
  }

  if (looksLikeLegacyCandidateDetail(item.detail)) {
    return true;
  }

  if (!containsChineseCharacters(item.detail)) {
    return true;
  }

  if (
    containsChineseCharacters(item.context) &&
    !containsChineseCharacters(item.term) &&
    !draft?.notes.trim() &&
    selectedExamplesFromEntry(draft ?? {
      exampleChoices: [],
      selectedExampleIndexes: [],
    }).length === 0
  ) {
    return true;
  }

  return false;
}

function quickCaptureDraftFromInboxItem(
  item: ActivityItem,
  draft: WorkspaceEditableEntry | null,
  reviewStateMap: ReviewStateMap,
) {
  return createQuickCaptureDraftRecord({
    term: item.term,
    kind: draft?.kind ?? inferLookupKindFromTerm(item.term, "word"),
    context: item.context ?? "",
    reviewLevel: reviewStateForTerm(item.term, reviewStateMap).level,
    meaning: selectedMeaningsFromEntry(draft ?? {
      meaningChoices: [],
      selectedMeaningIndexes: [],
    })[0] ?? draft?.detail ?? item.detail,
    example: selectedExamplesFromEntry(draft ?? {
      exampleChoices: [],
      selectedExampleIndexes: [],
    })[0] ?? "",
    partOfSpeech: draft?.partOfSpeech ?? "",
    notes: draft?.notes ?? "",
    existing: draft ?? null,
    savedAt: item.savedAt,
  });
}

export function migrateLegacyInboxState(
  input: InboxMigrationInput,
): InboxMigrationResult {
  let nextLibraryEntries = input.libraryEntries.slice();
  let nextQuickCaptureDrafts = { ...input.quickCaptureDrafts };
  const nextInboxEntryDrafts: Record<string, WorkspaceEditableEntry> = {};
  const remainingInboxItems: ActivityItem[] = [];
  const migratedToLibrary: string[] = [];
  const migratedToDrafts: string[] = [];

  for (const item of input.inboxItems) {
    const key = normalizedMigrationKey(item.term);
    const draft = input.inboxEntryDrafts[key] ?? null;
    const libraryMatch = nextLibraryEntries.find(
      (entry) => normalizedMigrationKey(entry.term) === key,
    ) ?? null;

    if (libraryMatch) {
      nextLibraryEntries = upsertLibraryEntry(nextLibraryEntries, {
        term: item.term,
        detail: draft?.detail ?? item.detail,
        context: item.context,
        savedAt: item.savedAt,
        kind: draft?.kind ?? inferLookupKindFromTerm(item.term, "word"),
        draft,
        favorite: libraryMatch.favorite,
      });
      migratedToLibrary.push(item.term);
      continue;
    }

    if (shouldKeepAsDraft(item, draft)) {
      const draftRecord = quickCaptureDraftFromInboxItem(item, draft, input.reviewStateMap);
      if (draftRecord) {
        nextQuickCaptureDrafts = upsertQuickCaptureDraft(nextQuickCaptureDrafts, draftRecord);
        migratedToDrafts.push(item.term);
        continue;
      }
    }

    nextLibraryEntries = upsertLibraryEntry(nextLibraryEntries, {
      term: item.term,
      detail: draft?.detail ?? item.detail,
      context: item.context,
      savedAt: item.savedAt,
      kind: draft?.kind ?? inferLookupKindFromTerm(item.term, "word"),
      draft,
    });
    migratedToLibrary.push(item.term);
  }

  for (const [key, draft] of Object.entries(input.inboxEntryDrafts)) {
    if (
      migratedToLibrary.some((term) => normalizedMigrationKey(term) === key) ||
      migratedToDrafts.some((term) => normalizedMigrationKey(term) === key)
    ) {
      continue;
    }

    const orphanDraftRecord = createQuickCaptureDraftRecord({
      term: draft.term,
      kind: draft.kind,
      context: draft.kind === "sentence" ? draft.term : "",
      reviewLevel: reviewStateForTerm(draft.term, input.reviewStateMap).level,
      meaning: selectedMeaningsFromEntry(draft)[0] ?? draft.detail,
      example: selectedExamplesFromEntry(draft)[0] ?? "",
      partOfSpeech: draft.partOfSpeech,
      notes: draft.notes,
      existing: draft,
    });

    if (orphanDraftRecord) {
      nextQuickCaptureDrafts = upsertQuickCaptureDraft(nextQuickCaptureDrafts, orphanDraftRecord);
      migratedToDrafts.push(draft.term);
      continue;
    }

    nextInboxEntryDrafts[key] = draft;
  }

  const hasChanges =
    migratedToLibrary.length > 0 ||
    migratedToDrafts.length > 0 ||
    remainingInboxItems.length !== input.inboxItems.length ||
    Object.keys(nextInboxEntryDrafts).length !== Object.keys(input.inboxEntryDrafts).length;

  return {
    inboxItems: remainingInboxItems,
    inboxEntryDrafts: nextInboxEntryDrafts,
    quickCaptureDrafts: nextQuickCaptureDrafts,
    libraryEntries: nextLibraryEntries,
    migratedToLibrary,
    migratedToDrafts,
    hasChanges,
  };
}
