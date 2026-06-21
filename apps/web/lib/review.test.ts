import test from "node:test";
import assert from "node:assert/strict";

import {
  buildReviewCard,
  buildReviewCandidates,
  defaultReviewState,
  matchesSubmittedAnswer,
  nextReviewState,
  normalizeReviewDecision,
  reviewDueBucket,
  reviewDueLabel,
  selectReviewQuestionTypeForCandidate,
  selectSmartReviewQuestionTypeForCandidate,
  undoLastReviewRating,
  type ReviewSourceKind,
  type ReviewRecord,
  type ReviewStateMap,
} from "./review";

const hourMs = 60 * 60 * 1000;
const dayMs = 24 * hourMs;

test("nextReviewState schedules good recall", () => {
  const now = Date.UTC(2026, 3, 23, 12, 0, 0);
  const next = nextReviewState(
    {
      level: 1,
      reviewCount: 2,
      lastReviewedAt: now - dayMs,
      dueAt: now,
      streak: 0,
      lapseCount: 1,
      lastDecision: "again",
    },
    "good",
    now,
  );

  assert.equal(next.level, 2);
  assert.equal(next.reviewCount, 3);
  assert.equal(next.lastReviewedAt, now);
  assert.equal(next.dueAt, now + 3 * dayMs);
  assert.equal(next.streak, 1);
  assert.equal(next.lapseCount, 1);
  assert.equal(next.lastDecision, "good");
});

test("nextReviewState schedules again and resets streak", () => {
  const now = Date.UTC(2026, 3, 23, 12, 0, 0);
  const next = nextReviewState(
    {
      level: 2,
      reviewCount: 4,
      lastReviewedAt: now - dayMs,
      dueAt: now,
      streak: 3,
      lapseCount: 0,
      lastDecision: "good",
    },
    "again",
    now,
  );

  assert.equal(next.level, 1);
  assert.equal(next.dueAt, now + 4 * hourMs);
  assert.equal(next.streak, 0);
  assert.equal(next.lapseCount, 1);
  assert.equal(next.lastDecision, "again");
});

test("nextReviewState keeps level for hard and extends easy spacing", () => {
  const now = Date.UTC(2026, 3, 23, 12, 0, 0);
  const current = {
    level: 2 as const,
    reviewCount: 4,
    lastReviewedAt: now - dayMs,
    dueAt: now,
    streak: 2,
    lapseCount: 0,
    lastDecision: "good" as const,
  };

  const hard = nextReviewState(current, "hard", now);
  const easy = nextReviewState(current, "easy", now);

  assert.equal(hard.level, 2);
  assert.equal(hard.dueAt, now + Math.round(3 * dayMs * 0.45));
  assert.equal(hard.streak, 2);
  assert.equal(hard.lastDecision, "hard");

  assert.equal(easy.level, 3);
  assert.equal(easy.dueAt, now + Math.round(7 * dayMs * 1.6));
  assert.equal(easy.streak, 3);
  assert.equal(easy.lastDecision, "easy");
});

test("normalizeReviewDecision migrates legacy decisions", () => {
  assert.equal(normalizeReviewDecision("downgrade"), "again");
  assert.equal(normalizeReviewDecision("keep"), "hard");
  assert.equal(normalizeReviewDecision("upgrade"), "good");
  assert.equal(normalizeReviewDecision("easy"), "easy");
  assert.equal(normalizeReviewDecision("unknown"), null);
});

