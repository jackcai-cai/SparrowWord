import type { ActivityItem, LookupResult } from "./mock-workspace";
import type { LibraryEntry } from "./workspace-library";
import {
  selectedExamplesFromEntry,
  selectedMeaningsFromEntry,
  type WorkspaceEditableEntry,
} from "./workspace-entry";

export type ReviewSourceKind = "library" | "favorites" | "history";
export type ReviewQuestionType = "multipleChoice" | "fillIn" | "flashcards";
export type ReviewQuestionStrategy = "smart" | "custom";
export type ReviewQuestionFamily = "multipleChoice" | "fillIn" | "flashcards";
export type ReviewDecision = "again" | "hard" | "good" | "easy";
export type ReviewSortOption =
  | "recommended"
  | "newestFirst"
  | "leastRecentlyReviewed"
  | "alphabetical";
export type ReviewLevel = 0 | 1 | 2 | 3 | 4;

export type ReviewStateRecord = {
  level: ReviewLevel;
  reviewCount: number;
  lastReviewedAt: number | null;
  dueAt: number | null;
  streak: number;
  lapseCount: number;
  lastDecision: ReviewDecision | null;
};

export type ReviewStateMap = Record<string, ReviewStateRecord>;

export type ReviewCandidate = {
  id: string;
  term: string;
  detail: string;
  partOfSpeech: string;
  example: string;
  context: string;
  notes: string;
  selectedMeanings: string[];
  selectedExamples: string[];
  referenceTags: string[];
  savedAt: number;
  sourceKinds: ReviewSourceKind[];
  hasBackingEntry: boolean;
  favorite: boolean;
  reviewLevel: ReviewLevel;
  reviewCount: number;
  lastReviewedAt: number | null;
};

export type ReviewLookupSnapshot = LookupResult & {
  term: string;
};

export type ReviewDraftEntry = Pick<
  WorkspaceEditableEntry,
  | "partOfSpeech"
  | "meaningChoices"
  | "selectedMeaningIndexes"
  | "exampleChoices"
  | "selectedExampleIndexes"
  | "referenceTags"
  | "notes"
>;

export type ReviewCard = {
  family: ReviewQuestionFamily;
  questionType: ReviewQuestionType;
  prompt: string;
  promptTitle: string;
  promptHint: string;
  supportingText: string;
  answer: string;
  acceptedAnswers: string[];
  distractors: string[];
};

export type ReviewRecord = {
  sessionId: string;
  candidateId: string;
  term: string;
  meaning: string;
  partOfSpeech: string;
  example: string;
  context: string;
  notes: string;
  prompt: string;
  promptTitle: string;
  questionType: ReviewQuestionType;
  decision: ReviewDecision;
  correct: boolean | null;
  answeredAt: number;
  sourceKinds: ReviewSourceKind[];
  submittedAnswer: string;
  reviewLevelBefore: ReviewLevel | null;
  reviewLevelAfter: ReviewLevel | null;
  reviewStateBefore?: ReviewStateRecord | null;
  reviewStateAfter?: ReviewStateRecord | null;
  isHistoryOnly: boolean;
};

export type ReviewUndoSessionState = {
  queue: string[];
  index: number;
  records: ReviewRecord[];
  pausedAt: number | null;
  activeCandidateId?: string | null;
  draftAnswer?: string;
  selectedChoice?: string;
  answerSubmitted?: boolean;
};

export type ReviewUndoResult<TSession extends ReviewUndoSessionState> = {
  session: TSession;
  reviewHistory: ReviewRecord[];
  reviewStateMap: ReviewStateMap;
  undoneRecord: ReviewRecord | null;
};

export function normalizedReviewKey(text: string): string {
  return text
    .trim()
    .replace(/\s+/g, " ")
    .toLowerCase();
}

function primaryMeaningText(snapshot: ReviewLookupSnapshot | null, candidate: ReviewCandidate): string {
  const selectedMeaning = candidate.detail.trim();
  if (selectedMeaning) {
    return selectedMeaning;
  }

  const firstMeaning = snapshot?.meaningGroups.flatMap((group) => group.definitions)[0]?.trim();
  if (firstMeaning) {
    return firstMeaning;
  }

  return candidate.detail || candidate.term;
}

