import test from "node:test";
import assert from "node:assert/strict";

import { migrateLegacyInboxState } from "./inbox-migration";
import type { ActivityItem } from "./mock-workspace";
import type { QuickCaptureDraftMap } from "./quick-capture";
import type { ReviewStateMap } from "./review";
import type { WorkspaceEditableEntry } from "./workspace-entry";
import type { LibraryEntry } from "./workspace-library";

function makeDraft(overrides: Partial<WorkspaceEditableEntry> = {}): WorkspaceEditableEntry {
  return {
    kind: "word",
    term: "abandon",
    partOfSpeech: "verb",
    detail: "放弃",
    meaningChoices: ["放弃"],
    meaningChoicePartOfSpeechLabels: ["verb"],
    selectedMeaningIndexes: [0],
    exampleChoices: ["They had to abandon the original plan."],
    selectedExampleIndexes: [0],
    englishDefinitions: [],
    inflectionLines: [],
    referenceTags: ["ECDICT"],
    notes: "",
    ...overrides,
  };
}

function makeLibraryEntry(overrides: Partial<LibraryEntry> = {}): LibraryEntry {
  return {
    id: "library-abandon",
    kind: "word",
    term: "abandon",
    partOfSpeech: "verb",
    detail: "放弃",
    meaningChoices: ["放弃"],
    meaningChoicePartOfSpeechLabels: ["verb"],
    selectedMeaningIndexes: [0],
    exampleChoices: ["They had to abandon the original plan."],
    selectedExampleIndexes: [0],
    englishDefinitions: [],
    inflectionLines: [],
    referenceTags: ["ECDICT"],
    notes: "",
    context: "They had to abandon the original plan.",
    favorite: false,
    savedAt: 100,
    updatedAt: 100,
    ...overrides,
  };
}

const emptyReviewState: ReviewStateMap = {};
const emptyQuickDrafts: QuickCaptureDraftMap = {};

test("migrateLegacyInboxState merges inbox entries into existing library rows", () => {
  const inboxItems: ActivityItem[] = [
    {
      id: "inbox-1",
      term: "abandon",
      detail: "放弃",
      context: "They had to abandon the original plan.",
      savedAt: 200,
    },
  ];

  const result = migrateLegacyInboxState({
    inboxItems,
    inboxEntryDrafts: {
      abandon: makeDraft({
        notes: "merged note",
        exampleChoices: ["They had to abandon the original plan."],
      }),
    },
    quickCaptureDrafts: emptyQuickDrafts,
    libraryEntries: [makeLibraryEntry()],
    reviewStateMap: emptyReviewState,
  });

  assert.equal(result.inboxItems.length, 0);
  assert.equal(result.migratedToLibrary[0], "abandon");
  assert.equal(result.libraryEntries[0]?.notes, "merged note");
});

test("migrateLegacyInboxState promotes high-confidence Chinese detail into Library", () => {
  const inboxItems: ActivityItem[] = [
    {
      id: "inbox-2",
      term: "conquer",
      detail: "战胜",
      context: "They managed to conquer the fear.",
      savedAt: 200,
    },
  ];

  const result = migrateLegacyInboxState({
    inboxItems,
    inboxEntryDrafts: {
      conquer: makeDraft({
        term: "conquer",
        detail: "战胜",
        meaningChoices: ["战胜"],
        exampleChoices: ["They managed to conquer the fear."],
      }),
    },
    quickCaptureDrafts: emptyQuickDrafts,
    libraryEntries: [],
    reviewStateMap: emptyReviewState,
  });

  assert.equal(result.inboxItems.length, 0);
  assert.deepEqual(result.migratedToLibrary, ["conquer"]);
  assert.equal(result.libraryEntries[0]?.term, "conquer");
});

test("migrateLegacyInboxState moves sentence captures into quick capture drafts", () => {
  const sentence = "They had to abandon the original plan.";
  const inboxItems: ActivityItem[] = [
    {
      id: "inbox-3",
      term: sentence,
      detail: "sentence captured for study",
      context: sentence,
      savedAt: 200,
    },
  ];

  const result = migrateLegacyInboxState({
    inboxItems,
    inboxEntryDrafts: {
      [sentence.toLowerCase()]: makeDraft({
        kind: "sentence",
        term: sentence,
        detail: "sentence captured for study",
        exampleChoices: [],
        selectedExampleIndexes: [],
      }),
    },
    quickCaptureDrafts: emptyQuickDrafts,
    libraryEntries: [],
    reviewStateMap: emptyReviewState,
  });

  assert.equal(result.inboxItems.length, 0);
  assert.deepEqual(result.migratedToDrafts, [sentence]);
  assert.ok(result.quickCaptureDrafts[sentence.toLowerCase()]);
});

test("migrateLegacyInboxState keeps English-gloss inbox items as drafts", () => {
  const inboxItems: ActivityItem[] = [
    {
      id: "inbox-4",
      term: "resilient",
      detail: "elastic; rebounds readily",
      context: "Small teams can be surprisingly resilient.",
      savedAt: 200,
    },
  ];

  const result = migrateLegacyInboxState({
    inboxItems,
    inboxEntryDrafts: {
      resilient: makeDraft({
        term: "resilient",
        detail: "elastic; rebounds readily",
        meaningChoices: ["elastic; rebounds readily"],
        exampleChoices: [],
        selectedExampleIndexes: [],
      }),
    },
    quickCaptureDrafts: emptyQuickDrafts,
    libraryEntries: [],
    reviewStateMap: emptyReviewState,
  });

  assert.deepEqual(result.migratedToDrafts, ["resilient"]);
  assert.ok(result.quickCaptureDrafts.resilient);
  assert.equal(result.libraryEntries.length, 0);
});

test("migrateLegacyInboxState also absorbs orphan inbox drafts into quick capture drafts", () => {
  const result = migrateLegacyInboxState({
    inboxItems: [],
    inboxEntryDrafts: {
      conquer: makeDraft({
        term: "conquer",
        detail: "战胜",
        meaningChoices: ["战胜"],
      }),
    },
    quickCaptureDrafts: emptyQuickDrafts,
    libraryEntries: [],
    reviewStateMap: emptyReviewState,
  });

  assert.equal(result.inboxItems.length, 0);
  assert.deepEqual(result.inboxEntryDrafts, {});
  assert.ok(result.quickCaptureDrafts.conquer);
  assert.deepEqual(result.migratedToDrafts, ["conquer"]);
});