test("undoLastReviewRating restores session, history, and review state", () => {
  const now = Date.UTC(2026, 3, 25, 14, 30, 0);
  const before = {
    ...defaultReviewState(),
    level: 1 as const,
    reviewCount: 2,
    lastReviewedAt: now - dayMs,
    dueAt: now,
    streak: 1,
    lastDecision: "hard" as const,
  };
  const after = nextReviewState(before, "good", now);
  const record: ReviewRecord = {
    sessionId: "session-1",
    candidateId: "candidate-1",
    term: "abandon",
    meaning: "放弃",
    partOfSpeech: "verb",
    example: "Don't abandon me!",
    context: "They had to abandon the original plan.",
    notes: "",
    prompt: "abandon",
    promptTitle: "Multiple Choice · Term to Meaning",
    questionType: "multipleChoice",
    decision: "good",
    correct: true,
    answeredAt: now,
    sourceKinds: ["history"],
    submittedAnswer: "放弃",
    reviewLevelBefore: before.level,
    reviewLevelAfter: after.level,
    reviewStateBefore: before,
    reviewStateAfter: after,
    isHistoryOnly: false,
  };

  const result = undoLastReviewRating(
    {
      sessionId: "session-1",
      queue: ["candidate-1", "candidate-2"],
      index: 1,
      records: [record],
      pausedAt: now,
      activeCandidateId: "candidate-2",
      draftAnswer: "stale",
      selectedChoice: "放弃",
      answerSubmitted: true,
    },
    [record],
    {
      abandon: after,
    },
  );

  assert.equal(result.undoneRecord, record);
  assert.equal(result.session.index, 0);
  assert.equal(result.session.activeCandidateId, "candidate-1");
  assert.equal(result.session.records.length, 0);
  assert.equal(result.session.pausedAt, null);
  assert.equal(result.session.draftAnswer, "");
  assert.equal(result.session.selectedChoice, "");
  assert.equal(result.session.answerSubmitted, false);
  assert.deepEqual(result.reviewHistory, []);
  assert.deepEqual(result.reviewStateMap.abandon, before);
});

test("reviewDueBucket and label reflect schedule state", () => {
  const now = Date.UTC(2026, 3, 23, 12, 0, 0);
  const fresh = defaultReviewState();
  const dueNow = {
    ...defaultReviewState(),
    reviewCount: 1,
    lastReviewedAt: now - dayMs,
    dueAt: now - 1,
  };
  const dueSoon = {
    ...defaultReviewState(),
    reviewCount: 1,
    lastReviewedAt: now - dayMs,
    dueAt: now + dayMs,
  };
  const scheduled = {
    ...defaultReviewState(),
    reviewCount: 3,
    lastReviewedAt: now - dayMs,
    dueAt: now + 5 * dayMs,
  };

  assert.equal(reviewDueBucket(fresh, now), "new");
  assert.equal(reviewDueBucket(dueNow, now), "dueNow");
  assert.equal(reviewDueBucket(dueSoon, now), "dueSoon");
  assert.equal(reviewDueBucket(scheduled, now), "scheduled");
  assert.equal(reviewDueLabel(fresh, now), "New");
  assert.equal(reviewDueLabel(dueNow, now), "Due now");
  assert.match(reviewDueLabel(dueSoon, now), /^Due in /);
  assert.match(reviewDueLabel(scheduled, now), /^Scheduled in /);
});

test("buildReviewCandidates merges sources and keeps curated fields", () => {
  const stateMap: ReviewStateMap = {
    alpha: {
      level: 2,
      reviewCount: 5,
      lastReviewedAt: 100,
      dueAt: 200,
      streak: 2,
      lapseCount: 1,
      lastDecision: "good",
    },
  };

  const candidates = buildReviewCandidates(
    [
      {
        id: "history-1",
        term: "alpha",
        detail: "old history detail",
        context: "old history context",
        savedAt: 10,
      },
    ],
    [
      {
        id: "inbox-1",
        term: "alpha",
        detail: "inbox detail",
        context: "inbox context",
        savedAt: 20,
      },
    ],
    [
      {
        id: "library-1",
        term: "alpha",
        kind: "word",
        detail: "library detail",
        partOfSpeech: "n.",
        meaningChoices: ["library detail", "alt detail"],
        meaningChoicePartOfSpeechLabels: ["n.", "adj."],
        selectedMeaningIndexes: [0, 1],
        exampleChoices: ["library example"],
        selectedExampleIndexes: [0],
        englishDefinitions: [],
        inflectionLines: [],
        referenceTags: ["exam"],
        notes: "library note",
        context: "library context",
        favorite: true,
        savedAt: 30,
        updatedAt: 40,
      },
    ],
    new Set<ReviewSourceKind>(["history", "library", "favorites"]),
    "recommended",
    stateMap,
    false,
    {
      alpha: {
        partOfSpeech: "n.",
        meaningChoices: ["draft detail"],
        selectedMeaningIndexes: [0],
        exampleChoices: ["draft example"],
        selectedExampleIndexes: [0],
        referenceTags: ["draft-tag"],
        notes: "draft note",
      },
    },
  );

  assert.equal(candidates.length, 1);
  assert.deepEqual(candidates[0]?.sourceKinds.sort(), ["favorites", "history", "library"].sort());
  assert.equal(candidates[0]?.detail, "library detail / alt detail");
  assert.equal(candidates[0]?.example, "library example");
  assert.equal(candidates[0]?.favorite, true);
  assert.equal(candidates[0]?.reviewLevel, 2);
  assert.equal(candidates[0]?.reviewCount, 5);
  assert.match(candidates[0]?.referenceTags.join(" "), /exam/);
});