function meaningAnswerChoices(snapshot: ReviewLookupSnapshot | null, candidate: ReviewCandidate): string[] {
  const rawChoices = [
    candidate.detail,
    ...snapshot?.meaningGroups.flatMap((group) => group.definitions) ?? [],
  ];

  const normalized = new Set<string>();
  const choices: string[] = [];

  for (const choice of rawChoices) {
    const trimmed = choice.trim();
    if (!trimmed) {
      continue;
    }

    const key = normalizedComparableText(trimmed);
    if (!key || normalized.has(key)) {
      continue;
    }

    normalized.add(key);
    choices.push(trimmed);
  }

  return choices;
}

function reviewPromptHint(candidate: ReviewCandidate): string {
  const levelHint = candidate.hasBackingEntry
    ? candidate.reviewLevel === 0
      ? "Treat this like a fresh term."
      : candidate.reviewLevel === 1
        ? "You have seen it, but it is still shaky."
        : candidate.reviewLevel === 2
          ? "You know it, but it still needs reinforcement."
          : candidate.reviewLevel === 3
            ? "This is fairly stable. Check the nuance."
            : "Mostly mastered. Verify the nuance, not just the headline."
    : "History only. This round will not update a saved level.";

  if (candidate.partOfSpeech) {
    return `${candidate.partOfSpeech} · ${levelHint}`;
  }

  return levelHint;
}

function candidateSupportingText(candidate: ReviewCandidate): string {
  if (candidate.selectedExamples[0]) {
    return candidate.selectedExamples[0];
  }

  if (candidate.example) {
    return candidate.example;
  }

  if (candidate.context) {
    return candidate.context;
  }

  if (candidate.notes) {
    return candidate.notes;
  }

  return "";
}

function looksLikeSentence(term: string): boolean {
  return /[.!?。！？]/u.test(term) || term.trim().split(/\s+/).filter(Boolean).length >= 6;
}

function mergeUniqueTexts(...groups: Array<string[] | undefined>): string[] {
  const seen = new Set<string>();
  const merged: string[] = [];

  for (const group of groups) {
    for (const value of group ?? []) {
      const trimmed = value.trim();
      if (!trimmed) {
        continue;
      }

      const key = normalizedReviewKey(trimmed);
      if (!key || seen.has(key)) {
        continue;
      }

      seen.add(key);
      merged.push(trimmed);
    }
  }

  return merged;
}

export function defaultReviewState(): ReviewStateRecord {
  return {
    level: 0,
    reviewCount: 0,
    lastReviewedAt: null,
    dueAt: null,
    streak: 0,
    lapseCount: 0,
    lastDecision: null,
  };
}

export function reviewStateForTerm(term: string, reviewStateMap: ReviewStateMap): ReviewStateRecord {
  return reviewStateMap[normalizedReviewKey(term)] ?? defaultReviewState();
}

export function sameReviewRecord(left: ReviewRecord, right: ReviewRecord): boolean {
  return (
    left.sessionId === right.sessionId &&
    left.candidateId === right.candidateId &&
    left.answeredAt === right.answeredAt
  );
}

export function undoLastReviewRating<TSession extends ReviewUndoSessionState>(
  session: TSession,
  reviewHistory: ReviewRecord[],
  reviewStateMap: ReviewStateMap,
): ReviewUndoResult<TSession> {
  if (session.records.length === 0) {
    return {
      session,
      reviewHistory,
      reviewStateMap,
      undoneRecord: null,
    };
  }

  const undoneRecord = session.records[session.records.length - 1];
  if (!undoneRecord) {
    return {
      session,
      reviewHistory,
      reviewStateMap,
      undoneRecord: null,
    };
  }

  const nextIndex = Math.max(0, session.index - 1);
  const activeCandidateId = session.queue[nextIndex] ?? null;
  const nextSession = {
    ...session,
    index: nextIndex,
    records: session.records.slice(0, -1),
    pausedAt: null,
    activeCandidateId,
    draftAnswer: "",
    selectedChoice: "",
    answerSubmitted: false,
  } as TSession;

  const nextReviewStateMap =
    !undoneRecord.isHistoryOnly && undoneRecord.reviewStateBefore
      ? {
          ...reviewStateMap,
          [normalizedReviewKey(undoneRecord.term)]: undoneRecord.reviewStateBefore,
        }
      : reviewStateMap;

  let removed = false;
  const nextReviewHistory = reviewHistory.filter((record) => {
    if (!removed && sameReviewRecord(record, undoneRecord)) {
      removed = true;
      return false;
    }

    return true;
  });

  return {
    session: nextSession,
    reviewHistory: nextReviewHistory,
    reviewStateMap: nextReviewStateMap,
    undoneRecord,
  };
}

