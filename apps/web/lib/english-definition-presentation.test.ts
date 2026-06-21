import test from "node:test";
import assert from "node:assert/strict";

import {
  buildEnglishDefinitionPresentation,
  splitPronunciationLines,
} from "./english-definition-presentation";

test("buildEnglishDefinitionPresentation cleans prefixes, extracts synonyms, and dedupes definitions", () => {
  const presentation = buildEnglishDefinitionPresentation([
    "adj satellite calm and emotionally steady",
    "Synonyms: composed, steady ; calm",
    "adjective calm and emotionally steady",
    "verb remain calm under pressure",
    "n. calm and emotionally steady",
  ], ["self-possessed", "steady"]);

  assert.deepEqual(presentation.primaryDefinitions, [
    "calm and emotionally steady",
    "remain calm under pressure",
  ]);
  assert.deepEqual(presentation.additionalDefinitions, []);
  assert.deepEqual(presentation.synonyms, ["composed", "steady", "calm", "self-possessed"]);
});

test("buildEnglishDefinitionPresentation pushes overflow definitions into additionalDefinitions", () => {
  const presentation = buildEnglishDefinitionPresentation([
    "first definition",
    "second definition",
    "third definition",
  ]);

  assert.deepEqual(presentation.primaryDefinitions, ["first definition", "second definition"]);
  assert.deepEqual(presentation.additionalDefinitions, ["third definition"]);
});

test("splitPronunciationLines separates BrE and AmE lines", () => {
  assert.deepEqual(
    splitPronunciationLines("BrE /stɔɪk/, AmE /stoʊɪk/"),
    ["BrE /stɔɪk/", "AmE /stoʊɪk/"],
  );
  assert.deepEqual(splitPronunciationLines("/stəʊɪk/"), ["/stəʊɪk/"]);
});