test("buildReviewCandidates keeps inbox and history out of a library-only queue", () => {
  const candidates = buildReviewCandidates(
    [
      {
        id: "history-1",
        term: "history-only",
        detail: "history detail",
        context: "history context",
        savedAt: 10,
      },
      {
        id: "history-2",
        term: "alpha",
        detail: "old detail",
        context: "old context",
        savedAt: 20,
      },
    ],
    [
      {
        id: "inbox-1",
        term: "inbox-only",
        detail: "inbox detail",
        context: "inbox context",
        savedAt: 30,
      },
    ],
    [
      {
        id: "library-1",
        term: "alpha",
        kind: "word",
        detail: "library detail",
        partOfSpeech: "n.",
        meaningChoices: ["library detail"],
        meaningChoicePartOfSpeechLabels: ["n."],
        selectedMeaningIndexes: [0],
        exampleChoices: ["library example"],
        selectedExampleIndexes: [0],
        englishDefinitions: [],
        inflectionLines: [],
        referenceTags: [],
        notes: "",
        context: "library context",
        favorite: false,
        savedAt: 40,
        updatedAt: 50,
      },
    ],
    new Set<ReviewSourceKind>(["library"]),
    "recommended",
    {},
  );

  assert.deepEqual(candidates.map((candidate) => candidate.term), ["alpha"]);
  assert.deepEqual(candidates[0]?.sourceKinds, ["library"]);
  assert.equal(candidates[0]?.hasBackingEntry, true);
});

test("matchesSubmittedAnswer accepts normalized answer segments", () => {
  assert.equal(matchesSubmittedAnswer("abandon", ["abandon / give up"]), true);
  assert.equal(matchesSubmittedAnswer("give up", ["abandon / give up"]), true);
  assert.equal(matchesSubmittedAnswer("wrong answer", ["abandon / give up"]), false);
});

test("selectReviewQuestionTypeForCandidate is stable per candidate", () => {
  const types = ["multipleChoice", "fillIn", "flashcards"] as const;
  const candidate = {
    id: "alpha",
    term: "alpha",
    reviewCount: 2,
  };

  assert.equal(
    selectReviewQuestionTypeForCandidate(candidate, [...types]),
    selectReviewQuestionTypeForCandidate(candidate, [...types]),
  );
  assert.equal(selectReviewQuestionTypeForCandidate(candidate, ["fillIn"]), "fillIn");
  assert.equal(selectReviewQuestionTypeForCandidate(candidate, []), "multipleChoice");
});

test("selectSmartReviewQuestionTypeForCandidate follows the default familiarity mix", () => {
  const types = ["multipleChoice", "fillIn", "flashcards"] as const;

  assert.equal(
    selectSmartReviewQuestionTypeForCandidate(
      {
        id: "a",
        term: "alpha",
        reviewCount: 0,
        reviewLevel: 0,
      },
      [...types],
    ),
    "multipleChoice",
  );
  assert.equal(
    selectSmartReviewQuestionTypeForCandidate(
      {
        id: "a",
        term: "alpha",
        reviewCount: 0,
        reviewLevel: 3,
      },
      [...types],
    ),
    "fillIn",
  );
});

