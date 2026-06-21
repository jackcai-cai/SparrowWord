import test from "node:test";
import assert from "node:assert/strict";

import {
  type DictionarySuggestion,
  lookupDictionaryEntry,
  reverseLookupDictionaryEntries,
  studySentenceCandidates,
  suggestDictionaryEntries,
} from "./offline-dictionary.js";

test("lookupDictionaryEntry prefers learner-facing Chinese summary for common words", () => {
  const shelter = lookupDictionaryEntry("shelter");
  const precious = lookupDictionaryEntry("precious");
  const source = lookupDictionaryEntry("source");

  assert.equal(shelter?.summary, "庇护所");
  assert.equal(precious?.summary, "宝贵的");
  assert.equal(source?.summary, "来源");
});

test("lookupDictionaryEntry keeps ECDICT English definitions ahead of noisier OEWN ones", () => {
  const shelter = lookupDictionaryEntry("shelter");
  const source = lookupDictionaryEntry("source");
  const measure = lookupDictionaryEntry("measure");
  const option = lookupDictionaryEntry("option");

  assert.equal(
    shelter?.englishDefinitions[0],
    "a structure that provides privacy and protection from danger",
  );
  assert.equal(
    source?.englishDefinitions[0],
    "a document (or organization) from which information is obtained",
  );
  assert.equal(
    measure?.englishDefinitions[0],
    "how much there is or how many there are of something that you can quantify",
  );
  assert.equal(
    option?.englishDefinitions[0],
    "one of a number of things from which only one can be chosen",
  );
});

test("suggestDictionaryEntries filters obvious low-quality phrase noise", () => {
  const shelter = suggestDictionaryEntries("shelter", 8).map((item: DictionarySuggestion) => item.term);
  const option = suggestDictionaryEntries("option", 8).map((item: DictionarySuggestion) => item.term);
  const spread = suggestDictionaryEntries("spread", 8).map((item: DictionarySuggestion) => item.term);
  const source = suggestDictionaryEntries("source", 8).map((item: DictionarySuggestion) => item.term);

  assert.ok(!shelter.includes("Shelter I."));
  assert.ok(!shelter.includes("Shelter Pt."));
  assert.ok(!option.includes("option box"));
  assert.ok(!option.includes("option day"));
  assert.ok(!spread.includes("spread F"));
  assert.ok(!source.includes("source-ma"));
});

test("suggestDictionaryEntries can fall back to cleaner related forms after noisy phrase filtering", () => {
  const suggest = suggestDictionaryEntries("suggest", 8).map((item: DictionarySuggestion) => item.term);
  const measure = suggestDictionaryEntries("measure", 8).map((item: DictionarySuggestion) => item.term);
  const arrange = suggestDictionaryEntries("arrange", 8).map((item: DictionarySuggestion) => item.term);

  assert.ok(suggest.includes("suggestion"));
  assert.ok(suggest.includes("suggested"));
  assert.deepEqual(measure, []);
  assert.deepEqual(arrange, []);
});

test("reverseLookupDictionaryEntries mixes CEDICT and ECDICT translation matches for cleaner study candidates", () => {
  const candidates = reverseLookupDictionaryEntries("战胜", 8).map((item) => item.term);

  assert.ok(candidates.includes("defeat"));
  assert.ok(candidates.includes("surmount"));
  assert.ok(candidates.includes("overcome"));
  assert.ok(candidates.includes("conquer"));
  assert.ok(!candidates.includes("victory"));
});

test("studySentenceCandidates strips trailing audit metadata and keeps real study terms", () => {
  const result = studySentenceCandidates("The committee reached a pragmatic compromise. AUDIT-N4", 8);
  const terms = result.candidates.map((candidate) => candidate.term.toLowerCase());

  assert.ok(terms.includes("pragmatic"));
  assert.ok(terms.includes("compromise"));
  assert.ok(!terms.some((term) => term.includes("audit")));
  assert.ok(!terms.some((term) => term.includes("n4")));
});