export function reviewLevelLabel(level: ReviewLevel): string {
  switch (level) {
    case 0:
      return "Unknown";
    case 1:
      return "Shaky";
    case 2:
      return "Familiar";
    case 3:
      return "Comfortable";
    case 4:
      return "Mastered";
    default:
      return "Unknown";
  }
}

export function normalizeReviewDecision(value: unknown): ReviewDecision | null {
  if (value === "again" || value === "hard" || value === "good" || value === "easy") {
    return value;
  }

  if (value === "downgrade") {
    return "again";
  }

  if (value === "keep") {
    return "hard";
  }

  if (value === "upgrade") {
    return "good";
  }

  return null;
}

export function nextReviewLevel(current: ReviewLevel, decision: ReviewDecision): ReviewLevel {
  switch (decision) {
    case "again":
      return Math.max(0, current - 1) as ReviewLevel;
    case "hard":
      return current;
    case "good":
      return Math.min(4, current + 1) as ReviewLevel;
    case "easy":
      return Math.min(4, current + 1) as ReviewLevel;
    default:
      return current;
  }
}

export function nextReviewState(
  current: ReviewStateRecord | undefined,
  decision: ReviewDecision,
  answeredAt: number,
): ReviewStateRecord {
  const state = current ?? defaultReviewState();
  const nextLevel = nextReviewLevel(state.level, decision);

  return {
    level: nextLevel,
    reviewCount: state.reviewCount + 1,
    lastReviewedAt: answeredAt,
    dueAt: nextReviewDueAt(state.level, nextLevel, decision, answeredAt),
    streak:
      decision === "good" || decision === "easy"
        ? state.streak + 1
        : decision === "hard"
          ? state.streak
          : 0,
    lapseCount: state.lapseCount + (decision === "again" ? 1 : 0),
    lastDecision: decision,
  };
}

const hourMs = 60 * 60 * 1000;
const dayMs = 24 * hourMs;
const reviewSpacingByLevel: Record<ReviewLevel, number> = {
  0: 8 * hourMs,
  1: dayMs,
  2: 3 * dayMs,
  3: 7 * dayMs,
  4: 21 * dayMs,
};

function nextReviewDueAt(
  currentLevel: ReviewLevel,
  nextLevel: ReviewLevel,
  decision: ReviewDecision,
  answeredAt: number,
): number {
  if (decision === "again") {
    return answeredAt + (nextLevel === 0 ? 20 * 60 * 1000 : 4 * hourMs);
  }

  if (decision === "hard") {
    return answeredAt + Math.max(4 * hourMs, Math.round(reviewSpacingByLevel[currentLevel] * 0.45));
  }

  if (decision === "easy") {
    return answeredAt + Math.round(reviewSpacingByLevel[nextLevel] * 1.6);
  }

  return answeredAt + reviewSpacingByLevel[nextLevel];
}

export function isReviewDue(state: ReviewStateRecord, now = Date.now()): boolean {
  if (state.reviewCount === 0 || state.lastReviewedAt === null) {
    return true;
  }

  return state.dueAt === null || state.dueAt <= now;
}

export function reviewDueBucket(
  state: ReviewStateRecord,
  now = Date.now(),
): "new" | "dueNow" | "dueSoon" | "scheduled" {
  if (state.reviewCount === 0 || state.lastReviewedAt === null) {
    return "new";
  }

  if (state.dueAt === null || state.dueAt <= now) {
    return "dueNow";
  }

  if (state.dueAt - now <= 2 * dayMs) {
    return "dueSoon";
  }

  return "scheduled";
}

export function reviewDueLabel(state: ReviewStateRecord, now = Date.now()): string {
  const bucket = reviewDueBucket(state, now);

  if (bucket === "new") {
    return "New";
  }

  if (bucket === "dueNow") {
    return "Due now";
  }

  if (bucket === "dueSoon") {
    return `Due ${formatReviewDueDistance(state.dueAt ?? now, now)}`;
  }

  return `Scheduled ${formatReviewDueDistance(state.dueAt ?? now, now)}`;
}