test("selectSmartReviewQuestionTypeForCandidate respects custom enabled formats", () => {
  assert.equal(
    selectSmartReviewQuestionTypeForCandidate(
      {
        id: "stable",
        term: "stable",
        reviewCount: 3,
        reviewLevel: 4,
      },
      ["flashcards"],
    ),
    "flashcards",
  );
});

test("buildReviewCard follows native fill-in direction", () => {
  const candidate = {
    id: "alpha",
    term: "alpha",
    detail: "第一个",
    partOfSpeech: "",
    example: "",
    context: "",
    notes: "",
    selectedMeanings: ["第一个"],
    selectedExamples: [],
    referenceTags: [],
    savedAt: 1,
    sourceKinds: ["library" as const],
    hasBackingEntry: true,
    favorite: false,
    reviewLevel: 2 as const,
    reviewCount: 0,
    lastReviewedAt: null,
  };

  const card = buildReviewCard(candidate, null, "fillIn", [candidate]);

  assert.equal(card.family, "fillIn");
  assert.equal(card.prompt, "第一个");
  assert.equal(card.answer, "alpha");
  assert.deepEqual(card.acceptedAnswers, ["alpha"]);
});

test("buildReviewCard switches flashcard direction by level", () => {
  const lowLevelCandidate = {
    id: "alpha",
    term: "alpha",
    detail: "第一个",
    partOfSpeech: "",
    example: "",
    context: "",
    notes: "",
    selectedMeanings: ["第一个"],
    selectedExamples: [],
    referenceTags: [],
    savedAt: 1,
    sourceKinds: ["library" as const],
    hasBackingEntry: true,
    favorite: false,
    reviewLevel: 1 as const,
    reviewCount: 0,
    lastReviewedAt: null,
  };
  const stableCandidate = {
    ...lowLevelCandidate,
    reviewLevel: 3 as const,
  };

  const lowCard = buildReviewCard(lowLevelCandidate, null, "flashcards", [lowLevelCandidate]);
  const stableCard = buildReviewCard(stableCandidate, null, "flashcards", [stableCandidate]);

  assert.equal(lowCard.prompt, "alpha");
  assert.equal(lowCard.answer, "第一个");
  assert.equal(stableCard.prompt, "第一个");
  assert.equal(stableCard.answer, "alpha");
});

test("buildReviewCard downgrades multiple choice when distractors are missing", () => {
  const candidate = {
    id: "charge",
    term: "charge",
    detail: "收费",
    partOfSpeech: "verb",
    example: "Charge!",
    context: "The bank may charge a small fee.",
    notes: "",
    selectedMeanings: ["收费"],
    selectedExamples: ["Charge!"],
    referenceTags: ["ECDICT"],
    savedAt: 1,
    sourceKinds: ["library" as const],
    hasBackingEntry: true,
    favorite: false,
    reviewLevel: 2 as const,
    reviewCount: 1,
    lastReviewedAt: null,
  };

  const card = buildReviewCard(
    candidate,
    {
      term: "charge",
      headword: "charge",
      pronunciation: "tʃɑ:dʒ",
      level: "TOEFL",
      summary: "收费",
      sourceTags: ["ECDICT"],
      meaningGroups: [{ partOfSpeech: "verb", definitions: ["收费"] }],
      examples: [{ english: "Charge!", chinese: "冲啊！" }],
      collocations: [],
      relatedTerms: [],
      englishDefinitions: [],
      inflectionLines: [],
      contextText: "Charge!",
    },
    "multipleChoice",
    [],
  );

  assert.equal(card.family, "flashcards");
  assert.equal(card.questionType, "flashcards");
  assert.equal(card.promptTitle, "Flashcard · Term to Meaning");
});
