import test from "node:test";
import assert from "node:assert/strict";

import { libraryEntryFromActivity, updateLibraryEntry, upsertLibraryEntry } from "./workspace-library";
import type { LookupResult } from "./mock-workspace";
import type { WorkspaceEditableEntry } from "./workspace-entry";

const snapshot: LookupResult = {
  headword: "conquer",
  pronunciation: "",
  level: "",
  summary: "战胜",
  sourceTags: ["ECDICT"],
  meaningGroups: [
    {
      partOfSpeech: "verb",
      definitions: ["战胜", "征服", "攻克"],
    },
  ],
  englishDefinitions: ["defeat"],
  inflectionLines: [],
  collocations: [],
  relatedTerms: [],
  contextText: "",
  examples: [
    {
      english: "They conquered the problem.",
      chinese: "他们战胜了这个问题。",
    },
    {
      english: "Unselected example.",
      chinese: "未选择例句。",
    },
  ],
};

test("libraryEntryFromActivity stores only Inbox-confirmed choices", () => {
  const draft: WorkspaceEditableEntry = {
    kind: "word",
    term: "conquer",
    partOfSpeech: "verb",
    detail: "战胜 / 征服",
    meaningCandidates: [
      {
        id: "conquer-0",
        partOfSpeech: "verb",
        meaning: "战胜",
        selected: true,
      },
      {
        id: "conquer-1",
        partOfSpeech: "verb",
        meaning: "征服",
        selected: true,
      },
      {
        id: "conquer-2",
        partOfSpeech: "verb",
        meaning: "攻克",
        selected: false,
      },
    ],
    meaningChoices: ["战胜", "征服", "攻克"],
    meaningChoicePartOfSpeechLabels: ["verb", "verb", "verb"],
    selectedMeaningIndexes: [0, 1],
    exampleChoices: ["They conquered the problem.", "Unselected example."],
    selectedExampleIndexes: [0],
    englishDefinitions: ["defeat"],
    inflectionLines: [],
    referenceTags: ["ECDICT"],
    notes: "",
  };

  const entry = libraryEntryFromActivity({
    term: "conquer",
    detail: "战胜 / 征服",
    context: "They conquered the problem.",
    savedAt: 100,
    kind: "word",
    snapshot,
    draft,
  });

  assert.deepEqual(entry.meaningChoices, ["战胜", "征服"]);
  assert.deepEqual(entry.selectedMeaningIndexes, [0, 1]);
  assert.deepEqual(
    entry.meaningCandidates?.map((candidate) => ({
      meaning: candidate.meaning,
      selected: candidate.selected,
    })),
    [
      { meaning: "战胜", selected: true },
      { meaning: "征服", selected: true },
    ],
  );
  assert.equal(entry.detail, "战胜 / 征服");
  assert.deepEqual(entry.exampleChoices, ["They conquered the problem."]);
  assert.deepEqual(entry.selectedExampleIndexes, [0]);
});

test("upsertLibraryEntry persists a sentence capture as a library item", () => {
  const sentence = "They had to abandon the original plan.";
  const [entry] = upsertLibraryEntry([], {
    term: sentence,
    detail: "sentence captured for study",
    context: sentence,
    savedAt: 100,
    kind: "sentence",
  });

  assert.equal(entry?.term, sentence);
  assert.equal(entry?.kind, "sentence");
  assert.equal(entry?.context, sentence);
  assert.deepEqual(entry?.meaningChoices, ["sentence captured for study"]);
  assert.deepEqual(entry?.selectedMeaningIndexes, [0]);
});

test("updateLibraryEntry keeps per-sense candidate edits aligned with flattened fields", () => {
  const [entry] = upsertLibraryEntry([], {
    term: "charge",
    detail: "收费",
    context: "The bank may charge a small fee.",
    savedAt: 100,
    kind: "word",
  });
  assert.ok(entry);

  const [updated] = updateLibraryEntry([entry], entry.id, {
    meaningCandidates: [
      {
        id: "charge-0",
        partOfSpeech: "verb",
        meaning: "收费",
        selected: true,
      },
      {
        id: "charge-1",
        partOfSpeech: "verb",
        meaning: "索价",
        selected: true,
      },
    ],
  });

  assert.equal(updated?.detail, "收费 / 索价");
  assert.deepEqual(updated?.meaningChoices, ["收费", "索价"]);
  assert.deepEqual(updated?.selectedMeaningIndexes, [0, 1]);
  assert.deepEqual(
    updated?.meaningCandidates?.map((candidate) => ({
      meaning: candidate.meaning,
      partOfSpeech: candidate.partOfSpeech,
      selected: candidate.selected,
    })),
    [
      { meaning: "收费", partOfSpeech: "verb", selected: true },
      { meaning: "索价", partOfSpeech: "verb", selected: true },
    ],
  );
});