function formatReviewDueDistance(targetAt: number, now: number): string {
  const distanceMs = Math.max(0, targetAt - now);
  const distanceHours = Math.round(distanceMs / hourMs);

  if (distanceHours < 24) {
    return `in ${Math.max(1, distanceHours)}h`;
  }

  const distanceDays = Math.round(distanceMs / dayMs);
  return `in ${Math.max(1, distanceDays)}d`;
}

export function buildReviewCandidates(
  historyItems: ActivityItem[],
  inboxItems: ActivityItem[],
  libraryEntries: LibraryEntry[],
  activeSources: Set<ReviewSourceKind>,
  sort: ReviewSortOption,
  reviewStateMap: ReviewStateMap,
  excludeMastered = false,
  inboxDrafts: Record<string, ReviewDraftEntry> = {},
): ReviewCandidate[] {
  const merged = new Map<
    string,
    ReviewCandidate & {
      sourcePriority: number;
    }
  >();

  function mergeCandidate(
    seed: {
      term: string;
      detail: string;
      partOfSpeech?: string;
      example?: string;
      context: string;
      notes?: string;
      selectedMeanings?: string[];
      selectedExamples?: string[];
      referenceTags?: string[];
      savedAt: number;
      favorite?: boolean;
      hasBackingEntry: boolean;
    },
    source: ReviewSourceKind,
    sourcePriority: number,
  ) {
    const key = normalizedReviewKey(seed.term);
    if (!key || looksLikeSentence(seed.term)) {
      return;
    }

    const state = reviewStateMap[key] ?? defaultReviewState();
    const existing = merged.get(key);
    if (existing) {
      if (!existing.sourceKinds.includes(source)) {
        existing.sourceKinds.push(source);
      }

      if (seed.favorite) {
        existing.favorite = true;
      }

      existing.hasBackingEntry = existing.hasBackingEntry || seed.hasBackingEntry;
      existing.savedAt = Math.max(existing.savedAt, seed.savedAt);
      existing.reviewLevel = state.level;
      existing.reviewCount = Math.max(existing.reviewCount, state.reviewCount);
      existing.lastReviewedAt = state.lastReviewedAt;

      if (sourcePriority >= existing.sourcePriority) {
        existing.term = seed.term;
        existing.detail = seed.detail || existing.detail;
        existing.partOfSpeech = seed.partOfSpeech || existing.partOfSpeech;
        existing.example = seed.example || existing.example;
        existing.context = seed.context || existing.context;
        existing.notes = seed.notes ?? existing.notes;
        existing.selectedMeanings = mergeUniqueTexts(seed.selectedMeanings, existing.selectedMeanings);
        existing.selectedExamples = mergeUniqueTexts(seed.selectedExamples, existing.selectedExamples);
        existing.referenceTags = mergeUniqueTexts(seed.referenceTags, existing.referenceTags);
        existing.sourcePriority = sourcePriority;
      } else {
        if (!existing.partOfSpeech && seed.partOfSpeech) {
          existing.partOfSpeech = seed.partOfSpeech;
        }
        if (!existing.example && seed.example) {
          existing.example = seed.example;
        }
        if (!existing.context && seed.context) {
          existing.context = seed.context;
        }
        if (!existing.notes && seed.notes) {
          existing.notes = seed.notes;
        }
        if (!existing.detail && seed.detail) {
          existing.detail = seed.detail;
        }
        if (seed.selectedMeanings?.length) {
          existing.selectedMeanings = mergeUniqueTexts(existing.selectedMeanings, seed.selectedMeanings);
        }
        if (seed.selectedExamples?.length) {
          existing.selectedExamples = mergeUniqueTexts(existing.selectedExamples, seed.selectedExamples);
        }
        if (seed.referenceTags?.length) {
          existing.referenceTags = mergeUniqueTexts(existing.referenceTags, seed.referenceTags);
        }
      }

      return;
    }

    merged.set(key, {
      id: key,
      term: seed.term,
      detail: seed.detail,
      partOfSpeech: seed.partOfSpeech ?? "",
      example: seed.example ?? "",
      context: seed.context,
      notes: seed.notes ?? "",
      selectedMeanings: mergeUniqueTexts(seed.selectedMeanings, seed.detail ? [seed.detail] : []),
      selectedExamples: mergeUniqueTexts(seed.selectedExamples, seed.example ? [seed.example] : []),
      referenceTags: mergeUniqueTexts(seed.referenceTags),
      savedAt: seed.savedAt,
      sourceKinds: [source],
      hasBackingEntry: seed.hasBackingEntry,
      favorite: seed.favorite ?? false,
      reviewLevel: state.level,
      reviewCount: state.reviewCount,
      lastReviewedAt: state.lastReviewedAt,
      sourcePriority,
    });
  }

  if (activeSources.has("library")) {
    for (const entry of libraryEntries) {
      const selectedMeanings = selectedMeaningsFromEntry(entry).join(" / ");
      const selectedExample = selectedExamplesFromEntry(entry)[0] ?? "";
      mergeCandidate(
        {
          term: entry.term,
          detail: selectedMeanings || entry.detail,
          partOfSpeech: entry.partOfSpeech,
          example: selectedExample,
          context: entry.context,
          notes: entry.notes,
          selectedMeanings: selectedMeaningsFromEntry(entry),
          selectedExamples: selectedExamplesFromEntry(entry),
          referenceTags: entry.referenceTags,
          savedAt: entry.updatedAt,
          favorite: entry.favorite,
          hasBackingEntry: true,
        },
        "library",
        3,
      );
    }
  }

  if (activeSources.has("favorites")) {
    for (const entry of libraryEntries) {
      if (!entry.favorite) {
        continue;
      }

      const selectedMeanings = selectedMeaningsFromEntry(entry).join(" / ");
      const selectedExample = selectedExamplesFromEntry(entry)[0] ?? "";
      mergeCandidate(
        {
          term: entry.term,
          detail: selectedMeanings || entry.detail,
          partOfSpeech: entry.partOfSpeech,
          example: selectedExample,
          context: entry.context,
          notes: entry.notes,
          selectedMeanings: selectedMeaningsFromEntry(entry),
          selectedExamples: selectedExamplesFromEntry(entry),
          referenceTags: entry.referenceTags,
          savedAt: entry.updatedAt,
          favorite: true,
          hasBackingEntry: true,
        },
        "favorites",
        4,
      );
    }
  }

  if (activeSources.has("history")) {
    for (const item of historyItems) {
      mergeCandidate(
        {
          term: item.term,
          detail: item.detail,
          partOfSpeech: "",
          example: "",
          context: item.context ?? "",
          savedAt: item.savedAt,
          hasBackingEntry: false,
        },
        "history",
        1,
      );
    }
  }

  const candidates = Array.from(merged.values()).filter(
    (candidate) => !(excludeMastered && candidate.reviewLevel >= 4),
  );

  if (sort === "newestFirst") {
    return candidates.sort((left, right) => right.savedAt - left.savedAt);
  }

  if (sort === "alphabetical") {
    return candidates.sort((left, right) => left.term.localeCompare(right.term));
  }

  if (sort === "leastRecentlyReviewed") {
    return candidates.sort((left, right) => {
      if (left.lastReviewedAt === null && right.lastReviewedAt !== null) {
        return -1;
      }

      if (left.lastReviewedAt !== null && right.lastReviewedAt === null) {
        return 1;
      }

      if (left.lastReviewedAt !== right.lastReviewedAt) {
        return (left.lastReviewedAt ?? 0) - (right.lastReviewedAt ?? 0);
      }

      if (left.reviewLevel !== right.reviewLevel) {
        return left.reviewLevel - right.reviewLevel;
      }

      return left.term.localeCompare(right.term);
    });
  }

  return candidates.sort((left, right) => {
    if (left.hasBackingEntry !== right.hasBackingEntry) {
      return left.hasBackingEntry ? -1 : 1;
    }

    if (left.reviewLevel !== right.reviewLevel) {
      return left.reviewLevel - right.reviewLevel;
    }

    if (left.lastReviewedAt === null && right.lastReviewedAt !== null) {
      return -1;
    }

    if (left.lastReviewedAt !== null && right.lastReviewedAt === null) {
      return 1;
    }

    if (left.lastReviewedAt !== right.lastReviewedAt) {
      return (left.lastReviewedAt ?? 0) - (right.lastReviewedAt ?? 0);
    }

    if (left.favorite !== right.favorite) {
      return left.favorite ? -1 : 1;
    }

    if (left.sourceKinds.length !== right.sourceKinds.length) {
      return right.sourceKinds.length - left.sourceKinds.length;
    }

    return right.savedAt - left.savedAt;
  });
}

