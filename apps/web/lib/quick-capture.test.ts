import test from "node:test";
import assert from "node:assert/strict";

import { type LookupResult } from "./mock-workspace";
import {
  buildQuickCaptureEditableEntry,
  createQuickCaptureDraftRecord,
  parseStoredQuickCaptureDraftMap,
  quickCaptureFormStateFromEntry,
  removeQuickCaptureDraft,
  upsertQuickCaptureDraft,
} from "./quick-capture";

const lookupSnapshot: LookupResult = {
  headword: "abandon",
  pronunciation: "",
  level: "",
  summary: "放弃",
  sourceTags: ["ECDICT"],
  meaningGroups: [
    {
      partOfSpeech: "verb",
      definitions: ["放弃", "抛弃", "中止"],
    },
  ],
  englishDefinitions: ["give up"],
  inflectionLines: [],
  collocations: [],
  relatedTerms: [],
  contextText: "",
  examples: [
    {
      english: "They had to abandon the original plan.",
      chinese: "他们不得不放弃原计划。",
    },
  ],
};

test("buildQuickCaptureEditableEntry keeps the edited meaning, example, and notes", () => {
  const entry = buildQuickCaptureEditableEntry({
    term: "abandon",
    kind: "word",
    context: "They had to abandon the original plan.",
    meaning: "放弃原计划",
    example: "They had to abandon the original plan.",
    partOfSpeech: "verb",
    notes: "Remember it with plan changes.",
    snapshot: lookupSnapshot,
  });

  assert.equal(entry.detail, "放弃原计划");
  assert.ok(entry.meaningChoices.includes("放弃原计划"));
  assert.ok(entry.meaningCandidates?.some((candidate) => candidate.meaning === "放弃原计划" && candidate.selected));
  assert.ok(entry.selectedMeaningIndexes.length > 0);
  assert.deepEqual(entry.exampleChoices, ["They had to abandon the original plan."]);
  assert.deepEqual(entry.selectedExampleIndexes, [0]);
  assert.equal(entry.partOfSpeech, "verb");
  assert.equal(entry.notes, "Remember it with plan changes.");
});

test("createQuickCaptureDraftRecord builds a reusable draft payload", () => {
  const draft = createQuickCaptureDraftRecord({
    term: "give up",
    kind: "phrase",
    context: "Don't give up on this plan.",
    reviewLevel: 2,
    meaning: "不要放弃",
    example: "Don't give up on this plan.",
    partOfSpeech: "phrase",
    notes: "Common encouragement phrase.",
  });

  assert.ok(draft);
  assert.equal(draft?.term, "give up");
  assert.equal(draft?.kind, "phrase");
  assert.equal(draft?.reviewLevel, 2);
  assert.equal(draft?.entry.detail, "不要放弃");
  assert.equal(draft?.entry.notes, "Common encouragement phrase.");
});

test("buildQuickCaptureEditableEntry derives detail from selected meaning candidates", () => {
  const entry = buildQuickCaptureEditableEntry({
    term: "charge",
    kind: "word",
    context: "The bank may charge a small fee.",
    meaningCandidates: [
      {
        id: "charge-fee",
        partOfSpeech: "verb",
        meaning: "收费",
        selected: true,
      },
      {
        id: "charge-accuse",
        partOfSpeech: "verb",
        meaning: "指控",
        selected: false,
      },
    ],
    snapshot: {
      ...lookupSnapshot,
      headword: "charge",
      summary: "收费",
    },
  });

  assert.equal(entry.detail, "收费");
  assert.deepEqual(
    entry.meaningCandidates?.map((candidate) => ({
      meaning: candidate.meaning,
      selected: candidate.selected,
    })),
    [
      { meaning: "收费", selected: true },
      { meaning: "指控", selected: false },
    ],
  );
});

test("parseStoredQuickCaptureDraftMap restores saved drafts and drops invalid rows", () => {
  const restored = parseStoredQuickCaptureDraftMap({
    valid: {
      term: "charge",
      kind: "word",
      context: "The bank may charge a small fee.",
      reviewLevel: 1,
      savedAt: 123,
      entry: {
        kind: "word",
        term: "charge",
        partOfSpeech: "verb",
        detail: "收费",
        meaningChoices: ["收费"],
        meaningChoicePartOfSpeechLabels: ["verb"],
        selectedMeaningIndexes: [0],
        exampleChoices: ["The bank may charge a small fee."],
        selectedExampleIndexes: [0],
        englishDefinitions: ["ask for money"],
        inflectionLines: [],
        referenceTags: ["ECDICT"],
        notes: "bank context",
      },
    },
    invalid: {
      term: "",
      entry: null,
    },
  });

  assert.deepEqual(Object.keys(restored), ["charge"]);
  assert.equal(restored.charge?.entry.detail, "收费");
  assert.equal(restored.charge?.savedAt, 123);
});

test("quickCaptureFormStateFromEntry exposes the selected fields back to the modal", () => {
  const entry = buildQuickCaptureEditableEntry({
    term: "conquer",
    kind: "word",
    context: "They conquered the fear.",
    meaning: "战胜",
    example: "They conquered the fear.",
    partOfSpeech: "verb",
    notes: "Use for overcoming fear.",
  });

  const formState = quickCaptureFormStateFromEntry(entry, {
    term: "conquer",
    kind: "word",
    context: "They conquered the fear.",
    reviewLevel: 3,
  });

  assert.ok(formState.meaningCandidates.some((candidate) => candidate.meaning === "战胜" && candidate.selected));
  assert.deepEqual(formState.exampleChoices, ["They conquered the fear."]);
  assert.deepEqual(formState.selectedExampleIndexes, [0]);
  assert.equal(formState.notes, "Use for overcoming fear.");
  assert.equal(formState.reviewLevel, 3);
});

test("createQuickCaptureDraftRecord preserves sentence draft context and kind", () => {
  const sentence = "They had to abandon the original plan.";
  const draft = createQuickCaptureDraftRecord({
    term: sentence,
    kind: "sentence",
    context: sentence,
    reviewLevel: 0,
    meaning: "sentence captured for study",
    notes: "Keep it as a full sentence draft.",
  });

  assert.ok(draft);
  assert.equal(draft?.kind, "sentence");
  assert.equal(draft?.context, sentence);
  assert.equal(draft?.entry.detail, "sentence captured for study");
  assert.equal(draft?.entry.notes, "Keep it as a full sentence draft.");
});

test("upsertQuickCaptureDraft and removeQuickCaptureDraft keep one draft per normalized term", () => {
  const first = createQuickCaptureDraftRecord({
    term: "Charge",
    kind: "word",
    context: "The bank may charge a small fee.",
    reviewLevel: 1,
    meaning: "收费",
  });
  const second = createQuickCaptureDraftRecord({
    term: "charge",
    kind: "word",
    context: "Charge this bill to me.",
    reviewLevel: 2,
    meaning: "收费",
    notes: "updated",
  });

  assert.ok(first);
  assert.ok(second);

  const merged = upsertQuickCaptureDraft(
    upsertQuickCaptureDraft({}, first!),
    second!,
  );

  assert.deepEqual(Object.keys(merged), ["charge"]);
  assert.equal(merged.charge?.reviewLevel, 2);
  assert.equal(merged.charge?.entry.notes, "updated");

  const cleared = removeQuickCaptureDraft(merged, "CHARGE");
  assert.deepEqual(cleared, {});
});
