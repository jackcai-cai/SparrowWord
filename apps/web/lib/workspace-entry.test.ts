import test from "node:test";
import assert from "node:assert/strict";

import {
  createEditableEntry,
  dedupeEditableChoiceState,
  finalizeEditableEntrySelection,
  keepOnlySelectedEditableChoices,
  reorderEditableChoiceState,
} from "./workspace-entry";

test("dedupeEditableChoiceState collapses duplicates and remaps selections", () => {
  const next = dedupeEditableChoiceState({
    choices: ["first meaning", "first meaning", "second meaning"],
    selectedIndexes: [1, 2],
    labels: ["n.", "n.", "adj."],
  });

  assert.deepEqual(next.choices, ["first meaning", "second meaning"]);
  assert.deepEqual(next.selectedIndexes, [0, 1]);
  assert.deepEqual(next.labels, ["n.", "adj."]);
});

test("keepOnlySelectedEditableChoices reduces the list to the current selection", () => {
  const next = keepOnlySelectedEditableChoices({
    choices: ["alpha", "beta", "gamma"],
    selectedIndexes: [2, 0],
    labels: ["n.", "v.", "adj."],
  });

  assert.deepEqual(next.choices, ["gamma", "alpha"]);
  assert.deepEqual(next.selectedIndexes, [0, 1]);
  assert.deepEqual(next.labels, ["adj.", "n."]);
});

test("finalizeEditableEntrySelection keeps only confirmed meanings and examples", () => {
  const next = finalizeEditableEntrySelection({
    kind: "word",
    term: "conquer",
    partOfSpeech: "verb",
    detail: "战胜",
    meaningChoices: ["战胜", "征服", "无关候选"],
    meaningChoicePartOfSpeechLabels: ["verb", "verb", "noun"],
    selectedMeaningIndexes: [0, 1],
    exampleChoices: ["A selected example.", "An unselected example."],
    selectedExampleIndexes: [0],
    englishDefinitions: ["defeat"],
    inflectionLines: [],
    referenceTags: ["ECDICT"],
    notes: "",
  });

  assert.deepEqual(next.meaningChoices, ["战胜", "征服"]);
  assert.deepEqual(next.meaningChoicePartOfSpeechLabels, ["verb", "verb"]);
  assert.deepEqual(next.selectedMeaningIndexes, [0, 1]);
  assert.equal(next.detail, "战胜 / 征服");
  assert.deepEqual(next.exampleChoices, ["A selected example."]);
  assert.deepEqual(next.selectedExampleIndexes, [0]);
});

test("reorderEditableChoiceState moves choices and keeps selected indexes aligned", () => {
  const next = reorderEditableChoiceState(
    {
      choices: ["alpha", "beta", "gamma"],
      selectedIndexes: [0, 2],
      labels: ["n.", "v.", "adj."],
    },
    2,
    0,
  );

  assert.deepEqual(next.choices, ["gamma", "alpha", "beta"]);
  assert.deepEqual(next.selectedIndexes, [1, 0]);
  assert.deepEqual(next.labels, ["adj.", "n.", "v."]);
});

test("createEditableEntry keeps fee-related charge senses available when context points to billing", () => {
  const entry = createEditableEntry({
    term: "charge",
    detail: "a special assignment that is given to a person or group",
    context: "The bank may charge a small fee.",
    snapshot: {
      headword: "charge",
      pronunciation: "tʃɑ:dʒ",
      level: "TOEFL",
      summary: "a special assignment that is given to a person or group",
      sourceTags: ["ECDICT"],
      meaningGroups: [
        {
          partOfSpeech: "noun",
          definitions: ["指控", "费用", "冲锋", "电荷", "炸药"],
        },
        {
          partOfSpeech: "verb",
          definitions: ["控诉", "加罪于", "使充满", "使充电", "使承担"],
        },
        {
          partOfSpeech: "verb",
          definitions: ["冲锋", "要价", "收费"],
        },
      ],
      examples: [],
      collocations: [],
      relatedTerms: [],
      englishDefinitions: [],
      inflectionLines: [],
      contextText: "Charge this bill to me.",
    },
  });

  assert.equal(entry.detail, "收费");
  assert.ok(entry.meaningChoices.includes("收费"));
  assert.deepEqual(entry.selectedMeaningIndexes, [entry.meaningChoices.indexOf("收费")]);
});