function shuffle<T>(items: T[]): T[] {
  const copy = [...items];
  for (let index = copy.length - 1; index > 0; index -= 1) {
    const swapIndex = Math.floor(Math.random() * (index + 1));
    [copy[index], copy[swapIndex]] = [copy[swapIndex]!, copy[index]!];
  }
  return copy;
}

export function buildReviewCard(
  candidate: ReviewCandidate,
  snapshot: ReviewLookupSnapshot | null,
  questionType: ReviewQuestionType,
  distractorPool: ReviewCandidate[],
): ReviewCard {
  const primaryMeaning = primaryMeaningText(snapshot, candidate);
  const headword = snapshot?.headword ?? candidate.term;
  const meaningChoices = meaningAnswerChoices(snapshot, candidate);
  const joinedMeanings = meaningChoices.join(" / ") || primaryMeaning;
  const supportingText = candidateSupportingText(candidate);
  const promptHint = reviewPromptHint(candidate);

  if (questionType === "flashcards" && candidate.reviewLevel >= 2) {
    return {
      family: "flashcards",
      questionType,
      prompt: primaryMeaning,
      promptTitle: "Flashcard · Meaning to Term",
      promptHint,
      supportingText,
      answer: headword,
      acceptedAnswers: mergeUniqueTexts([headword, candidate.term]),
      distractors: [],
    };
  }

  if (questionType === "flashcards") {
    return {
      family: "flashcards",
      questionType,
      prompt: headword,
      promptTitle: "Flashcard · Term to Meaning",
      promptHint,
      supportingText,
      answer: joinedMeanings,
      acceptedAnswers: meaningChoices.length > 0 ? meaningChoices : [primaryMeaning],
      distractors: [],
    };
  }

  if (questionType === "fillIn") {
    return {
      family: "fillIn",
      questionType,
      prompt: primaryMeaning,
      promptTitle: "Fill In · Meaning to Term",
      promptHint,
      supportingText,
      answer: headword,
      acceptedAnswers: mergeUniqueTexts([headword, candidate.term]),
      distractors: [],
    };
  }

  const wrongChoices = shuffle(
    distractorPool
      .filter((item) => normalizedReviewKey(item.term) !== normalizedReviewKey(candidate.term))
      .map((item) => primaryMeaningText(null, item))
      .filter(Boolean),
  ).slice(0, 3);

  if (wrongChoices.length < 2) {
    return {
      family: "flashcards",
      questionType: "flashcards",
      prompt: headword,
      promptTitle: "Flashcard · Term to Meaning",
      promptHint,
      supportingText,
      answer: joinedMeanings,
      acceptedAnswers: meaningChoices.length > 0 ? meaningChoices : [primaryMeaning],
      distractors: [],
    };
  }

  return {
    family: "multipleChoice",
    questionType,
    prompt: headword,
    promptTitle: "Multiple Choice · Term to Meaning",
    promptHint,
    supportingText,
    answer: primaryMeaning,
    acceptedAnswers: [primaryMeaning],
    distractors: shuffle([primaryMeaning, ...wrongChoices]),
  };
}

const defaultReviewQuestionTypes: ReviewQuestionType[] = ["multipleChoice", "fillIn", "flashcards"];

function uniqueReviewQuestionTypes(questionTypes: ReviewQuestionType[]): ReviewQuestionType[] {
  const allowed = new Set(defaultReviewQuestionTypes);
  const unique: ReviewQuestionType[] = [];

  for (const questionType of questionTypes) {
    if (allowed.has(questionType) && !unique.includes(questionType)) {
      unique.push(questionType);
    }
  }

  return unique;
}

function reviewQuestionTypeSeed(candidate: Pick<ReviewCandidate, "id" | "reviewCount" | "term">): number {
  return Array.from(candidate.id).reduce(
    (partialResult, char) => (partialResult * 31 + (char.codePointAt(0) ?? 0)) % 9973,
    candidate.reviewCount + candidate.term.length,
  );
}

function chooseReviewQuestionType(
  candidate: Pick<ReviewCandidate, "id" | "reviewCount" | "term">,
  questionTypes: ReviewQuestionType[],
): ReviewQuestionType {
  if (questionTypes.length === 0) {
    return "multipleChoice";
  }

  if (questionTypes.length === 1) {
    return questionTypes[0]!;
  }

  const index = Math.abs(reviewQuestionTypeSeed(candidate)) % questionTypes.length;
  return questionTypes[index] ?? "multipleChoice";
}

export function selectReviewQuestionTypeForCandidate(
  candidate: Pick<ReviewCandidate, "id" | "reviewCount" | "term">,
  questionTypes: ReviewQuestionType[],
): ReviewQuestionType {
  return chooseReviewQuestionType(candidate, uniqueReviewQuestionTypes(questionTypes));
}

const smartReviewQuestionTypeWeights: Record<ReviewLevel, ReviewQuestionType[]> = {
  0: ["multipleChoice", "multipleChoice", "flashcards"],
  1: ["multipleChoice", "flashcards", "fillIn"],
  2: ["fillIn", "multipleChoice", "flashcards"],
  3: ["fillIn", "fillIn", "flashcards"],
  4: ["fillIn", "flashcards", "fillIn"],
};

export function selectSmartReviewQuestionTypeForCandidate(
  candidate: Pick<ReviewCandidate, "id" | "reviewCount" | "term" | "reviewLevel">,
  questionTypes: ReviewQuestionType[],
): ReviewQuestionType {
  const allowedTypes = uniqueReviewQuestionTypes(questionTypes);
  const enabledTypes = allowedTypes.length > 0 ? allowedTypes : defaultReviewQuestionTypes;
  const weightedTypes = smartReviewQuestionTypeWeights[candidate.reviewLevel].filter((type) =>
    enabledTypes.includes(type),
  );

  if (weightedTypes.length === 0) {
    return chooseReviewQuestionType(candidate, enabledTypes);
  }

  return chooseReviewQuestionType(candidate, weightedTypes);
}

export function reviewQuestionFamily(questionType: ReviewQuestionType): ReviewQuestionFamily {
  switch (questionType) {
    case "multipleChoice":
      return "multipleChoice";
    case "fillIn":
      return "fillIn";
    case "flashcards":
      return "flashcards";
    default:
      return "multipleChoice";
  }
}

export function matchesSubmittedAnswer(submission: string, acceptedAnswers: string[]): boolean {
  const normalizedSubmission = normalizedComparableText(submission);
  if (!normalizedSubmission) {
    return false;
  }

  return acceptedAnswers.some((accepted) => {
    const normalizedAccepted = normalizedComparableText(accepted);
    if (!normalizedAccepted) {
      return false;
    }

    if (normalizedSubmission === normalizedAccepted) {
      return true;
    }

    const acceptedSegments = answerSegments(accepted)
      .map((segment) => normalizedComparableText(segment))
      .filter(Boolean);
    return acceptedSegments.includes(normalizedSubmission);
  });
}

function normalizedComparableText(text: string): string {
  return text
    .trim()
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\s'-]/gu, " ")
    .replace(/\s+/g, " ");
}

function answerSegments(text: string): string[] {
  return text
    .split(/[;,/|，；、]/)
    .map((segment) => segment.trim())
    .filter(Boolean);
}

export function lookupSnapshotFromApiData(data: {
  entry: {
    headword: string;
    phonetic: string;
    level: string;
    summary: string;
    source_tags: string[];
    meaning_groups: Array<{
      partOfSpeech: string;
      definitions: string[];
    }>;
    english_definitions: string[];
    inflection_lines: string[];
    collocations: string[];
    related_terms: string[];
    examples: Array<{
      english: string;
      chinese: string;
    }>;
  } | null;
} | null): ReviewLookupSnapshot | null {
  if (!data?.entry) {
    return null;
  }

  const entry = data.entry;
  return {
    term: entry.headword,
    headword: entry.headword,
    pronunciation: entry.phonetic,
    level: entry.level || "Dictionary",
    summary: entry.summary,
    sourceTags: entry.source_tags,
    meaningGroups: entry.meaning_groups,
    examples: entry.examples,
    collocations: entry.collocations,
    relatedTerms: entry.related_terms,
    englishDefinitions: entry.english_definitions,
    inflectionLines: entry.inflection_lines,
    contextText: entry.examples[0]?.english ?? "",
  };
}
