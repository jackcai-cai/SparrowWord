"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import {
  Children,
  startTransition,
  useEffect,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type ChangeEvent,
  type FormEvent,
  type PointerEvent as ReactPointerEvent,
  type ReactNode,
} from "react";

import { loadSentenceStudy } from "../../lib/dict-api";
import { dictApiBaseUrl } from "../../lib/dict-api-base";
import type {
  ActivityItem,
  ActivityMeta,
  LookupKind,
  LookupResult,
  SuggestionItem,
  WorkspaceState,
} from "../../lib/mock-workspace";
import {
  buildReviewCandidates,
  buildReviewCard,
  defaultReviewState,
  isReviewDue,
  lookupSnapshotFromApiData,
  matchesSubmittedAnswer,
  nextReviewState,
  normalizeReviewDecision,
  normalizedReviewKey,
  reviewDueBucket,
  reviewDueLabel,
  reviewLevelLabel,
  reviewStateForTerm,
  selectReviewQuestionTypeForCandidate,
  selectSmartReviewQuestionTypeForCandidate,
  undoLastReviewRating,
  type ReviewCard,
  type ReviewCandidate,
  type ReviewDecision,
  type ReviewLookupSnapshot,
  type ReviewLevel,
  type ReviewQuestionFamily,
  type ReviewQuestionStrategy,
  type ReviewQuestionType,
  type ReviewRecord,
  type ReviewSortOption,
  type ReviewSourceKind,
  type ReviewStateMap,
  type ReviewStateRecord,
} from "../../lib/review";
import {
  addEntriesToLibraryArrangement,
  createLibraryArrangement,
  entriesForLibraryArrangement,
  moveEntryInLibraryArrangement,
  normalizeLibraryArrangements,
  parseStoredLibraryArrangements,
  replaceLibraryArrangementEntries,
  renameLibraryArrangement,
  removeEntriesFromLibraryArrangement,
  removeLibraryArrangement,
  type SavedLibraryArrangement,
} from "../../lib/workspace-arrangements";
import {
  automaticPronunciationVoiceURI,
  defaultWorkspacePreferences,
  parseStoredWorkspacePreferences,
  workspaceLayoutLimits,
  type WorkspacePaneLayoutPreference,
  type WorkspacePreferences,
} from "../../lib/workspace-preferences";
import {
  buildEnglishDefinitionPresentation,
  splitPronunciationLines,
} from "../../lib/english-definition-presentation";
import {
  appendTrashItems,
  parseStoredTrashItems,
  removeTrashItems,
  trashItemFromActivity,
  trashItemFromLibrary,
  type WorkspaceTrashItem,
} from "../../lib/workspace-trash";
import {
  duplicateLibraryEntries,
  mergeDuplicateLibraryEntries,
  parseStoredLibraryEntries,
  removeLibraryEntry,
  restoreLibraryEntry,
  updateLibraryEntry,
  upsertLibraryEntry,
  type LibraryEntry,
} from "../../lib/workspace-library";
import { migrateLegacyInboxState } from "../../lib/inbox-migration";
import {
  buildQuickCaptureEditableEntry,
  createQuickCaptureDraftRecord,
  parseStoredQuickCaptureDraftMap,
  quickCaptureFormStateFromEntry,
  removeQuickCaptureDraft,
  upsertQuickCaptureDraft,
  type QuickCaptureDraftMap,
} from "../../lib/quick-capture";
import {
  dedupeEditableChoiceState,
  keepOnlySelectedEditableChoices,
  createEditableEntry,
  editableExampleChoiceCount,
  editableMeaningChoiceCount,
  meaningCandidatesFromChoices,
  parseStoredEditableEntryMap,
  reorderEditableChoiceState,
  sanitizeInlineText,
  sanitizeParagraphText,
  selectedExamplesFromEntry,
  selectedMeaningsFromEntry,
  type MeaningCandidate,
  type WorkspaceEditableEntry,
} from "../../lib/workspace-entry";

type WorkspaceSection = "lookup" | "inbox" | "library" | "review" | "history";
type ActivityKind = "history" | "inbox";
type LibraryFilter = "all" | "favorites" | `saved:${string}`;
type LibraryLevelFilter = "all" | `${ReviewLevel}`;
type LibrarySortOption = "updatedNewest" | "updatedOldest" | "weakestFirst" | "alphabetical";
type InboxSortOption = "savedNewest" | "savedOldest" | "alphabetical";
type HistorySortOption = "savedNewest" | "savedOldest" | "alphabetical";
type LookupFetchStatus = "idle" | "loading" | "error";
type SettingsPanel = "general" | "study" | "resources" | "recovery";

type WorkspaceClientProps = {
  initialClientId: string | null;
  initialWorkspace: WorkspaceState;
  initialHistoryItems: ActivityItem[];
  initialInboxItems: ActivityItem[];
  initialPersistedState: unknown | null;
  initialSection: WorkspaceSection;
  initialKind: LookupKind;
  initialContext: string;
  initialSelectedActivityId: string | null;
  initialSelectedLibraryEntryId: string | null;
  initialSource: string | null;
  starterQueries: string[];
};

type WorkspaceLayoutStyle = CSSProperties & {
  "--desk-sidebar-width": string;
  "--desk-content-rail-width": string;
};

type WorkspaceContentGridProps = {
  children: ReactNode;
  layoutPreference: WorkspacePaneLayoutPreference;
  onResizeStart: (event: ReactPointerEvent<HTMLDivElement>) => void;
  onResetLayout: () => void;
};

function WorkspaceContentGrid({
  children,
  layoutPreference,
  onResizeStart,
  onResetLayout,
}: WorkspaceContentGridProps) {
  const panes = Children.toArray(children);
  const [leadingPane, ...trailingPanes] = panes;
  const showsHorizontalResizer = trailingPanes.length > 0 && layoutPreference !== "vertical";

  return (
    <div className="desk-content-grid" data-layout={layoutPreference}>
      {leadingPane}
      {showsHorizontalResizer ? (
        <div
          aria-label="Resize workspace columns"
          aria-orientation="vertical"
          className="desk-layout-resizer desk-content-resizer"
          onDoubleClick={onResetLayout}
          onPointerDown={onResizeStart}
          role="separator"
          tabIndex={0}
          title="Drag to resize. Double-click to reset layout."
        />
      ) : null}
      {trailingPanes}
    </div>
  );
}

type ActivityEnvelope = {
  ok: boolean;
  data: {
    client_id: string;
    items: Array<{
      id: string;
      term: string;
      detail: string;
      context: string;
      saved_at: number;
      meta?: ActivityMeta | null;
    }>;
  } | null;
};

type LookupProxyEnvelope = {
  ok: boolean;
  data: {
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
  } | null;
};

type ReviewSessionState = {
  sessionId: string;
  queue: string[];
  index: number;
  records: ReviewRecord[];
  activeCandidateId: string | null;
  draftAnswer: string;
  selectedChoice: string;
  answerSubmitted: boolean;
  questionTypes: ReviewQuestionType[];
  questionStrategy: ReviewQuestionStrategy;
  styleTitle: string;
  styleDetail: string;
  startedAt: number;
  pausedAt: number | null;
  sourceKinds: ReviewSourceKind[];
};

type ReviewQuickFilter =
  | "all"
  | "dueNow"
  | "unknown"
  | "needsWork"
  | "recentMistakes"
  | "favoritesOnly"
  | "historyOnly";

type SentenceStudyCandidate = {
  term: string;
  kind: LookupKind;
  score: number;
  reason: string;
  summary: string;
};

type ReviewHistoryRound = {
  sessionId: string;
  answeredAt: number;
  items: ReviewRecord[];
  sourceKinds: ReviewSourceKind[];
};

type DictApiHealth = {
  service: string;
  ok: boolean;
  phase: string;
  ready?: boolean;
  required_dictionaries?: string[];
  missing_required_dictionaries?: string[];
  dictionaries: {
    ecdict: boolean;
    cedict: boolean;
    oewn: boolean;
    tatoeba: boolean;
    paths: {
      ecdict: string;
      cedict: string;
      oewn: string;
      tatoeba: string;
    };
  };
  storage: {
    activity_store?: {
      available: boolean;
      path: string;
    };
    feedback_log?: {
      path: string;
    };
  };
  runtime?: {
    reverse_lookup_cache?: {
      entries: number;
      hits: number;
      misses: number;
      ttl_seconds: number;
    };
    sentence_study_cache?: {
      entries: number;
      hits: number;
      misses: number;
      ttl_seconds: number;
    };
  };
};

type WorkspaceHeroStat = {
  label: string;
  value: string;
};

type InboxDraftDigest = {
  selectedMeaningCount: number;
  selectedExampleCount: number;
  hasContext: boolean;
  hasNotes: boolean;
  score: number;
  isReady: boolean;
  stageLabel: string;
  primaryMeaning: string;
  primaryExample: string;
};

type LibraryEntryDigest = {
  selectedMeaningCount: number;
  selectedExampleCount: number;
  primaryMeaning: string;
  primaryExample: string;
  collectionNames: string[];
  duplicateCount: number;
  collectibleLabel: string;
  collectibleHint: string;
  reviewSummary: string;
};

type ReviewSessionDigest = {
  answeredCount: number;
  remainingCount: number;
  completionPercent: number;
  againCount: number;
  hardCount: number;
  goodCount: number;
  easyCount: number;
  currentStreak: number;
  momentumLabel: string;
  reviewPulse: string;
};

type ReviewDueDigest = {
  dueNow: number;
  dueSoon: number;
  scheduled: number;
  fresh: number;
};

type ReviewClusterDigest = {
  label: string;
  count: number;
  detail: string;
};

type SentenceMagicSummary = {
  candidateCount: number;
  tokenCount: number;
  matchedEntryCount: number;
  wordCount: number;
  phraseCount: number;
  strongestTerm: string;
  strongestReason: string;
  sourcePreview: string;
  engineLabel: string;
};

type QuickCapturePreset = {
  id: string;
  label: string;
  caption: string;
  term: string;
  kind: LookupKind;
  context: string;
  reviewLevel: ReviewLevel;
  entry: WorkspaceEditableEntry | null;
};

type QuickCaptureImportItem = {
  id: string;
  term: string;
  context: string;
  kind: LookupKind;
};

type WorkspacePersistenceSnapshot = {
  libraryEntries: LibraryEntry[];
  savedLibraryArrangements: SavedLibraryArrangement[];
  inboxEntryDrafts: Record<string, WorkspaceEditableEntry>;
  quickCaptureDrafts: QuickCaptureDraftMap;
  reviewStateMap: ReviewStateMap;
  reviewHistory: ReviewRecord[];
  reviewSession: ReviewSessionState | null;
  workspacePreferences: WorkspacePreferences;
  trashItems: WorkspaceTrashItem[];
};

type WorkspaceBackupPayload = {
  version: 1 | 2;
  exportedAt: string;
  clientId: string | null;
  inboxItems: ActivityItem[];
  historyItems: ActivityItem[];
  snapshot: WorkspacePersistenceSnapshot;
};

const sectionLabels: Record<WorkspaceSection, string> = {
  lookup: "Lookup",
  inbox: "Inbox",
  library: "Library",
  review: "Review",
  history: "History",
};

const lookupKindLabels: Record<LookupKind, string> = {
  word: "Word",
  phrase: "Phrase",
  sentence: "Sentence",
};

const libraryFilterLabels: Record<LibraryFilter, string> = {
  all: "All Library",
  favorites: "Favorites",
};

const settingsPanelLabels: Record<SettingsPanel, string> = {
  general: "General",
  study: "Study",
  resources: "Resources & AI",
  recovery: "Data & Recovery",
};

const settingsPanelSearchText: Record<SettingsPanel, string> = {
  general: "general interface voice pronunciation layout library clean view settings tags frequency dictionary",
  study: "study review mastered familiarity learning defaults",
  resources: "resources ai api dictionary offline sentence health runtime caches model",
  recovery: "recovery data trash backup diagnostics reset import export workspace",
};

const workspacePaneLayoutLabels: Record<WorkspacePaneLayoutPreference, string> = {
  automatic: "Automatic",
  horizontal: "Side by Side",
  vertical: "Top and Bottom",
};

const reviewSourceLabels: Record<ReviewSourceKind, string> = {
  library: "Library",
  favorites: "Favorites",
  history: "History",
};
const reviewSourceOrder = ["library", "favorites", "history"] as const satisfies readonly ReviewSourceKind[];
const defaultReviewSources = ["library"] as const satisfies readonly ReviewSourceKind[];

const reviewQuestionTypeLabels: Record<ReviewQuestionType, { title: string; detail: string }> = {
  multipleChoice: {
    title: "Multiple Choice",
    detail: "Show the term first and pick the best meaning.",
  },
  fillIn: {
    title: "Fill In",
    detail: "Show the meaning first and type the English term.",
  },
  flashcards: {
    title: "Flashcards",
    detail: "Flip the card, then rate how stable it felt.",
  },
};

const reviewQuestionStrategyLabels: Record<ReviewQuestionStrategy, { title: string; detail: string }> = {
  smart: {
    title: "Smart Mix",
    detail: "Default. Weaker terms lean on recognition; stable terms move toward recall.",
  },
  custom: {
    title: "Custom Mix",
    detail: "Use only the selected formats and rotate them evenly across the round.",
  },
};

const reviewQuickFilterLabels: Record<ReviewQuickFilter, string> = {
  all: "All",
  dueNow: "Due Now",
  unknown: "Unknown",
  needsWork: "Needs Work",
  recentMistakes: "Recent Mistakes",
  favoritesOnly: "Favorites",
  historyOnly: "History Only",
};

const reviewDecisionLabels: Record<ReviewDecision, { title: string; detail: string }> = {
  again: {
    title: "Again",
    detail: "Missed it or guessed. Bring it back very soon.",
  },
  hard: {
    title: "Hard",
    detail: "Remembered it, but not comfortably. Keep the level and shorten the interval.",
  },
  good: {
    title: "Good",
    detail: "Solid recall. Move it forward on the normal schedule.",
  },
  easy: {
    title: "Easy",
    detail: "Immediate recall. Move it forward with a longer interval.",
  },
};

type ReviewRoundSize = "10" | "20" | "50" | "all";
type ReviewHistorySourceFilter = "all" | ReviewSourceKind;
type ReviewHistoryDecisionFilter = "all" | ReviewDecision;

const libraryStorageKey = "sparrowword-library";
const inboxDraftStorageKey = "sparrowword-inbox-drafts";
const quickCaptureDraftStorageKey = "sparrowword-quick-capture-drafts";
const reviewStateStorageKey = "sparrowword-review-state";
const reviewHistoryStorageKey = "sparrowword-review-history";
const reviewSessionStorageKey = "sparrowword-review-session";
const workspacePreferencesStorageKey = "sparrowword-workspace-preferences";
const trashStorageKey = "sparrowword-trash";
const libraryArrangementsStorageKey = "sparrowword-library-arrangements";
const reviewLevelOptions: ReviewLevel[] = [0, 1, 2, 3, 4];

const historyStatusLabels: Record<NonNullable<ActivityMeta["status"]>, string> = {
  inProgress: "In Progress",
  completed: "Completed",
  cancelled: "Cancelled",
  failed: "Failed",
};

const historyStudyActionLabels: Record<NonNullable<ActivityMeta["inboxAction"]>, string> = {
  createdInbox: "Saved to Quick Capture Drafts",
  updatedInbox: "Updated Quick Capture Draft",
  skippedExistingLibrary: "Already in Library",
  historyOnly: "History Only",
  awaitingCandidateSelection: "Awaiting Study Choice",
};

const trashSourceLabels: Record<WorkspaceTrashItem["source"], string> = {
  inbox: "Quick Capture Draft",
  history: "History",
  library: "Library",
};

const historyLookupModeLabels: Record<NonNullable<ActivityMeta["lookupMode"]>, string> = {
  empty: "Empty",
  lookup: "Lookup",
  reverse: "Reverse Lookup",
  "no-result": "No Result",
};

function buildLookupRequestUrl(term: string): string {
  const url = new URL("/lookup", dictApiBaseUrl());
  url.searchParams.set("q", term);
  return url.toString();
}

function buildActivityRequestUrl(kind: ActivityKind): string {
  return new URL(`/${kind}`, dictApiBaseUrl()).toString();
}

function clampWorkspaceLayoutValue(value: number, min: number, max: number): number {
  return Math.min(Math.max(Math.round(value), min), max);
}

function reviewSourceSummary(sourceKinds: ReviewSourceKind[]): string {
  return sourceKinds.map((source) => reviewSourceLabels[source]).join(" · ");
}

function reviewDecisionLabel(decision: ReviewDecision): string {
  return reviewDecisionLabels[decision].title;
}

function reviewAdvanceButtonLabel(decision: ReviewDecision, remainingCardsAfterCurrent: number): string {
  const action = remainingCardsAfterCurrent <= 0 ? "Save & Finish" : "Save & Next";
  return `${action} · ${reviewDecisionLabel(decision)}`;
}

function reviewAdvanceSummary(options: {
  decision: ReviewDecision;
  family: ReviewQuestionFamily;
  correct: boolean | null;
  remainingCardsAfterCurrent: number;
}): string {
  const { decision, family, correct, remainingCardsAfterCurrent } = options;
  const isLastCard = remainingCardsAfterCurrent <= 0;

  if (family === "flashcards") {
    return isLastCard
      ? "This is the last card in the round. Save a rating to finish, and use Undo on the next screen if you need to reopen it."
      : "Pick a rating, save it, and move straight to the next card.";
  }

  if (correct) {
    if (isLastCard) {
      return `This is the last card in the round. Save ${reviewDecisionLabel(decision)} to finish and return to the review queue.`;
    }

    return `Save ${reviewDecisionLabel(decision)} and move to the next card, or switch to Hard or Easy if that fits better.`;
  }

  if (isLastCard) {
    return `This is the last card in the round. Save ${reviewDecisionLabel(decision)} to finish, and it will come back quickly in the next queue.`;
  }

  return `Save ${reviewDecisionLabel(decision)} now and it will come back very soon in this study cycle.`;
}

function isStableReviewDecision(decision: ReviewDecision): boolean {
  return decision === "good" || decision === "easy";
}

function isWeakReviewRecord(record: ReviewRecord): boolean {
  return record.decision === "again" || record.decision === "hard" || record.correct === false;
}

function reviewSourceSelectionLabel(sourceKinds: Set<ReviewSourceKind>): string {
  const ordered = reviewSourceOrder.filter((source) => sourceKinds.has(source));
  if (ordered.length === 0) {
    return "No Sources";
  }
  if (ordered.length === reviewSourceOrder.length) {
    return "All Sources";
  }
  return ordered.map((source) => reviewSourceLabels[source]).join(" · ");
}

function defaultReviewSourceSet(): Set<ReviewSourceKind> {
  return new Set(defaultReviewSources);
}

function orderedReviewQuestionTypes(questionTypes: Set<ReviewQuestionType>): ReviewQuestionType[] {
  return (["multipleChoice", "fillIn", "flashcards"] as ReviewQuestionType[]).filter((questionType) =>
    questionTypes.has(questionType),
  );
}

function describeReviewQuestionTypes(
  questionTypes: Set<ReviewQuestionType>,
  questionStrategy: ReviewQuestionStrategy,
): {
  title: string;
  detail: string;
} {
  const ordered = orderedReviewQuestionTypes(questionTypes);
  if (ordered.length === 0) {
    return {
      title: "No question types",
      detail: "Choose at least one format before starting a round.",
    };
  }

  if (questionStrategy === "smart") {
    const enabledFormatNames = ordered.map((type) => reviewQuestionTypeLabels[type].title).join(", ");
    return {
      title: reviewQuestionStrategyLabels.smart.title,
      detail:
        ordered.length === 3
          ? reviewQuestionStrategyLabels.smart.detail
          : `Smart Mix using ${enabledFormatNames}.`,
    };
  }

  if (ordered.length === 1) {
    const only = ordered[0]!;
    return {
      title: reviewQuestionTypeLabels[only].title,
      detail: reviewQuestionTypeLabels[only].detail,
    };
  }

  return {
    title: reviewQuestionStrategyLabels.custom.title,
    detail: "Selected formats rotate deterministically across the round.",
  };
}

function arrangementFilterId(filter: LibraryFilter): string | null {
  return filter.startsWith("saved:") ? filter.slice("saved:".length) : null;
}

function normalizedTerm(value: string): string {
  return value.trim().replace(/\s+/g, " ").toLowerCase();
}

function containsChineseCharacters(text: string): boolean {
  return /[\u3400-\u9fff]/u.test(text);
}

function cjkTextProps(text: string): { className?: string; lang?: string } {
  return containsChineseCharacters(text) ? { className: "desk-cjk-text", lang: "zh-CN" } : {};
}

function looksLikeSentence(text: string): boolean {
  return /[.!?。！？]/u.test(text) || text.trim().split(/\s+/).filter(Boolean).length >= 6;
}

function inferLookupKindFromTerm(term: string, fallback: LookupKind = "word"): LookupKind {
  const trimmed = term.trim();
  if (!trimmed) {
    return fallback;
  }

  if (looksLikeSentence(trimmed)) {
    return "sentence";
  }

  if (trimmed.includes(" ")) {
    return "phrase";
  }

  return fallback;
}

const englishSentenceStopwords = new Set([
  "a",
  "an",
  "and",
  "are",
  "as",
  "at",
  "be",
  "been",
  "being",
  "but",
  "by",
  "for",
  "from",
  "had",
  "has",
  "have",
  "he",
  "her",
  "his",
  "i",
  "in",
  "is",
  "it",
  "its",
  "me",
  "my",
  "of",
  "on",
  "or",
  "our",
  "she",
  "so",
  "than",
  "that",
  "the",
  "their",
  "them",
  "there",
  "they",
  "this",
  "to",
  "us",
  "was",
  "we",
  "were",
  "will",
  "with",
  "you",
  "your",
]);

function extractSentenceStudyCandidates(sentence: string): SentenceStudyCandidate[] {
  if (containsChineseCharacters(sentence)) {
    return [];
  }

  const tokens = sentence
    .split(/[^A-Za-z'-]+/)
    .map((token) => token.trim())
    .filter(Boolean);

  if (tokens.length === 0) {
    return [];
  }

  const scored = new Map<string, SentenceStudyCandidate>();

  function pushCandidate(term: string, kind: LookupKind, score: number, reason: string) {
    const cleaned = term.trim().replace(/\s+/g, " ");
    if (!cleaned) {
      return;
    }

    const key = normalizedTerm(cleaned);
    const existing = scored.get(key);
    if (!existing || score > existing.score) {
      scored.set(key, {
        term: cleaned,
        kind,
        score,
        reason,
        summary: kind === "phrase" ? "Phrase candidate from sentence study." : "Content-word candidate from sentence study.",
      });
    }
  }

  for (const token of tokens) {
    const normalized = normalizedTerm(token);
    if (!normalized || englishSentenceStopwords.has(normalized)) {
      continue;
    }

    const score = Math.min(12, token.length) + (token.length >= 8 ? 4 : 0);
    pushCandidate(token, "word", score, "content word");
  }

  for (let index = 0; index < tokens.length - 1; index += 1) {
    const first = tokens[index]!;
    const second = tokens[index + 1]!;
    const firstNormalized = normalizedTerm(first);
    const secondNormalized = normalizedTerm(second);

    if (
      (!englishSentenceStopwords.has(firstNormalized) || first.length >= 6) &&
      (!englishSentenceStopwords.has(secondNormalized) || second.length >= 6)
    ) {
      const phrase = `${first} ${second}`;
      const score = Math.min(14, phrase.length) + 6;
      pushCandidate(phrase, "phrase", score, "phrase from sentence");
    }
  }

  return Array.from(scored.values())
    .sort((left, right) => {
      if (left.score !== right.score) {
        return right.score - left.score;
      }

      if (left.kind !== right.kind) {
        return left.kind === "phrase" ? -1 : 1;
      }

      return left.term.localeCompare(right.term);
    })
    .slice(0, 8);
}

function sentenceTokenCount(sentence: string): number {
  return sentence
    .split(/[^A-Za-z'-]+/)
    .map((token) => token.trim())
    .filter(Boolean).length;
}

function lookupPlaceholder(kind: LookupKind): string {
  switch (kind) {
    case "word":
      return "Type a word, or enter Chinese to reverse lookup English";
    case "phrase":
      return "Type a phrase, or enter a Chinese phrase to find English options";
    case "sentence":
      return "Type an English or Chinese sentence";
    default:
      return "Type a word or phrase";
  }
}

function buildWorkspaceHref({
  section = "lookup",
  q,
  source,
  kind = "word",
  context,
  itemId,
  entryId,
}: {
  section?: WorkspaceSection;
  q?: string | null;
  source?: string | null;
  kind?: LookupKind;
  context?: string | null;
  itemId?: string | null;
  entryId?: string | null;
}): string {
  const params = new URLSearchParams();
  params.set("section", section);
  params.set("kind", kind);

  const trimmedQuery = q?.trim();
  if (trimmedQuery) {
    params.set("q", trimmedQuery);
  }

  const trimmedSource = source?.trim();
  if (trimmedSource) {
    params.set("source", trimmedSource);
  }

  const trimmedContext = context?.trim();
  if (trimmedContext) {
    params.set("context", trimmedContext);
  }

  const trimmedItemId = itemId?.trim();
  if (trimmedItemId) {
    params.set("item", trimmedItemId);
  }

  const trimmedEntryId = entryId?.trim();
  if (trimmedEntryId) {
    params.set("entry", trimmedEntryId);
  }

  return `/workspace?${params.toString()}`;
}

function lookupRouteContext(kind: LookupKind, query: string, context: string): string | null {
  const trimmedContext = context.trim();
  if (kind === "sentence") {
    return trimmedContext || query.trim() || null;
  }

  return trimmedContext || null;
}

function lookupContextForSubmission(options: {
  kind: LookupKind;
  query: string;
  context: string;
  initialQuery: string;
  initialContext: string;
  contextDirty: boolean;
}): string | null {
  if (options.kind === "sentence") {
    return lookupRouteContext(options.kind, options.query, options.context);
  }

  const trimmedContext = options.context.trim();
  if (!trimmedContext) {
    return null;
  }

  if (options.contextDirty) {
    return trimmedContext;
  }

  const trimmedInitialQuery = options.initialQuery.trim();
  const trimmedInitialContext = options.initialContext.trim();
  const trimmedQuery = options.query.trim();

  if (trimmedQuery !== trimmedInitialQuery && trimmedContext === trimmedInitialContext) {
    return null;
  }

  return trimmedContext;
}

function formatRelativeTime(savedAt: number): string {
  const minutes = Math.max(0, Math.round((Date.now() - savedAt) / 60000));

  if (minutes < 1) {
    return "Just now";
  }

  if (minutes < 60) {
    return `${minutes} min ago`;
  }

  const hours = Math.round(minutes / 60);
  if (hours < 24) {
    return `${hours} hr ago`;
  }

  const days = Math.round(hours / 24);
  return `${days} day ago`;
}

function formatElapsedDuration(startedAt: number, endedAt: number): string {
  const elapsedMinutes = Math.max(1, Math.round((endedAt - startedAt) / 60000));

  if (elapsedMinutes < 60) {
    return `${elapsedMinutes} min`;
  }

  const hours = Math.floor(elapsedMinutes / 60);
  const minutes = elapsedMinutes % 60;
  if (minutes === 0) {
    return `${hours} hr`;
  }

  return `${hours} hr ${minutes} min`;
}

function upsertActivity(items: ActivityItem[], nextItem: ActivityItem): ActivityItem[] {
  const normalized = normalizedTerm(nextItem.term);
  return [nextItem, ...items.filter((item) => normalizedTerm(item.term) !== normalized)].slice(0, 24);
}

function prependHistoryActivity(items: ActivityItem[], nextItem: ActivityItem): ActivityItem[] {
  return [nextItem, ...items].slice(0, 160);
}

function preferredLookupDetailFromWorkspace(workspace: WorkspaceState, context: string): string {
  if (!workspace.lookup) {
    return workspace.mode === "reverse"
      ? `reverse lookup from ${workspace.query}`
      : workspace.mode === "no-result" && workspace.kind === "sentence"
        ? "sentence captured for study"
        : "lookup result visited";
  }

  return createEditableEntry({
    term: workspace.lookup.headword,
    kind: workspace.kind,
    detail: workspace.lookup.summary,
    context,
    snapshot: workspace.lookup,
  }).detail;
}

function historyDetailFromWorkspace(workspace: WorkspaceState, context: string): string {
  if (workspace.kind === "sentence") {
    return "sentence captured for study";
  }

  if (workspace.mode === "reverse") {
    return `reverse lookup from ${workspace.query}`;
  }

  if (workspace.lookup) {
    return preferredLookupDetailFromWorkspace(workspace, context);
  }

  return "lookup result visited";
}

function inboxDetailFromWorkspace(workspace: WorkspaceState, context: string): string {
  if (workspace.kind === "sentence") {
    return "sentence captured for study";
  }

  if (workspace.lookup) {
    return preferredLookupDetailFromWorkspace(workspace, context);
  }

  if (workspace.mode === "reverse") {
    return `saved after reverse lookup from ${workspace.query}`;
  }

  return "saved from workspace";
}

function historyMetaFromWorkspace(
  workspace: WorkspaceState,
  source: string | null,
  options: {
    inboxExists: boolean;
    libraryExists: boolean;
  },
): ActivityMeta {
  const sourceLabel = workspace.sourceLabel ?? source ?? "Lookup";
  const baseMeta: ActivityMeta = {
    originalQuery: workspace.query,
    sourceLabel,
    lookupKind: workspace.kind,
    lookupMode: workspace.mode,
  };

  if (workspace.mode === "reverse") {
    return {
      ...baseMeta,
      inboxAction: "awaitingCandidateSelection",
      status: "completed",
      statusMessage:
        workspace.reverseMatches.length > 0
          ? `Found ${workspace.reverseMatches.length} English candidates.`
          : workspace.statusBody,
    };
  }

  if (workspace.mode === "no-result") {
    if (workspace.kind === "sentence") {
      return {
        ...baseMeta,
        inboxAction: options.libraryExists
          ? "skippedExistingLibrary"
          : options.inboxExists
            ? "updatedInbox"
            : "createdInbox",
        status: "completed",
        statusMessage: "Sentence captured for study.",
      };
    }

    return {
      ...baseMeta,
      inboxAction: "historyOnly",
      status: "failed",
      statusMessage: workspace.statusBody,
    };
  }

  return {
    ...baseMeta,
    inboxAction: options.libraryExists ? "skippedExistingLibrary" : "historyOnly",
    status: "completed",
    statusMessage: workspace.statusTitle,
  };
}

function mapActivityItems(items: unknown): ActivityItem[] {
  if (!Array.isArray(items)) {
    return [];
  }

  return items
    .filter(
      (item) =>
        item &&
        typeof item === "object" &&
        typeof item.id === "string" &&
        typeof item.term === "string" &&
        typeof item.detail === "string" &&
        typeof item.context === "string" &&
        typeof item.saved_at === "number",
    )
    .map((item) => ({
      id: item.id as string,
      term: item.term as string,
      detail: item.detail as string,
      context: item.context as string,
      savedAt: item.saved_at as number,
      meta:
        item.meta && typeof item.meta === "object"
          ? (item.meta as ActivityMeta)
          : null,
    }));
}

function pickSelectedItem(items: ActivityItem[], query: string, itemId?: string | null): ActivityItem | null {
  if (items.length === 0) {
    return null;
  }

  const trimmedItemId = itemId?.trim();
  if (trimmedItemId) {
    return items.find((item) => item.id === trimmedItemId) ?? items[0] ?? null;
  }

  const normalizedQuery = normalizedTerm(query);
  if (!normalizedQuery) {
    return items[0] ?? null;
  }

  return items.find((item) => normalizedTerm(item.term) === normalizedQuery) ?? items[0] ?? null;
}

function pickSelectedLibraryEntry(
  entries: LibraryEntry[],
  query: string,
  entryId?: string | null,
): LibraryEntry | null {
  if (entries.length === 0) {
    return null;
  }

  const trimmedEntryId = entryId?.trim();
  if (trimmedEntryId) {
    return entries.find((entry) => entry.id === trimmedEntryId) ?? entries[0] ?? null;
  }

  const normalizedQuery = normalizedTerm(query);
  if (!normalizedQuery) {
    return entries[0] ?? null;
  }

  return entries.find((entry) => normalizedTerm(entry.term) === normalizedQuery) ?? entries[0] ?? null;
}

function isPronounceableEnglish(text: string): boolean {
  const trimmed = text.trim();
  return Boolean(trimmed) && !containsChineseCharacters(trimmed);
}

function makeSessionId(): string {
  return `review-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
}

function workspaceLookupToSnapshot(lookup: LookupResult): ReviewLookupSnapshot {
  return {
    term: lookup.headword,
    ...lookup,
  };
}

function readStoredLibraryItems(): LibraryEntry[] {
  if (typeof window === "undefined") {
    return [];
  }

  try {
    const raw = window.localStorage.getItem(libraryStorageKey);
    if (!raw) {
      return [];
    }

    return parseStoredLibraryEntries(JSON.parse(raw));
  } catch {
    return [];
  }
}

function readStoredLibraryArrangements(): SavedLibraryArrangement[] {
  if (typeof window === "undefined") {
    return [];
  }

  try {
    const raw = window.localStorage.getItem(libraryArrangementsStorageKey);
    if (!raw) {
      return [];
    }

    return parseStoredLibraryArrangements(JSON.parse(raw));
  } catch {
    return [];
  }
}

function readStoredInboxDrafts(): Record<string, WorkspaceEditableEntry> {
  if (typeof window === "undefined") {
    return {};
  }

  try {
    const raw = window.localStorage.getItem(inboxDraftStorageKey);
    if (!raw) {
      return {};
    }

    return parseStoredEditableEntryMap(JSON.parse(raw));
  } catch {
    return {};
  }
}

function readStoredQuickCaptureDrafts(): QuickCaptureDraftMap {
  if (typeof window === "undefined") {
    return {};
  }

  try {
    const raw = window.localStorage.getItem(quickCaptureDraftStorageKey);
    if (!raw) {
      return {};
    }

    return parseStoredQuickCaptureDraftMap(JSON.parse(raw));
  } catch {
    return {};
  }
}

function normalizeStoredReviewStateRecord(value: unknown): ReviewStateRecord | null {
  if (!value || typeof value !== "object") {
    return null;
  }

  const record = value as Record<string, unknown>;
  const level = record.level;
  const reviewCount = record.reviewCount;
  const lastReviewedAt = record.lastReviewedAt;
  const dueAt = record.dueAt;
  const streak = record.streak;
  const lapseCount = record.lapseCount;
  const lastDecision = normalizeReviewDecision(record.lastDecision);

  if (level !== 0 && level !== 1 && level !== 2 && level !== 3 && level !== 4) {
    return null;
  }

  return {
    level,
    reviewCount: typeof reviewCount === "number" && Number.isFinite(reviewCount) ? reviewCount : 0,
    lastReviewedAt:
      typeof lastReviewedAt === "number" && Number.isFinite(lastReviewedAt) ? lastReviewedAt : null,
    dueAt: typeof dueAt === "number" && Number.isFinite(dueAt) ? dueAt : null,
    streak: typeof streak === "number" && Number.isFinite(streak) ? streak : 0,
    lapseCount: typeof lapseCount === "number" && Number.isFinite(lapseCount) ? lapseCount : 0,
    lastDecision,
  };
}

function parseStoredReviewStateMap(value: unknown): ReviewStateMap {
  if (!value || typeof value !== "object") {
    return {};
  }

  const entries = Object.entries(value as Record<string, unknown>);
  const next: ReviewStateMap = {};

  for (const [key, record] of entries) {
    if (!record || typeof record !== "object") {
      continue;
    }

    const normalizedRecord = normalizeStoredReviewStateRecord(record);
    if (!normalizedRecord) {
      continue;
    }

    next[key] = normalizedRecord;
  }

  return next;
}

function readStoredReviewStateMap(): ReviewStateMap {
  if (typeof window === "undefined") {
    return {};
  }

  try {
    const raw = window.localStorage.getItem(reviewStateStorageKey);
    if (!raw) {
      return {};
    }

    return parseStoredReviewStateMap(JSON.parse(raw));
  } catch {
    return {};
  }
}

function normalizeStoredReviewQuestionType(value: unknown): ReviewQuestionType | null {
  if (value === "multipleChoice" || value === "fillIn" || value === "flashcards") {
    return value;
  }

  if (value === "meaningToTerm" || value === "termToMeaning") {
    return "fillIn";
  }

  if (value === "flashcardMeaningToTerm" || value === "flashcardTermToMeaning") {
    return "flashcards";
  }

  return null;
}

function normalizeStoredReviewQuestionStrategy(value: unknown): ReviewQuestionStrategy {
  return value === "custom" ? "custom" : "smart";
}

function normalizeStoredReviewSourceKinds(value: unknown): ReviewSourceKind[] {
  if (!Array.isArray(value)) {
    return [];
  }

  const normalized = value
    .map((item) => {
      if (item === "inbox") {
        return "history";
      }

      return item;
    })
    .filter(
      (item): item is ReviewSourceKind =>
        item === "library" || item === "favorites" || item === "history",
    );

  return Array.from(new Set(normalized));
}

function parseStoredReviewHistoryValue(value: unknown): ReviewRecord[] {
  if (!Array.isArray(value)) {
    return [];
  }

  const parsed = value
    .map((item): ReviewRecord | null => {
      if (!item || typeof item !== "object") {
        return null;
      }

      const record = item as ReviewRecord;
      const questionType = normalizeStoredReviewQuestionType(record.questionType);
      const decision = normalizeReviewDecision(record.decision);
      if (
        typeof record.sessionId !== "string" ||
        typeof record.candidateId !== "string" ||
        typeof record.term !== "string" ||
        typeof record.meaning !== "string" ||
        typeof record.prompt !== "string" ||
        typeof record.promptTitle !== "string" ||
        !questionType ||
        !decision ||
        (typeof record.correct !== "boolean" && record.correct !== null)
      ) {
        return null;
      }

      return {
        ...record,
        questionType,
        decision,
        sourceKinds: normalizeStoredReviewSourceKinds(record.sourceKinds),
        reviewStateBefore: normalizeStoredReviewStateRecord(
          (record as { reviewStateBefore?: unknown }).reviewStateBefore,
        ),
        reviewStateAfter: normalizeStoredReviewStateRecord(
          (record as { reviewStateAfter?: unknown }).reviewStateAfter,
        ),
      };
    })
    .filter((item): item is ReviewRecord => item !== null);

  const byKey = new Map<string, ReviewRecord>();
  for (const record of parsed) {
    const key = [
      record.sessionId,
      record.candidateId,
      record.term,
      record.questionType,
      record.decision,
      record.submittedAnswer,
      record.reviewLevelBefore,
      record.reviewLevelAfter,
    ].join("::");
    const current = byKey.get(key);
    if (!current || record.answeredAt >= current.answeredAt) {
      byKey.set(key, record);
    }
  }

  return Array.from(byKey.values()).sort((left, right) => right.answeredAt - left.answeredAt);
}

function readStoredReviewHistory(): ReviewRecord[] {
  if (typeof window === "undefined") {
    return [];
  }

  try {
    const raw = window.localStorage.getItem(reviewHistoryStorageKey);
    if (!raw) {
      return [];
    }

    return parseStoredReviewHistoryValue(JSON.parse(raw));
  } catch {
    return [];
  }
}

function parseStoredReviewSession(value: unknown): ReviewSessionState | null {
  if (!value || typeof value !== "object") {
    return null;
  }

  const record = value as Record<string, unknown>;
  if (
    typeof record.sessionId !== "string" ||
    !Array.isArray(record.queue) ||
    typeof record.index !== "number" ||
    !Array.isArray(record.records) ||
    !Array.isArray(record.questionTypes) ||
    typeof record.styleTitle !== "string" ||
    typeof record.styleDetail !== "string"
  ) {
    return null;
  }

  const queue = record.queue.filter((item): item is string => typeof item === "string" && item.trim().length > 0);
  const parsedRecords = Array.isArray(record.records)
    ? parseStoredReviewHistoryValue(record.records)
    : [];

  const questionTypes = Array.from(
    new Set(
      (record.questionTypes as unknown[])
        .map((item) => normalizeStoredReviewQuestionType(item))
        .filter((item): item is ReviewQuestionType => item !== null),
    ),
  );

  if (queue.length === 0 || questionTypes.length === 0) {
    return null;
  }

  const startedAt =
    typeof record.startedAt === "number" && Number.isFinite(record.startedAt) ? record.startedAt : Date.now();
  const pausedAt =
    typeof record.pausedAt === "number" && Number.isFinite(record.pausedAt) ? record.pausedAt : null;
  const activeCandidateId =
    typeof record.activeCandidateId === "string" && queue.includes(record.activeCandidateId)
      ? record.activeCandidateId
      : queue[Math.min(Math.max(0, Math.floor(record.index)), queue.length - 1)] ?? null;
  const draftAnswer = typeof record.draftAnswer === "string" ? record.draftAnswer : "";
  const selectedChoice = typeof record.selectedChoice === "string" ? record.selectedChoice : "";
  const answerSubmitted = typeof record.answerSubmitted === "boolean" ? record.answerSubmitted : false;
  const sourceKinds = normalizeStoredReviewSourceKinds(record.sourceKinds);

  const parsedSession = {
    sessionId: record.sessionId,
    queue,
    index: Math.min(Math.max(0, Math.floor(record.index)), queue.length),
    records: parsedRecords,
    activeCandidateId,
    draftAnswer,
    selectedChoice,
    answerSubmitted,
    questionTypes,
    questionStrategy:
      record.questionStrategy === undefined
        ? "custom"
        : normalizeStoredReviewQuestionStrategy(record.questionStrategy),
    styleTitle: record.styleTitle,
    styleDetail: record.styleDetail,
    startedAt,
    pausedAt,
    sourceKinds,
  };

  if (parsedSession.index >= parsedSession.queue.length && parsedSession.pausedAt === null) {
    return null;
  }

  return parsedSession;
}

function readStoredReviewSession(): ReviewSessionState | null {
  if (typeof window === "undefined") {
    return null;
  }

  try {
    const raw = window.localStorage.getItem(reviewSessionStorageKey);
    if (!raw) {
      return null;
    }

    return parseStoredReviewSession(JSON.parse(raw));
  } catch {
    return null;
  }
}

function readStoredWorkspacePreferences(): WorkspacePreferences {
  if (typeof window === "undefined") {
    return defaultWorkspacePreferences();
  }

  try {
    const raw = window.localStorage.getItem(workspacePreferencesStorageKey);
    if (!raw) {
      return defaultWorkspacePreferences();
    }

    return parseStoredWorkspacePreferences(JSON.parse(raw));
  } catch {
    return defaultWorkspacePreferences();
  }
}

function readStoredTrash(): WorkspaceTrashItem[] {
  if (typeof window === "undefined") {
    return [];
  }

  try {
    const raw = window.localStorage.getItem(trashStorageKey);
    if (!raw) {
      return [];
    }

    return parseStoredTrashItems(JSON.parse(raw));
  } catch {
    return [];
  }
}

function parseWorkspacePersistenceSnapshot(value: unknown): WorkspacePersistenceSnapshot | null {
  if (!value || typeof value !== "object") {
    return null;
  }

  const record = value as Record<string, unknown>;
  const reviewHistory = parseStoredReviewHistoryValue(record.reviewHistory);
  const reviewStateMap = parseStoredReviewStateMap(record.reviewStateMap);
  for (const reviewRecord of reviewHistory) {
    if (reviewRecord.isHistoryOnly || !reviewRecord.reviewStateAfter) {
      continue;
    }

    reviewStateMap[normalizedReviewKey(reviewRecord.term)] = reviewRecord.reviewStateAfter;
  }

  return {
    libraryEntries: parseStoredLibraryEntries(record.libraryEntries),
    savedLibraryArrangements: parseStoredLibraryArrangements(record.savedLibraryArrangements),
    inboxEntryDrafts: parseStoredEditableEntryMap(record.inboxEntryDrafts),
    quickCaptureDrafts: parseStoredQuickCaptureDraftMap(record.quickCaptureDrafts),
    reviewStateMap,
    reviewHistory,
    reviewSession: parseStoredReviewSession(record.reviewSession),
    workspacePreferences: parseStoredWorkspacePreferences(record.workspacePreferences),
    trashItems: parseStoredTrashItems(record.trashItems),
  };
}

function emptyWorkspacePersistenceSnapshot(): WorkspacePersistenceSnapshot {
  return {
    libraryEntries: [],
    savedLibraryArrangements: [],
    inboxEntryDrafts: {},
    quickCaptureDrafts: {},
    reviewStateMap: {},
    reviewHistory: [],
    reviewSession: null,
    workspacePreferences: defaultWorkspacePreferences(),
    trashItems: [],
  };
}

function writeWorkspacePersistenceSnapshotToLocalStorage(snapshot: WorkspacePersistenceSnapshot) {
  if (typeof window === "undefined") {
    return;
  }

  window.localStorage.setItem(libraryStorageKey, JSON.stringify(snapshot.libraryEntries));
  window.localStorage.setItem(libraryArrangementsStorageKey, JSON.stringify(snapshot.savedLibraryArrangements));
  window.localStorage.setItem(inboxDraftStorageKey, JSON.stringify(snapshot.inboxEntryDrafts));
  window.localStorage.setItem(quickCaptureDraftStorageKey, JSON.stringify(snapshot.quickCaptureDrafts));
  window.localStorage.setItem(reviewStateStorageKey, JSON.stringify(snapshot.reviewStateMap));
  window.localStorage.setItem(reviewHistoryStorageKey, JSON.stringify(snapshot.reviewHistory.slice(0, 160)));
  if (snapshot.reviewSession) {
    window.localStorage.setItem(reviewSessionStorageKey, JSON.stringify(snapshot.reviewSession));
  } else {
    window.localStorage.removeItem(reviewSessionStorageKey);
  }
  window.localStorage.setItem(workspacePreferencesStorageKey, JSON.stringify(snapshot.workspacePreferences));
  window.localStorage.setItem(trashStorageKey, JSON.stringify(snapshot.trashItems));
}

function parseImportedActivityItems(value: unknown): ActivityItem[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .filter(
      (item) =>
        item &&
        typeof item === "object" &&
        typeof item.id === "string" &&
        typeof item.term === "string" &&
        typeof item.detail === "string",
    )
    .map((item) => {
      const record = item as Record<string, unknown>;
      const savedAt =
        typeof record.savedAt === "number"
          ? record.savedAt
          : typeof record.saved_at === "number"
            ? record.saved_at
            : Date.now();

      return {
        id: record.id as string,
        term: record.term as string,
        detail: record.detail as string,
        context: typeof record.context === "string" ? record.context : "",
        savedAt,
        meta: record.meta && typeof record.meta === "object" ? (record.meta as ActivityMeta) : null,
      };
    })
    .sort((left, right) => right.savedAt - left.savedAt);
}

function parseWorkspaceBackupPayload(value: unknown): {
  snapshot: WorkspacePersistenceSnapshot;
  inboxItems: ActivityItem[];
  historyItems: ActivityItem[];
} | null {
  const directSnapshot = parseWorkspacePersistenceSnapshot(value);
  if (directSnapshot) {
    return {
      snapshot: directSnapshot,
      inboxItems: [],
      historyItems: [],
    };
  }

  if (!value || typeof value !== "object") {
    return null;
  }

  const record = value as Record<string, unknown>;
  const snapshot = parseWorkspacePersistenceSnapshot(record.snapshot ?? record.workspaceState);
  if (!snapshot) {
    return null;
  }

  return {
    snapshot,
    inboxItems: parseImportedActivityItems(record.inboxItems),
    historyItems: parseImportedActivityItems(record.historyItems),
  };
}

function readStoredWorkspacePersistenceSnapshot(): WorkspacePersistenceSnapshot {
  return {
    libraryEntries: readStoredLibraryItems(),
    savedLibraryArrangements: readStoredLibraryArrangements(),
    inboxEntryDrafts: readStoredInboxDrafts(),
    quickCaptureDrafts: readStoredQuickCaptureDrafts(),
    reviewStateMap: readStoredReviewStateMap(),
    reviewHistory: readStoredReviewHistory(),
    reviewSession: readStoredReviewSession(),
    workspacePreferences: readStoredWorkspacePreferences(),
    trashItems: readStoredTrash(),
  };
}

function workspacePersistenceSnapshotHasData(snapshot: WorkspacePersistenceSnapshot | null): boolean {
  if (!snapshot) {
    return false;
  }

  return (
    snapshot.libraryEntries.length > 0 ||
    snapshot.savedLibraryArrangements.length > 0 ||
    Object.keys(snapshot.inboxEntryDrafts).length > 0 ||
    Object.keys(snapshot.quickCaptureDrafts).length > 0 ||
    Object.keys(snapshot.reviewStateMap).length > 0 ||
    snapshot.reviewHistory.length > 0 ||
    Boolean(snapshot.reviewSession) ||
    snapshot.trashItems.length > 0 ||
    snapshot.workspacePreferences.excludeMasteredFromReview ||
    snapshot.workspacePreferences.isLibraryCleanMode ||
    snapshot.workspacePreferences.workspacePaneLayoutPreference !== "automatic" ||
    snapshot.workspacePreferences.showLookupReferenceTags ||
    snapshot.workspacePreferences.pronunciationVoiceURI !== automaticPronunciationVoiceURI
  );
}

function reviewSessionHasInProgressAnswer(session: ReviewSessionState | null): boolean {
  return Boolean(
    session &&
      (session.draftAnswer.trim() ||
        session.selectedChoice.trim() ||
        session.answerSubmitted),
  );
}

function latestLibraryUpdatedAt(snapshot: WorkspacePersistenceSnapshot | null): number {
  return Math.max(
    0,
    ...(snapshot?.libraryEntries ?? []).map((entry) => Math.max(entry.updatedAt, entry.savedAt)),
  );
}

function latestReviewHistoryAnsweredAt(snapshot: WorkspacePersistenceSnapshot | null): number {
  return Math.max(0, ...(snapshot?.reviewHistory ?? []).map((record) => record.answeredAt));
}

function localSnapshotLooksNewer(
  localSnapshot: WorkspacePersistenceSnapshot,
  serverSnapshot: WorkspacePersistenceSnapshot | null,
): boolean {
  if (!serverSnapshot) {
    return workspacePersistenceSnapshotHasData(localSnapshot);
  }

  if (localSnapshot.libraryEntries.length > serverSnapshot.libraryEntries.length) {
    return true;
  }

  if (
    localSnapshot.libraryEntries.length === serverSnapshot.libraryEntries.length &&
    latestLibraryUpdatedAt(localSnapshot) > latestLibraryUpdatedAt(serverSnapshot)
  ) {
    return true;
  }

  if (JSON.stringify(localSnapshot.workspacePreferences) !== JSON.stringify(serverSnapshot.workspacePreferences)) {
    return true;
  }

  if (localSnapshot.reviewHistory.length > serverSnapshot.reviewHistory.length) {
    return true;
  }

  return latestReviewHistoryAnsweredAt(localSnapshot) > latestReviewHistoryAnsweredAt(serverSnapshot);
}

function shouldPreferLocalPersistenceSnapshot(
  localSnapshot: WorkspacePersistenceSnapshot,
  serverSnapshot: WorkspacePersistenceSnapshot | null,
): boolean {
  if (!workspacePersistenceSnapshotHasData(serverSnapshot)) {
    return workspacePersistenceSnapshotHasData(localSnapshot);
  }

  if (localSnapshotLooksNewer(localSnapshot, serverSnapshot)) {
    return true;
  }

  const localSession = localSnapshot.reviewSession;
  const serverSession = serverSnapshot?.reviewSession ?? null;
  if (!localSession || !serverSession || localSession.sessionId !== serverSession.sessionId) {
    return false;
  }

  if (localSession.records.length > serverSession.records.length) {
    return true;
  }

  if (localSession.index > serverSession.index) {
    return true;
  }

  return (
    localSession.index === serverSession.index &&
    localSession.records.length === serverSession.records.length &&
    reviewSessionHasInProgressAnswer(localSession) &&
    !reviewSessionHasInProgressAnswer(serverSession)
  );
}

function migrateWorkspaceInboxState(options: {
  inboxItems: ActivityItem[];
  snapshot: WorkspacePersistenceSnapshot;
}): {
  inboxItems: ActivityItem[];
  snapshot: WorkspacePersistenceSnapshot;
  migratedToLibrary: string[];
  migratedToDrafts: string[];
  hasChanges: boolean;
} {
  const migration = migrateLegacyInboxState({
    inboxItems: options.inboxItems,
    inboxEntryDrafts: options.snapshot.inboxEntryDrafts,
    quickCaptureDrafts: options.snapshot.quickCaptureDrafts,
    libraryEntries: options.snapshot.libraryEntries,
    reviewStateMap: options.snapshot.reviewStateMap,
  });

  return {
    inboxItems: migration.inboxItems,
    snapshot: {
      ...options.snapshot,
      inboxEntryDrafts: migration.inboxEntryDrafts,
      quickCaptureDrafts: migration.quickCaptureDrafts,
      libraryEntries: migration.libraryEntries,
    },
    migratedToLibrary: migration.migratedToLibrary,
    migratedToDrafts: migration.migratedToDrafts,
    hasChanges: migration.hasChanges,
  };
}

function parseQuickCaptureImportInput(text: string): QuickCaptureImportItem[] {
  const lines = text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);

  const seen = new Set<string>();
  const items: QuickCaptureImportItem[] = [];

  for (const line of lines) {
    const parts = line.split(/\s*(?:::|\t|\|)\s*/, 2);
    const term = sanitizeInlineText(parts[0]);
    const rawContext = parts.length > 1 ? sanitizeParagraphText(parts[1]) : "";
    if (!term) {
      continue;
    }

    const kind = inferLookupKindFromTerm(term, "word");
    const context = rawContext || (kind === "sentence" ? term : "");
    const key = `${kind}:${normalizedTerm(term)}:${normalizedTerm(context)}`;
    if (seen.has(key)) {
      continue;
    }

    seen.add(key);
    items.push({
      id: `capture-import-${items.length + 1}`,
      term,
      context,
      kind,
    });
  }

  return items.slice(0, 24);
}

function editableEntryFromActivity(
  item: Pick<ActivityItem, "term" | "detail" | "context">,
  snapshot: LookupResult | null,
  existing?: WorkspaceEditableEntry | null,
): WorkspaceEditableEntry {
  return createEditableEntry({
    term: item.term,
    kind: inferLookupKindFromTerm(item.term, "word"),
    detail: item.detail,
    context: item.context,
    notes: existing?.notes ?? "",
    snapshot,
    existing: existing ?? null,
  });
}

function sameEditableEntry(
  left: WorkspaceEditableEntry | null | undefined,
  right: WorkspaceEditableEntry | null | undefined,
): boolean {
  return JSON.stringify(left ?? null) === JSON.stringify(right ?? null);
}

function toggledSelection(indexes: number[], index: number): number[] {
  if (indexes.includes(index)) {
    return indexes.filter((value) => value !== index);
  }

  return [...indexes, index];
}

function ensuredSelection(indexes: number[], index: number): number[] {
  if (indexes.includes(index)) {
    return indexes;
  }

  return [...indexes, index];
}

function promotedSelection(indexes: number[], index: number): number[] {
  if (!indexes.includes(index)) {
    return indexes;
  }

  return [index, ...indexes.filter((value) => value !== index)];
}

function movedSelection(indexes: number[], index: number, direction: -1 | 1): number[] {
  const currentIndex = indexes.findIndex((value) => value === index);
  if (currentIndex < 0) {
    return indexes;
  }

  const nextIndex = currentIndex + direction;
  if (nextIndex < 0 || nextIndex >= indexes.length) {
    return indexes;
  }

  const next = [...indexes];
  [next[currentIndex], next[nextIndex]] = [next[nextIndex]!, next[currentIndex]!];
  return next;
}

function removeIndexedChoice(
  choices: string[],
  selectedIndexes: number[],
  indexToRemove: number,
): {
  choices: string[];
  selectedIndexes: number[];
} {
  const choicesWithoutRemoved = choices.filter((_, index) => index !== indexToRemove);
  const nextSelectedIndexes = selectedIndexes
    .filter((index) => index !== indexToRemove)
    .map((index) => (index > indexToRemove ? index - 1 : index));

  return {
    choices: choicesWithoutRemoved,
    selectedIndexes: nextSelectedIndexes,
  };
}

function keepOnlySelectedIds(current: Set<string>, validIds: string[]): Set<string> {
  const valid = new Set(validIds);
  return new Set(Array.from(current).filter((id) => valid.has(id)));
}

function submittedAnswerText(
  questionType: ReviewQuestionType,
  draftAnswer: string,
  selectedChoice: string,
  card: ReviewCard | null,
): string {
  if (!card) {
    return "";
  }

  if (questionType === "multipleChoice") {
    return selectedChoice;
  }

  if (card.family === "fillIn") {
    return draftAnswer.trim();
  }

  return card.answer;
}

function appendReferenceTags(currentTags: string[], draft: string): {
  nextTags: string[];
  message: string | null;
} {
  const candidates = draft
    .split(/[,\n，;；]/)
    .map((value) => sanitizeInlineText(value))
    .filter(Boolean);

  if (candidates.length === 0) {
    return {
      nextTags: currentTags,
      message: null,
    };
  }

  const seen = new Set(currentTags.map((tag) => normalizedTerm(tag)));
  const nextTags = [...currentTags];
  let added = 0;

  for (const candidate of candidates) {
    const key = normalizedTerm(candidate);
    if (!key || seen.has(key)) {
      continue;
    }

    seen.add(key);
    nextTags.push(candidate);
    added += 1;
  }

  return {
    nextTags,
    message: added === 0 ? "Those tags are already on this entry." : null,
  };
}

function sortActivityItems(
  items: ActivityItem[],
  sort: InboxSortOption | HistorySortOption,
): ActivityItem[] {
  const sorted = [...items];

  if (sort === "savedOldest") {
    return sorted.sort((left, right) => left.savedAt - right.savedAt);
  }

  if (sort === "alphabetical") {
    return sorted.sort((left, right) => left.term.localeCompare(right.term));
  }

  return sorted.sort((left, right) => right.savedAt - left.savedAt);
}

function activityMatchesSearch(item: ActivityItem, search: string): boolean {
  if (!search) {
    return true;
  }

  return [
    item.term,
    item.detail,
    item.context ?? "",
    item.meta?.originalQuery ?? "",
    item.meta?.sourceLabel ?? "",
    item.meta?.lookupKind ?? "",
    item.meta?.lookupMode ?? "",
    item.meta?.statusMessage ?? "",
  ]
    .join(" ")
    .toLowerCase()
    .includes(search);
}

function reviewCandidateMatchesSearch(candidate: ReviewCandidate, search: string): boolean {
  if (!search) {
    return true;
  }

  return [
    candidate.term,
    candidate.detail,
    candidate.partOfSpeech,
    candidate.example,
    candidate.context,
    candidate.notes,
    candidate.selectedMeanings.join(" "),
    candidate.selectedExamples.join(" "),
    candidate.referenceTags.join(" "),
    candidate.sourceKinds.join(" "),
    reviewLevelLabel(candidate.reviewLevel),
  ]
    .join(" ")
    .toLowerCase()
    .includes(search);
}

function matchesReviewQuickFilter(
  candidate: ReviewCandidate,
  filter: ReviewQuickFilter,
  recentMistakeCandidateIds: Set<string>,
  reviewStateMap: ReviewStateMap,
): boolean {
  const reviewState = reviewStateForTerm(candidate.term, reviewStateMap);

  if (filter === "dueNow") {
    return isReviewDue(reviewState);
  }

  if (filter === "unknown") {
    return candidate.reviewLevel === 0;
  }

  if (filter === "needsWork") {
    return candidate.reviewLevel <= 1 || recentMistakeCandidateIds.has(candidate.id);
  }

  if (filter === "recentMistakes") {
    return recentMistakeCandidateIds.has(candidate.id);
  }

  if (filter === "favoritesOnly") {
    return candidate.favorite;
  }

  if (filter === "historyOnly") {
    return !candidate.hasBackingEntry;
  }

  return true;
}

function libraryEntryMatchesSearch(entry: LibraryEntry, search: string): boolean {
  if (!search) {
    return true;
  }

  return [
    entry.term,
    entry.detail,
    entry.context,
    entry.notes,
    entry.partOfSpeech,
    entry.meaningChoices.join(" "),
    entry.exampleChoices.join(" "),
    entry.englishDefinitions.join(" "),
    entry.referenceTags.join(" "),
  ]
    .join(" ")
    .toLowerCase()
    .includes(search);
}

function libraryEntryMatchesLevel(
  entry: LibraryEntry,
  levelFilter: LibraryLevelFilter,
  reviewStateMap: ReviewStateMap,
): boolean {
  if (levelFilter === "all") {
    return true;
  }

  return reviewStateForTerm(entry.term, reviewStateMap).level === Number(levelFilter);
}

function sortLibraryEntries(
  entries: LibraryEntry[],
  sort: LibrarySortOption,
  reviewStateMap: ReviewStateMap,
): LibraryEntry[] {
  const sorted = [...entries];

  if (sort === "updatedNewest") {
    return sorted.sort((left, right) => right.updatedAt - left.updatedAt);
  }

  if (sort === "updatedOldest") {
    return sorted.sort((left, right) => left.updatedAt - right.updatedAt);
  }

  if (sort === "alphabetical") {
    return sorted.sort((left, right) => left.term.localeCompare(right.term));
  }

  return sorted.sort((left, right) => {
    const leftState = reviewStateForTerm(left.term, reviewStateMap);
    const rightState = reviewStateForTerm(right.term, reviewStateMap);

    if (leftState.level !== rightState.level) {
      return leftState.level - rightState.level;
    }

    if (leftState.lastReviewedAt === null && rightState.lastReviewedAt !== null) {
      return -1;
    }

    if (leftState.lastReviewedAt !== null && rightState.lastReviewedAt === null) {
      return 1;
    }

    if (leftState.lastReviewedAt !== rightState.lastReviewedAt) {
      return (leftState.lastReviewedAt ?? 0) - (rightState.lastReviewedAt ?? 0);
    }

    return right.updatedAt - left.updatedAt;
  });
}

function groupReviewHistory(records: ReviewRecord[]): ReviewHistoryRound[] {
  const grouped = new Map<string, ReviewHistoryRound>();

  for (const record of records) {
    const existing = grouped.get(record.sessionId);
    if (existing) {
      existing.items.push(record);
      existing.answeredAt = Math.max(existing.answeredAt, record.answeredAt);
      existing.sourceKinds = Array.from(new Set([...existing.sourceKinds, ...record.sourceKinds])) as ReviewSourceKind[];
    } else {
      grouped.set(record.sessionId, {
        sessionId: record.sessionId,
        answeredAt: record.answeredAt,
        items: [record],
        sourceKinds: [...record.sourceKinds],
      });
    }
  }

  return Array.from(grouped.values())
    .map((round) => ({
      ...round,
      items: round.items.slice().sort((left, right) => left.answeredAt - right.answeredAt),
    }))
    .sort((left, right) => right.answeredAt - left.answeredAt);
}

function renderMeaningList(snapshot: ReviewLookupSnapshot): ReactNode {
  return (
    <div className="desk-meaning-stack">
      {snapshot.meaningGroups.map((group) => (
        <div className="desk-meaning-group" key={`${group.partOfSpeech}-${group.definitions.join("-")}`}>
          <strong>{group.partOfSpeech || "sense"}</strong>
          <ul>
            {group.definitions.map((definition) => (
              <li key={definition} {...cjkTextProps(definition)}>
                {definition}
              </li>
            ))}
          </ul>
        </div>
      ))}
    </div>
  );
}

function primaryMeaningFromSnapshot(snapshot: ReviewLookupSnapshot): { partOfSpeech: string; text: string } | null {
  for (const group of snapshot.meaningGroups) {
    for (const definition of group.definitions) {
      const trimmed = definition.trim();
      if (trimmed) {
        return {
          partOfSpeech: group.partOfSpeech || "sense",
          text: trimmed,
        };
      }
    }
  }

  return snapshot.summary.trim()
    ? {
        partOfSpeech: snapshot.meaningGroups[0]?.partOfSpeech || "summary",
        text: snapshot.summary.trim(),
      }
    : null;
}

function leadExampleFromSnapshot(snapshot: ReviewLookupSnapshot): ReviewLookupSnapshot["examples"][number] | null {
  return snapshot.examples.find((example) => example.english.trim() || example.chinese.trim()) ?? null;
}

function renderEnglishDefinitionBlock(
  snapshot: Pick<ReviewLookupSnapshot, "englishDefinitions">,
): ReactNode {
  const presentation = buildEnglishDefinitionPresentation(snapshot.englishDefinitions);
  const hasContent =
    presentation.primaryDefinitions.length > 0 ||
    presentation.additionalDefinitions.length > 0 ||
    presentation.synonyms.length > 0;

  if (!hasContent) {
    return null;
  }

  return (
    <div className="desk-info-block">
      <h3>English Definitions</h3>
      {presentation.primaryDefinitions.length > 0 ? (
        <ul className="desk-plain-list">
          {presentation.primaryDefinitions.map((line) => (
            <li key={line}>{line}</li>
          ))}
        </ul>
      ) : null}
      {presentation.synonyms.length > 0 ? (
        <div className="desk-info-block">
          <h4>Synonyms</h4>
          <div className="desk-chip-row">
            {presentation.synonyms.map((term) => (
              <span className="soft-tag" key={term}>
                {term}
              </span>
            ))}
          </div>
        </div>
      ) : null}
      {presentation.additionalDefinitions.length > 0 ? (
        <details className="desk-native-menu">
          <summary>
            <span>More</span>
            <strong>{presentation.additionalDefinitions.length} extra</strong>
          </summary>
          <div className="desk-native-menu-panel">
            <ul className="desk-plain-list">
              {presentation.additionalDefinitions.map((line) => (
                <li key={line}>{line}</li>
              ))}
            </ul>
          </div>
        </details>
      ) : null}
    </div>
  );
}

function inboxDraftDigest(
  item: Pick<ActivityItem, "detail" | "context">,
  draft: WorkspaceEditableEntry | null | undefined,
): InboxDraftDigest {
  const selectedMeanings = draft ? selectedMeaningsFromEntry(draft) : [];
  const selectedExamples = draft ? selectedExamplesFromEntry(draft) : [];
  const hasContext = Boolean((item.context ?? "").trim());
  const hasNotes = Boolean(draft?.notes.trim());
  const score =
    Number(selectedMeanings.length > 0) +
    Number(selectedExamples.length > 0) +
    Number(hasContext) +
    Number(hasNotes);

  let stageLabel = "Shape this entry";
  if (selectedMeanings.length === 0) {
    stageLabel = "Pick a meaning";
  } else if (selectedExamples.length === 0 && !hasContext) {
    stageLabel = "Add texture";
  } else if (selectedExamples.length === 0) {
    stageLabel = "Add an example";
  } else if (!hasContext) {
    stageLabel = "Strong draft";
  } else {
    stageLabel = "Ready to confirm";
  }

  return {
    selectedMeaningCount: selectedMeanings.length,
    selectedExampleCount: selectedExamples.length,
    hasContext,
    hasNotes,
    score,
    isReady: selectedMeanings.length > 0,
    stageLabel,
    primaryMeaning: selectedMeanings[0]?.trim() || draft?.detail.trim() || item.detail.trim() || "Meaning not chosen yet",
    primaryExample: selectedExamples[0]?.trim() || "",
  };
}

function buildLibraryEntryDigest(
  entry: LibraryEntry,
  options: {
    reviewLevel: ReviewLevel;
    reviewCount: number;
    duplicateCount: number;
    collectionNames: string[];
  },
): LibraryEntryDigest {
  const selectedMeanings = selectedMeaningsFromEntry(entry);
  const selectedExamples = selectedExamplesFromEntry(entry);
  const collectionCount = options.collectionNames.length;
  const primaryMeaning =
    selectedMeanings[0]?.trim() || entry.detail.trim() || "Meaning still needs curation.";
  const primaryExample = selectedExamples[0]?.trim() || entry.context.trim() || "";
  const collectibleScore =
    Number(entry.favorite) +
    Number(collectionCount > 0) +
    Number(selectedExamples.length > 0) +
    Number(selectedMeanings.length > 1) +
    Number(options.reviewLevel >= 2);

  let collectibleLabel = "Needs curation";
  if (collectibleScore >= 4) {
    collectibleLabel = "Shelf-ready";
  } else if (collectibleScore >= 2) {
    collectibleLabel = "Worth revisiting";
  }

  let collectibleHint = "Add a meaning or example before review.";
  if (entry.favorite && collectionCount > 0) {
    collectibleHint = "Favorited and filed in a collection.";
  } else if (collectionCount > 0) {
    collectibleHint = `Filed in ${collectionCount} collection${collectionCount === 1 ? "" : "s"}.`;
  } else if (selectedExamples.length > 0) {
    collectibleHint = "Example selected.";
  } else if (options.duplicateCount > 0) {
    collectibleHint = "Duplicate headwords available.";
  } else if (options.reviewCount > 0) {
    collectibleHint = "Already in review.";
  }

  const reviewSummary =
    options.reviewCount > 0
      ? `${reviewLevelLabel(options.reviewLevel)} · ${options.reviewCount} review${
          options.reviewCount === 1 ? "" : "s"
        }`
      : `${reviewLevelLabel(options.reviewLevel)} · not reviewed yet`;

  return {
    selectedMeaningCount: selectedMeanings.length,
    selectedExampleCount: selectedExamples.length,
    primaryMeaning,
    primaryExample,
    collectionNames: options.collectionNames,
    duplicateCount: options.duplicateCount,
    collectibleLabel,
    collectibleHint,
    reviewSummary,
  };
}

function libraryStudyMeaningLines(entry: LibraryEntry): string[] {
  if (Array.isArray(entry.meaningCandidates) && entry.meaningCandidates.length > 0) {
    const candidateLines = entry.meaningCandidates
      .filter((candidate) => candidate.selected)
      .map((candidate) => {
        const meaning = sanitizeInlineText(candidate.meaning);
        const partOfSpeech = sanitizeInlineText(candidate.partOfSpeech);
        if (!meaning) {
          return "";
        }
        return partOfSpeech ? `${partOfSpeech} · ${meaning}` : meaning;
      })
      .filter(Boolean);

    if (candidateLines.length > 0) {
      return candidateLines;
    }
  }

  const fallbackLines = Array.from(new Set(entry.selectedMeaningIndexes))
    .filter((index) => Number.isInteger(index) && index >= 0 && index < entry.meaningChoices.length)
    .map((index) => {
      const meaning = sanitizeInlineText(entry.meaningChoices[index] ?? "");
      const partOfSpeech = sanitizeInlineText(entry.meaningChoicePartOfSpeechLabels[index] ?? "");
      return meaning ? (partOfSpeech ? `${partOfSpeech} · ${meaning}` : meaning) : "";
    })
    .filter(Boolean);

  return fallbackLines.length > 0
    ? fallbackLines
    : selectedMeaningsFromEntry(entry).filter(Boolean);
}

function libraryStudyExampleLines(entry: LibraryEntry): string[] {
  return selectedExamplesFromEntry(entry)
    .map((example) => sanitizeParagraphText(example))
    .filter(Boolean);
}

function editableMeaningCandidatesForEntry(entry: LibraryEntry): MeaningCandidate[] {
  if (Array.isArray(entry.meaningCandidates) && entry.meaningCandidates.length > 0) {
    return entry.meaningCandidates.map((candidate, index) => ({
      id: sanitizeInlineText(candidate.id, `library-sense-${entry.id}-${index}`),
      partOfSpeech: sanitizeInlineText(candidate.partOfSpeech),
      meaning: sanitizeInlineText(candidate.meaning),
      selected: candidate.selected !== false,
    }));
  }

  return entry.meaningChoices.map((meaning, index) => ({
    id: `library-sense-${entry.id}-${index}`,
    partOfSpeech: sanitizeInlineText(entry.meaningChoicePartOfSpeechLabels[index] ?? ""),
    meaning: sanitizeInlineText(meaning),
    selected: true,
  }));
}

function buildReviewSessionDigest(session: ReviewSessionState): ReviewSessionDigest {
  const answeredCount = session.records.length;
  const remainingCount = Math.max(0, session.queue.length - answeredCount);
  const againCount = session.records.filter((record) => record.decision === "again").length;
  const hardCount = session.records.filter((record) => record.decision === "hard").length;
  const goodCount = session.records.filter((record) => record.decision === "good").length;
  const easyCount = session.records.filter((record) => record.decision === "easy").length;

  let currentStreak = 0;
  for (let index = session.records.length - 1; index >= 0; index -= 1) {
    const decision = session.records[index]?.decision;
    if (!decision || !isStableReviewDecision(decision)) {
      break;
    }

    currentStreak += 1;
  }

  const completionPercent =
    session.queue.length === 0 ? 0 : Math.round((answeredCount / session.queue.length) * 100);

  let momentumLabel = "Fresh round";
  if (currentStreak >= 2) {
    momentumLabel = `${currentStreak}-card stable streak`;
  } else if (againCount === 0 && answeredCount > 0) {
    momentumLabel = "Clean round so far";
  } else if (againCount > 0) {
    momentumLabel = `${againCount} card${againCount === 1 ? "" : "s"} need another pass`;
  }

  const stableCount = goodCount + easyCount;
  const effortCount = againCount + hardCount;
  const reviewPulse =
    answeredCount === 0
      ? "No answers locked yet."
      : `${stableCount} stable call${stableCount === 1 ? "" : "s"} · ${effortCount} effort mark${
          effortCount === 1 ? "" : "s"
        }`;

  return {
    answeredCount,
    remainingCount,
    completionPercent,
    againCount,
    hardCount,
    goodCount,
    easyCount,
    currentStreak,
    momentumLabel,
    reviewPulse,
  };
}

function reviewStateSummaryText(state: ReviewStateRecord): string {
  if (state.reviewCount === 0) {
    return `${reviewLevelLabel(state.level)} · not reviewed yet`;
  }

  return `${reviewLevelLabel(state.level)} · ${state.reviewCount} review${state.reviewCount === 1 ? "" : "s"}`;
}

function reviewStateSecondaryText(state: ReviewStateRecord): string | null {
  if (state.reviewCount === 0 && state.level > 0) {
    return "Manual familiarity only. Review history has not started yet.";
  }

  if (state.reviewCount > 0) {
    return (
      `${reviewDueLabel(state)}` +
      (state.streak > 0 ? ` · ${state.streak} stable in a row` : "")
    );
  }

  return null;
}

function reviewAvailabilityLabel(state: ReviewStateRecord): string {
  return state.reviewCount === 0 ? "Not reviewed yet" : reviewDueLabel(state);
}

function buildReviewDueDigest(
  candidates: ReviewCandidate[],
  reviewStateMap: ReviewStateMap,
): ReviewDueDigest {
  const digest: ReviewDueDigest = {
    dueNow: 0,
    dueSoon: 0,
    scheduled: 0,
    fresh: 0,
  };

  for (const candidate of candidates) {
    const state = reviewStateForTerm(candidate.term, reviewStateMap);
    const bucket = reviewDueBucket(state);
    if (bucket === "new") {
      digest.fresh += 1;
    } else if (bucket === "dueNow") {
      digest.dueNow += 1;
    } else if (bucket === "dueSoon") {
      digest.dueSoon += 1;
    } else {
      digest.scheduled += 1;
    }
  }

  return digest;
}

function buildReviewMistakeClusters(records: ReviewRecord[]): ReviewClusterDigest[] {
  const weakRecords = records.filter(isWeakReviewRecord);
  if (weakRecords.length === 0) {
    return [];
  }

  const counters = new Map<string, ReviewClusterDigest>();
  const register = (key: string, label: string, detail: string) => {
    const existing = counters.get(key);
    if (existing) {
      existing.count += 1;
      return;
    }

    counters.set(key, {
      label,
      count: 1,
      detail,
    });
  };

  for (const record of weakRecords) {
    register(
      `question:${record.questionType}`,
      reviewQuestionTypeLabels[record.questionType].title,
      "Question shape",
    );
    const primarySource = record.sourceKinds[0] ?? "history";
    register(`source:${primarySource}`, reviewSourceLabels[primarySource], "Source lane");
    if (record.partOfSpeech) {
      register(`pos:${record.partOfSpeech}`, record.partOfSpeech, "Part of speech");
    }
  }

  return Array.from(counters.values())
    .sort((left, right) => {
      if (right.count !== left.count) {
        return right.count - left.count;
      }

      return left.label.localeCompare(right.label);
    })
    .slice(0, 6);
}

function formatStorageBytes(raw: string): string {
  const bytes = new TextEncoder().encode(raw).length;
  if (bytes < 1024) {
    return `${bytes} B`;
  }

  if (bytes < 1024 * 1024) {
    return `${(bytes / 1024).toFixed(1)} KB`;
  }

  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

type ChoiceField = "meaning" | "example";

type EditableChoiceSectionState = {
  choices: string[];
  selectedIndexes: number[];
  labels?: string[];
};

function editableChoiceSectionState(
  entry: Pick<
    WorkspaceEditableEntry,
    "meaningChoices" | "selectedMeaningIndexes" | "meaningChoicePartOfSpeechLabels" | "exampleChoices" | "selectedExampleIndexes"
  >,
  field: ChoiceField,
): EditableChoiceSectionState {
  if (field === "meaning") {
    return {
      choices: entry.meaningChoices,
      selectedIndexes: entry.selectedMeaningIndexes,
      labels: entry.meaningChoicePartOfSpeechLabels,
    };
  }

  return {
    choices: entry.exampleChoices,
    selectedIndexes: entry.selectedExampleIndexes,
  };
}

function editableChoiceSectionUpdates(
  field: ChoiceField,
  state: EditableChoiceSectionState,
): Partial<WorkspaceEditableEntry> {
  if (field === "meaning") {
    return {
      meaningChoices: state.choices,
      selectedMeaningIndexes: state.selectedIndexes,
      meaningChoicePartOfSpeechLabels: state.labels ?? [],
    };
  }

  return {
    exampleChoices: state.choices,
    selectedExampleIndexes: state.selectedIndexes,
  };
}

function truncatedPreview(text: string, limit = 140): string {
  const cleaned = text.trim().replace(/\s+/g, " ");
  if (cleaned.length <= limit) {
    return cleaned;
  }

  return `${cleaned.slice(0, Math.max(0, limit - 1)).trimEnd()}…`;
}

function buildSentenceMagicSummary(
  sentence: string,
  candidates: SentenceStudyCandidate[],
  options?: {
    tokenCount?: number;
    matchedEntryCount?: number;
    source?: "fallback" | "live";
  },
): SentenceMagicSummary {
  const strongest = candidates[0] ?? null;

  return {
    candidateCount: candidates.length,
    tokenCount: options?.tokenCount ?? sentenceTokenCount(sentence),
    matchedEntryCount: options?.matchedEntryCount ?? 0,
    wordCount: candidates.filter((candidate) => candidate.kind === "word").length,
    phraseCount: candidates.filter((candidate) => candidate.kind === "phrase").length,
    strongestTerm: strongest?.term ?? "No candidate yet",
    strongestReason: strongest?.reason ?? "Try a shorter English sentence or capture it manually.",
    sourcePreview: truncatedPreview(sentence, 180),
    engineLabel: options?.source === "live" ? "Live sentence study" : "Local sentence study",
  };
}

function adjacentActivityItem(items: ActivityItem[], currentId: string, direction: -1 | 1): ActivityItem | null {
  if (items.length === 0) {
    return null;
  }

  const currentIndex = items.findIndex((item) => item.id === currentId);
  if (currentIndex === -1) {
    return items[0] ?? null;
  }

  return items[currentIndex + direction] ?? null;
}

function suggestionKindLabel(kind: SuggestionItem["kind"]): string {
  switch (kind) {
    case "correction":
      return "Correction";
    case "related":
      return "Related";
    case "phrase":
      return "Phrase";
    case "starter":
      return "Starter";
    default:
      return "Suggestion";
  }
}

export default function WorkspaceClient({
  initialClientId,
  initialWorkspace,
  initialHistoryItems,
  initialInboxItems,
  initialPersistedState,
  initialSection,
  initialKind,
  initialContext,
  initialSelectedActivityId,
  initialSelectedLibraryEntryId,
  initialSource,
  starterQueries,
}: WorkspaceClientProps) {
  const router = useRouter();
  const activityClientId = initialClientId?.trim() ?? "";
  const initialPersistenceSnapshot = parseWorkspacePersistenceSnapshot(initialPersistedState);
  const [historyItems, setHistoryItems] = useState<ActivityItem[]>(initialHistoryItems);
  const [inboxItems, setInboxItems] = useState<ActivityItem[]>(initialInboxItems);
  const [inboxEntryDrafts, setInboxEntryDrafts] = useState<Record<string, WorkspaceEditableEntry>>(
    initialPersistenceSnapshot?.inboxEntryDrafts ?? {},
  );
  const [quickCaptureDrafts, setQuickCaptureDrafts] = useState<QuickCaptureDraftMap>(
    initialPersistenceSnapshot?.quickCaptureDrafts ?? {},
  );
  const [libraryEntries, setLibraryEntries] = useState<LibraryEntry[]>(
    initialPersistenceSnapshot?.libraryEntries ?? [],
  );
  const [savedLibraryArrangements, setSavedLibraryArrangements] = useState<SavedLibraryArrangement[]>(
    initialPersistenceSnapshot?.savedLibraryArrangements ?? [],
  );
  const [trashItems, setTrashItems] = useState<WorkspaceTrashItem[]>(
    initialPersistenceSnapshot?.trashItems ?? [],
  );
  const [workspacePreferences, setWorkspacePreferences] = useState<WorkspacePreferences>(
    initialPersistenceSnapshot?.workspacePreferences ?? defaultWorkspacePreferences(),
  );
  const [inboxSearch, setInboxSearch] = useState("");
  const [inboxSort, setInboxSort] = useState<InboxSortOption>("savedNewest");
  const [historySearch, setHistorySearch] = useState("");
  const [historySort, setHistorySort] = useState<HistorySortOption>("savedNewest");
  const [librarySearch, setLibrarySearch] = useState("");
  const [libraryFilter, setLibraryFilter] = useState<LibraryFilter>("all");
  const [libraryLevelFilter, setLibraryLevelFilter] = useState<LibraryLevelFilter>("all");
  const [librarySort, setLibrarySort] = useState<LibrarySortOption>("updatedNewest");
  const [arrangementNameDraft, setArrangementNameDraft] = useState("");
  const [queryDraft, setQueryDraft] = useState(initialWorkspace.query);
  const [kindDraft, setKindDraft] = useState<LookupKind>(initialKind);
  const [contextDraft, setContextDraft] = useState(initialContext);
  const [isLookupContextDirty, setIsLookupContextDirty] = useState(false);
  const [isQuickCaptureOpen, setIsQuickCaptureOpen] = useState(false);
  const [captureTermDraft, setCaptureTermDraft] = useState("");
  const [captureContextDraft, setCaptureContextDraft] = useState("");
  const [captureKindDraft, setCaptureKindDraft] = useState<LookupKind>("word");
  const [captureReviewLevelDraft, setCaptureReviewLevelDraft] = useState<ReviewLevel>(0);
  const [captureMeaningCandidatesDraft, setCaptureMeaningCandidatesDraft] = useState<MeaningCandidate[]>([]);
  const [captureMeaningCandidatesDirty, setCaptureMeaningCandidatesDirty] = useState(false);
  const [captureExampleChoicesDraft, setCaptureExampleChoicesDraft] = useState<string[]>([]);
  const [captureSelectedExampleIndexesDraft, setCaptureSelectedExampleIndexesDraft] = useState<number[]>([]);
  const [captureExampleChoicesDirty, setCaptureExampleChoicesDirty] = useState(false);
  const [captureCustomExampleDraft, setCaptureCustomExampleDraft] = useState("");
  const [captureCustomExampleMessage, setCaptureCustomExampleMessage] = useState<string | null>(null);
  const [captureNotesDraft, setCaptureNotesDraft] = useState("");
  const [captureSeedMode, setCaptureSeedMode] = useState<"seeded" | "typed">("seeded");
  const [captureKeepOpen, setCaptureKeepOpen] = useState(false);
  const [captureLastSavedTerm, setCaptureLastSavedTerm] = useState<string | null>(null);
  const [captureImportDraft, setCaptureImportDraft] = useState("");
  const [captureImportMessage, setCaptureImportMessage] = useState<string | null>(null);
  const [captureStatusMessage, setCaptureStatusMessage] = useState<string | null>(null);
  const [isSettingsOpen, setIsSettingsOpen] = useState(false);
  const [activeSettingsPanel, setActiveSettingsPanel] = useState<SettingsPanel>("general");
  const [settingsSearchDraft, setSettingsSearchDraft] = useState("");
  const [pendingActivityAction, setPendingActivityAction] = useState<string | null>(null);
  const [selectedTrashIds, setSelectedTrashIds] = useState<Set<string>>(new Set());
  const [isInboxSelecting, setIsInboxSelecting] = useState(false);
  const [selectedInboxIds, setSelectedInboxIds] = useState<Set<string>>(new Set());
  const [isHistorySelecting, setIsHistorySelecting] = useState(false);
  const [selectedHistoryIds, setSelectedHistoryIds] = useState<Set<string>>(new Set());
  const [isLibrarySelecting, setIsLibrarySelecting] = useState(false);
  const [selectedLibraryIds, setSelectedLibraryIds] = useState<Set<string>>(new Set());
  const [reviewSources, setReviewSources] = useState<Set<ReviewSourceKind>>(defaultReviewSourceSet);
  const [reviewQuickFilter, setReviewQuickFilter] = useState<ReviewQuickFilter>("all");
  const [reviewQuestionStrategy, setReviewQuestionStrategy] = useState<ReviewQuestionStrategy>(
    workspacePreferences.review.questionStrategy,
  );
  const [reviewQuestionTypes, setReviewQuestionTypes] = useState<Set<ReviewQuestionType>>(
    new Set<ReviewQuestionType>(workspacePreferences.review.questionTypes),
  );
  const [reviewSort, setReviewSort] = useState<ReviewSortOption>("recommended");
  const [reviewRoundSize] = useState<ReviewRoundSize>("all");
  const [reviewCandidateSearch, setReviewCandidateSearch] = useState("");
  const [selectedReviewIds, setSelectedReviewIds] = useState<Set<string>>(new Set());
  const [reviewSession, setReviewSession] = useState<ReviewSessionState | null>(
    initialPersistenceSnapshot?.reviewSession ?? null,
  );
  const [reviewExitIntent, setReviewExitIntent] = useState(false);
  const [reviewDraftAnswer, setReviewDraftAnswer] = useState(
    initialPersistenceSnapshot?.reviewSession?.draftAnswer ?? "",
  );
  const [reviewSelectedChoice, setReviewSelectedChoice] = useState(
    initialPersistenceSnapshot?.reviewSession?.selectedChoice ?? "",
  );
  const [reviewAnswerSubmitted, setReviewAnswerSubmitted] = useState(
    initialPersistenceSnapshot?.reviewSession?.answerSubmitted ?? false,
  );
  const [reviewStateMap, setReviewStateMap] = useState<ReviewStateMap>(
    initialPersistenceSnapshot?.reviewStateMap ?? {},
  );
  const [reviewHistory, setReviewHistory] = useState<ReviewRecord[]>(
    initialPersistenceSnapshot?.reviewHistory ?? [],
  );
  const [reviewHistorySearch, setReviewHistorySearch] = useState("");
  const [reviewHistorySourceFilter, setReviewHistorySourceFilter] =
    useState<ReviewHistorySourceFilter>("all");
  const [reviewHistoryDecisionFilter, setReviewHistoryDecisionFilter] =
    useState<ReviewHistoryDecisionFilter>("all");
  const [selectedReviewRoundId, setSelectedReviewRoundId] = useState<string | null>(null);
  const [lookupSnapshots, setLookupSnapshots] = useState<Record<string, ReviewLookupSnapshot | null>>({});
  const [lookupFetchStatus, setLookupFetchStatus] = useState<Record<string, LookupFetchStatus>>({});
  const [availableVoices, setAvailableVoices] = useState<SpeechSynthesisVoice[]>([]);
  const [dictHealthStatus, setDictHealthStatus] = useState<LookupFetchStatus>("idle");
  const [dictHealth, setDictHealth] = useState<DictApiHealth | null>(null);
  const [customMeaningDraft, setCustomMeaningDraft] = useState("");
  const [customMeaningMessage, setCustomMeaningMessage] = useState<string | null>(null);
  const [customExampleDraft, setCustomExampleDraft] = useState("");
  const [customExampleMessage, setCustomExampleMessage] = useState<string | null>(null);
  const [customTagDraft, setCustomTagDraft] = useState("");
  const [customTagMessage, setCustomTagMessage] = useState<string | null>(null);
  const [sentenceFocusTerm, setSentenceFocusTerm] = useState("");
  const [reverseFocusTerm, setReverseFocusTerm] = useState("");
  const [sentenceStudyServerCandidates, setSentenceStudyServerCandidates] = useState<SentenceStudyCandidate[] | null>(
    null,
  );
  const [sentenceStudyStatus, setSentenceStudyStatus] = useState<LookupFetchStatus>("idle");
  const [sentenceStudyTokenCount, setSentenceStudyTokenCount] = useState(0);
  const [sentenceStudyMatchedEntryCount, setSentenceStudyMatchedEntryCount] = useState(0);
  const [sentenceStudySource, setSentenceStudySource] = useState<"fallback" | "live">("fallback");
  const [sentenceStudyElapsedMs, setSentenceStudyElapsedMs] = useState<number | null>(null);
  const [sentenceStudyCached, setSentenceStudyCached] = useState(false);
  const [workspacePersistenceReady, setWorkspacePersistenceReady] = useState(
    workspacePersistenceSnapshotHasData(initialPersistenceSnapshot) || initialPersistedState !== null,
  );
  const [workspacePersistenceSyncState, setWorkspacePersistenceSyncState] = useState<
    "idle" | "syncing" | "synced" | "error"
  >(initialPersistedState !== null ? "synced" : "idle");
  const [workspacePersistenceLastSyncedAt, setWorkspacePersistenceLastSyncedAt] = useState<number | null>(null);
  const [diagnosticsMessage, setDiagnosticsMessage] = useState<string | null>(null);
  const historyFingerprintRef = useRef("");
  const inboxMigrationFingerprintRef = useRef("");
  const didHydrateLocalPersistenceRef = useRef(false);
  const workspacePersistenceFingerprintRef = useRef(
    initialPersistenceSnapshot ? JSON.stringify(initialPersistenceSnapshot) : "",
  );
  const captureImportFileInputRef = useRef<HTMLInputElement | null>(null);
  const workspaceBackupFileInputRef = useRef<HTMLInputElement | null>(null);
  const workspaceLayoutStyle = useMemo<WorkspaceLayoutStyle>(
    () => ({
      "--desk-sidebar-width": `${workspacePreferences.layout.sidebarWidth}px`,
      "--desk-content-rail-width": `${workspacePreferences.layout.contentRailWidth}px`,
    }),
    [workspacePreferences.layout.contentRailWidth, workspacePreferences.layout.sidebarWidth],
  );
  const normalizedSettingsSearch = settingsSearchDraft.trim().toLowerCase();
  const visibleSettingsPanels = useMemo(
    () =>
      (Object.keys(settingsPanelLabels) as SettingsPanel[]).filter((panel) => {
        if (!normalizedSettingsSearch) {
          return true;
        }

        return `${settingsPanelLabels[panel]} ${settingsPanelSearchText[panel]}`
          .toLowerCase()
          .includes(normalizedSettingsSearch);
      }),
    [normalizedSettingsSearch],
  );

  function updateWorkspaceLayout(updates: Partial<WorkspacePreferences["layout"]>) {
    setWorkspacePreferences((current) => ({
      ...current,
      layout: {
        ...current.layout,
        ...updates,
      },
    }));
  }

  function resetWorkspaceLayout() {
    updateWorkspaceLayout(defaultWorkspacePreferences().layout);
  }

  function beginWorkspaceResize(
    event: ReactPointerEvent<HTMLDivElement>,
    dimension: "sidebarWidth" | "contentRailWidth",
  ) {
    if (event.button !== 0) {
      return;
    }

    event.preventDefault();
    const startX = event.clientX;
    const startValue = workspacePreferences.layout[dimension];
    const limits = workspaceLayoutLimits[dimension];

    function handlePointerMove(moveEvent: PointerEvent) {
      const nextValue = clampWorkspaceLayoutValue(
        startValue + moveEvent.clientX - startX,
        limits.min,
        limits.max,
      );
      updateWorkspaceLayout({ [dimension]: nextValue });
    }

    function handlePointerUp() {
      document.body.classList.remove("desk-is-resizing");
      window.removeEventListener("pointermove", handlePointerMove);
      window.removeEventListener("pointerup", handlePointerUp);
    }

    document.body.classList.add("desk-is-resizing");
    window.addEventListener("pointermove", handlePointerMove);
    window.addEventListener("pointerup", handlePointerUp, { once: true });
  }

  useEffect(() => {
    setHistoryItems(initialHistoryItems);
  }, [initialHistoryItems]);

  useEffect(() => {
    setInboxItems(initialInboxItems);
  }, [initialInboxItems]);

  useEffect(() => {
    setQueryDraft(initialWorkspace.query);
  }, [initialWorkspace.query]);

  useEffect(() => {
    setKindDraft(initialKind);
  }, [initialKind]);

  useEffect(() => {
    setContextDraft(initialContext);
    setIsLookupContextDirty(false);
  }, [initialContext]);

  useEffect(() => {
    if (didHydrateLocalPersistenceRef.current) {
      return;
    }

    didHydrateLocalPersistenceRef.current = true;
    const localSnapshot = readStoredWorkspacePersistenceSnapshot();
    if (
      shouldPreferLocalPersistenceSnapshot(localSnapshot, initialPersistenceSnapshot) ||
      (!workspacePersistenceReady && workspacePersistenceSnapshotHasData(localSnapshot))
    ) {
      setInboxEntryDrafts(localSnapshot.inboxEntryDrafts);
      setQuickCaptureDrafts(localSnapshot.quickCaptureDrafts);
      setLibraryEntries(localSnapshot.libraryEntries);
      setSavedLibraryArrangements(localSnapshot.savedLibraryArrangements);
      setReviewStateMap(localSnapshot.reviewStateMap);
      setReviewHistory(localSnapshot.reviewHistory);
      setReviewSession(localSnapshot.reviewSession);
      setWorkspacePreferences(localSnapshot.workspacePreferences);
      setReviewQuestionStrategy(localSnapshot.workspacePreferences.review.questionStrategy);
      setReviewQuestionTypes(new Set(localSnapshot.workspacePreferences.review.questionTypes));
      setTrashItems(localSnapshot.trashItems);
    }

    setWorkspacePersistenceReady(true);
  }, [initialPersistenceSnapshot, workspacePersistenceReady]);

  const workspacePersistenceSnapshot = useMemo<WorkspacePersistenceSnapshot>(
    () => ({
      libraryEntries,
      savedLibraryArrangements,
      inboxEntryDrafts,
      quickCaptureDrafts,
      reviewStateMap,
      reviewHistory: reviewHistory.slice(0, 160),
      reviewSession,
      workspacePreferences,
      trashItems,
    }),
    [
      inboxEntryDrafts,
      libraryEntries,
      quickCaptureDrafts,
      reviewHistory,
      reviewSession,
      reviewStateMap,
      savedLibraryArrangements,
      trashItems,
      workspacePreferences,
    ],
  );

  const workspacePersistenceFingerprint = useMemo(
    () => JSON.stringify(workspacePersistenceSnapshot),
    [workspacePersistenceSnapshot],
  );

  useEffect(() => {
    if (typeof window === "undefined" || !workspacePersistenceReady) {
      return;
    }

    writeWorkspacePersistenceSnapshotToLocalStorage(workspacePersistenceSnapshot);
  }, [workspacePersistenceReady, workspacePersistenceSnapshot]);

  useEffect(() => {
    if (!workspacePersistenceReady || typeof window === "undefined" || !activityClientId) {
      return;
    }

    if (workspacePersistenceFingerprint === workspacePersistenceFingerprintRef.current) {
      return;
    }

    const timeoutId = window.setTimeout(() => {
      setWorkspacePersistenceSyncState("syncing");
      void fetch(new URL("/workspace-state", dictApiBaseUrl()).toString(), {
        method: "PUT",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          client_id: activityClientId,
          snapshot: workspacePersistenceSnapshot,
        }),
      }).then((response) => {
        if (response.ok) {
          workspacePersistenceFingerprintRef.current = workspacePersistenceFingerprint;
          setWorkspacePersistenceSyncState("synced");
          setWorkspacePersistenceLastSyncedAt(Date.now());
        } else {
          setWorkspacePersistenceSyncState("error");
        }
      }).catch(() => {
        // Keep the local mirror even if the server sync misses this round.
        setWorkspacePersistenceSyncState("error");
      });
    }, 800);

    return () => {
      window.clearTimeout(timeoutId);
    };
  }, [
    activityClientId,
    workspacePersistenceFingerprint,
    workspacePersistenceReady,
    workspacePersistenceSnapshot,
  ]);

  useEffect(() => {
    setSavedLibraryArrangements((current) => {
      const next = normalizeLibraryArrangements(current, libraryEntries);
      return JSON.stringify(next) === JSON.stringify(current) ? current : next;
    });
  }, [libraryEntries]);

  useEffect(() => {
    const activeArrangementId = arrangementFilterId(libraryFilter);
    if (!activeArrangementId) {
      return;
    }

    if (savedLibraryArrangements.some((arrangement) => arrangement.id === activeArrangementId)) {
      return;
    }

    setLibraryFilter("all");
  }, [libraryFilter, savedLibraryArrangements]);

  useEffect(() => {
    const activeArrangementId = arrangementFilterId(libraryFilter);
    if (!activeArrangementId) {
      setArrangementNameDraft("");
      return;
    }

    const activeArrangement = savedLibraryArrangements.find(
      (arrangement) => arrangement.id === activeArrangementId,
    );
    setArrangementNameDraft(activeArrangement?.name ?? "");
  }, [libraryFilter, savedLibraryArrangements]);

  useEffect(() => {
    setSelectedTrashIds((current) => keepOnlySelectedIds(current, trashItems.map((item) => item.id)));
  }, [trashItems]);

  useEffect(() => {
    if (!workspacePersistenceReady) {
      return;
    }

    const inboxFingerprint = JSON.stringify({
      items: inboxItems.map((item) => [item.id, item.term, item.detail, item.context ?? "", item.savedAt]),
      draftKeys: Object.keys(inboxEntryDrafts).sort(),
    });
    if (inboxFingerprint === inboxMigrationFingerprintRef.current) {
      return;
    }

    if (inboxItems.length === 0 && Object.keys(inboxEntryDrafts).length === 0) {
      inboxMigrationFingerprintRef.current = inboxFingerprint;
      return;
    }

    const migration = migrateWorkspaceInboxState({
      inboxItems,
      snapshot: workspacePersistenceSnapshot,
    });

    inboxMigrationFingerprintRef.current = inboxFingerprint;
    if (!migration.hasChanges) {
      return;
    }

    setInboxItems(migration.inboxItems);
    setInboxEntryDrafts(migration.snapshot.inboxEntryDrafts);
    setQuickCaptureDrafts(migration.snapshot.quickCaptureDrafts);
    setLibraryEntries(migration.snapshot.libraryEntries);
    commitWorkspacePersistenceSnapshot(migration.snapshot);

    if (activityClientId) {
      void replaceActivityFeed("inbox", migration.inboxItems)
        .then((items) => setInboxItems(items))
        .catch(() => {
          // Keep the migrated local state even if the server cleanup misses once.
        });
    }
  }, [
    activityClientId,
    inboxEntryDrafts,
    inboxItems,
    quickCaptureDrafts,
    libraryEntries,
    reviewStateMap,
    workspacePersistenceReady,
    workspacePersistenceSnapshot,
  ]);

  useEffect(() => {
    if (typeof window === "undefined" || !("speechSynthesis" in window)) {
      return;
    }

    function syncVoices() {
      setAvailableVoices(window.speechSynthesis.getVoices());
    }

    syncVoices();
    window.speechSynthesis.addEventListener("voiceschanged", syncVoices);
    return () => {
      window.speechSynthesis.removeEventListener("voiceschanged", syncVoices);
    };
  }, []);

  useEffect(() => {
    if (
      !isSettingsOpen ||
      (activeSettingsPanel !== "resources" && activeSettingsPanel !== "recovery")
    ) {
      return;
    }

    let cancelled = false;
    setDictHealthStatus("loading");

    void fetch(new URL("/health", dictApiBaseUrl()).toString(), {
      cache: "no-store",
      headers: {
        Accept: "application/json",
      },
    })
      .then(async (response) => {
        if (!response.ok) {
          throw new Error("dict_health_failed");
        }

        return (await response.json()) as DictApiHealth;
      })
      .then((health) => {
        if (cancelled) {
          return;
        }

        setDictHealth(health);
        setDictHealthStatus("idle");
      })
      .catch(() => {
        if (cancelled) {
          return;
        }

        setDictHealth(null);
        setDictHealthStatus("error");
      });

    return () => {
      cancelled = true;
    };
  }, [activeSettingsPanel, isSettingsOpen]);

  useEffect(() => {
    if (visibleSettingsPanels.length === 0) {
      return;
    }

    if (!visibleSettingsPanels.includes(activeSettingsPanel)) {
      setActiveSettingsPanel(visibleSettingsPanels[0] ?? "general");
    }
  }, [activeSettingsPanel, visibleSettingsPanels]);

  useEffect(() => {
    if (!initialWorkspace.lookup) {
      return;
    }

    const snapshot = workspaceLookupToSnapshot(initialWorkspace.lookup);
    const keys = [
      normalizedTerm(initialWorkspace.lookup.headword),
      normalizedTerm(initialWorkspace.query),
    ].filter(Boolean);

    setLookupSnapshots((current) => {
      const next = { ...current };
      for (const key of keys) {
        next[key] = snapshot;
      }
      return next;
    });

    setLookupFetchStatus((current) => {
      const next = { ...current };
      for (const key of keys) {
        next[key] = "idle";
      }
      return next;
    });
  }, [initialWorkspace.lookup, initialWorkspace.query]);

  useEffect(() => {
    if (initialSection !== "lookup" || !initialWorkspace.query) {
      return;
    }

    const fingerprint = `${initialWorkspace.mode}:${initialWorkspace.kind}:${initialWorkspace.query}:${
      initialWorkspace.lookup?.headword ?? ""
    }`;
    if (historyFingerprintRef.current === fingerprint) {
      return;
    }

    historyFingerprintRef.current = fingerprint;

    const historyMeta = historyMetaFromWorkspace(initialWorkspace, initialSource, {
      inboxExists: inboxItems.some(
        (item) =>
          normalizedTerm(item.term) ===
          normalizedTerm(initialWorkspace.lookup?.headword ?? initialWorkspace.query),
      ),
      libraryExists: libraryEntries.some(
        (entry) =>
          normalizedTerm(entry.term) ===
          normalizedTerm(initialWorkspace.lookup?.headword ?? initialWorkspace.query),
      ),
    });

    const historyEntry: ActivityItem = {
      id: `${initialWorkspace.query}-${Date.now()}`,
      term: initialWorkspace.lookup?.headword ?? initialWorkspace.query,
      detail: historyDetailFromWorkspace(initialWorkspace, initialContext),
      context: initialContext,
      savedAt: Date.now(),
      meta: historyMeta,
    };

    startTransition(() => {
      setHistoryItems((current) => prependHistoryActivity(current, historyEntry));
    });
    void syncActivity("history", historyEntry);
  }, [initialContext, initialSection, initialSource, initialWorkspace, inboxItems, libraryEntries]);

  const filteredInboxItems = useMemo(() => {
    const search = normalizedTerm(inboxSearch);
    return sortActivityItems(
      inboxItems.filter((item) => activityMatchesSearch(item, search)),
      inboxSort,
    );
  }, [inboxItems, inboxSearch, inboxSort]);

  const filteredHistoryItems = useMemo(() => {
    const search = normalizedTerm(historySearch);
    return sortActivityItems(
      historyItems.filter((item) => activityMatchesSearch(item, search)),
      historySort,
    );
  }, [historyItems, historySearch, historySort]);

  const selectedInboxItem = useMemo(
    () => pickSelectedItem(filteredInboxItems, initialWorkspace.query, initialSelectedActivityId),
    [filteredInboxItems, initialSelectedActivityId, initialWorkspace.query],
  );

  const selectedHistoryItem = useMemo(
    () => pickSelectedItem(filteredHistoryItems, initialWorkspace.query, initialSelectedActivityId),
    [filteredHistoryItems, initialSelectedActivityId, initialWorkspace.query],
  );

  const filteredLibraryEntries = useMemo(() => {
    const search = normalizedTerm(librarySearch);
    const matchesLibraryFilters = (entry: LibraryEntry) =>
      libraryEntryMatchesSearch(entry, search) &&
      libraryEntryMatchesLevel(entry, libraryLevelFilter, reviewStateMap);

    if (libraryFilter === "favorites") {
      return sortLibraryEntries(
        libraryEntries.filter((entry) => entry.favorite).filter(matchesLibraryFilters),
        librarySort,
        reviewStateMap,
      );
    }

    const activeArrangement = arrangementFilterId(libraryFilter)
      ? savedLibraryArrangements.find((arrangement) => arrangement.id === arrangementFilterId(libraryFilter))
      : null;
    if (activeArrangement) {
      return entriesForLibraryArrangement(libraryEntries, activeArrangement).filter(matchesLibraryFilters);
    }

    return sortLibraryEntries(
      libraryEntries.filter(matchesLibraryFilters),
      librarySort,
      reviewStateMap,
    );
  }, [libraryEntries, libraryFilter, libraryLevelFilter, librarySearch, librarySort, reviewStateMap, savedLibraryArrangements]);

  const selectedLibraryEntry = useMemo(
    () =>
      pickSelectedLibraryEntry(
        filteredLibraryEntries,
        initialWorkspace.query,
        initialSelectedLibraryEntryId,
      ),
    [filteredLibraryEntries, initialSelectedLibraryEntryId, initialWorkspace.query],
  );

  const selectedLibraryDuplicates = useMemo(
    () => (selectedLibraryEntry ? duplicateLibraryEntries(libraryEntries, selectedLibraryEntry.id) : []),
    [libraryEntries, selectedLibraryEntry],
  );

  const libraryDuplicateCounts = useMemo(() => {
    const counts = new Map<string, number>();
    for (const entry of libraryEntries) {
      const key = normalizedTerm(entry.term);
      counts.set(key, (counts.get(key) ?? 0) + 1);
    }

    const duplicatesById = new Map<string, number>();
    for (const entry of libraryEntries) {
      const duplicateCount = Math.max(0, (counts.get(normalizedTerm(entry.term)) ?? 1) - 1);
      duplicatesById.set(entry.id, duplicateCount);
    }

    return duplicatesById;
  }, [libraryEntries]);

  const activeSavedArrangement = useMemo(() => {
    const arrangementId = arrangementFilterId(libraryFilter);
    if (!arrangementId) {
      return null;
    }

    return savedLibraryArrangements.find((arrangement) => arrangement.id === arrangementId) ?? null;
  }, [libraryFilter, savedLibraryArrangements]);

  const customLibraryCollections = useMemo(
    () => savedLibraryArrangements.filter((arrangement) => arrangement.mode === "collection"),
    [savedLibraryArrangements],
  );

  const savedReadingArrangements = useMemo(
    () => savedLibraryArrangements.filter((arrangement) => arrangement.mode === "arrangement"),
    [savedLibraryArrangements],
  );

  const activeCustomCollection = activeSavedArrangement?.mode === "collection" ? activeSavedArrangement : null;

  const libraryCollectionsByEntry = useMemo(() => {
    const next = new Map<string, string[]>();

    for (const collection of customLibraryCollections) {
      for (const entryId of collection.entryIds) {
        const current = next.get(entryId) ?? [];
        current.push(collection.name);
        next.set(entryId, current);
      }
    }

    return next;
  }, [customLibraryCollections]);

  const collectionSeedEntryIds = useMemo(() => {
    if (selectedLibraryIds.size > 0) {
      return filteredLibraryEntries
        .filter((entry) => selectedLibraryIds.has(entry.id))
        .map((entry) => entry.id);
    }

    if (selectedLibraryEntry) {
      return [selectedLibraryEntry.id];
    }

    return [];
  }, [filteredLibraryEntries, selectedLibraryEntry, selectedLibraryIds]);

  const selectedTrashItems = useMemo(
    () => trashItems.filter((item) => selectedTrashIds.has(item.id)),
    [selectedTrashIds, trashItems],
  );

  const selectedTrashSummary = useMemo(
    () => ({
      inbox: selectedTrashItems.filter((item) => item.source === "inbox").length,
      history: selectedTrashItems.filter((item) => item.source === "history").length,
      library: selectedTrashItems.filter((item) => item.source === "library").length,
    }),
    [selectedTrashItems],
  );

  useEffect(() => {
    setSelectedInboxIds((current) => keepOnlySelectedIds(current, filteredInboxItems.map((item) => item.id)));
  }, [filteredInboxItems]);

  useEffect(() => {
    setSelectedHistoryIds((current) => keepOnlySelectedIds(current, filteredHistoryItems.map((item) => item.id)));
  }, [filteredHistoryItems]);

  useEffect(() => {
    setSelectedLibraryIds((current) => keepOnlySelectedIds(current, filteredLibraryEntries.map((entry) => entry.id)));
  }, [filteredLibraryEntries]);

  const selectedInboxDraft = useMemo(() => {
    if (!selectedInboxItem) {
      return null;
    }

    const key = normalizedTerm(selectedInboxItem.term);
    return editableEntryFromActivity(
      selectedInboxItem,
      lookupSnapshotForTerm(selectedInboxItem.term),
      inboxEntryDrafts[key] ?? null,
    );
  }, [inboxEntryDrafts, lookupSnapshots, selectedInboxItem]);

  const inboxDigestById = useMemo<Record<string, InboxDraftDigest>>(
    () =>
      Object.fromEntries(
        inboxItems.map((item) => {
          const draft = inboxEntryDrafts[normalizedTerm(item.term)] ?? null;
          return [item.id, inboxDraftDigest(item, draft)];
        }),
      ),
    [inboxEntryDrafts, inboxItems],
  );

  const inboxQueueStats = useMemo(
    () => ({
      ready: inboxItems.filter((item) => inboxDigestById[item.id]?.isReady).length,
      needsMeaning: inboxItems.filter((item) => (inboxDigestById[item.id]?.selectedMeaningCount ?? 0) === 0).length,
      withExample: inboxItems.filter((item) => (inboxDigestById[item.id]?.selectedExampleCount ?? 0) > 0).length,
      withNotes: inboxItems.filter((item) => inboxDigestById[item.id]?.hasNotes).length,
    }),
    [inboxDigestById, inboxItems],
  );

  const reviewSourceCounts = useMemo(
    () => ({
      inbox: inboxItems.filter((item) => !looksLikeSentence(item.term)).length,
      library: libraryEntries.filter((entry) => !looksLikeSentence(entry.term)).length,
      favorites: libraryEntries.filter((entry) => entry.favorite && !looksLikeSentence(entry.term)).length,
      history: buildReviewCandidates(
        historyItems,
        [],
        [],
        new Set<ReviewSourceKind>(["history"]),
        "recommended",
        reviewStateMap,
        workspacePreferences.excludeMasteredFromReview,
      ).length,
    }),
    [historyItems, inboxItems, libraryEntries, reviewStateMap, workspacePreferences.excludeMasteredFromReview],
  );

  const reviewCandidates = useMemo(
    () => {
      const candidates = buildReviewCandidates(
        historyItems,
        inboxItems,
        libraryEntries,
        reviewSources,
        reviewSort,
        reviewStateMap,
        workspacePreferences.excludeMasteredFromReview,
        inboxEntryDrafts,
      );

      if (reviewSort !== "recommended") {
        return candidates;
      }

      return candidates.slice().sort((left, right) => {
        const leftState = reviewStateForTerm(left.term, reviewStateMap);
        const rightState = reviewStateForTerm(right.term, reviewStateMap);
        const leftBucket = reviewDueBucket(leftState);
        const rightBucket = reviewDueBucket(rightState);
        const duePriority = {
          dueNow: 0,
          new: 1,
          dueSoon: 2,
          scheduled: 3,
        } as const;

        if (duePriority[leftBucket] !== duePriority[rightBucket]) {
          return duePriority[leftBucket] - duePriority[rightBucket];
        }

        if ((leftState.dueAt ?? 0) !== (rightState.dueAt ?? 0)) {
          return (leftState.dueAt ?? 0) - (rightState.dueAt ?? 0);
        }

        if (leftState.lapseCount !== rightState.lapseCount) {
          return rightState.lapseCount - leftState.lapseCount;
        }

        return left.term.localeCompare(right.term);
      });
    },
    [
      historyItems,
      inboxItems,
      libraryEntries,
      reviewSources,
      reviewSort,
      reviewStateMap,
      workspacePreferences.excludeMasteredFromReview,
      inboxEntryDrafts,
    ],
  );

  const recentMistakeCandidateIds = useMemo(
    () =>
      new Set(
        reviewHistory
          .filter(isWeakReviewRecord)
          .slice(0, 48)
          .map((record) => record.candidateId),
      ),
    [reviewHistory],
  );

  const filteredReviewCandidates = useMemo(() => {
    const search = normalizedTerm(reviewCandidateSearch);
    return reviewCandidates.filter((candidate) => {
      if (!reviewCandidateMatchesSearch(candidate, search)) {
        return false;
      }

      return matchesReviewQuickFilter(
        candidate,
        reviewQuickFilter,
        recentMistakeCandidateIds,
        reviewStateMap,
      );
    });
  }, [recentMistakeCandidateIds, reviewCandidateSearch, reviewCandidates, reviewQuickFilter, reviewStateMap]);

  const reviewQuickFilterCounts = useMemo<Record<ReviewQuickFilter, number>>(
    () => ({
      all: reviewCandidates.length,
      dueNow: reviewCandidates.filter((candidate) =>
        matchesReviewQuickFilter(candidate, "dueNow", recentMistakeCandidateIds, reviewStateMap),
      ).length,
      unknown: reviewCandidates.filter((candidate) =>
        matchesReviewQuickFilter(candidate, "unknown", recentMistakeCandidateIds, reviewStateMap),
      ).length,
      needsWork: reviewCandidates.filter((candidate) =>
        matchesReviewQuickFilter(candidate, "needsWork", recentMistakeCandidateIds, reviewStateMap),
      ).length,
      recentMistakes: reviewCandidates.filter((candidate) =>
        matchesReviewQuickFilter(candidate, "recentMistakes", recentMistakeCandidateIds, reviewStateMap),
      ).length,
      favoritesOnly: reviewCandidates.filter((candidate) =>
        matchesReviewQuickFilter(candidate, "favoritesOnly", recentMistakeCandidateIds, reviewStateMap),
      ).length,
      historyOnly: reviewCandidates.filter((candidate) =>
        matchesReviewQuickFilter(candidate, "historyOnly", recentMistakeCandidateIds, reviewStateMap),
      ).length,
    }),
    [recentMistakeCandidateIds, reviewCandidates, reviewStateMap],
  );

  const reviewDueDigest = useMemo(
    () => buildReviewDueDigest(reviewCandidates, reviewStateMap),
    [reviewCandidates, reviewStateMap],
  );

  const reviewMistakeClusters = useMemo(
    () => buildReviewMistakeClusters(reviewHistory.slice(0, 120)),
    [reviewHistory],
  );

  const workspaceStateFootprint = useMemo(
    () => formatStorageBytes(workspacePersistenceFingerprint),
    [workspacePersistenceFingerprint],
  );

  const diagnosticsSnapshot = useMemo(
    () => ({
      route: {
        section: initialSection,
        kind: initialKind,
        query: initialWorkspace.query,
        mode: initialWorkspace.mode,
      },
      workspace: {
        inbox: inboxItems.length,
        history: historyItems.length,
        library: libraryEntries.length,
        favorites: libraryEntries.filter((entry) => entry.favorite).length,
        customCollections: savedLibraryArrangements.filter((arrangement) => arrangement.mode === "collection").length,
        savedArrangements: savedLibraryArrangements.filter((arrangement) => arrangement.mode === "arrangement").length,
        trash: trashItems.length,
      },
      review: {
        candidates: reviewCandidates.length,
        due: reviewDueDigest,
        rounds: groupReviewHistory(reviewHistory).length,
        mistakeClusters: reviewMistakeClusters,
      },
      persistence: {
        ready: workspacePersistenceReady,
        syncState: workspacePersistenceSyncState,
        lastSyncedAt: workspacePersistenceLastSyncedAt,
        footprint: workspaceStateFootprint,
      },
      sentenceStudy: {
        status: sentenceStudyStatus,
        source: sentenceStudySource,
        cached: sentenceStudyCached,
        elapsedMs: sentenceStudyElapsedMs,
        matchedEntryCount: sentenceStudyMatchedEntryCount,
      },
      dictRuntime: dictHealth?.runtime ?? null,
    }),
    [
      dictHealth?.runtime,
      historyItems.length,
      inboxItems.length,
      initialKind,
      initialSection,
      initialWorkspace.mode,
      initialWorkspace.query,
      libraryEntries.length,
      reviewCandidates.length,
      reviewDueDigest,
      reviewHistory,
      reviewMistakeClusters,
      savedLibraryArrangements,
      sentenceStudyCached,
      sentenceStudyElapsedMs,
      sentenceStudyMatchedEntryCount,
      sentenceStudySource,
      sentenceStudyStatus,
      trashItems.length,
      workspacePersistenceLastSyncedAt,
      workspacePersistenceReady,
      workspacePersistenceSyncState,
      workspaceStateFootprint,
    ],
  );

  const favoriteCount = useMemo(
    () => libraryEntries.filter((entry) => entry.favorite).length,
    [libraryEntries],
  );

  const libraryDigestById = useMemo<Record<string, LibraryEntryDigest>>(
    () =>
      Object.fromEntries(
        libraryEntries.map((entry) => {
          const reviewState = reviewStateForTerm(entry.term, reviewStateMap);
          return [
            entry.id,
            buildLibraryEntryDigest(entry, {
              reviewLevel: reviewState.level,
              reviewCount: reviewState.reviewCount,
              duplicateCount: libraryDuplicateCounts.get(entry.id) ?? 0,
              collectionNames: libraryCollectionsByEntry.get(entry.id) ?? [],
            }),
          ];
        }),
      ),
    [libraryCollectionsByEntry, libraryDuplicateCounts, libraryEntries, reviewStateMap],
  );

  const visibleLibraryStats = useMemo(
    () => ({
      withExamples: filteredLibraryEntries.filter(
        (entry) => (libraryDigestById[entry.id]?.selectedExampleCount ?? 0) > 0,
      ).length,
      inCollections: filteredLibraryEntries.filter(
        (entry) => (libraryDigestById[entry.id]?.collectionNames.length ?? 0) > 0,
      ).length,
      stable: filteredLibraryEntries.filter(
        (entry) => reviewStateForTerm(entry.term, reviewStateMap).level >= 2,
      ).length,
    }),
    [filteredLibraryEntries, libraryDigestById, reviewStateMap],
  );

  useEffect(() => {
    if (initialSection !== "inbox" || isQuickCaptureOpen || isSettingsOpen || !selectedInboxItem) {
      return;
    }

    function handleInboxKeydown(event: KeyboardEvent) {
      const target = event.target as HTMLElement | null;
      if (
        target &&
        (target.isContentEditable ||
          target.tagName === "INPUT" ||
          target.tagName === "TEXTAREA" ||
          target.tagName === "SELECT")
      ) {
        return;
      }

      if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
        event.preventDefault();
        confirmSelectedInboxItemAndAdvance();
        return;
      }

      if (event.metaKey || event.ctrlKey || event.altKey) {
        return;
      }

      if (event.key === "j" || event.key === "ArrowDown") {
        event.preventDefault();
        focusAdjacentInboxItem(1);
        return;
      }

      if (event.key === "k" || event.key === "ArrowUp") {
        event.preventDefault();
        focusAdjacentInboxItem(-1);
      }
    }

    window.addEventListener("keydown", handleInboxKeydown);
    return () => {
      window.removeEventListener("keydown", handleInboxKeydown);
    };
  }, [initialSection, isQuickCaptureOpen, isSettingsOpen, selectedInboxItem, filteredInboxItems, inboxDigestById]);

  useEffect(() => {
    const visibleIds = new Set(filteredReviewCandidates.map((item) => item.id));
    setSelectedReviewIds((current) => {
      if (current.size === 0) {
        return current;
      }

      const next = new Set(Array.from(current).filter((id) => visibleIds.has(id)));
      return next.size === current.size ? current : next;
    });
  }, [filteredReviewCandidates]);

  useEffect(() => {
    const validIds = new Set(reviewCandidates.map((item) => item.id));
    setReviewSession((current) => {
      if (!current) {
        return current;
      }

      const nextQueue = current.queue.filter((id) => validIds.has(id));
      if (nextQueue.length === 0) {
        return null;
      }

      const nextIndex = Math.min(current.index, nextQueue.length);
      if (nextQueue.length === current.queue.length && nextIndex === current.index) {
        return current;
      }

      return {
        ...current,
        queue: nextQueue,
        index: nextIndex,
      };
    });
  }, [reviewCandidates]);

  const selectedReviewItems = useMemo(() => {
    if (selectedReviewIds.size === 0) {
      return filteredReviewCandidates;
    }

    return filteredReviewCandidates.filter((item) => selectedReviewIds.has(item.id));
  }, [filteredReviewCandidates, selectedReviewIds]);

  const currentReviewStyle = useMemo(
    () => describeReviewQuestionTypes(reviewQuestionTypes, reviewQuestionStrategy),
    [reviewQuestionStrategy, reviewQuestionTypes],
  );

  const reviewLaunchCandidates = useMemo(() => {
    const visibleItems = selectedReviewIds.size === 0 ? filteredReviewCandidates : selectedReviewItems;

    if (selectedReviewIds.size === 0 && reviewRoundSize !== "all") {
      return visibleItems.slice(0, Number(reviewRoundSize));
    }

    return visibleItems;
  }, [filteredReviewCandidates, reviewRoundSize, selectedReviewIds, selectedReviewItems]);

  const currentReviewCandidate = useMemo(() => {
    if (!reviewSession) {
      return null;
    }

    const currentId = reviewSession.queue[reviewSession.index];
    return reviewCandidates.find((item) => item.id === currentId) ?? null;
  }, [reviewCandidates, reviewSession]);

  function lookupSnapshotForTerm(term: string | null | undefined): ReviewLookupSnapshot | null {
    const key = normalizedTerm(term ?? "");
    if (!key) {
      return null;
    }

    return lookupSnapshots[key] ?? null;
  }

  function lookupStatusForTerm(term: string | null | undefined): LookupFetchStatus {
    const key = normalizedTerm(term ?? "");
    if (!key) {
      return "idle";
    }

    return lookupFetchStatus[key] ?? "idle";
  }

  const selectedInboxSnapshot = useMemo(
    () => lookupSnapshotForTerm(selectedInboxItem?.term),
    [lookupSnapshots, selectedInboxItem],
  );

  const selectedHistorySnapshot = useMemo(
    () => lookupSnapshotForTerm(selectedHistoryItem?.term),
    [lookupSnapshots, selectedHistoryItem],
  );

  const selectedLibrarySnapshot = useMemo(
    () => lookupSnapshotForTerm(selectedLibraryEntry?.term),
    [lookupSnapshots, selectedLibraryEntry],
  );

  const currentReviewLookup = useMemo(
    () => lookupSnapshotForTerm(currentReviewCandidate?.term),
    [lookupSnapshots, currentReviewCandidate],
  );

  useEffect(() => {
    if (initialSection !== "inbox" || !selectedInboxItem) {
      return;
    }

    const key = normalizedTerm(selectedInboxItem.term);
    const nextDraft = editableEntryFromActivity(
      selectedInboxItem,
      selectedInboxSnapshot,
      inboxEntryDrafts[key] ?? null,
    );

    setInboxEntryDrafts((current) => {
      if (sameEditableEntry(current[key], nextDraft)) {
        return current;
      }

      return {
        ...current,
        [key]: nextDraft,
      };
    });
  }, [inboxEntryDrafts, initialSection, selectedInboxItem, selectedInboxSnapshot]);

  useEffect(() => {
    if (initialSection !== "library" || !selectedLibraryEntry || !selectedLibrarySnapshot) {
      return;
    }
    // Library is the confirmed study source. Do not auto-mutate confirmed entries on route entry.
    // Use the explicit "Refresh Candidates" action when the user wants fresh dictionary enrichment.
  }, [initialSection, selectedLibraryEntry, selectedLibrarySnapshot]);

  const currentReviewQuestionType = useMemo<ReviewQuestionType>(() => {
    if (!reviewSession || !currentReviewCandidate) {
      return "multipleChoice";
    }

    if (reviewSession.questionStrategy === "smart") {
      return selectSmartReviewQuestionTypeForCandidate(currentReviewCandidate, reviewSession.questionTypes);
    }

    return selectReviewQuestionTypeForCandidate(currentReviewCandidate, reviewSession.questionTypes);
  }, [currentReviewCandidate, reviewSession]);

  const currentReviewCard = useMemo(() => {
    if (!currentReviewCandidate) {
      return null;
    }

    return buildReviewCard(currentReviewCandidate, currentReviewLookup, currentReviewQuestionType, reviewCandidates);
  }, [currentReviewCandidate, currentReviewLookup, currentReviewQuestionType, reviewCandidates]);

  useEffect(() => {
    if (!reviewSession || !currentReviewCandidate) {
      setReviewDraftAnswer("");
      setReviewSelectedChoice("");
      setReviewAnswerSubmitted(false);
      return;
    }

    const activeCandidateId =
      reviewSession.activeCandidateId ?? reviewSession.queue[reviewSession.index] ?? null;
    if (activeCandidateId !== currentReviewCandidate.id) {
      setReviewDraftAnswer("");
      setReviewSelectedChoice("");
      setReviewAnswerSubmitted(false);
      return;
    }

    setReviewDraftAnswer(reviewSession.draftAnswer);
    setReviewSelectedChoice(reviewSession.selectedChoice);
    setReviewAnswerSubmitted(reviewSession.answerSubmitted);
  }, [currentReviewCandidate?.id, currentReviewQuestionType, reviewSession?.sessionId]);

  useEffect(() => {
    if (!reviewSession || !currentReviewCandidate) {
      return;
    }

    setReviewSession((current) => {
      if (!current) {
        return current;
      }

      const activeCandidateId = current.activeCandidateId ?? current.queue[current.index] ?? null;
      if (activeCandidateId !== currentReviewCandidate.id) {
        return current;
      }

      if (
        current.draftAnswer === reviewDraftAnswer &&
        current.selectedChoice === reviewSelectedChoice &&
        current.answerSubmitted === reviewAnswerSubmitted
      ) {
        return current;
      }

      return {
        ...current,
        activeCandidateId,
        draftAnswer: reviewDraftAnswer,
        selectedChoice: reviewSelectedChoice,
        answerSubmitted: reviewAnswerSubmitted,
      };
    });
  }, [
    currentReviewCandidate?.id,
    reviewAnswerSubmitted,
    reviewDraftAnswer,
    reviewSelectedChoice,
    reviewSession?.sessionId,
  ]);

  useEffect(() => {
    if (!isQuickCaptureOpen) {
      return;
    }

    const trimmedTerm = captureTermDraft.trim();
    if (!trimmedTerm || containsChineseCharacters(trimmedTerm) || looksLikeSentence(trimmedTerm)) {
      return;
    }

    if (captureMeaningCandidatesDirty && captureMeaningCandidatesDraft.length > 0) {
      return;
    }

    const snapshot = captureSnapshotForTerm(trimmedTerm);
    const matchingDraft = quickCaptureDrafts[normalizedTerm(trimmedTerm)]?.entry ?? null;
    const shouldReuseSavedDraft = captureSeedMode === "seeded";
    if (!snapshot && !matchingDraft) {
      return;
    }

    const seededEntry = buildQuickCaptureEditableEntry({
      term: trimmedTerm,
      kind: captureKindDraft,
      context: captureContextDraft,
      exampleChoices: captureExampleChoicesDirty ? captureExampleChoicesDraft : undefined,
      selectedExampleIndexes: captureExampleChoicesDirty ? captureSelectedExampleIndexesDraft : undefined,
      notes: captureNotesDraft,
      snapshot,
      existing: shouldReuseSavedDraft ? matchingDraft : null,
    });

    setCaptureMeaningCandidatesDraft((current) => {
      const nextCandidates =
        seededEntry.meaningCandidates ??
        meaningCandidatesFromChoices(
          seededEntry.meaningChoices,
          seededEntry.meaningChoicePartOfSpeechLabels,
          seededEntry.selectedMeaningIndexes,
        );

      return JSON.stringify(current) === JSON.stringify(nextCandidates) ? current : nextCandidates;
    });
    if (!captureExampleChoicesDirty) {
      setCaptureExampleChoicesDraft(seededEntry.exampleChoices);
      setCaptureSelectedExampleIndexesDraft(seededEntry.selectedExampleIndexes);
    }
  }, [
    captureContextDraft,
    captureExampleChoicesDirty,
    captureExampleChoicesDraft,
    captureSelectedExampleIndexesDraft,
    captureKindDraft,
    captureMeaningCandidatesDirty,
    captureMeaningCandidatesDraft,
    captureNotesDraft,
    captureSeedMode,
    captureTermDraft,
    isQuickCaptureOpen,
    lookupSnapshots,
    quickCaptureDrafts,
  ]);

  const currentReviewCorrect = useMemo(() => {
    if (!reviewAnswerSubmitted || !currentReviewCard) {
      return null;
    }

    if (currentReviewCard.family === "flashcards") {
      return null;
    }

    if (currentReviewCard.family === "multipleChoice") {
      return reviewSelectedChoice === currentReviewCard.answer;
    }

    return matchesSubmittedAnswer(reviewDraftAnswer, currentReviewCard.acceptedAnswers);
  }, [currentReviewCard, reviewAnswerSubmitted, reviewDraftAnswer, reviewSelectedChoice]);

  const activeReviewSessionDigest = useMemo(
    () => (reviewSession ? buildReviewSessionDigest(reviewSession) : null),
    [reviewSession],
  );

  const upcomingReviewCandidates = useMemo(() => {
    if (!reviewSession) {
      return [];
    }

    return reviewSession.queue
      .slice(reviewSession.index + 1, reviewSession.index + 6)
      .map((candidateId) => reviewCandidates.find((item) => item.id === candidateId) ?? null)
      .filter((candidate): candidate is ReviewCandidate => Boolean(candidate));
  }, [reviewCandidates, reviewSession]);

  const groupedReviewHistory = useMemo(() => groupReviewHistory(reviewHistory), [reviewHistory]);

  const filteredReviewHistory = useMemo(() => {
    const search = normalizedTerm(reviewHistorySearch);

    return groupedReviewHistory.filter((round) => {
      if (reviewHistorySourceFilter !== "all" && !round.sourceKinds.includes(reviewHistorySourceFilter)) {
        return false;
      }

      const items =
        reviewHistoryDecisionFilter === "all"
          ? round.items
          : round.items.filter((item) => item.decision === reviewHistoryDecisionFilter);

      if (items.length === 0) {
        return false;
      }

      if (!search) {
        return true;
      }

      return items.some((item) =>
        [
          item.term,
          item.meaning,
          item.prompt,
          item.submittedAnswer,
          item.example,
          item.context,
          item.notes,
        ]
          .join(" ")
          .toLowerCase()
          .includes(search),
      );
    });
  }, [
    groupedReviewHistory,
    reviewHistoryDecisionFilter,
    reviewHistorySearch,
    reviewHistorySourceFilter,
  ]);

  const selectedReviewRound = useMemo(
    () => filteredReviewHistory.find((round) => round.sessionId === selectedReviewRoundId) ?? null,
    [filteredReviewHistory, selectedReviewRoundId],
  );

  const fallbackSentenceStudyCandidates = useMemo(
    () =>
      initialWorkspace.kind === "sentence" && initialWorkspace.query
        ? extractSentenceStudyCandidates(initialWorkspace.query)
        : [],
    [initialWorkspace.kind, initialWorkspace.query],
  );

  const sentenceStudyCandidates = useMemo(
    () => sentenceStudyServerCandidates ?? fallbackSentenceStudyCandidates,
    [fallbackSentenceStudyCandidates, sentenceStudyServerCandidates],
  );

  const sentenceMagicSummary = useMemo(
    () =>
      buildSentenceMagicSummary(initialWorkspace.query, sentenceStudyCandidates, {
        tokenCount:
          sentenceStudyTokenCount > 0 ? sentenceStudyTokenCount : sentenceTokenCount(initialWorkspace.query),
        matchedEntryCount: sentenceStudyMatchedEntryCount,
        source: sentenceStudySource,
      }),
    [
      initialWorkspace.query,
      sentenceStudyCandidates,
      sentenceStudyMatchedEntryCount,
      sentenceStudySource,
      sentenceStudyTokenCount,
    ],
  );

  const sentenceFocusSnapshot = useMemo(
    () => lookupSnapshotForTerm(sentenceFocusTerm),
    [lookupSnapshots, sentenceFocusTerm],
  );

  const reverseFocusSnapshot = useMemo(
    () => lookupSnapshotForTerm(reverseFocusTerm),
    [lookupSnapshots, reverseFocusTerm],
  );

  const orderedQuickCaptureDrafts = useMemo(
    () =>
      Object.values(quickCaptureDrafts)
        .slice()
        .sort((left, right) => right.savedAt - left.savedAt),
    [quickCaptureDrafts],
  );

  const quickCapturePresets = useMemo(() => {
    const presets: QuickCapturePreset[] = [];
    const seen = new Set<string>();

    function pushPreset(preset: QuickCapturePreset | null) {
      if (!preset) {
        return;
      }

      const key = `${preset.kind}:${normalizedTerm(preset.term)}`;
      if (!preset.term.trim() || seen.has(key)) {
        return;
      }

      seen.add(key);
      presets.push(preset);
    }

    pushPreset(
      selectedInboxItem
        ? {
            id: `inbox:${selectedInboxItem.id}`,
            label: "Selected inbox item",
            caption: "Reuse the draft you are already shaping.",
            term: selectedInboxItem.term,
            kind: inferLookupKindFromTerm(selectedInboxItem.term, "word"),
            context: selectedInboxItem.context ?? "",
            reviewLevel: reviewStateForTerm(selectedInboxItem.term, reviewStateMap).level,
            entry:
              inboxEntryDrafts[normalizedTerm(selectedInboxItem.term)] ??
              editableEntryFromActivity(
                selectedInboxItem,
                lookupSnapshotForTerm(selectedInboxItem.term),
                null,
              ),
          }
        : null,
    );

    pushPreset(
      selectedHistoryItem
        ? {
            id: `history:${selectedHistoryItem.id}`,
            label: "Selected history item",
            caption: "Pull this breadcrumb back into active study.",
            term: selectedHistoryItem.term,
            kind: inferLookupKindFromTerm(selectedHistoryItem.term, "word"),
            context: selectedHistoryItem.context ?? "",
            reviewLevel: reviewStateForTerm(selectedHistoryItem.term, reviewStateMap).level,
            entry: editableEntryFromActivity(
              selectedHistoryItem,
              lookupSnapshotForTerm(selectedHistoryItem.term),
              quickCaptureDrafts[normalizedTerm(selectedHistoryItem.term)]?.entry ?? null,
            ),
          }
        : null,
    );

    pushPreset(
      selectedLibraryEntry
        ? {
            id: `library:${selectedLibraryEntry.id}`,
            label: "Selected library entry",
            caption: "Capture a variation or a note from the current shelf card.",
            term: selectedLibraryEntry.term,
            kind: selectedLibraryEntry.kind,
            context: selectedLibraryEntry.context ?? "",
            reviewLevel: reviewStateForTerm(selectedLibraryEntry.term, reviewStateMap).level,
            entry: selectedLibraryEntry,
          }
        : null,
    );

    pushPreset(
      initialWorkspace.lookup
        ? {
            id: `lookup:${initialWorkspace.lookup.headword}`,
            label: "Current lookup",
            caption: "Use the live lookup result as the next capture seed.",
            term: initialWorkspace.lookup.headword,
            kind: initialWorkspace.kind,
            context: initialContext ?? "",
            reviewLevel: reviewStateForTerm(initialWorkspace.lookup.headword, reviewStateMap).level,
            entry: createEditableEntry({
              term: initialWorkspace.lookup.headword,
              kind: initialWorkspace.kind,
              detail: initialWorkspace.lookup.summary,
              context: initialContext ?? "",
              snapshot: initialWorkspace.lookup,
              existing: quickCaptureDrafts[normalizedTerm(initialWorkspace.lookup.headword)]?.entry ?? null,
            }),
          }
        : null,
    );

    pushPreset(
      sentenceStudyCandidates[0]
        ? {
            id: `sentence:${sentenceStudyCandidates[0].term}`,
            label: "Strongest sentence candidate",
            caption: sentenceStudyCandidates[0].reason,
            term: sentenceStudyCandidates[0].term,
            kind: sentenceStudyCandidates[0].kind,
            context: initialWorkspace.query,
            reviewLevel: 0,
            entry: createEditableEntry({
              term: sentenceStudyCandidates[0].term,
              kind: sentenceStudyCandidates[0].kind,
              detail:
                lookupSnapshotForTerm(sentenceStudyCandidates[0].term)?.summary ??
                sentenceStudyCandidates[0].summary,
              context: initialWorkspace.query,
              snapshot: lookupSnapshotForTerm(sentenceStudyCandidates[0].term),
              existing: quickCaptureDrafts[normalizedTerm(sentenceStudyCandidates[0].term)]?.entry ?? null,
            }),
          }
        : null,
    );

    pushPreset(
      queryDraft.trim()
        ? {
            id: `draft:${queryDraft.trim()}`,
            label: "Current query",
            caption: "Drop the text already sitting in the lookup bar into capture.",
            term: queryDraft.trim(),
            kind: kindDraft,
            context: initialContext ?? contextDraft ?? "",
            reviewLevel: 0,
            entry: createEditableEntry({
              term: queryDraft.trim(),
              kind: kindDraft,
              detail: queryDraft.trim(),
              context: initialContext ?? contextDraft ?? "",
              snapshot: lookupSnapshotForTerm(queryDraft.trim()),
              existing: quickCaptureDrafts[normalizedTerm(queryDraft.trim())]?.entry ?? null,
            }),
          }
        : null,
    );

    orderedQuickCaptureDrafts.forEach((draft, index) => {
      pushPreset({
        id: `quick-capture-draft:${normalizedTerm(draft.term)}:${index}`,
        label: "Saved draft",
        caption: "Continue shaping this draft before it becomes a library entry.",
        term: draft.term,
        kind: draft.kind,
        context: draft.context,
        reviewLevel: draft.reviewLevel,
        entry: draft.entry,
      });
    });

    return presets.slice(0, 6);
  }, [
    contextDraft,
    inboxEntryDrafts,
    initialContext,
    initialWorkspace.kind,
    initialWorkspace.lookup,
    initialWorkspace.query,
    kindDraft,
    lookupSnapshots,
    orderedQuickCaptureDrafts,
    quickCaptureDrafts,
    queryDraft,
    reviewStateMap,
    selectedHistoryItem,
    selectedInboxItem,
    selectedLibraryEntry,
    sentenceStudyCandidates,
  ]);

  const recentQuickCaptureItems = useMemo(() => inboxItems.slice(0, 4), [inboxItems]);
  const bulkCapturePreviewItems = useMemo(
    () => parseQuickCaptureImportInput(captureImportDraft),
    [captureImportDraft],
  );

  useEffect(() => {
    if (initialWorkspace.kind !== "sentence" || !initialWorkspace.query.trim()) {
      setSentenceStudyServerCandidates(null);
      setSentenceStudyStatus("idle");
      setSentenceStudyTokenCount(0);
      setSentenceStudyMatchedEntryCount(0);
      setSentenceStudySource("fallback");
      setSentenceStudyElapsedMs(null);
      setSentenceStudyCached(false);
      return;
    }

    let cancelled = false;
    setSentenceStudyServerCandidates(null);
    setSentenceStudyStatus("loading");
    setSentenceStudyTokenCount(sentenceTokenCount(initialWorkspace.query));
    setSentenceStudyMatchedEntryCount(0);
    setSentenceStudySource("fallback");
    setSentenceStudyElapsedMs(null);
    setSentenceStudyCached(false);

    void loadSentenceStudy(initialWorkspace.query)
      .then((result) => {
        if (cancelled) {
          return;
        }

        if (!result) {
          setSentenceStudyStatus("error");
          return;
        }

        setSentenceStudyTokenCount(result.token_count);
        setSentenceStudyMatchedEntryCount(result.matched_entry_count);
        setSentenceStudyElapsedMs(
          typeof result.elapsed_ms === "number" && Number.isFinite(result.elapsed_ms)
            ? result.elapsed_ms
            : null,
        );
        setSentenceStudyCached(Boolean(result.cached));
        if (result.candidates.length > 0) {
          setSentenceStudyServerCandidates(
            result.candidates.map((candidate) => ({
              term: candidate.term,
              kind: candidate.kind,
              score: candidate.score,
              reason: candidate.reason,
              summary: candidate.summary,
            })),
          );
          setSentenceStudySource("live");
        }
        setSentenceStudyStatus("idle");
      })
      .catch(() => {
        if (!cancelled) {
          setSentenceStudyStatus("error");
        }
      });

    return () => {
      cancelled = true;
    };
  }, [initialWorkspace.kind, initialWorkspace.query]);

  useEffect(() => {
    if (!selectedReviewRoundId) {
      return;
    }

    if (filteredReviewHistory.some((round) => round.sessionId === selectedReviewRoundId)) {
      return;
    }

    setSelectedReviewRoundId(null);
  }, [filteredReviewHistory, selectedReviewRoundId]);

  useEffect(() => {
    const nextFocus = sentenceStudyCandidates[0]?.term ?? "";
    setSentenceFocusTerm((current) =>
      current && sentenceStudyCandidates.some((candidate) => candidate.term === current) ? current : nextFocus,
    );
  }, [sentenceStudyCandidates]);

  useEffect(() => {
    const reverseCandidates =
      initialWorkspace.mode === "reverse" ? initialWorkspace.reverseMatches.slice(0, 6) : [];
    const nextFocus = reverseCandidates[0]?.term ?? "";
    setReverseFocusTerm((current) =>
      current && reverseCandidates.some((candidate) => candidate.term === current) ? current : nextFocus,
    );
  }, [initialWorkspace.mode, initialWorkspace.reverseMatches]);

  useEffect(() => {
    setCustomMeaningDraft("");
    setCustomMeaningMessage(null);
    setCustomExampleDraft("");
    setCustomExampleMessage(null);
    setCustomTagDraft("");
    setCustomTagMessage(null);
  }, [initialSection, selectedInboxItem?.id, selectedLibraryEntry?.id]);

  const desiredLookupTerms = useMemo(() => {
    const terms = new Set<string>();
    const candidates = [
      selectedInboxItem?.term,
      selectedHistoryItem?.term,
      selectedLibraryEntry?.term,
      currentReviewCandidate?.term,
      sentenceFocusTerm,
      reverseFocusTerm,
      isQuickCaptureOpen ? captureTermDraft : null,
      ...sentenceStudyCandidates.slice(0, 6).map((candidate) => candidate.term),
      ...initialWorkspace.reverseMatches.slice(0, 4).map((candidate) => candidate.term),
    ];

    for (const term of candidates) {
      if (!term || containsChineseCharacters(term) || looksLikeSentence(term)) {
        continue;
      }

      terms.add(term);
    }

    return Array.from(terms);
  }, [
    currentReviewCandidate,
    selectedHistoryItem,
    selectedInboxItem,
    selectedLibraryEntry,
    reverseFocusTerm,
    isQuickCaptureOpen,
    initialWorkspace.reverseMatches,
    captureTermDraft,
    sentenceFocusTerm,
    sentenceStudyCandidates,
  ]);
  const desiredLookupTermFingerprint = useMemo(
    () => desiredLookupTerms.map((term) => normalizedTerm(term)).join("\n"),
    [desiredLookupTerms],
  );

  useEffect(() => {
    const pendingTerms = desiredLookupTerms.filter((term) => {
      const key = normalizedTerm(term);
      return key && lookupSnapshots[key] === undefined && lookupStatusForTerm(term) !== "loading";
    });

    if (pendingTerms.length === 0) {
      return;
    }

    const pendingKeys = pendingTerms.map((term) => normalizedTerm(term));
    let cancelled = false;

    setLookupFetchStatus((current) => ({
      ...current,
      ...Object.fromEntries(pendingKeys.map((key) => [key, "loading" as const])),
    }));

    void Promise.all(
      pendingTerms.map(async (term) => {
        const response = await fetch(buildLookupRequestUrl(term), {
          cache: "no-store",
          headers: {
            Accept: "application/json",
          },
        });
        if (!response.ok) {
          throw new Error("lookup_failed");
        }

        const envelope = (await response.json()) as LookupProxyEnvelope;
        return {
          key: normalizedTerm(term),
          snapshot: lookupSnapshotFromApiData(envelope.data),
          status: "idle" as LookupFetchStatus,
        };
      }),
    )
      .then((results) => {
        if (cancelled) {
          return;
        }

        setLookupSnapshots((current) => {
          const next = { ...current };
          for (const result of results) {
            next[result.key] = result.snapshot;
          }
          return next;
        });
        setLookupFetchStatus((current) => {
          const next = { ...current };
          for (const result of results) {
            next[result.key] = result.status;
          }
          return next;
        });
      })
      .catch(() => {
        if (cancelled) {
          return;
        }

        setLookupSnapshots((current) => {
          const next = { ...current };
          for (const key of pendingKeys) {
            next[key] = null;
          }
          return next;
        });
        setLookupFetchStatus((current) => {
          const next = { ...current };
          for (const key of pendingKeys) {
            next[key] = "error";
          }
          return next;
        });
      });

    return () => {
      cancelled = true;
    };
  }, [desiredLookupTermFingerprint]);

  const currentLookupDraftRecord = useMemo(() => {
    if (!initialWorkspace.lookup) {
      return null;
    }

    return quickCaptureDrafts[normalizedTerm(initialWorkspace.lookup.headword)] ?? null;
  }, [initialWorkspace.lookup, quickCaptureDrafts]);

  const isCurrentLookupInLibrary = useMemo(() => {
    if (!initialWorkspace.lookup) {
      return false;
    }

    const normalized = normalizedTerm(initialWorkspace.lookup.headword);
    return libraryEntries.some((entry) => normalizedTerm(entry.term) === normalized);
  }, [initialWorkspace.lookup, libraryEntries]);

  const currentSentenceDraftRecord = useMemo(() => {
    if (initialWorkspace.kind !== "sentence" || !initialWorkspace.query.trim()) {
      return null;
    }

    const normalized = normalizedTerm(initialWorkspace.query);
    return quickCaptureDrafts[normalized] ?? null;
  }, [initialWorkspace.kind, initialWorkspace.query, quickCaptureDrafts]);

  const isCurrentSentenceInLibrary = useMemo(() => {
    if (initialWorkspace.kind !== "sentence" || !initialWorkspace.query.trim()) {
      return false;
    }

    const normalized = normalizedTerm(initialWorkspace.query);
    return libraryEntries.some((entry) => normalizedTerm(entry.term) === normalized);
  }, [initialWorkspace.kind, initialWorkspace.query, libraryEntries]);

  const canPlayCurrentAudio = useMemo(
    () => isPronounceableEnglish(initialWorkspace.lookup?.headword ?? ""),
    [initialWorkspace.lookup?.headword],
  );

  function playPronunciation(term: string) {
    if (!isPronounceableEnglish(term) || typeof window === "undefined") {
      return;
    }

    const utterance = new SpeechSynthesisUtterance(term);
    const preferredVoice =
      workspacePreferences.pronunciationVoiceURI === automaticPronunciationVoiceURI
        ? null
        : availableVoices.find((voice) => voice.voiceURI === workspacePreferences.pronunciationVoiceURI) ?? null;

    if (preferredVoice) {
      utterance.voice = preferredVoice;
      utterance.lang = preferredVoice.lang;
    }

    window.speechSynthesis.cancel();
    window.speechSynthesis.speak(utterance);
  }

  function setReviewLevelForTerm(term: string, level: ReviewLevel) {
    const key = normalizedReviewKey(term);

    setReviewStateMap((current) => {
      const previous = current[key] ?? defaultReviewState();
      return {
        ...current,
        [key]: {
          level,
          reviewCount: previous.reviewCount,
          lastReviewedAt: previous.lastReviewedAt,
          dueAt: previous.dueAt,
          streak: previous.streak,
          lapseCount: previous.lapseCount,
          lastDecision: previous.lastDecision,
        },
      };
    });
  }

  function updateInboxActivityItem(
    item: ActivityItem,
    updates: Partial<Pick<ActivityItem, "detail" | "context">>,
  ) {
    const nextItem: ActivityItem = {
      ...item,
      detail: updates.detail ?? item.detail,
      context: sanitizeParagraphText(updates.context ?? item.context ?? ""),
    };

    setInboxItems((current) =>
      current.map((candidate) => (candidate.id === item.id ? nextItem : candidate)),
    );
    void syncActivity("inbox", nextItem);
  }

  function updateInboxDraft(
    item: ActivityItem,
    updates: Partial<WorkspaceEditableEntry>,
    options?: {
      syncDetail?: boolean;
    },
  ) {
    const key = normalizedTerm(item.term);
    const snapshot = lookupSnapshotForTerm(item.term);
    const currentDraft = editableEntryFromActivity(item, snapshot, inboxEntryDrafts[key] ?? null);
    const nextDraft = createEditableEntry({
      term: item.term,
      kind: updates.kind ?? currentDraft.kind,
      detail: updates.detail ?? currentDraft.detail,
      context: item.context,
      notes: updates.notes ?? currentDraft.notes,
      snapshot,
      existing: {
        ...currentDraft,
        ...updates,
        meaningChoices: updates.meaningChoices ?? currentDraft.meaningChoices,
        meaningChoicePartOfSpeechLabels:
          updates.meaningChoicePartOfSpeechLabels ?? currentDraft.meaningChoicePartOfSpeechLabels,
        selectedMeaningIndexes: updates.selectedMeaningIndexes ?? currentDraft.selectedMeaningIndexes,
        exampleChoices: updates.exampleChoices ?? currentDraft.exampleChoices,
        selectedExampleIndexes: updates.selectedExampleIndexes ?? currentDraft.selectedExampleIndexes,
        englishDefinitions: updates.englishDefinitions ?? currentDraft.englishDefinitions,
        inflectionLines: updates.inflectionLines ?? currentDraft.inflectionLines,
        referenceTags: updates.referenceTags ?? currentDraft.referenceTags,
      },
    });

    setInboxEntryDrafts((current) => ({
      ...current,
      [key]: nextDraft,
    }));

    if (options?.syncDetail) {
      updateInboxActivityItem(item, {
        detail: nextDraft.detail,
      });
    }
  }

  function refreshInboxDraft(item: ActivityItem) {
    const snapshot = lookupSnapshotForTerm(item.term);
    const key = normalizedTerm(item.term);
    const nextDraft = createEditableEntry({
      term: item.term,
      kind: inferLookupKindFromTerm(item.term, "word"),
      detail: item.detail,
      context: item.context,
      notes: inboxEntryDrafts[key]?.notes ?? "",
      snapshot,
      existing: {
        notes: inboxEntryDrafts[key]?.notes ?? "",
      },
    });

    setInboxEntryDrafts((current) => ({
      ...current,
      [key]: nextDraft,
    }));
    updateInboxActivityItem(item, {
      detail: nextDraft.detail,
    });
  }

  function applyInboxChoiceSectionState(
    item: ActivityItem,
    field: ChoiceField,
    state: EditableChoiceSectionState,
  ) {
    updateInboxDraft(item, editableChoiceSectionUpdates(field, state), {
      syncDetail: field === "meaning",
    });
  }

  function refreshLibraryEntryFromSnapshot(entry: LibraryEntry) {
    const snapshot = lookupSnapshotForTerm(entry.term);
    const nextDraft = createEditableEntry({
      term: entry.term,
      kind: entry.kind,
      detail: entry.detail,
      context: entry.context,
      notes: entry.notes,
      snapshot,
      existing: entry,
    });

    setLibraryEntries((current) =>
      updateLibraryEntry(current, entry.id, {
        kind: nextDraft.kind,
        partOfSpeech: nextDraft.partOfSpeech,
        detail: nextDraft.detail,
        notes: nextDraft.notes,
        meaningCandidates: nextDraft.meaningCandidates,
        meaningChoices: nextDraft.meaningChoices,
        meaningChoicePartOfSpeechLabels: nextDraft.meaningChoicePartOfSpeechLabels,
        selectedMeaningIndexes: nextDraft.selectedMeaningIndexes,
        exampleChoices: nextDraft.exampleChoices,
        selectedExampleIndexes: nextDraft.selectedExampleIndexes,
        englishDefinitions: nextDraft.englishDefinitions,
        inflectionLines: nextDraft.inflectionLines,
        referenceTags: nextDraft.referenceTags,
      }),
    );
  }

  function applyQuickCaptureFormState(
    state: {
      term: string;
      kind: LookupKind;
      context: string;
      reviewLevel: ReviewLevel;
      meaningCandidates: MeaningCandidate[];
      exampleChoices: string[];
      selectedExampleIndexes: number[];
      notes: string;
    },
  ) {
    setCaptureTermDraft(state.term);
    setCaptureContextDraft(state.context);
    setCaptureKindDraft(state.kind);
    setCaptureReviewLevelDraft(state.reviewLevel);
    setCaptureMeaningCandidatesDraft(state.meaningCandidates);
    setCaptureMeaningCandidatesDirty(false);
    setCaptureExampleChoicesDraft(state.exampleChoices);
    setCaptureSelectedExampleIndexesDraft(state.selectedExampleIndexes);
    setCaptureExampleChoicesDirty(false);
    setCaptureCustomExampleDraft("");
    setCaptureCustomExampleMessage(null);
    setCaptureNotesDraft(state.notes);
    setCaptureSeedMode("seeded");
    setCaptureLastSavedTerm(null);
    setCaptureImportMessage(null);
    setCaptureStatusMessage(null);
  }

  function openQuickCapture() {
    const preferredPreset = quickCapturePresets[0] ?? null;
    const fallbackTerm = preferredPreset?.term ?? initialWorkspace.lookup?.headword ?? queryDraft;
    const fallbackContext = preferredPreset?.context ?? initialContext ?? contextDraft ?? "";
    const fallbackKind = preferredPreset?.kind ?? initialWorkspace.kind ?? kindDraft;
    const fallbackReviewLevel =
      preferredPreset?.reviewLevel ??
      (initialWorkspace.lookup
        ? reviewStateForTerm(initialWorkspace.lookup.headword, reviewStateMap).level
        : 0);
    const fallbackEntry =
      preferredPreset?.entry ??
      buildQuickCaptureEditableEntry({
        term: fallbackTerm,
        kind: fallbackKind,
        context: fallbackContext,
        snapshot: lookupSnapshotForTerm(fallbackTerm),
        existing: quickCaptureDrafts[normalizedTerm(fallbackTerm)]?.entry ?? null,
      });

    applyQuickCaptureFormState(
      quickCaptureFormStateFromEntry(fallbackEntry, {
        term: fallbackTerm,
        kind: fallbackKind,
        context: fallbackContext,
        reviewLevel: fallbackReviewLevel,
      }),
    );
    setIsQuickCaptureOpen(true);
  }

  function closeQuickCapture() {
    setIsQuickCaptureOpen(false);
    setCaptureLastSavedTerm(null);
    setCaptureImportMessage(null);
    setCaptureStatusMessage(null);
  }

  function startFreshQuickCaptureDraft() {
    applyQuickCaptureFormState({
      term: "",
      kind: "word",
      context: "",
      reviewLevel: 0,
      meaningCandidates: [],
      exampleChoices: [],
      selectedExampleIndexes: [],
      notes: "",
    });
    setCaptureSeedMode("typed");
    setCaptureStatusMessage(null);
    setIsQuickCaptureOpen(true);
  }

  function applyQuickCapturePreset(preset: QuickCapturePreset) {
    const entry =
      preset.entry ??
      buildQuickCaptureEditableEntry({
        term: preset.term,
        kind: preset.kind,
        context: preset.context,
        snapshot: lookupSnapshotForTerm(preset.term),
        existing: quickCaptureDrafts[normalizedTerm(preset.term)]?.entry ?? null,
      });

    applyQuickCaptureFormState(
      quickCaptureFormStateFromEntry(entry, {
        term: preset.term,
        kind: preset.kind,
        context: preset.context,
        reviewLevel: preset.reviewLevel,
      }),
    );
  }

  function openQuickCaptureWithPreset(preset: QuickCapturePreset) {
    applyQuickCapturePreset(preset);
    setIsQuickCaptureOpen(true);
  }

  function addQuickCaptureMeaningCandidate() {
    setCaptureMeaningCandidatesDirty(true);
    setCaptureMeaningCandidatesDraft((current) => [
      ...current,
      {
        id: `capture-sense-${Date.now()}-${current.length}`,
        partOfSpeech: "",
        meaning: "",
        selected: current.every((candidate) => !candidate.selected),
      },
    ].slice(0, editableMeaningChoiceCount));
  }

  function updateQuickCaptureMeaningCandidate(
    index: number,
    updates: Partial<MeaningCandidate>,
  ) {
    setCaptureMeaningCandidatesDirty(true);
    setCaptureMeaningCandidatesDraft((current) =>
      current.map((candidate, candidateIndex) =>
        candidateIndex === index
          ? {
              ...candidate,
              ...updates,
            }
          : candidate,
      ),
    );
  }

  function toggleQuickCaptureMeaningCandidate(index: number) {
    setCaptureMeaningCandidatesDirty(true);
    setCaptureMeaningCandidatesDraft((current) =>
      current.map((candidate, candidateIndex) =>
        candidateIndex === index
          ? {
              ...candidate,
              selected: !candidate.selected,
            }
          : candidate,
      ),
    );
  }

  function removeQuickCaptureMeaningCandidate(index: number) {
    setCaptureMeaningCandidatesDirty(true);
    setCaptureMeaningCandidatesDraft((current) =>
      current.filter((_, candidateIndex) => candidateIndex !== index),
    );
  }

  function updateQuickCaptureExampleChoices(
    choices: string[],
    selectedIndexes: number[],
  ) {
    setCaptureExampleChoicesDirty(true);
    setCaptureExampleChoicesDraft(choices);
    setCaptureSelectedExampleIndexesDraft(selectedIndexes);
  }

  function commitQuickCaptureCustomExample() {
    const cleaned = sanitizeParagraphText(captureCustomExampleDraft);
    if (!cleaned) {
      setCaptureCustomExampleMessage(null);
      return;
    }

    const existingIndex = captureExampleChoicesDraft.findIndex(
      (choice) => normalizedTerm(choice) === normalizedTerm(cleaned),
    );
    if (existingIndex >= 0) {
      updateQuickCaptureExampleChoices(
        captureExampleChoicesDraft,
        ensuredSelection(captureSelectedExampleIndexesDraft, existingIndex),
      );
      setCaptureCustomExampleDraft("");
      setCaptureCustomExampleMessage(null);
      return;
    }

    if (captureExampleChoicesDraft.length >= editableExampleChoiceCount) {
      setCaptureCustomExampleMessage("You can keep up to 3 example sentences.");
      return;
    }

    updateQuickCaptureExampleChoices(
      [...captureExampleChoicesDraft, cleaned],
      [...captureSelectedExampleIndexesDraft, captureExampleChoicesDraft.length],
    );
    setCaptureCustomExampleDraft("");
    setCaptureCustomExampleMessage(null);
  }

  async function pasteClipboardIntoCaptureImport() {
    if (typeof navigator === "undefined" || !navigator.clipboard?.readText) {
      setCaptureImportMessage("Clipboard paste is not available in this browser.");
      return;
    }

    try {
      const text = await navigator.clipboard.readText();
      if (!text.trim()) {
        setCaptureImportMessage("Clipboard is empty.");
        return;
      }

      setCaptureImportDraft(text);
      setCaptureImportMessage("Clipboard text loaded into bulk import.");
    } catch {
      setCaptureImportMessage("Clipboard read failed. Paste text into the bulk import box instead.");
    }
  }

  async function importCaptureFile(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) {
      return;
    }

    try {
      const text = await file.text();
      setCaptureImportDraft(text);
      setCaptureImportMessage(`Loaded ${file.name} into bulk import.`);
    } catch {
      setCaptureImportMessage("That file could not be read.");
    } finally {
      event.target.value = "";
    }
  }

  function captureSnapshotForTerm(term: string): LookupResult | null {
    return (
      lookupSnapshotForTerm(term) ??
      (initialWorkspace.lookup && normalizedTerm(initialWorkspace.lookup.headword) === normalizedTerm(term)
        ? initialWorkspace.lookup
        : null)
    );
  }

  function openQuickCaptureForSeed(options: {
    term: string;
    kind: LookupKind;
    context: string;
    reviewLevel?: ReviewLevel;
    detail?: string;
    partOfSpeech?: string;
    notes?: string;
  }) {
    const term = sanitizeInlineText(options.term);
    if (!term) {
      return;
    }

    const kind = options.kind ?? inferLookupKindFromTerm(term, "word");
    const context = sanitizeParagraphText(options.context);
    const snapshot = captureSnapshotForTerm(term);
    const entry = buildQuickCaptureEditableEntry({
      term,
      kind,
      context,
      meaning: sanitizeInlineText(options.detail),
      partOfSpeech: sanitizeInlineText(options.partOfSpeech),
      notes: sanitizeParagraphText(options.notes),
      snapshot,
      existing: quickCaptureDrafts[normalizedTerm(term)]?.entry ?? null,
    });

    applyQuickCaptureFormState(
      quickCaptureFormStateFromEntry(entry, {
        term,
        kind,
        context,
        reviewLevel: options.reviewLevel ?? reviewStateForTerm(term, reviewStateMap).level,
      }),
    );
    setIsQuickCaptureOpen(true);
  }

  function refillQuickCaptureSuggestions() {
    const trimmedTerm = captureTermDraft.trim();
    if (!trimmedTerm) {
      setCaptureStatusMessage("Type a term first so SparrowWord can fetch suggestions.");
      return;
    }

    const snapshot = captureSnapshotForTerm(trimmedTerm);
    if (!snapshot) {
      setCaptureStatusMessage(`No live lookup snapshot is ready for ${trimmedTerm} yet.`);
      return;
    }

    const seededEntry = buildQuickCaptureEditableEntry({
      term: trimmedTerm,
      kind: captureKindDraft,
      context: captureContextDraft,
      notes: captureNotesDraft,
      snapshot,
      existing: null,
    });

    setCaptureMeaningCandidatesDraft(
      seededEntry.meaningCandidates ??
        meaningCandidatesFromChoices(
          seededEntry.meaningChoices,
          seededEntry.meaningChoicePartOfSpeechLabels,
          seededEntry.selectedMeaningIndexes,
        ),
    );
    setCaptureMeaningCandidatesDirty(false);
    setCaptureExampleChoicesDraft(seededEntry.exampleChoices);
    setCaptureSelectedExampleIndexesDraft(seededEntry.selectedExampleIndexes);
    setCaptureExampleChoicesDirty(false);
    setCaptureCustomExampleDraft("");
    setCaptureCustomExampleMessage(null);
    setCaptureSeedMode("typed");
    setCaptureStatusMessage(`Filled fresh suggestions for ${trimmedTerm}.`);
  }

  function saveQuickCaptureSeedAsDraft(options: {
    term: string;
    kind: LookupKind;
    context: string;
    reviewLevel?: ReviewLevel;
    detail?: string;
    partOfSpeech?: string;
    notes?: string;
  }): boolean {
    const term = sanitizeInlineText(options.term);
    if (!term) {
      return false;
    }

    const draftRecord = createQuickCaptureDraftRecord({
      term,
      kind: options.kind,
      context: options.context,
      reviewLevel: options.reviewLevel ?? reviewStateForTerm(term, reviewStateMap).level,
      meaning: options.detail,
      partOfSpeech: options.partOfSpeech,
      notes: options.notes,
      snapshot: captureSnapshotForTerm(term),
      existing: quickCaptureDrafts[normalizedTerm(term)]?.entry ?? null,
    });

    if (!draftRecord) {
      return false;
    }

    const nextQuickCaptureDrafts = upsertQuickCaptureDraft(quickCaptureDrafts, draftRecord);
    setQuickCaptureDrafts(nextQuickCaptureDrafts);
    commitWorkspacePersistenceSnapshot({
      ...workspacePersistenceSnapshot,
      quickCaptureDrafts: nextQuickCaptureDrafts,
    });
    setCaptureStatusMessage(`Draft saved for ${term}.`);
    return true;
  }

  function currentQuickCaptureEditableEntry(): WorkspaceEditableEntry | null {
    const trimmedTerm = captureTermDraft.trim();
    if (!trimmedTerm) {
      return null;
    }

    return buildQuickCaptureEditableEntry({
      term: trimmedTerm,
      kind: captureKindDraft,
      context: captureContextDraft,
      meaningCandidates: captureMeaningCandidatesDraft,
      exampleChoices: captureExampleChoicesDraft,
      selectedExampleIndexes: captureSelectedExampleIndexesDraft,
      notes: captureNotesDraft,
      snapshot: captureSnapshotForTerm(trimmedTerm),
      existing: quickCaptureDrafts[normalizedTerm(trimmedTerm)]?.entry ?? null,
    });
  }

  function saveQuickCaptureToLibrary(event?: { preventDefault(): void }) {
    event?.preventDefault();

    const trimmedTerm = captureTermDraft.trim();
    const nextDraft = currentQuickCaptureEditableEntry();
    if (!trimmedTerm || !nextDraft) {
      return;
    }

    const matchingLibraryEntry =
      libraryEntries.find((entry) => normalizedTerm(entry.term) === normalizedTerm(trimmedTerm)) ?? null;
    const snapshot = captureSnapshotForTerm(trimmedTerm);
    const savedAt = Date.now();
    const nextLibraryEntries = upsertLibraryEntry(libraryEntries, {
      term: trimmedTerm,
      detail: nextDraft.detail,
      context: sanitizeParagraphText(captureContextDraft),
      savedAt,
      kind: captureKindDraft,
      snapshot,
      draft: nextDraft,
    });
    const nextQuickCaptureDrafts = removeQuickCaptureDraft(quickCaptureDrafts, trimmedTerm);
    const reviewKey = normalizedReviewKey(trimmedTerm);
    const previousReviewState = reviewStateMap[reviewKey] ?? defaultReviewState();
    const nextReviewStateMap: ReviewStateMap = {
      ...reviewStateMap,
      [reviewKey]: {
        ...previousReviewState,
        level: captureReviewLevelDraft,
      },
    };

    setLibraryEntries(nextLibraryEntries);
    setQuickCaptureDrafts(nextQuickCaptureDrafts);
    setReviewStateMap(nextReviewStateMap);
    commitWorkspacePersistenceSnapshot({
      ...workspacePersistenceSnapshot,
      libraryEntries: nextLibraryEntries,
      quickCaptureDrafts: nextQuickCaptureDrafts,
      reviewStateMap: nextReviewStateMap,
    });

    setCaptureLastSavedTerm(trimmedTerm);
    setCaptureStatusMessage(
      matchingLibraryEntry ? `Updated Library entry for ${trimmedTerm}.` : `Saved ${trimmedTerm} to Library.`,
    );
    setIsQuickCaptureOpen(false);
    router.push(
      buildWorkspaceHref({
        section: "library",
        q: trimmedTerm,
        source: "capture",
        kind: captureKindDraft,
        context: sanitizeParagraphText(captureContextDraft),
      }),
    );
  }

  function saveQuickCaptureAsDraft(event?: { preventDefault(): void }) {
    event?.preventDefault();

    const trimmedTerm = captureTermDraft.trim();
    const snapshot = captureSnapshotForTerm(trimmedTerm);
    const draftRecord = createQuickCaptureDraftRecord({
      term: trimmedTerm,
      kind: captureKindDraft,
      context: captureContextDraft,
      reviewLevel: captureReviewLevelDraft,
      meaningCandidates: captureMeaningCandidatesDraft,
      exampleChoices: captureExampleChoicesDraft,
      selectedExampleIndexes: captureSelectedExampleIndexesDraft,
      notes: captureNotesDraft,
      snapshot,
      existing: quickCaptureDrafts[normalizedTerm(trimmedTerm)]?.entry ?? null,
    });

    if (!trimmedTerm || !draftRecord) {
      return;
    }

    const nextQuickCaptureDrafts = upsertQuickCaptureDraft(quickCaptureDrafts, draftRecord);
    setQuickCaptureDrafts(nextQuickCaptureDrafts);
    commitWorkspacePersistenceSnapshot({
      ...workspacePersistenceSnapshot,
      quickCaptureDrafts: nextQuickCaptureDrafts,
    });
    applyQuickCaptureFormState(
      quickCaptureFormStateFromEntry(draftRecord.entry, {
        term: draftRecord.term,
        kind: draftRecord.kind,
        context: draftRecord.context,
        reviewLevel: draftRecord.reviewLevel,
      }),
    );
    setCaptureLastSavedTerm(trimmedTerm);
    setCaptureStatusMessage(`Draft saved for ${trimmedTerm}.`);
  }

  function importQuickCaptureDrafts() {
    const parsedItems = parseQuickCaptureImportInput(captureImportDraft);
    if (parsedItems.length === 0) {
      setCaptureImportMessage("Nothing importable was found. Use one item per line, or `term :: context`.");
      return;
    }

    let nextQuickCaptureDrafts = quickCaptureDrafts;
    let savedCount = 0;
    parsedItems.forEach((item) => {
      const draftRecord = createQuickCaptureDraftRecord({
        term: item.term,
        context: item.context,
        kind: item.kind,
        reviewLevel: 0,
        snapshot: captureSnapshotForTerm(item.term),
        existing: nextQuickCaptureDrafts[normalizedTerm(item.term)]?.entry ?? null,
      });
      if (!draftRecord) {
        return;
      }

      nextQuickCaptureDrafts = upsertQuickCaptureDraft(nextQuickCaptureDrafts, draftRecord);
      savedCount += 1;
    });

    if (savedCount === 0) {
      setCaptureImportMessage("Nothing importable was saved.");
      return;
    }

    setQuickCaptureDrafts(nextQuickCaptureDrafts);
    commitWorkspacePersistenceSnapshot({
      ...workspacePersistenceSnapshot,
      quickCaptureDrafts: nextQuickCaptureDrafts,
    });

    setCaptureImportDraft("");
    setCaptureImportMessage(`Imported ${savedCount} item${savedCount === 1 ? "" : "s"} into Drafts.`);
    setCaptureLastSavedTerm(parsedItems[parsedItems.length - 1]?.term ?? null);
  }

  function openSettings(panel: SettingsPanel = "general") {
    setDiagnosticsMessage(null);
    setSettingsSearchDraft("");
    setActiveSettingsPanel(panel);
    setIsSettingsOpen(true);
  }

  function closeSettings() {
    setDiagnosticsMessage(null);
    setIsSettingsOpen(false);
  }

  async function copyDiagnosticsPayload(payload: unknown, successMessage: string) {
    if (typeof navigator === "undefined" || !navigator.clipboard) {
      setDiagnosticsMessage("Clipboard access is not available here.");
      return;
    }

    try {
      await navigator.clipboard.writeText(JSON.stringify(payload, null, 2));
      setDiagnosticsMessage(successMessage);
    } catch {
      setDiagnosticsMessage("The diagnostics snapshot could not be copied.");
    }
  }

  function resetWorkspaceTransientState() {
    setPendingActivityAction(null);
    setSelectedTrashIds(new Set());
    setSelectedInboxIds(new Set());
    setSelectedHistoryIds(new Set());
    setSelectedLibraryIds(new Set());
    setSelectedReviewIds(new Set());
    setSelectedReviewRoundId(null);
    setIsInboxSelecting(false);
    setIsHistorySelecting(false);
    setIsLibrarySelecting(false);
    setReviewExitIntent(false);
    setReviewDraftAnswer("");
    setReviewSelectedChoice("");
    setReviewAnswerSubmitted(false);
    setCustomMeaningDraft("");
    setCustomMeaningMessage(null);
    setCustomExampleDraft("");
    setCustomExampleMessage(null);
    setCustomTagDraft("");
    setCustomTagMessage(null);
    setCaptureStatusMessage(null);
  }

  function applyWorkspacePersistenceState(snapshot: WorkspacePersistenceSnapshot) {
    const normalizedSnapshot: WorkspacePersistenceSnapshot = {
      ...snapshot,
      savedLibraryArrangements: normalizeLibraryArrangements(
        snapshot.savedLibraryArrangements,
        snapshot.libraryEntries,
      ),
      reviewHistory: snapshot.reviewHistory.slice(0, 160),
    };

    setInboxEntryDrafts(normalizedSnapshot.inboxEntryDrafts);
    setQuickCaptureDrafts(normalizedSnapshot.quickCaptureDrafts);
    setLibraryEntries(normalizedSnapshot.libraryEntries);
    setSavedLibraryArrangements(normalizedSnapshot.savedLibraryArrangements);
    setReviewStateMap(normalizedSnapshot.reviewStateMap);
    setReviewHistory(normalizedSnapshot.reviewHistory);
    setReviewSession(normalizedSnapshot.reviewSession);
    setWorkspacePreferences(normalizedSnapshot.workspacePreferences);
    setTrashItems(normalizedSnapshot.trashItems);
    setWorkspacePersistenceReady(true);
    setWorkspacePersistenceSyncState(activityClientId ? "syncing" : "idle");
  }

  async function replaceActivityFeed(kind: ActivityKind, items: ActivityItem[]): Promise<ActivityItem[]> {
    if (!activityClientId) {
      return items;
    }

    const clearResponse = await fetch(buildActivityRequestUrl(kind), {
      method: "DELETE",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        client_id: activityClientId,
      }),
    });

    if (!clearResponse.ok) {
      throw new Error(`${kind}_clear_failed`);
    }

    let latestItems: ActivityItem[] = [];
    for (const item of items) {
      const response = await fetch(buildActivityRequestUrl(kind), {
        method: "POST",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          client_id: activityClientId,
          term: item.term,
          detail: item.detail,
          context: item.context ?? "",
          meta: item.meta ?? null,
          saved_at: item.savedAt,
        }),
      });

      if (!response.ok) {
        throw new Error(`${kind}_restore_failed`);
      }

      const envelope = (await response.json()) as ActivityEnvelope;
      latestItems = mapActivityItems(envelope.data?.items ?? latestItems);
    }

    return latestItems;
  }

  async function applyWorkspaceBackup(
    backup: {
      snapshot: WorkspacePersistenceSnapshot;
      inboxItems: ActivityItem[];
      historyItems: ActivityItem[];
    },
    successMessage: string,
  ) {
    const migratedBackup = migrateWorkspaceInboxState({
      inboxItems: backup.inboxItems,
      snapshot: backup.snapshot,
    });
    resetWorkspaceTransientState();
    applyWorkspacePersistenceState(migratedBackup.snapshot);
    setInboxItems(migratedBackup.inboxItems);
    setHistoryItems(backup.historyItems);

    if (!activityClientId) {
      setDiagnosticsMessage(`${successMessage} Activity sync is unavailable in this browser session.`);
      return;
    }

    setPendingActivityAction("workspace-backup-restore");
    try {
      const nextHistoryItems = await replaceActivityFeed("history", backup.historyItems);
      const nextInboxItems = await replaceActivityFeed("inbox", migratedBackup.inboxItems);
      setHistoryItems(nextHistoryItems);
      setInboxItems(nextInboxItems);
      setDiagnosticsMessage(successMessage);
    } catch {
      setDiagnosticsMessage(
        `${successMessage} Replacing legacy activity data on the dict service failed, so a full reload may pull older server data back in.`,
      );
    } finally {
      setPendingActivityAction((current) => (current === "workspace-backup-restore" ? null : current));
    }
  }

  async function downloadWorkspaceBackup() {
    if (typeof window === "undefined") {
      setDiagnosticsMessage("Backup download is only available in the browser.");
      return;
    }

    try {
      const payload: WorkspaceBackupPayload = {
        version: 2,
        exportedAt: new Date().toISOString(),
        clientId: activityClientId || null,
        inboxItems,
        historyItems,
        snapshot: workspacePersistenceSnapshot,
      };
      const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
      const url = window.URL.createObjectURL(blob);
      const link = window.document.createElement("a");
      const timestamp = payload.exportedAt.replace(/[:.]/g, "-");
      link.href = url;
      link.download = `sparrowword-workspace-${timestamp}.json`;
      window.document.body.appendChild(link);
      link.click();
      link.remove();
      window.setTimeout(() => window.URL.revokeObjectURL(url), 0);
      setDiagnosticsMessage("Downloaded workspace backup.");
    } catch {
      setDiagnosticsMessage("Workspace backup download failed.");
    }
  }

  async function importWorkspaceBackupFile(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    if (!file) {
      return;
    }

    try {
      const text = await file.text();
      const parsed = parseWorkspaceBackupPayload(JSON.parse(text));
      if (!parsed) {
        setDiagnosticsMessage("That file is not a valid SparrowWord workspace backup.");
        return;
      }

      if (
        typeof window !== "undefined" &&
        !window.confirm(
          "Importing this backup will replace current History, Library, Review, Drafts, Collections, and Trash data in this browser. Continue?",
        )
      ) {
        return;
      }

      await applyWorkspaceBackup(parsed, `Imported workspace backup from ${file.name}.`);
    } catch {
      setDiagnosticsMessage("That backup file could not be read.");
    } finally {
      event.target.value = "";
    }
  }

  async function resetWorkspaceBackup() {
    if (
      typeof window !== "undefined" &&
      !window.confirm(
        "Reset the current workspace? This clears History, Library, Review progress, saved arrangements, drafts, and Trash for this browser.",
      )
    ) {
      return;
    }

    await applyWorkspaceBackup(
      {
        snapshot: emptyWorkspacePersistenceSnapshot(),
        inboxItems: [],
        historyItems: [],
      },
      "Reset workspace state to a clean baseline.",
    );
  }

  function commitWorkspacePersistenceSnapshot(snapshot: WorkspacePersistenceSnapshot) {
    writeWorkspacePersistenceSnapshotToLocalStorage(snapshot);

    if (!activityClientId) {
      return;
    }

    const fingerprint = JSON.stringify(snapshot);
    setWorkspacePersistenceSyncState("syncing");
    void fetch(new URL("/workspace-state", dictApiBaseUrl()).toString(), {
      method: "PUT",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        client_id: activityClientId,
        snapshot,
      }),
    }).then((response) => {
      if (response.ok) {
        workspacePersistenceFingerprintRef.current = fingerprint;
        setWorkspacePersistenceSyncState("synced");
        setWorkspacePersistenceLastSyncedAt(Date.now());
      } else {
        setWorkspacePersistenceSyncState("error");
      }
    }).catch(() => {
      setWorkspacePersistenceSyncState("error");
    });
  }

  async function syncActivity(kind: ActivityKind, entry: ActivityItem) {
    try {
      if (!activityClientId) {
        return;
      }

      const response = await fetch(buildActivityRequestUrl(kind), {
        method: "POST",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          client_id: activityClientId,
          term: entry.term,
          detail: entry.detail,
          context: entry.context ?? "",
          meta: entry.meta ?? null,
          saved_at: entry.savedAt,
        }),
      });

      if (!response.ok) {
        return;
      }

      const envelope = (await response.json()) as ActivityEnvelope;
      const items = mapActivityItems(envelope.data?.items ?? []);
      if (items.length === 0) {
        return;
      }

      if (kind === "history") {
        setHistoryItems(items);
        return;
      }

      setInboxItems(items);
    } catch {
      // Keep optimistic local state if sync misses once.
    }
  }

  async function mutateActivity(
    kind: ActivityKind,
    actionKey: string,
    body: Record<string, unknown>,
    optimisticItems: ActivityItem[],
    rollbackItems: ActivityItem[],
  ) {
    setPendingActivityAction(actionKey);

    if (kind === "history") {
      setHistoryItems(optimisticItems);
    } else {
      setInboxItems(optimisticItems);
    }

    try {
      if (!activityClientId) {
        return;
      }

      const response = await fetch(buildActivityRequestUrl(kind), {
        method: "DELETE",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          client_id: activityClientId,
          ...body,
        }),
      });

      if (!response.ok) {
        throw new Error("activity_delete_failed");
      }

      const envelope = (await response.json()) as ActivityEnvelope;
      const items = mapActivityItems(envelope.data?.items ?? []);
      if (kind === "history") {
        setHistoryItems(items);
      } else {
        setInboxItems(items);
      }
    } catch {
      if (kind === "history") {
        setHistoryItems(rollbackItems);
      } else {
        setInboxItems(rollbackItems);
      }
    } finally {
      setPendingActivityAction((current) => (current === actionKey ? null : current));
    }
  }

  async function mutateActivityBatch(
    kind: ActivityKind,
    actionKey: string,
    itemsToDelete: ActivityItem[],
    optimisticItems: ActivityItem[],
    rollbackItems: ActivityItem[],
  ) {
    setPendingActivityAction(actionKey);

    if (kind === "history") {
      setHistoryItems(optimisticItems);
    } else {
      setInboxItems(optimisticItems);
    }

    try {
      if (!activityClientId) {
        return;
      }

      if (itemsToDelete.length === rollbackItems.length) {
        await mutateActivity(kind, actionKey, {}, optimisticItems, rollbackItems);
        return;
      }

      let latestItems = optimisticItems;
      for (const item of itemsToDelete) {
        const response = await fetch(buildActivityRequestUrl(kind), {
          method: "DELETE",
          headers: {
            Accept: "application/json",
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            client_id: activityClientId,
            item_id: item.id,
          }),
        });

        if (!response.ok) {
          throw new Error("activity_batch_delete_failed");
        }

        const envelope = (await response.json()) as ActivityEnvelope;
        latestItems = mapActivityItems(envelope.data?.items ?? latestItems);
      }

      if (kind === "history") {
        setHistoryItems(latestItems);
      } else {
        setInboxItems(latestItems);
      }
    } catch {
      if (kind === "history") {
        setHistoryItems(rollbackItems);
      } else {
        setInboxItems(rollbackItems);
      }
    } finally {
      setPendingActivityAction((current) => (current === actionKey ? null : current));
    }
  }

  function archiveActivityItems(kind: ActivityKind, items: ActivityItem[]) {
    if (items.length === 0) {
      return;
    }

    setTrashItems((current) =>
      appendTrashItems(
        current,
        items.map((item) =>
          trashItemFromActivity(
            kind,
            item,
            kind === "inbox" ? inboxEntryDrafts[normalizedTerm(item.term)] ?? null : null,
          ),
        ),
      ),
    );
  }

  function archiveLibraryItems(items: LibraryEntry[]) {
    if (items.length === 0) {
      return;
    }

    setTrashItems((current) =>
      appendTrashItems(
        current,
        items.map((item) => trashItemFromLibrary(item)),
      ),
    );
  }

  function removeHistoryItem(itemId: string) {
    const rollbackItems = historyItems;
    const removedItem = historyItems.find((item) => item.id === itemId);
    const nextItems = historyItems.filter((item) => item.id !== itemId);
    if (removedItem) {
      archiveActivityItems("history", [removedItem]);
    }
    void mutateActivity("history", `history:${itemId}`, { item_id: itemId }, nextItems, rollbackItems);
  }

  function removeInboxItem(itemId: string) {
    const rollbackItems = inboxItems;
    const removedItem = inboxItems.find((item) => item.id === itemId);
    const nextItems = inboxItems.filter((item) => item.id !== itemId);
    if (removedItem) {
      archiveActivityItems("inbox", [removedItem]);
    }
    void mutateActivity("inbox", `inbox:${itemId}`, { item_id: itemId }, nextItems, rollbackItems);
  }

  function clearHistory() {
    archiveActivityItems("history", historyItems);
    void mutateActivity("history", "history:clear", {}, [], historyItems);
  }

  function clearInbox() {
    archiveActivityItems("inbox", inboxItems);
    void mutateActivity("inbox", "inbox:clear", {}, [], inboxItems);
  }

  function currentSentenceCaptureEntry(savedAt = Date.now()): {
    entry: ActivityItem;
    draft: WorkspaceEditableEntry;
  } | null {
    const term = initialWorkspace.query.trim();
    if (initialWorkspace.kind !== "sentence" || !term) {
      return null;
    }

    const detail = inboxDetailFromWorkspace(initialWorkspace, initialContext || term);
    const draft = createEditableEntry({
      term,
      kind: "sentence",
      detail,
      context: initialContext || term,
    });

    return {
      entry: {
        id: `${term}-${savedAt}`,
        term,
        detail: draft.detail,
        context: initialContext || term,
        savedAt,
      },
      draft,
    };
  }

  function saveCurrentSentenceAsDraft() {
    const capture = currentSentenceCaptureEntry();
    if (!capture) {
      return;
    }

    saveQuickCaptureSeedAsDraft({
      term: capture.entry.term,
      kind: "sentence",
      context: capture.entry.context ?? "",
      detail: capture.draft.detail,
      notes: capture.draft.notes,
      reviewLevel: reviewStateForTerm(capture.entry.term, reviewStateMap).level,
    });
  }

  function openCurrentLookupInQuickCapture() {
    openQuickCapture();
  }

  function moveHistoryItemToLibrary(item: ActivityItem) {
    const matchingInboxItem = inboxItems.find(
      (candidate) => normalizedTerm(candidate.term) === normalizedTerm(item.term),
    );
    if (matchingInboxItem) {
      removeInboxItem(matchingInboxItem.id);
    }

    moveActivityIntoLibrary(
      {
        term: item.term,
        detail: item.detail,
        context: item.context,
        savedAt: item.savedAt,
      },
      {
        kind: inferLookupKindFromTerm(item.term, "word"),
        snapshot: lookupSnapshotForTerm(item.term),
        draft: quickCaptureDrafts[normalizedTerm(item.term)]?.entry ?? null,
      },
    );
  }

  function openHistoryItemInQuickCapture(item: ActivityItem) {
    const snapshot = lookupSnapshotForTerm(item.term);
    const draftEntry =
      quickCaptureDrafts[normalizedTerm(item.term)]?.entry ??
      editableEntryFromActivity(item, snapshot, null);

    applyQuickCaptureFormState(
      quickCaptureFormStateFromEntry(draftEntry, {
        term: item.term,
        kind: inferLookupKindFromTerm(item.term, "word"),
        context: item.context ?? "",
        reviewLevel: reviewStateForTerm(item.term, reviewStateMap).level,
      }),
    );
    setIsQuickCaptureOpen(true);
  }

  function openSentenceCandidateInQuickCapture(candidate: SentenceStudyCandidate) {
    openQuickCaptureForSeed({
      term: candidate.term,
      kind: candidate.kind,
      context: initialWorkspace.query,
      detail: lookupSnapshotForTerm(candidate.term)?.summary ?? candidate.summary,
      reviewLevel: 0,
      notes: candidate.reason,
    });
  }

  function saveSentenceCandidateAsDraft(candidate: SentenceStudyCandidate) {
    if (saveQuickCaptureSeedAsDraft({
      term: candidate.term,
      kind: candidate.kind,
      context: initialWorkspace.query,
      detail: lookupSnapshotForTerm(candidate.term)?.summary ?? candidate.summary,
      reviewLevel: 0,
      notes: candidate.reason,
    })) {
      setCaptureLastSavedTerm(candidate.term);
    }
  }

  function saveSentenceCandidateBatchToDrafts(candidates: SentenceStudyCandidate[]) {
    const queue = candidates.slice(0, 3);
    if (queue.length === 0) {
      return;
    }

    let nextQuickCaptureDrafts = quickCaptureDrafts;
    let savedCount = 0;
    for (const candidate of queue) {
      const draftRecord = createQuickCaptureDraftRecord({
        term: candidate.term,
        kind: candidate.kind,
        context: initialWorkspace.query,
        meaning: lookupSnapshotForTerm(candidate.term)?.summary ?? candidate.summary,
        reviewLevel: 0,
        notes: candidate.reason,
        snapshot: captureSnapshotForTerm(candidate.term),
        existing: nextQuickCaptureDrafts[normalizedTerm(candidate.term)]?.entry ?? null,
      });
      if (!draftRecord) {
        continue;
      }
      nextQuickCaptureDrafts = upsertQuickCaptureDraft(nextQuickCaptureDrafts, draftRecord);
      savedCount += 1;
    }

    if (savedCount === 0) {
      return;
    }

    setQuickCaptureDrafts(nextQuickCaptureDrafts);
    commitWorkspacePersistenceSnapshot({
      ...workspacePersistenceSnapshot,
      quickCaptureDrafts: nextQuickCaptureDrafts,
    });
    setCaptureLastSavedTerm(queue[queue.length - 1]?.term ?? null);
    setCaptureStatusMessage(`Saved ${savedCount} sentence candidate${savedCount === 1 ? "" : "s"} to Drafts.`);
  }

  function openReverseCandidateInQuickCapture(match: {
    term: string;
    gloss: string;
    partOfSpeech: string;
    note: string;
  }) {
    openQuickCaptureForSeed({
      term: match.term,
      kind: inferLookupKindFromTerm(match.term, "word"),
      context: initialWorkspace.query,
      detail: lookupSnapshotForTerm(match.term)?.summary ?? match.gloss,
      partOfSpeech: match.partOfSpeech,
      reviewLevel: 0,
      notes: match.note,
    });
  }

  function saveReverseCandidateAsDraft(match: {
    term: string;
    gloss: string;
    partOfSpeech: string;
    note: string;
  }) {
    if (saveQuickCaptureSeedAsDraft({
      term: match.term,
      kind: inferLookupKindFromTerm(match.term, "word"),
      context: initialWorkspace.query,
      detail: lookupSnapshotForTerm(match.term)?.summary ?? match.gloss,
      partOfSpeech: match.partOfSpeech,
      reviewLevel: 0,
      notes: match.note,
    })) {
      setCaptureLastSavedTerm(match.term);
      setCaptureStatusMessage(`Draft saved for ${match.term}.`);
    }
  }

  function saveReverseCandidateToLibrary(match: {
    term: string;
    gloss: string;
    partOfSpeech: string;
    note: string;
  }) {
    moveActivityIntoLibrary(
      {
        term: match.term,
        detail: lookupSnapshotForTerm(match.term)?.summary ?? match.gloss,
        context: initialWorkspace.query,
        savedAt: Date.now(),
      },
      {
        kind: inferLookupKindFromTerm(match.term, "word"),
        snapshot: lookupSnapshotForTerm(match.term),
        draft: quickCaptureDrafts[normalizedTerm(match.term)]?.entry ?? null,
      },
    );
  }

  function saveSentenceCandidateToLibrary(candidate: SentenceStudyCandidate) {
    moveActivityIntoLibrary(
      {
        term: candidate.term,
        detail: lookupSnapshotForTerm(candidate.term)?.summary ?? candidate.summary,
        context: initialWorkspace.query,
        savedAt: Date.now(),
      },
      {
        kind: candidate.kind,
        snapshot: lookupSnapshotForTerm(candidate.term),
        draft: quickCaptureDrafts[normalizedTerm(candidate.term)]?.entry ?? null,
      },
    );
  }

  function saveCurrentSentenceToLibrary() {
    const capture = currentSentenceCaptureEntry();
    if (!capture) {
      return;
    }

    const matchingInboxItem = inboxItems.find(
      (item) => normalizedTerm(item.term) === normalizedTerm(capture.entry.term),
    );
    if (matchingInboxItem) {
      removeInboxItem(matchingInboxItem.id);
    }

    moveActivityIntoLibrary(capture.entry, {
      kind: "sentence",
      draft: quickCaptureDrafts[normalizedTerm(capture.entry.term)]?.entry ?? capture.draft,
    });
  }

  function saveActivityIntoLibrary(
    item: Pick<ActivityItem, "term" | "detail" | "context" | "savedAt">,
    options?: {
      kind?: LookupKind;
      snapshot?: LookupResult | null;
      draft?: WorkspaceEditableEntry | null;
    },
  ) {
    const nextLibraryEntries = upsertLibraryEntry(libraryEntries, {
      ...item,
      kind: options?.kind,
      snapshot: options?.snapshot,
      draft: options?.draft,
    });

    setLibraryEntries(nextLibraryEntries);
    commitWorkspacePersistenceSnapshot({
      ...workspacePersistenceSnapshot,
      libraryEntries: nextLibraryEntries,
    });
  }

  function moveActivityIntoLibrary(
    item: Pick<ActivityItem, "term" | "detail" | "context" | "savedAt">,
    options?: {
      kind?: LookupKind;
      snapshot?: LookupResult | null;
      draft?: WorkspaceEditableEntry | null;
    },
  ) {
    saveActivityIntoLibrary(item, options);
    router.push(
      buildWorkspaceHref({
        section: "library",
        q: item.term,
        source: "library",
        kind: inferLookupKindFromTerm(item.term, "word"),
        context: item.context,
      }),
    );
  }

  function openInboxItem(item: ActivityItem) {
    router.push(
      buildWorkspaceHref({
        section: "inbox",
        q: item.term,
        source: "inbox",
        kind: inferLookupKindFromTerm(item.term, "word"),
        context: item.context,
        itemId: item.id,
      }),
    );
  }

  function moveInboxItemToLibrary(
    item: ActivityItem,
    options?: {
      keepFlow?: boolean;
    },
  ) {
    const termKey = normalizedTerm(item.term);
    const nextVisibleItem =
      options?.keepFlow
        ? adjacentActivityItem(filteredInboxItems, item.id, 1) ??
          adjacentActivityItem(filteredInboxItems, item.id, -1)
        : null;

    saveActivityIntoLibrary(item, {
      kind: inboxEntryDrafts[termKey]?.kind ?? inferLookupKindFromTerm(item.term, "word"),
      snapshot: lookupSnapshotForTerm(item.term),
      draft: inboxEntryDrafts[termKey] ?? null,
    });
    removeInboxItem(item.id);

    if (options?.keepFlow && nextVisibleItem) {
      openInboxItem(nextVisibleItem);
      return;
    }

    router.push(
      buildWorkspaceHref({
        section: "library",
        q: item.term,
        source: "library",
        kind: inferLookupKindFromTerm(item.term, "word"),
        context: item.context,
      }),
    );
  }

  function moveCurrentLookupToLibrary() {
    if (!initialWorkspace.lookup) {
      return;
    }

    const nextDraft = createEditableEntry({
      term: initialWorkspace.lookup.headword,
      kind: initialWorkspace.kind,
      detail: initialWorkspace.lookup.summary || inboxDetailFromWorkspace(initialWorkspace, initialContext),
      context: initialContext,
      snapshot: initialWorkspace.lookup,
    });
    const matchingInboxItem = inboxItems.find(
      (item) => normalizedTerm(item.term) === normalizedTerm(initialWorkspace.lookup?.headword ?? ""),
    );
    if (matchingInboxItem) {
      removeInboxItem(matchingInboxItem.id);
    }

    moveActivityIntoLibrary({
      term: initialWorkspace.lookup.headword,
      detail: nextDraft.detail,
      context: initialContext,
      savedAt: Date.now(),
    }, {
      kind: initialWorkspace.kind,
      snapshot: initialWorkspace.lookup,
      draft: nextDraft,
    });
  }

  function openLibraryEntryInQuickCapture(entry: LibraryEntry) {
    applyQuickCaptureFormState(
      quickCaptureFormStateFromEntry(entry, {
        term: entry.term,
        kind: entry.kind,
        context: entry.context ?? "",
        reviewLevel: reviewStateForTerm(entry.term, reviewStateMap).level,
      }),
    );
    setIsQuickCaptureOpen(true);
  }

  function updateLibraryField(
    entryId: string,
    updates: Partial<
      Pick<
        LibraryEntry,
        | "detail"
        | "context"
        | "notes"
        | "favorite"
        | "term"
        | "kind"
        | "partOfSpeech"
        | "meaningCandidates"
        | "meaningChoices"
        | "meaningChoicePartOfSpeechLabels"
        | "selectedMeaningIndexes"
        | "exampleChoices"
        | "selectedExampleIndexes"
        | "englishDefinitions"
        | "inflectionLines"
        | "referenceTags"
      >
    >,
  ) {
    setLibraryEntries((current) => updateLibraryEntry(current, entryId, updates));
  }

  function replaceLibraryMeaningCandidates(entry: LibraryEntry, candidates: MeaningCandidate[]) {
    updateLibraryField(entry.id, {
      meaningCandidates: candidates.map((candidate, index) => ({
        id: sanitizeInlineText(candidate.id, `library-sense-${entry.id}-${index}`),
        partOfSpeech: sanitizeInlineText(candidate.partOfSpeech),
        meaning: sanitizeInlineText(candidate.meaning),
        selected: candidate.selected !== false,
      })),
    });
  }

  function addLibraryMeaningCandidate(entry: LibraryEntry) {
    const currentCandidates = editableMeaningCandidatesForEntry(entry);
    if (currentCandidates.length >= editableMeaningChoiceCount) {
      setCustomMeaningMessage("You can keep up to 5 meanings.");
      return;
    }

    replaceLibraryMeaningCandidates(entry, [
      ...currentCandidates,
      {
        id: `library-sense-${entry.id}-${Date.now()}`,
        partOfSpeech: "",
        meaning: "",
        selected: true,
      },
    ]);
    setCustomMeaningMessage(null);
  }

  function updateLibraryMeaningCandidate(
    entry: LibraryEntry,
    index: number,
    updates: Partial<MeaningCandidate>,
  ) {
    const currentCandidates = editableMeaningCandidatesForEntry(entry);
    replaceLibraryMeaningCandidates(
      entry,
      currentCandidates.map((candidate, candidateIndex) =>
        candidateIndex === index
          ? {
              ...candidate,
              ...updates,
              selected: true,
            }
          : candidate,
      ),
    );
  }

  function moveLibraryMeaningCandidate(entry: LibraryEntry, index: number, direction: -1 | 1) {
    const currentCandidates = editableMeaningCandidatesForEntry(entry);
    const nextIndex = index + direction;
    if (nextIndex < 0 || nextIndex >= currentCandidates.length) {
      return;
    }

    const nextCandidates = currentCandidates.slice();
    const candidate = nextCandidates[index];
    if (!candidate) {
      return;
    }
    nextCandidates.splice(index, 1);
    nextCandidates.splice(nextIndex, 0, candidate);
    replaceLibraryMeaningCandidates(entry, nextCandidates);
  }

  function removeLibraryMeaningCandidate(entry: LibraryEntry, index: number) {
    replaceLibraryMeaningCandidates(
      entry,
      editableMeaningCandidatesForEntry(entry).filter((_, candidateIndex) => candidateIndex !== index),
    );
  }

  function applyLibraryChoiceSectionState(
    entryId: string,
    field: ChoiceField,
    state: EditableChoiceSectionState,
  ) {
    updateLibraryField(entryId, editableChoiceSectionUpdates(field, state));
  }

  function mergeLibraryDuplicates(entryId: string) {
    setLibraryEntries((current) => mergeDuplicateLibraryEntries(current, entryId));
  }

  function deleteLibraryEntry(entryId: string) {
    const entry = libraryEntries.find((item) => item.id === entryId);
    if (entry) {
      archiveLibraryItems([entry]);
    }

    setLibraryEntries((current) => removeLibraryEntry(current, entryId));
  }

  function updateWorkspacePreference<K extends keyof WorkspacePreferences>(
    key: K,
    value: WorkspacePreferences[K],
  ) {
    setWorkspacePreferences((current) => {
      const nextPreferences = {
        ...current,
        [key]: value,
      };
      commitWorkspacePersistenceSnapshot({
        ...workspacePersistenceSnapshot,
        workspacePreferences: nextPreferences,
      });
      return nextPreferences;
    });
  }

  function setLibraryCleanMode(enabled: boolean) {
    updateWorkspacePreference("isLibraryCleanMode", enabled);
    if (enabled) {
      setIsLibrarySelecting(false);
      setSelectedLibraryIds(new Set());
    }
  }

  function toggleActivitySelection(kind: ActivityKind, itemId: string) {
    const setter = kind === "inbox" ? setSelectedInboxIds : setSelectedHistoryIds;
    setter((current) => {
      const next = new Set(current);
      if (next.has(itemId)) {
        next.delete(itemId);
      } else {
        next.add(itemId);
      }
      return next;
    });
  }

  function toggleSelectAllActivity(kind: ActivityKind) {
    const items = kind === "inbox" ? filteredInboxItems : filteredHistoryItems;
    const selectedIds = kind === "inbox" ? selectedInboxIds : selectedHistoryIds;
    const setter = kind === "inbox" ? setSelectedInboxIds : setSelectedHistoryIds;

    setter(() => {
      if (selectedIds.size === items.length) {
        return new Set();
      }

      return new Set(items.map((item) => item.id));
    });
  }

  function archiveAndRemoveActivityBatch(kind: ActivityKind, itemIds: Set<string>) {
    const items = (kind === "inbox" ? inboxItems : historyItems).filter((item) => itemIds.has(item.id));
    if (items.length === 0) {
      return;
    }

    const rollbackItems = kind === "inbox" ? inboxItems : historyItems;
    const optimisticItems = rollbackItems.filter((item) => !itemIds.has(item.id));

    archiveActivityItems(kind, items);
    if (kind === "inbox") {
      setSelectedInboxIds(new Set());
      setIsInboxSelecting(false);
    } else {
      setSelectedHistoryIds(new Set());
      setIsHistorySelecting(false);
    }

    void mutateActivityBatch(kind, `${kind}:batch`, items, optimisticItems, rollbackItems);
  }

  function moveInboxSelectionToLibrary() {
    const items = inboxItems.filter((item) => selectedInboxIds.has(item.id));
    if (items.length === 0) {
      return;
    }

    setLibraryEntries((current) =>
      items.reduce(
        (next, item) =>
          upsertLibraryEntry(next, {
            ...item,
            kind: inboxEntryDrafts[normalizedTerm(item.term)]?.kind ?? inferLookupKindFromTerm(item.term, "word"),
            snapshot: lookupSnapshotForTerm(item.term),
            draft: inboxEntryDrafts[normalizedTerm(item.term)] ?? null,
          }),
        current,
      ),
    );
    archiveAndRemoveActivityBatch("inbox", selectedInboxIds);
    const first = items[0];
    if (first) {
      router.push(
        buildWorkspaceHref({
          section: "library",
          q: first.term,
          source: "library",
          kind: inferLookupKindFromTerm(first.term, "word"),
          context: first.context,
        }),
      );
    }
  }

  function focusAdjacentInboxItem(direction: -1 | 1) {
    if (!selectedInboxItem) {
      return;
    }

    const nextItem = adjacentActivityItem(filteredInboxItems, selectedInboxItem.id, direction);
    if (!nextItem) {
      return;
    }

    openInboxItem(nextItem);
  }

  function focusFirstReadyInboxItem() {
    const nextItem = filteredInboxItems.find((item) => inboxDigestById[item.id]?.isReady) ?? filteredInboxItems[0] ?? null;
    if (!nextItem) {
      return;
    }

    openInboxItem(nextItem);
  }

  function confirmSelectedInboxItemAndAdvance() {
    if (!selectedInboxItem) {
      return;
    }

    moveInboxItemToLibrary(selectedInboxItem, { keepFlow: true });
  }

  function saveHistorySelectionToInbox() {
    const items = historyItems.filter((item) => selectedHistoryIds.has(item.id));
    if (items.length === 0) {
      return;
    }

    const drafts = items.map((item) =>
      createEditableEntry({
        term: item.term,
        kind: inferLookupKindFromTerm(item.term, "word"),
        detail: item.detail,
        context: item.context,
        snapshot: lookupSnapshotForTerm(item.term),
        existing: inboxEntryDrafts[normalizedTerm(item.term)] ?? null,
      }),
    );
    const entries = items.map((item, index) => ({
      ...item,
      id: `${item.term}-${Date.now()}-${index}`,
      detail: drafts[index]?.detail ?? item.detail,
      savedAt: Date.now() + index,
    }));

    setInboxEntryDrafts((current) => {
      const next = { ...current };
      for (const [index, item] of items.entries()) {
        const draft = drafts[index];
        if (draft) {
          next[normalizedTerm(item.term)] = draft;
        }
      }
      return next;
    });

    startTransition(() => {
      setInboxItems((current) => entries.reduce((next, entry) => upsertActivity(next, entry), current));
    });

    for (const entry of entries) {
      void syncActivity("inbox", entry);
    }

    setSelectedHistoryIds(new Set());
    setIsHistorySelecting(false);
  }

  function toggleLibrarySelection(entryId: string) {
    setSelectedLibraryIds((current) => {
      const next = new Set(current);
      if (next.has(entryId)) {
        next.delete(entryId);
      } else {
        next.add(entryId);
      }
      return next;
    });
  }

  function toggleSelectAllLibrary() {
    setSelectedLibraryIds((current) => {
      if (current.size === filteredLibraryEntries.length) {
        return new Set();
      }

      return new Set(filteredLibraryEntries.map((entry) => entry.id));
    });
  }

  function moveLibrarySelectionToInbox() {
    const entries = libraryEntries.filter((entry) => selectedLibraryIds.has(entry.id));
    if (entries.length === 0) {
      return;
    }

    const activityEntries = entries.map((entry, index) => ({
      id: `${entry.term}-${Date.now()}-${index}`,
      term: entry.term,
      detail: entry.detail,
      context: entry.context,
      savedAt: Date.now() + index,
    }));

    setInboxEntryDrafts((current) => {
      const next = { ...current };
      for (const entry of entries) {
        next[normalizedTerm(entry.term)] = createEditableEntry({
          term: entry.term,
          kind: entry.kind,
          detail: entry.detail,
          context: entry.context,
          notes: entry.notes,
          snapshot: lookupSnapshotForTerm(entry.term),
          existing: entry,
        });
      }
      return next;
    });

    startTransition(() => {
      setInboxItems((current) =>
        activityEntries.reduce((next, entry) => upsertActivity(next, entry), current),
      );
      setLibraryEntries((current) => current.filter((entry) => !selectedLibraryIds.has(entry.id)));
    });

    for (const entry of activityEntries) {
      void syncActivity("inbox", entry);
    }

    setSelectedLibraryIds(new Set());
    setIsLibrarySelecting(false);
  }

  function deleteLibrarySelection() {
    const entries = libraryEntries.filter((entry) => selectedLibraryIds.has(entry.id));
    if (entries.length === 0) {
      return;
    }

    archiveLibraryItems(entries);
    setLibraryEntries((current) => current.filter((entry) => !selectedLibraryIds.has(entry.id)));
    setSelectedLibraryIds(new Set());
    setIsLibrarySelecting(false);
  }

  function updateFavoriteForLibrarySelection(nextFavorite: boolean) {
    if (selectedLibraryIds.size === 0) {
      return;
    }

    setLibraryEntries((current) =>
      current.map((entry) =>
        selectedLibraryIds.has(entry.id)
          ? {
              ...entry,
              favorite: nextFavorite,
              updatedAt: Date.now(),
            }
          : entry,
        ),
    );
  }

  function saveCurrentLibraryArrangement() {
    if (filteredLibraryEntries.length === 0) {
      return;
    }

    const nextArrangements = createLibraryArrangement(
      savedLibraryArrangements,
      arrangementNameDraft,
      filteredLibraryEntries.map((entry) => entry.id),
      "arrangement",
    );
    const newest = nextArrangements[0] ?? null;
    setSavedLibraryArrangements(nextArrangements);
    setArrangementNameDraft("");
    if (newest) {
      setLibraryFilter(`saved:${newest.id}`);
    }
  }

  function saveLibraryCollectionFromSelection() {
    if (collectionSeedEntryIds.length === 0) {
      return;
    }

    const nextArrangements = createLibraryArrangement(
      savedLibraryArrangements,
      arrangementNameDraft,
      collectionSeedEntryIds,
      "collection",
    );
    const newest = nextArrangements[0] ?? null;
    setSavedLibraryArrangements(nextArrangements);
    setArrangementNameDraft("");
    if (newest) {
      setLibraryFilter(`saved:${newest.id}`);
    }
  }

  function updateActiveLibraryArrangement() {
    if (!activeSavedArrangement || filteredLibraryEntries.length === 0 || librarySearch.trim()) {
      return;
    }

    setSavedLibraryArrangements((current) =>
      replaceLibraryArrangementEntries(
        current,
        activeSavedArrangement.id,
        filteredLibraryEntries.map((entry) => entry.id),
      ),
    );
  }

  function deleteActiveLibraryArrangement() {
    const activeArrangementId = arrangementFilterId(libraryFilter);
    if (!activeArrangementId) {
      return;
    }

    setSavedLibraryArrangements((current) =>
      removeLibraryArrangement(current, activeArrangementId),
    );
    setLibraryFilter("all");
  }

  function renameActiveLibraryArrangement() {
    const activeArrangementId = arrangementFilterId(libraryFilter);
    if (!activeArrangementId) {
      return;
    }

    setSavedLibraryArrangements((current) =>
      renameLibraryArrangement(current, activeArrangementId, arrangementNameDraft),
    );
  }

  function moveSelectedLibraryEntryWithinArrangement(direction: -1 | 1) {
    if (!activeSavedArrangement || !selectedLibraryEntry) {
      return;
    }

    setSavedLibraryArrangements((current) =>
      moveEntryInLibraryArrangement(current, activeSavedArrangement.id, selectedLibraryEntry.id, direction),
    );
  }

  function toggleLibraryEntryInCollection(entryId: string, collectionId: string) {
    const collection = savedLibraryArrangements.find((arrangement) => arrangement.id === collectionId);
    if (!collection || collection.mode !== "collection") {
      return;
    }

    setSavedLibraryArrangements((current) =>
      collection.entryIds.includes(entryId)
        ? removeEntriesFromLibraryArrangement(current, collectionId, [entryId])
        : addEntriesToLibraryArrangement(current, collectionId, [entryId]),
    );
  }

  function removeSelectionFromActiveCollection() {
    if (!activeCustomCollection || selectedLibraryIds.size === 0) {
      return;
    }

    setSavedLibraryArrangements((current) =>
      removeEntriesFromLibraryArrangement(
        current,
        activeCustomCollection.id,
        Array.from(selectedLibraryIds),
      ),
    );
    setSelectedLibraryIds(new Set());
  }

  function toggleTrashSelection(itemId: string) {
    setSelectedTrashIds((current) => {
      const next = new Set(current);
      if (next.has(itemId)) {
        next.delete(itemId);
      } else {
        next.add(itemId);
      }
      return next;
    });
  }

  function toggleSelectAllTrash() {
    setSelectedTrashIds((current) => {
      if (current.size === trashItems.length) {
        return new Set();
      }

      return new Set(trashItems.map((item) => item.id));
    });
  }

  function restoreSelectedTrashItems() {
    const items = trashItems.filter((item) => selectedTrashIds.has(item.id));
    if (items.length === 0) {
      return;
    }

    const libraryRestores = items.filter(
      (item): item is Extract<WorkspaceTrashItem, { source: "library" }> => item.source === "library",
    );
    const inboxRestores = items.filter(
      (item): item is Extract<WorkspaceTrashItem, { source: "inbox" }> => item.source === "inbox",
    );
    const historyRestores = items.filter(
      (item): item is Extract<WorkspaceTrashItem, { source: "history" }> => item.source === "history",
    );

    if (libraryRestores.length > 0) {
      setLibraryEntries((current) =>
        libraryRestores.reduce(
          (next, item) => restoreLibraryEntry(next, item.entry),
          current,
        ),
      );
    }

    const restoredInboxDraftRecords = inboxRestores
      .map((item, index) =>
        createQuickCaptureDraftRecord({
          term: item.entry.term,
          kind: item.draft?.kind ?? inferLookupKindFromTerm(item.entry.term, "word"),
          context: item.entry.context ?? "",
          reviewLevel: reviewStateForTerm(item.entry.term, reviewStateMap).level,
          meaning: item.draft?.detail ?? item.entry.detail,
          example: item.draft ? selectedExamplesFromEntry(item.draft)[0] ?? "" : "",
          partOfSpeech: item.draft?.partOfSpeech ?? "",
          notes: item.draft?.notes ?? "",
          snapshot: lookupSnapshotForTerm(item.entry.term),
          existing: item.draft ?? null,
          savedAt: Date.now() + index,
        }),
      )
      .filter((item): item is NonNullable<typeof item> => item !== null);
    const restoredHistoryItems = historyRestores.map((item, index) => ({
      ...item.entry,
      id: `${item.entry.term}-${Date.now()}-${index}`,
      savedAt: Date.now() + index,
    }));
    const firstRestoreTarget = items[0] ?? null;

    if (restoredInboxDraftRecords.length > 0) {
      setQuickCaptureDrafts((current) =>
        restoredInboxDraftRecords.reduce(
          (next, entry) => upsertQuickCaptureDraft(next, entry),
          current,
        ),
      );
    }

    if (restoredHistoryItems.length > 0) {
      setHistoryItems((current) =>
        restoredHistoryItems.reduce((next, entry) => prependHistoryActivity(next, entry), current),
      );
      for (const entry of restoredHistoryItems) {
        void syncActivity("history", entry);
      }
    }

    setTrashItems((current) => removeTrashItems(current, selectedTrashIds));
    setSelectedTrashIds(new Set());

    if (firstRestoreTarget) {
      closeSettings();
      if (firstRestoreTarget.source === "library") {
        router.push(
          buildWorkspaceHref({
            section: "library",
            q: firstRestoreTarget.entry.term,
            source: "trash",
            kind: firstRestoreTarget.entry.kind,
            context: firstRestoreTarget.entry.context,
            entryId: firstRestoreTarget.entry.id,
          }),
        );
        return;
      }

      if (firstRestoreTarget.source === "inbox") {
        const restoredDraft =
          restoredInboxDraftRecords[inboxRestores.findIndex((item) => item.id === firstRestoreTarget.id)];
        if (restoredDraft) {
          applyQuickCaptureFormState(
            quickCaptureFormStateFromEntry(restoredDraft.entry, {
              term: restoredDraft.term,
              kind: restoredDraft.kind,
              context: restoredDraft.context,
              reviewLevel: restoredDraft.reviewLevel,
            }),
          );
          setIsQuickCaptureOpen(true);
        }
        return;
      }

      const restored = restoredHistoryItems[historyRestores.findIndex((item) => item.id === firstRestoreTarget.id)];
      if (restored) {
        router.push(
          buildWorkspaceHref({
            section: "history",
            q: restored.term,
            source: "trash",
            kind: inferLookupKindFromTerm(restored.term, "word"),
            context: restored.context,
            itemId: restored.id,
          }),
        );
      }
    }
  }

  function deleteSelectedTrashItems() {
    setTrashItems((current) => removeTrashItems(current, selectedTrashIds));
    setSelectedTrashIds(new Set());
  }

  function submitLookup(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const trimmedQuery = queryDraft.trim();
    router.push(
      buildWorkspaceHref({
        section: "lookup",
        q: trimmedQuery,
        source: trimmedQuery ? "search" : null,
        kind: kindDraft,
        context: lookupContextForSubmission({
          kind: kindDraft,
          query: trimmedQuery,
          context: contextDraft,
          initialQuery: initialWorkspace.query,
          initialContext,
          contextDirty: isLookupContextDirty,
        }),
      }),
    );
  }

  function jumpToLookup(query: string, source: string, kind: LookupKind = inferLookupKindFromTerm(query, kindDraft)) {
    router.push(
      buildWorkspaceHref({
        section: "lookup",
        q: query,
        source,
        kind,
        context: lookupContextForSubmission({
          kind,
          query,
          context: contextDraft,
          initialQuery: initialWorkspace.query,
          initialContext,
          contextDirty: isLookupContextDirty,
        }),
      }),
    );
  }

  function toggleReviewSource(source: ReviewSourceKind) {
    setReviewSources((current) => {
      const next = new Set(current);
      if (next.has(source)) {
        next.delete(source);
      } else {
        next.add(source);
      }
      return next;
    });
  }

  function updateReviewQuestionStrategy(strategy: ReviewQuestionStrategy) {
    setReviewQuestionStrategy(strategy);
    setWorkspacePreferences((current) => ({
      ...current,
      review: {
        ...current.review,
        questionStrategy: strategy,
      },
    }));
  }

  function resetReviewSmartDefaults() {
    const questionTypes: ReviewQuestionType[] = ["multipleChoice", "fillIn", "flashcards"];
    setReviewQuestionStrategy("smart");
    setReviewQuestionTypes(new Set(questionTypes));
    setWorkspacePreferences((current) => ({
      ...current,
      review: {
        ...current.review,
        questionStrategy: "smart",
        questionTypes,
      },
    }));
  }

  function toggleReviewQuestionType(type: ReviewQuestionType) {
    setReviewQuestionTypes((current) => {
      const next = new Set(current);
      if (next.has(type)) {
        next.delete(type);
      } else {
        next.add(type);
      }
      setWorkspacePreferences((preferences) => ({
        ...preferences,
        review: {
          ...preferences.review,
          questionTypes: orderedReviewQuestionTypes(next),
        },
      }));
      return next;
    });
  }

  function toggleReviewSelection(candidateId: string) {
    setSelectedReviewIds((current) => {
      const next = new Set(current);
      if (next.has(candidateId)) {
        next.delete(candidateId);
      } else {
        next.add(candidateId);
      }
      return next;
    });
  }

  function toggleSelectAllReview() {
    setSelectedReviewIds((current) => {
      if (current.size === filteredReviewCandidates.length) {
        return new Set();
      }

      return new Set(filteredReviewCandidates.map((item) => item.id));
    });
  }

  function applyReviewQuickFilter(filter: ReviewQuickFilter) {
    setReviewQuickFilter(filter);
    setSelectedReviewIds(new Set());
  }

  function queueReviewFilter(filter: ReviewQuickFilter) {
    const ids = reviewCandidates
      .filter((candidate) => matchesReviewQuickFilter(candidate, filter, recentMistakeCandidateIds, reviewStateMap))
      .map((candidate) => candidate.id);

    setReviewQuickFilter(filter);
    setReviewCandidateSearch("");
    setSelectedReviewIds(new Set(ids));
  }

  function startReviewSession() {
    if (reviewQuestionTypes.size === 0) {
      return;
    }

    const questionTypes = orderedReviewQuestionTypes(reviewQuestionTypes);
    if (questionTypes.length === 0) {
      return;
    }

    const visibleItems = selectedReviewIds.size === 0 ? filteredReviewCandidates : selectedReviewItems;
    const sessionItems =
      selectedReviewIds.size === 0 && reviewRoundSize !== "all"
        ? visibleItems.slice(0, Number(reviewRoundSize))
        : visibleItems;
    const queue = sessionItems.map((item) => item.id);
    if (queue.length === 0) {
      return;
    }

    const nextSession = {
      sessionId: makeSessionId(),
      queue,
      index: 0,
      records: [],
      activeCandidateId: queue[0] ?? null,
      draftAnswer: "",
      selectedChoice: "",
      answerSubmitted: false,
      questionTypes,
      questionStrategy: reviewQuestionStrategy,
      styleTitle: currentReviewStyle.title,
      styleDetail: currentReviewStyle.detail,
      startedAt: Date.now(),
      pausedAt: null,
      sourceKinds: Array.from(new Set(sessionItems.flatMap((item) => item.sourceKinds))) as ReviewSourceKind[],
    };
    setReviewSession(nextSession);
    commitWorkspacePersistenceSnapshot({
      ...workspacePersistenceSnapshot,
      reviewSession: nextSession,
    });
    setReviewExitIntent(false);
    setReviewDraftAnswer("");
    setReviewSelectedChoice("");
    setReviewAnswerSubmitted(false);
  }

  function endReviewSession() {
    setReviewSession(null);
    commitWorkspacePersistenceSnapshot({
      ...workspacePersistenceSnapshot,
      reviewSession: null,
    });
    setReviewExitIntent(false);
    setReviewDraftAnswer("");
    setReviewSelectedChoice("");
    setReviewAnswerSubmitted(false);
  }

  function pauseReviewSession() {
    const nextSession = reviewSession
      ? {
          ...reviewSession,
          pausedAt: Date.now(),
        }
      : reviewSession;
    setReviewSession(nextSession);
    if (nextSession) {
      commitWorkspacePersistenceSnapshot({
        ...workspacePersistenceSnapshot,
        reviewSession: nextSession,
      });
    }
    setReviewExitIntent(false);
  }

  function resumeReviewSession() {
    const nextSession = reviewSession
      ? {
          ...reviewSession,
          pausedAt: null,
        }
      : reviewSession;
    setReviewSession(nextSession);
    if (nextSession) {
      commitWorkspacePersistenceSnapshot({
        ...workspacePersistenceSnapshot,
        reviewSession: nextSession,
      });
    }
    setReviewExitIntent(false);
  }

  function retryWeakerReviewCards() {
    if (!reviewSession) {
      return;
    }

    const weakerIds = Array.from(
      new Set(
        reviewSession.records
          .filter(isWeakReviewRecord)
          .map((record) => record.candidateId),
      ),
    );

    setReviewCandidateSearch("");
    setSelectedReviewIds(new Set(weakerIds));
    endReviewSession();
  }

  function updateReviewSelectedChoice(choice: string) {
    setReviewSelectedChoice(choice);
    if (!currentReviewCandidate) {
      return;
    }

    setReviewSession((current) =>
      current
        ? {
            ...current,
            activeCandidateId: currentReviewCandidate.id,
            selectedChoice: choice,
          }
        : current,
    );
  }

  function updateReviewDraftAnswer(answer: string) {
    setReviewDraftAnswer(answer);
    if (!currentReviewCandidate) {
      return;
    }

    setReviewSession((current) =>
      current
        ? {
            ...current,
            activeCandidateId: currentReviewCandidate.id,
            draftAnswer: answer,
          }
        : current,
    );
  }

  function submitReviewAnswer() {
    if (!currentReviewCard || !currentReviewCandidate) {
      return;
    }

    if (currentReviewCard.family === "multipleChoice" && !reviewSelectedChoice) {
      return;
    }

    if (currentReviewCard.family === "fillIn" && !reviewDraftAnswer.trim()) {
      return;
    }

    setReviewAnswerSubmitted(true);
    setReviewSession((current) =>
      current
        ? {
            ...current,
            activeCandidateId: currentReviewCandidate.id,
            draftAnswer: reviewDraftAnswer,
            selectedChoice: reviewSelectedChoice,
            answerSubmitted: true,
          }
        : current,
    );
  }

  function applyReviewDecision(decision: ReviewDecision) {
    if (!reviewSession || !currentReviewCandidate || !currentReviewCard) {
      return;
    }

    const answeredAt = Date.now();
    const termKey = normalizedReviewKey(currentReviewCandidate.term);
    const previousState = reviewStateMap[termKey] ?? defaultReviewState();
    const nextState = currentReviewCandidate.hasBackingEntry
      ? nextReviewState(previousState, decision, answeredAt)
      : previousState;
    const nextReviewStateMap = currentReviewCandidate.hasBackingEntry
      ? {
          ...reviewStateMap,
          [termKey]: nextState,
        }
      : reviewStateMap;

    if (currentReviewCandidate.hasBackingEntry) {
      setReviewStateMap(nextReviewStateMap);
    }

    const record: ReviewRecord = {
      sessionId: reviewSession.sessionId,
      candidateId: currentReviewCandidate.id,
      term: currentReviewCandidate.term,
      meaning: currentReviewCandidate.detail || currentReviewLookup?.summary || currentReviewCandidate.term,
      partOfSpeech: currentReviewCandidate.partOfSpeech,
      example: currentReviewCandidate.example,
      context: currentReviewCandidate.context,
      notes: currentReviewCandidate.notes,
      prompt: currentReviewCard.prompt,
      promptTitle: currentReviewCard.promptTitle,
      questionType: currentReviewCard.questionType,
      decision,
      correct: currentReviewCard.family === "flashcards" ? null : currentReviewCorrect,
      answeredAt,
      sourceKinds: currentReviewCandidate.sourceKinds,
      submittedAnswer: submittedAnswerText(
        currentReviewCard.questionType,
        reviewDraftAnswer,
        reviewSelectedChoice,
        currentReviewCard,
      ),
      reviewLevelBefore: currentReviewCandidate.hasBackingEntry ? previousState.level : null,
      reviewLevelAfter: currentReviewCandidate.hasBackingEntry ? nextState.level : null,
      reviewStateBefore: currentReviewCandidate.hasBackingEntry ? previousState : null,
      reviewStateAfter: currentReviewCandidate.hasBackingEntry ? nextState : null,
      isHistoryOnly: !currentReviewCandidate.hasBackingEntry,
    };

    const nextReviewHistory = [record, ...reviewHistory].slice(0, 160);
    setReviewHistory(nextReviewHistory);

    const nextIndex = reviewSession.index + 1;
    const nextActiveCandidateId = reviewSession.queue[nextIndex] ?? null;
    const nextReviewSession = {
      ...reviewSession,
      index: nextIndex,
      records: [...reviewSession.records, record],
      activeCandidateId: nextActiveCandidateId,
      draftAnswer: "",
      selectedChoice: "",
      answerSubmitted: false,
    };

    commitWorkspacePersistenceSnapshot({
      ...workspacePersistenceSnapshot,
      reviewStateMap: nextReviewStateMap,
      reviewHistory: nextReviewHistory,
      reviewSession: nextReviewSession,
    });

    if (nextIndex >= reviewSession.queue.length) {
      setReviewSession(nextReviewSession);
      setReviewDraftAnswer("");
      setReviewSelectedChoice("");
      setReviewAnswerSubmitted(false);
      return;
    }

    setReviewSession(nextReviewSession);
    setReviewDraftAnswer("");
    setReviewSelectedChoice("");
    setReviewAnswerSubmitted(false);
  }

  function undoLastReviewDecision() {
    if (!reviewSession || reviewSession.records.length === 0) {
      return;
    }

    const undoResult = undoLastReviewRating(reviewSession, reviewHistory, reviewStateMap);
    if (!undoResult.undoneRecord) {
      return;
    }

    setReviewSession(undoResult.session);
    setReviewStateMap(undoResult.reviewStateMap);
    setReviewHistory(undoResult.reviewHistory);
    commitWorkspacePersistenceSnapshot({
      ...workspacePersistenceSnapshot,
      reviewStateMap: undoResult.reviewStateMap,
      reviewHistory: undoResult.reviewHistory,
      reviewSession: undoResult.session,
    });
    setReviewDraftAnswer("");
    setReviewSelectedChoice("");
    setReviewAnswerSubmitted(false);
    setReviewExitIntent(false);
  }

  const navigationItems: Array<{
    section: WorkspaceSection;
    label: string;
    count: number | null;
    href: string;
  }> = [
    {
      section: "lookup",
      label: sectionLabels.lookup,
      count: null,
      href: buildWorkspaceHref({
        section: "lookup",
        q: queryDraft || initialWorkspace.query,
        source: initialWorkspace.query ? initialSource ?? "search" : null,
        kind: kindDraft,
        context: lookupRouteContext(kindDraft, queryDraft || initialWorkspace.query, contextDraft),
      }),
    },
    {
      section: "library",
      label: sectionLabels.library,
      count: libraryEntries.length,
      href: buildWorkspaceHref({ section: "library" }),
    },
    {
      section: "review",
      label: sectionLabels.review,
      count: reviewCandidates.length,
      href: buildWorkspaceHref({ section: "review" }),
    },
    {
      section: "history",
      label: sectionLabels.history,
      count: historyItems.length,
      href: buildWorkspaceHref({ section: "history" }),
    },
  ];

  function renderLookupSuggestionCards(
    suggestions: WorkspaceState["suggestions"],
    source: string,
    fallbackKind: LookupKind,
  ): ReactNode {
    if (suggestions.length === 0) {
      return null;
    }

    return (
      <div className="desk-smart-grid">
        {suggestions.map((item) => {
          const targetKind =
            item.kind === "phrase"
              ? "phrase"
              : inferLookupKindFromTerm(item.term, fallbackKind);

          return (
            <article className="desk-suggestion-card" key={`${item.kind}-${item.term}`}>
              <div className="desk-suggestion-card-head">
                <span>{suggestionKindLabel(item.kind)}</span>
                <strong>{item.term}</strong>
              </div>
              <p>{item.hint}</p>
              <button
                className="secondary-button"
                onClick={() => jumpToLookup(item.term, source, targetKind)}
                type="button"
              >
                Open {lookupKindLabels[targetKind]}
              </button>
            </article>
          );
        })}
      </div>
    );
  }

  function renderSnapshotBlocks(
    snapshot: ReviewLookupSnapshot | null,
    options?: {
      status?: LookupFetchStatus;
      fallbackDetail?: string;
      context?: string;
      notes?: string;
      emptyTitle?: string;
    },
  ): ReactNode {
    if (!snapshot) {
      return (
        <>
          {options?.context ? (
            <div className="desk-info-block">
              <h3>Original context</h3>
              <p>{options.context}</p>
            </div>
          ) : null}
          {options?.notes ? (
            <div className="desk-info-block">
              <h3>Notes</h3>
              <p>{options.notes}</p>
            </div>
          ) : null}
          <div className="desk-info-block">
            <h3>{options?.emptyTitle ?? "Dictionary detail"}</h3>
            <p>
              {options?.status === "loading"
                ? "Loading the live dictionary preview for this item."
                : options?.status === "error"
                  ? "The dictionary preview did not load this time, but the saved item is still here."
                  : options?.fallbackDetail || "Open this item in Lookup to inspect the full dictionary result."}
            </p>
          </div>
        </>
      );
    }

    return (
      <>
        {options?.context ? (
          <div className="desk-info-block">
            <h3>Original context</h3>
            <p>{options.context}</p>
          </div>
        ) : null}
        {options?.notes ? (
          <div className="desk-info-block">
            <h3>Notes</h3>
            <p>{options.notes}</p>
          </div>
        ) : null}
        {workspacePreferences.showLookupReferenceTags && snapshot.sourceTags.length > 0 ? (
          <div className="desk-chip-row">
            {snapshot.sourceTags.map((tag) => (
              <span className="soft-tag" key={tag}>
                {tag}
              </span>
            ))}
          </div>
        ) : null}
        <div className="desk-info-block">
          <h3>Pronunciation</h3>
          {splitPronunciationLines(snapshot.pronunciation).length > 0 ? (
            <ul className="desk-plain-list">
              {splitPronunciationLines(snapshot.pronunciation).map((line) => (
                <li key={line}>{line}</li>
              ))}
            </ul>
          ) : (
            <p>
              This result does not include phonetics yet, but the headword is still available for review.
            </p>
          )}
        </div>
        <div className="desk-info-block">
          <h3>Chinese Meaning</h3>
          {renderMeaningList(snapshot)}
        </div>
        {renderEnglishDefinitionBlock(snapshot)}
        {snapshot.inflectionLines.length > 0 ? (
          <div className="desk-info-block">
            <h3>Inflections</h3>
            <ul className="desk-plain-list">
              {snapshot.inflectionLines.map((line) => (
                <li key={line}>{line}</li>
              ))}
            </ul>
          </div>
        ) : null}
        <div className="desk-info-block">
          <h3>Common Collocations / Phrases</h3>
          {snapshot.collocations.length > 0 ? (
            <div className="desk-chip-row">
              {snapshot.collocations.map((item) => (
                <button
                  className="desk-chip-button"
                  key={item}
                  onClick={() => jumpToLookup(item, "suggestion", inferLookupKindFromTerm(item, "phrase"))}
                  type="button"
                >
                  {item}
                </button>
              ))}
            </div>
          ) : (
            <p>No collocations were surfaced for this entry yet.</p>
          )}
        </div>
        {snapshot.relatedTerms.length > 0 ? (
          <div className="desk-info-block">
            <h3>Related Terms</h3>
            <div className="desk-chip-row">
              {snapshot.relatedTerms.map((item) => (
                <span className="soft-tag" key={item}>
                  {item}
                </span>
              ))}
            </div>
          </div>
        ) : null}
        {snapshot.examples.length > 0 ? (
          <div className="desk-info-block">
            <h3>Examples</h3>
            <div className="desk-example-stack">
              {snapshot.examples.map((example) => (
                <article className="desk-example-card" key={`${example.english}-${example.chinese}`}>
                  <p>{example.english}</p>
                  <span {...cjkTextProps(example.chinese)}>{example.chinese}</span>
                </article>
              ))}
            </div>
          </div>
        ) : null}
      </>
    );
  }

  function renderNativeEmptyPanel(title: string, body: string, actions?: ReactNode): ReactNode {
    return (
      <div className="desk-native-empty">
        <h3>{title}</h3>
        <p>{body}</p>
        {actions ? <div className="desk-chip-row">{actions}</div> : null}
      </div>
    );
  }

  function renderRecoveryLane({
    kicker,
    title,
    body,
    stats = [],
    actions,
    tone = "default",
  }: {
    kicker: string;
    title: string;
    body: string;
    stats?: WorkspaceHeroStat[];
    actions?: ReactNode;
    tone?: "default" | "accent" | "warning";
  }): ReactNode {
    const className =
      tone === "accent"
        ? "desk-recovery-card is-accent"
        : tone === "warning"
          ? "desk-recovery-card is-warning"
          : "desk-recovery-card";

    return (
      <div className={className}>
        <div className="desk-recovery-head">
          <div>
            <p className="desk-kicker">{kicker}</p>
            <h3>{title}</h3>
          </div>
          {stats[0] ? <span className="soft-tag soft-tag--accent">{stats[0].value}</span> : null}
        </div>
        <p className="desk-library-summary">{body}</p>
        {stats.length > 0 ? (
          <div className="desk-library-trait-grid">
            {stats.map((stat) => (
              <div className="desk-mini-stat-card" key={`${kicker}-${stat.label}`}>
                <span>{stat.label}</span>
                <strong>{stat.value}</strong>
              </div>
            ))}
          </div>
        ) : null}
        {actions ? <div className="desk-recovery-actions">{actions}</div> : null}
      </div>
    );
  }

  function renderLookupDetail(): ReactNode {
    if (initialWorkspace.mode === "empty") {
      return (
        <section className="app-panel desk-detail-panel">
          {renderNativeEmptyPanel(
            "No lookup result yet",
            "Enter a word, phrase, Chinese query, or sentence on the left.",
          )}
        </section>
      );
    }

    if (initialWorkspace.mode === "no-result") {
      const sentenceMode = initialWorkspace.kind === "sentence";
      const dictionaryOffline = initialWorkspace.statusTitle === "Dictionary service offline.";
      const focusedSentenceCandidate =
        sentenceStudyCandidates.find((candidate) => candidate.term === sentenceFocusTerm) ??
        sentenceStudyCandidates[0] ??
        null;

      return (
        <section className="app-panel desk-detail-panel">
          <div className="desk-detail-header">
            <div>
              <h2>
                {sentenceMode ? "Sentence mode" : dictionaryOffline ? "Dictionary service offline" : "No exact result yet"}
              </h2>
              <p className="desk-subtle">{initialWorkspace.statusTitle}</p>
            </div>
            {sentenceMode ? (
              <div className="desk-detail-actions">
                <button className="secondary-button" onClick={saveCurrentSentenceAsDraft} type="button">
                  {currentSentenceDraftRecord ? "Sentence Draft Saved" : "Save Sentence as Draft"}
                </button>
                <button className="secondary-button" onClick={saveCurrentSentenceToLibrary} type="button">
                  {isCurrentSentenceInLibrary ? "In Library" : "Add Sentence to Library"}
                </button>
              </div>
            ) : null}
          </div>

          {!sentenceMode && initialWorkspace.suggestions.length > 0 ? (
            <div className="desk-info-block">
              <h3>Suggestions</h3>
              {renderLookupSuggestionCards(initialWorkspace.suggestions, "suggestion", "word")}
            </div>
          ) : null}

          <div className="desk-chip-row">
            {sentenceMode && currentSentenceDraftRecord ? <span className="soft-tag">Draft saved</span> : null}
            {sentenceMode && isCurrentSentenceInLibrary ? <span className="soft-tag">In Library</span> : null}
            {sentenceMode ? (
              <button
                className="secondary-button"
                onClick={() => {
                  setKindDraft("phrase");
                  setQueryDraft(initialWorkspace.query);
                  router.push(
                    buildWorkspaceHref({
                      section: "lookup",
                      q: initialWorkspace.query,
                      source: initialSource ?? "search",
                      kind: "phrase",
                      context: initialContext,
                    }),
                  );
                }}
                type="button"
              >
                Try as Phrase Lookup
              </button>
            ) : null}
          </div>

          {sentenceMode ? (
            <div className="desk-info-block">
              <div className="desk-detail-header">
                <div>
                  <h3>Sentence study candidates</h3>
                  <p>{sentenceMagicSummary.sourcePreview}</p>
                </div>
                <span className="soft-tag soft-tag--accent">{sentenceMagicSummary.candidateCount} picks</span>
              </div>
              <div className="desk-chip-row">
                {focusedSentenceCandidate ? (
                  <button
                    className="desk-accent-button"
                    onClick={() => openSentenceCandidateInQuickCapture(focusedSentenceCandidate)}
                    type="button"
                  >
                    Edit Focused Candidate
                  </button>
                ) : null}
                {sentenceStudyCandidates.length > 1 ? (
                  <button
                    className="secondary-button"
                    onClick={() => saveSentenceCandidateBatchToDrafts(sentenceStudyCandidates)}
                    type="button"
                  >
                    Save Top 3 as Drafts
                  </button>
                ) : null}
              </div>
            </div>
          ) : null}

          {sentenceMode ? (
            <div className="desk-info-block">
              <h3>Sentence study candidates</h3>
              {sentenceStudyCandidates.length > 0 ? (
                <div className="desk-candidate-list">
                  {sentenceStudyCandidates.map((candidate) => {
                    const isFocused = candidate.term === focusedSentenceCandidate?.term;

                    return (
                      <div
                        className={isFocused ? "desk-candidate-button is-active" : "desk-candidate-button"}
                        key={`${candidate.kind}-${candidate.term}`}
                      >
                        <button
                          className="desk-plain-action"
                          onClick={() => setSentenceFocusTerm(candidate.term)}
                          type="button"
                        >
                          <strong>{candidate.term}</strong>
                          <span>
                            {lookupKindLabels[candidate.kind]} · {candidate.reason}
                          </span>
                          <small>Candidate score {candidate.score}</small>
                          <p>{candidate.summary}</p>
                        </button>
                        <div className="desk-chip-row">
                          <button
                            className="secondary-button"
                            onClick={() =>
                              router.push(
                                buildWorkspaceHref({
                                  section: "lookup",
                                  q: candidate.term,
                                  source: "sentence",
                                  kind: candidate.kind,
                                  context: initialWorkspace.query,
                                }),
                              )
                            }
                            type="button"
                          >
                            Open in {lookupKindLabels[candidate.kind]}
                          </button>
                          <button
                            className="secondary-button"
                            onClick={() => openSentenceCandidateInQuickCapture(candidate)}
                            type="button"
                          >
                            Open in Quick Capture
                          </button>
                          <button
                            className="secondary-button"
                            onClick={() => saveSentenceCandidateAsDraft(candidate)}
                            type="button"
                          >
                            Save as Draft
                          </button>
                        </div>
                      </div>
                    );
                  })}
                </div>
              ) : (
                <div className="desk-empty-inline">
                  <p>
                    No study candidates were extracted from this sentence yet. Try a shorter English sentence.
                  </p>
                </div>
              )}
            </div>
          ) : null}

          {sentenceMode && focusedSentenceCandidate ? (
            <>
              <div className="desk-info-block">
                <h3>Focused study preview</h3>
                <p>
                  {focusedSentenceCandidate.term} · {lookupKindLabels[focusedSentenceCandidate.kind]}
                </p>
                <small>{focusedSentenceCandidate.summary}</small>
              </div>
              {renderSnapshotBlocks(sentenceFocusSnapshot, {
                status: lookupStatusForTerm(focusedSentenceCandidate.term),
                fallbackDetail: `Still fetching dictionary detail for ${focusedSentenceCandidate.term}.`,
                context: initialWorkspace.query,
                emptyTitle: "Candidate preview",
              })}
            </>
          ) : null}

          {initialWorkspace.suggestions.length > 0 ? (
            <div className="desk-info-block">
              <h3>Suggestions</h3>
              <div className="desk-chip-row">
                {initialWorkspace.suggestions.map((item) => (
                  <button
                    className="desk-chip-button"
                    key={`${item.kind}-${item.term}`}
                    onClick={() => jumpToLookup(item.term, "suggestion", inferLookupKindFromTerm(item.term, "word"))}
                    type="button"
                  >
                    {item.term}
                  </button>
                ))}
              </div>
            </div>
          ) : null}
        </section>
      );
    }

    if (initialWorkspace.mode === "reverse") {
      const topMatch = initialWorkspace.reverseMatches[0] ?? null;
      const focusedReverseMatch =
        initialWorkspace.reverseMatches.find((match) => match.term === reverseFocusTerm) ?? topMatch;

      return (
        <section className="app-panel desk-detail-panel">
          <div className="desk-detail-header">
            <div>
              <h2 {...cjkTextProps(initialWorkspace.query)}>{initialWorkspace.query}</h2>
              <p className="desk-subtle">Chinese query</p>
            </div>
          </div>

          <div className="desk-info-block">
            <h3>English candidates</h3>
            {initialWorkspace.reverseMatches.length > 0 ? (
              <div className="desk-candidate-list">
                {initialWorkspace.reverseMatches.map((match) => {
                  const isFocused = match.term === focusedReverseMatch?.term;

                  return (
                    <div
                      className={isFocused ? "desk-candidate-button is-active" : "desk-candidate-button"}
                      key={`${match.term}-${match.gloss}`}
                    >
                      <button
                        className="desk-plain-action"
                        onClick={() => setReverseFocusTerm(match.term)}
                        type="button"
                      >
                        <strong>{match.term}</strong>
                        <span>{match.partOfSpeech}</span>
                        <p>{match.gloss}</p>
                        <small>{match.note}</small>
                      </button>
                      <div className="desk-chip-row">
                        <button
                          className="secondary-button"
                          onClick={() => jumpToLookup(match.term, "reverse", inferLookupKindFromTerm(match.term, "word"))}
                          type="button"
                        >
                          Open in Lookup
                        </button>
                        <button
                          className="secondary-button"
                          onClick={() => openReverseCandidateInQuickCapture(match)}
                          type="button"
                        >
                          Open in Quick Capture
                        </button>
                        <button
                          className="secondary-button"
                          onClick={() => saveReverseCandidateAsDraft(match)}
                          type="button"
                        >
                          Save as Draft
                        </button>
                        <button
                          className="secondary-button"
                          onClick={() => saveReverseCandidateToLibrary(match)}
                          type="button"
                        >
                          Add to Library
                        </button>
                      </div>
                    </div>
                  );
                })}
              </div>
            ) : (
              <div className="desk-empty-inline">
                <p>No reverse lookup candidates yet.</p>
              </div>
            )}
          </div>

          <div className="desk-chip-row">
            {topMatch ? (
              <button
                className="secondary-button"
                onClick={() => jumpToLookup(topMatch.term, "reverse", inferLookupKindFromTerm(topMatch.term, "word"))}
                type="button"
              >
                Open Best Match
              </button>
            ) : null}
          </div>

          {focusedReverseMatch ? (
            <>
              <div className="desk-info-block">
                <h3>Focused reverse preview</h3>
                <p className="desk-preview-head">{focusedReverseMatch.term}</p>
                <p>{focusedReverseMatch.gloss}</p>
              </div>
              {renderSnapshotBlocks(reverseFocusSnapshot, {
                status: lookupStatusForTerm(focusedReverseMatch.term),
                fallbackDetail: focusedReverseMatch.gloss,
                context: initialWorkspace.query,
                emptyTitle: "Candidate preview",
              })}
            </>
          ) : initialWorkspace.lookup ? (
            <div className="desk-info-block">
              <h3>Best match preview</h3>
              <p className="desk-preview-head">{initialWorkspace.lookup.headword}</p>
              <p>{initialWorkspace.lookup.summary}</p>
            </div>
          ) : null}
        </section>
      );
    }

    if (!initialWorkspace.lookup) {
      return null;
    }

    const lookupSnapshot = workspaceLookupToSnapshot(initialWorkspace.lookup);
    const currentReviewState = reviewStateForTerm(initialWorkspace.lookup.headword, reviewStateMap);
    const exactMatch =
      normalizedTerm(initialWorkspace.query) === normalizedTerm(initialWorkspace.lookup.headword);

    return (
      <section className="app-panel desk-detail-panel">
        <div className="desk-detail-header">
          <div>
            <div className="desk-lookup-headline">
              <h2>{initialWorkspace.lookup.headword}</h2>
              <button
                aria-label={isCurrentLookupInLibrary ? "Already in Library" : "Quick Save to Library"}
                className={isCurrentLookupInLibrary ? "desk-lookup-star-button is-active" : "desk-lookup-star-button"}
                onClick={moveCurrentLookupToLibrary}
                title={isCurrentLookupInLibrary ? "Already in Library" : "Quick Save to Library"}
                type="button"
              >
                {isCurrentLookupInLibrary ? "★" : "☆"}
              </button>
            </div>
            <p className="desk-subtle">
              {lookupKindLabels[initialWorkspace.kind]}
              {normalizedTerm(initialWorkspace.query) !== normalizedTerm(initialWorkspace.lookup.headword)
                ? ` · Search: ${initialWorkspace.query}`
                : ""}
            </p>
          </div>
          <div className="desk-detail-actions">
            {canPlayCurrentAudio ? (
              <button className="secondary-button" onClick={() => playPronunciation(initialWorkspace.lookup!.headword)} type="button">
                Play Audio
              </button>
            ) : null}
            <button className="secondary-button" onClick={openCurrentLookupInQuickCapture} type="button">
              {currentLookupDraftRecord ? "Draft in Quick Capture" : "Edit in Quick Capture"}
            </button>
          </div>
        </div>

        <div className="desk-chip-row">
          <span className="soft-tag">{reviewLevelLabel(currentReviewState.level)}</span>
          {currentLookupDraftRecord ? <span className="soft-tag">Draft saved</span> : null}
        </div>

        {!exactMatch ? <span className="soft-tag">Resolved match</span> : null}

        {renderSnapshotBlocks(lookupSnapshot, {
          context: initialContext,
          fallbackDetail: initialWorkspace.lookup.summary,
        })}

        {initialWorkspace.suggestions.length > 0 ? (
          <div className="desk-info-block">
            <h3>Related phrases & terms</h3>
            {renderLookupSuggestionCards(initialWorkspace.suggestions, "suggestion", initialWorkspace.kind)}
          </div>
        ) : null}
      </section>
    );
  }

  function renderLookupSection(): ReactNode {
    return (
      <WorkspaceContentGrid
        layoutPreference={workspacePreferences.workspacePaneLayoutPreference}
        onResetLayout={resetWorkspaceLayout}
        onResizeStart={(event) => beginWorkspaceResize(event, "contentRailWidth")}
      >
        <section className="app-panel desk-form-panel">
          <p className="desk-section-title">Lookup</p>

          <form className="desk-search-form" onSubmit={submitLookup}>
            <div className="desk-segment-row" role="tablist" aria-label="Lookup type">
              {(["word", "phrase", "sentence"] as LookupKind[]).map((kind) => (
                <button
                  aria-pressed={kindDraft === kind}
                  className={kindDraft === kind ? "desk-segment is-active" : "desk-segment"}
                  key={kind}
                  onClick={() => setKindDraft(kind)}
                  type="button"
                >
                  {lookupKindLabels[kind]}
                </button>
              ))}
            </div>

            <div className="desk-input-row">
                <input
                  onChange={(event) => setQueryDraft(event.target.value)}
                  placeholder={lookupPlaceholder(kindDraft)}
                  value={queryDraft}
                />
              <button className="desk-primary-button" type="submit">
                Lookup
              </button>
            </div>

            {initialWorkspace.suggestions.length > 0 ? (
              <div className="desk-inline-suggestions">
                <span>Local suggestions</span>
                <div className="desk-chip-row">
                  {initialWorkspace.suggestions.map((item) => (
                    <button
                      className="desk-chip-button"
                      key={`${item.kind}-${item.term}`}
                      onClick={() =>
                        jumpToLookup(item.term, "suggestion", inferLookupKindFromTerm(item.term, kindDraft))
                      }
                      type="button"
                    >
                      {item.term}
                    </button>
                  ))}
                </div>
              </div>
            ) : null}

            {kindDraft !== "sentence" ? (
              <div className="desk-context-block">
                <label htmlFor="lookup-context">Original sentence / context</label>
                <textarea
                  id="lookup-context"
                  onChange={(event) => {
                    setContextDraft(event.target.value);
                    setIsLookupContextDirty(true);
                  }}
                  placeholder="Paste the sentence where you met this word so Quick Capture and Library can keep the source context."
                  value={contextDraft}
                />
              </div>
            ) : (
              <div className="desk-context-block desk-context-note">
                <p>Sentence lookup keeps the sentence as context and can send extracted candidates to Quick Capture or Drafts.</p>
              </div>
            )}
          </form>
        </section>

        {renderLookupDetail()}
      </WorkspaceContentGrid>
    );
  }

  function renderEditableChoicesSection(options: {
    title: string;
    selectedTitle: string;
    choices: string[];
    selectedIndexes: number[];
    partOfSpeechLabels?: string[];
    emptyMessage: string;
    customDraft: string;
    customMessage: string | null;
    customPlaceholder: string;
    onCustomDraftChange: (value: string) => void;
    onCommitCustom: () => void;
    onToggle: (index: number) => void;
    onRemove: (index: number) => void;
    onPartOfSpeechChange?: (index: number, value: string) => void;
    onPromoteSelection?: (index: number) => void;
    onMoveSelection?: (index: number, direction: -1 | 1) => void;
    onSelectAll?: () => void;
    onKeepSelected?: () => void;
    onDedupe?: () => void;
    onMoveChoice?: (index: number, direction: -1 | 1) => void;
    lockedSelection?: boolean;
  }): ReactNode {
    const lockedSelection = options.lockedSelection ?? false;

    return (
      <div className="desk-entry-editor-section">
        <div className="desk-entry-editor-heading">
          <h3>{options.title}</h3>
          <span>
            {lockedSelection
              ? `${options.choices.length} saved`
              : `${options.selectedIndexes.length}/${options.choices.length}`}
          </span>
        </div>

        {options.choices.length > 0 ? (
          <div className="desk-entry-choice-list">
            {options.choices.map((choice, index) => {
              const isSelected = options.selectedIndexes.includes(index);
              const partOfSpeech = options.partOfSpeechLabels?.[index]?.trim() ?? "";

              return (
                <div className={isSelected ? "desk-entry-choice-row is-selected" : "desk-entry-choice-row"} key={`${choice}-${index}`}>
                  {lockedSelection ? (
                    <span className="desk-choice-radio is-selected">✓</span>
                  ) : (
                    <button
                      aria-pressed={isSelected}
                      className={isSelected ? "desk-choice-radio is-selected" : "desk-choice-radio"}
                      onClick={() => options.onToggle(index)}
                      type="button"
                    >
                      {isSelected ? "✓" : ""}
                    </button>
                  )}
                  <div className={options.onPartOfSpeechChange ? "desk-entry-choice-main has-pos-editor" : "desk-entry-choice-main"}>
                    {lockedSelection ? (
                      <div className="desk-entry-choice-card is-selected">
                        {partOfSpeech ? <span>{partOfSpeech}</span> : null}
                        <strong {...cjkTextProps(choice)}>{choice}</strong>
                      </div>
                    ) : (
                      <button
                        className={isSelected ? "desk-entry-choice-card is-selected" : "desk-entry-choice-card"}
                        onClick={() => options.onToggle(index)}
                        type="button"
                      >
                        {partOfSpeech ? <span>{partOfSpeech}</span> : null}
                        <strong {...cjkTextProps(choice)}>{choice}</strong>
                      </button>
                    )}
                    {options.onPartOfSpeechChange ? (
                      <input
                        aria-label={`Part of speech for ${choice}`}
                        className="desk-entry-choice-input"
                        onChange={(event) => options.onPartOfSpeechChange?.(index, event.target.value)}
                        placeholder="Part-of-speech label"
                        value={partOfSpeech}
                      />
                    ) : null}
                  </div>
                  <button className="activity-remove" onClick={() => options.onRemove(index)} type="button">
                    Delete
                  </button>
                </div>
              );
            })}
          </div>
        ) : (
          <div className="desk-empty-inline">
            <p>{options.emptyMessage}</p>
          </div>
        )}

        <div className="desk-entry-add-row">
          <input
            onChange={(event) => options.onCustomDraftChange(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === "Enter") {
                event.preventDefault();
                options.onCommitCustom();
              }
            }}
            placeholder={options.customPlaceholder}
            value={options.customDraft}
          />
          <button className="secondary-button" onClick={options.onCommitCustom} type="button">
            Add
          </button>
        </div>
        {options.customMessage ? <p className="desk-inline-error">{options.customMessage}</p> : null}
      </div>
    );
  }

  function renderReferenceTagsEditor(options: {
    tags: string[];
    customDraft: string;
    customMessage: string | null;
    onCustomDraftChange: (value: string) => void;
    onCommitCustom: () => void;
    onRemove: (index: number) => void;
  }): ReactNode {
    return (
      <div className="desk-entry-editor-section">
        <div className="desk-entry-editor-heading">
          <h3>Reference Tags</h3>
          <span>{options.tags.length} tags</span>
        </div>

        {options.tags.length > 0 ? (
          <div className="desk-chip-row">
            {options.tags.map((tag, index) => (
              <button className="desk-chip-button" key={`${tag}-${index}`} onClick={() => options.onRemove(index)} type="button">
                {tag} ×
              </button>
            ))}
          </div>
        ) : (
          <p className="desk-footer-note">No reference tags on this entry yet.</p>
        )}

        <div className="desk-entry-add-row">
          <input
            onChange={(event) => options.onCustomDraftChange(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === "Enter") {
                event.preventDefault();
                options.onCommitCustom();
              }
            }}
            placeholder="Add tags, separated by commas"
            value={options.customDraft}
          />
          <button className="secondary-button" onClick={options.onCommitCustom} type="button">
            Add
          </button>
        </div>
        {options.customMessage ? <p className="desk-inline-error">{options.customMessage}</p> : null}
      </div>
    );
  }

  function renderActivitySection(kind: ActivityKind): ReactNode {
    const allItems = kind === "inbox" ? inboxItems : historyItems;
    const items = kind === "inbox" ? filteredInboxItems : filteredHistoryItems;
    const selectedItem = kind === "inbox" ? selectedInboxItem : selectedHistoryItem;
    const selectedSnapshot = kind === "inbox" ? selectedInboxSnapshot : selectedHistorySnapshot;
    const selectedEditor = kind === "inbox" ? selectedInboxDraft : null;
    const isSelecting = kind === "inbox" ? isInboxSelecting : isHistorySelecting;
    const selectedIds = kind === "inbox" ? selectedInboxIds : selectedHistoryIds;
    const hasHistorySearch = kind === "history" && historySearch.trim().length > 0;
    const matchingLibraryEntry = selectedItem
      ? libraryEntries.find((entry) => normalizedTerm(entry.term) === normalizedTerm(selectedItem.term)) ?? null
      : null;
    const matchingQuickCaptureDraft =
      kind === "history" && selectedItem
        ? quickCaptureDrafts[normalizedTerm(selectedItem.term)] ?? null
        : null;
    const relatedHistoryItems =
      kind === "history" && selectedItem
        ? historyItems
            .filter(
              (item) =>
                item.id !== selectedItem.id &&
                normalizedTerm(item.term) === normalizedTerm(selectedItem.term),
            )
            .slice()
            .sort((left, right) => right.savedAt - left.savedAt)
            .slice(0, 6)
        : [];
    const selectedReviewState = selectedItem
      ? reviewStateForTerm(selectedItem.term, reviewStateMap)
      : defaultReviewState();
    const selectedInboxDigest =
      kind === "inbox" && selectedItem && selectedEditor ? inboxDraftDigest(selectedItem, selectedEditor) : null;
    const nextVisibleInboxItem =
      kind === "inbox" && selectedItem ? adjacentActivityItem(items, selectedItem.id, 1) : null;
    const previousVisibleInboxItem =
      kind === "inbox" && selectedItem ? adjacentActivityItem(items, selectedItem.id, -1) : null;
    const firstReadyInboxItem =
      kind === "inbox" ? items.find((item) => inboxDigestById[item.id]?.isReady) ?? null : null;
    const firstVisibleItem = items[0] ?? null;

    return (
      <WorkspaceContentGrid
        layoutPreference={workspacePreferences.workspacePaneLayoutPreference}
        onResetLayout={resetWorkspaceLayout}
        onResizeStart={(event) => beginWorkspaceResize(event, "contentRailWidth")}
      >
        <section className="app-panel desk-form-panel">
          {kind === "inbox" && allItems.length > 0 ? (
            <div className="desk-native-control-row">
              <label className="desk-sort-label" htmlFor="inbox-sort">
                Sort
              </label>
              <select
                id="inbox-sort"
                onChange={(event) => setInboxSort(event.target.value as InboxSortOption)}
                value={inboxSort}
              >
                <option value="savedNewest">Recently saved</option>
                <option value="savedOldest">Oldest saved</option>
                <option value="alphabetical">Alphabetical</option>
              </select>
            </div>
          ) : kind === "history" && (allItems.length > 0 || hasHistorySearch) ? (
            <div className="desk-input-row">
              <input
                onChange={(event) => setHistorySearch(event.target.value)}
                placeholder="Filter history by English or Chinese"
                value={historySearch}
              />
            </div>
          ) : null}

          {items.length > 0 ? (
            <div className="desk-native-control-row">
              <button
                className="secondary-button"
                onClick={() => {
                  if (kind === "inbox") {
                    setIsInboxSelecting((current) => !current);
                    setSelectedInboxIds(new Set());
                  } else {
                    setIsHistorySelecting((current) => !current);
                    setSelectedHistoryIds(new Set());
                  }
                }}
                type="button"
              >
                {isSelecting ? "Done" : "Multi-select"}
              </button>
            </div>
          ) : null}

          {isSelecting ? (
            <div className="desk-batch-bar">
              <span>
                {selectedIds.size} selected · {items.length} visible
              </span>
              <div className="desk-chip-row">
                <button className="secondary-button" onClick={() => toggleSelectAllActivity(kind)} type="button">
                  {selectedIds.size === items.length && items.length > 0 ? "Clear all" : "Select all"}
                </button>
                <button
                  className="secondary-button"
                  disabled={selectedIds.size === 0}
                  onClick={() => archiveAndRemoveActivityBatch(kind, selectedIds)}
                  type="button"
                >
                  Delete Selected
                </button>
              </div>
            </div>
          ) : null}

          {items.length > 0 ? (
            <ul className="desk-activity-list">
              {items.map((item) => (
                <li className="desk-activity-row" key={item.id}>
                  <div className="desk-selectable-row">
                    {isSelecting ? (
                      <button
                        className={selectedIds.has(item.id) ? "desk-select-toggle is-selected" : "desk-select-toggle"}
                        onClick={() => toggleActivitySelection(kind, item.id)}
                        type="button"
                      >
                        {selectedIds.has(item.id) ? "Selected" : "Select"}
                      </button>
                    ) : null}
                    <Link
                      className={selectedItem?.id === item.id ? "desk-activity-link is-active" : "desk-activity-link"}
                      href={buildWorkspaceHref({
                        section: kind,
                        q: item.term,
                        source: kind,
                        kind: inferLookupKindFromTerm(item.term, "word"),
                        context: item.context,
                        itemId: item.id,
                      })}
                    >
                      <div className="desk-activity-head">
                        <strong>{item.term}</strong>
                        <span>{formatRelativeTime(item.savedAt)}</span>
                      </div>
                      {(() => {
                        const activityDetail =
                          kind === "inbox"
                            ? inboxEntryDrafts[normalizedTerm(item.term)]?.detail ?? item.detail
                            : item.detail;
                        return <p {...cjkTextProps(activityDetail)}>{activityDetail}</p>;
                      })()}
                      {kind === "history" && item.meta?.status ? (
                        <small>{historyStatusLabels[item.meta.status]}</small>
                      ) : null}
                      {item.context ? <small {...cjkTextProps(item.context)}>{item.context}</small> : null}
                    </Link>
                  </div>
                </li>
              ))}
            </ul>
          ) : (
            renderNativeEmptyPanel(
              hasHistorySearch
                ? "No visible matches"
                : kind === "inbox"
                  ? "Inbox is empty"
                  : "History is empty",
              hasHistorySearch
                ? "Clear the filter."
                : kind === "inbox"
                  ? "Lookup saves words and phrases here automatically."
                  : "Lookup records appear here automatically.",
              <>
                {hasHistorySearch ? (
                  <button
                    className="secondary-button"
                    onClick={() => setHistorySearch("")}
                    type="button"
                  >
                    Clear Filter
                  </button>
                ) : null}
                <Link className="secondary-button" href={buildWorkspaceHref({ section: "lookup", kind: "word" })}>
                  Open Lookup
                </Link>
              </>,
            )
          )}
        </section>

        <section className="app-panel desk-detail-panel">
          {selectedItem && kind === "inbox" && selectedEditor ? (
            <>
              <div className="desk-detail-header">
                <div>
                  <h2>{selectedItem.term}</h2>
                  <p className="desk-subtle">Selected from Inbox</p>
                </div>
                <div className="desk-detail-actions">
                  {isPronounceableEnglish(selectedItem.term) ? (
                    <button className="secondary-button" onClick={() => playPronunciation(selectedItem.term)} type="button">
                      Play Audio
                    </button>
                  ) : null}
                  <Link
                    className="secondary-button"
                    href={buildWorkspaceHref({
                      section: "lookup",
                      q: selectedItem.term,
                      source: kind,
                      kind: inferLookupKindFromTerm(selectedItem.term, "word"),
                      context: selectedItem.context,
                    })}
                  >
                    Open in Lookup
                  </Link>
                  <button className="secondary-button" onClick={() => refreshInboxDraft(selectedItem)} type="button">
                    Refresh Candidates
                  </button>
                  <button className="secondary-button" onClick={() => moveInboxItemToLibrary(selectedItem)} type="button">
                    {matchingLibraryEntry ? "Refresh Library Entry" : "Confirm into Library"}
                  </button>
                </div>
              </div>

              <div className="desk-entry-editor-meta">
                <div className="desk-segment-row" role="tablist" aria-label="Inbox entry type">
                  {(["word", "phrase", "sentence"] as LookupKind[]).map((entryKind) => (
                    <button
                      aria-pressed={selectedEditor.kind === entryKind}
                      className={selectedEditor.kind === entryKind ? "desk-segment is-active" : "desk-segment"}
                      key={entryKind}
                      onClick={() => updateInboxDraft(selectedItem, { kind: entryKind })}
                      type="button"
                    >
                      {lookupKindLabels[entryKind]}
                    </button>
                  ))}
                </div>
                <div className="desk-entry-select-group">
                  <label htmlFor="inbox-familiarity">Familiarity</label>
                  <select
                    id="inbox-familiarity"
                    onChange={(event) => setReviewLevelForTerm(selectedItem.term, Number(event.target.value) as ReviewLevel)}
                    value={selectedReviewState.level}
                  >
                    {reviewLevelOptions.map((level) => (
                      <option key={level} value={level}>
                        {reviewLevelLabel(level)}
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              <div className="desk-context-block">
                <label htmlFor="inbox-part-of-speech">Preferred part of speech</label>
                <input
                  id="inbox-part-of-speech"
                  onChange={(event) =>
                    updateInboxDraft(selectedItem, {
                      partOfSpeech: sanitizeInlineText(event.target.value),
                    })
                  }
                  placeholder="e.g. n. / phr. / adj."
                  value={selectedEditor.partOfSpeech}
                />
              </div>

              <div className="desk-chip-row">
                {matchingLibraryEntry ? <span className="soft-tag">Also in Library</span> : null}
                {matchingLibraryEntry?.favorite ? <span className="soft-tag">Favorite</span> : null}
                {selectedEditor.partOfSpeech ? <span className="soft-tag">{selectedEditor.partOfSpeech}</span> : null}
                <span className="soft-tag">{reviewLevelLabel(selectedReviewState.level)}</span>
              </div>

              {renderEditableChoicesSection({
                title: "Chinese Meaning Candidates",
                selectedTitle: "Selected meanings",
                choices: selectedEditor.meaningChoices,
                selectedIndexes: selectedEditor.selectedMeaningIndexes,
                partOfSpeechLabels: selectedEditor.meaningChoicePartOfSpeechLabels,
                emptyMessage: "No meaning candidates yet. Refresh the live dictionary preview first.",
                customDraft: customMeaningDraft,
                customMessage: customMeaningMessage,
                customPlaceholder: "(Custom meaning)",
                onCustomDraftChange: (value) => {
                  setCustomMeaningDraft(value);
                  setCustomMeaningMessage(null);
                },
                onCommitCustom: () => {
                  const cleaned = customMeaningDraft.trim();
                  if (!cleaned) {
                    setCustomMeaningMessage(null);
                    return;
                  }

                  const existingIndex = selectedEditor.meaningChoices.findIndex(
                    (choice) => normalizedTerm(choice) === normalizedTerm(cleaned),
                  );
                  if (existingIndex >= 0) {
                    updateInboxDraft(
                      selectedItem,
                      {
                        selectedMeaningIndexes: ensuredSelection(
                          selectedEditor.selectedMeaningIndexes,
                          existingIndex,
                        ),
                      },
                      { syncDetail: true },
                    );
                    setCustomMeaningDraft("");
                    setCustomMeaningMessage(null);
                    return;
                  }

                  if (selectedEditor.meaningChoices.length >= editableMeaningChoiceCount) {
                    setCustomMeaningMessage("You can keep up to 5 meanings.");
                    return;
                  }

                  updateInboxDraft(
                    selectedItem,
                    {
                      meaningChoices: [...selectedEditor.meaningChoices, cleaned],
                      meaningChoicePartOfSpeechLabels: [
                        ...selectedEditor.meaningChoicePartOfSpeechLabels,
                        "",
                      ],
                      selectedMeaningIndexes: [
                        ...selectedEditor.selectedMeaningIndexes,
                        selectedEditor.meaningChoices.length,
                      ],
                    },
                    { syncDetail: true },
                  );
                  setCustomMeaningDraft("");
                  setCustomMeaningMessage(null);
                },
                onToggle: (index) =>
                  updateInboxDraft(
                    selectedItem,
                    {
                      selectedMeaningIndexes: toggledSelection(
                        selectedEditor.selectedMeaningIndexes,
                        index,
                      ),
                    },
                    { syncDetail: true },
                  ),
                onPartOfSpeechChange: (index, value) => {
                  const nextLabels = [...selectedEditor.meaningChoicePartOfSpeechLabels];
                  nextLabels[index] = sanitizeInlineText(value);
                  updateInboxDraft(selectedItem, {
                    meaningChoicePartOfSpeechLabels: nextLabels,
                  });
                },
                onPromoteSelection: (index) =>
                  updateInboxDraft(
                    selectedItem,
                    {
                      selectedMeaningIndexes: promotedSelection(
                        selectedEditor.selectedMeaningIndexes,
                        index,
                      ),
                    },
                    { syncDetail: true },
                  ),
                onMoveSelection: (index, direction) =>
                  updateInboxDraft(
                    selectedItem,
                    {
                      selectedMeaningIndexes: movedSelection(
                        selectedEditor.selectedMeaningIndexes,
                        index,
                        direction,
                      ),
                    },
                    { syncDetail: true },
                  ),
                onRemove: (index) => {
                  const nextMeaningState = removeIndexedChoice(
                    selectedEditor.meaningChoices,
                    selectedEditor.selectedMeaningIndexes,
                    index,
                  );
                  updateInboxDraft(
                    selectedItem,
                    {
                      meaningChoices: nextMeaningState.choices,
                      meaningChoicePartOfSpeechLabels: selectedEditor.meaningChoicePartOfSpeechLabels.filter(
                        (_, labelIndex) => labelIndex !== index,
                      ),
                      selectedMeaningIndexes: nextMeaningState.selectedIndexes,
                    },
                    { syncDetail: true },
                  );
                },
                onSelectAll: () =>
                  applyInboxChoiceSectionState(selectedItem, "meaning", {
                    ...editableChoiceSectionState(selectedEditor, "meaning"),
                    selectedIndexes: selectedEditor.meaningChoices.map((_, index) => index),
                  }),
                onKeepSelected: () =>
                  applyInboxChoiceSectionState(
                    selectedItem,
                    "meaning",
                    keepOnlySelectedEditableChoices(editableChoiceSectionState(selectedEditor, "meaning")),
                  ),
                onDedupe: () =>
                  applyInboxChoiceSectionState(
                    selectedItem,
                    "meaning",
                    dedupeEditableChoiceState(editableChoiceSectionState(selectedEditor, "meaning")),
                  ),
                onMoveChoice: (index, direction) =>
                  applyInboxChoiceSectionState(
                    selectedItem,
                    "meaning",
                    reorderEditableChoiceState(
                      editableChoiceSectionState(selectedEditor, "meaning"),
                      index,
                      index + direction,
                    ),
                  ),
              })}

              {renderEditableChoicesSection({
                title: "Example Sentence Candidates",
                selectedTitle: "Selected examples",
                choices: selectedEditor.exampleChoices,
                selectedIndexes: selectedEditor.selectedExampleIndexes,
                emptyMessage: "No example candidates yet. Refresh candidates after the dictionary preview loads.",
                customDraft: customExampleDraft,
                customMessage: customExampleMessage,
                customPlaceholder: "(Custom example)",
                onCustomDraftChange: (value) => {
                  setCustomExampleDraft(value);
                  setCustomExampleMessage(null);
                },
                onCommitCustom: () => {
                  const cleaned = sanitizeParagraphText(customExampleDraft);
                  if (!cleaned) {
                    setCustomExampleMessage(null);
                    return;
                  }

                  const existingIndex = selectedEditor.exampleChoices.findIndex(
                    (choice) => normalizedTerm(choice) === normalizedTerm(cleaned),
                  );
                  if (existingIndex >= 0) {
                    updateInboxDraft(selectedItem, {
                      selectedExampleIndexes: ensuredSelection(
                        selectedEditor.selectedExampleIndexes,
                        existingIndex,
                      ),
                    });
                    setCustomExampleDraft("");
                    setCustomExampleMessage(null);
                    return;
                  }

                  if (selectedEditor.exampleChoices.length >= editableExampleChoiceCount) {
                    setCustomExampleMessage("You can keep up to 3 example sentences.");
                    return;
                  }

                  updateInboxDraft(selectedItem, {
                    exampleChoices: [...selectedEditor.exampleChoices, cleaned],
                    selectedExampleIndexes: [
                      ...selectedEditor.selectedExampleIndexes,
                      selectedEditor.exampleChoices.length,
                    ],
                  });
                  setCustomExampleDraft("");
                  setCustomExampleMessage(null);
                },
                onToggle: (index) =>
                  updateInboxDraft(selectedItem, {
                    selectedExampleIndexes: toggledSelection(
                      selectedEditor.selectedExampleIndexes,
                      index,
                    ),
                  }),
                onPromoteSelection: (index) =>
                  updateInboxDraft(selectedItem, {
                    selectedExampleIndexes: promotedSelection(
                      selectedEditor.selectedExampleIndexes,
                      index,
                    ),
                  }),
                onMoveSelection: (index, direction) =>
                  updateInboxDraft(selectedItem, {
                    selectedExampleIndexes: movedSelection(
                      selectedEditor.selectedExampleIndexes,
                      index,
                      direction,
                    ),
                  }),
                onRemove: (index) => {
                  const nextExampleState = removeIndexedChoice(
                    selectedEditor.exampleChoices,
                    selectedEditor.selectedExampleIndexes,
                    index,
                  );
                  updateInboxDraft(selectedItem, {
                    exampleChoices: nextExampleState.choices,
                    selectedExampleIndexes: nextExampleState.selectedIndexes,
                  });
                },
                onSelectAll: () =>
                  applyInboxChoiceSectionState(selectedItem, "example", {
                    ...editableChoiceSectionState(selectedEditor, "example"),
                    selectedIndexes: selectedEditor.exampleChoices.map((_, index) => index),
                  }),
                onKeepSelected: () =>
                  applyInboxChoiceSectionState(
                    selectedItem,
                    "example",
                    keepOnlySelectedEditableChoices(editableChoiceSectionState(selectedEditor, "example")),
                  ),
                onDedupe: () =>
                  applyInboxChoiceSectionState(
                    selectedItem,
                    "example",
                    dedupeEditableChoiceState(editableChoiceSectionState(selectedEditor, "example")),
                  ),
                onMoveChoice: (index, direction) =>
                  applyInboxChoiceSectionState(
                    selectedItem,
                    "example",
                    reorderEditableChoiceState(
                      editableChoiceSectionState(selectedEditor, "example"),
                      index,
                      index + direction,
                    ),
                  ),
              })}

              <div className="desk-context-block">
                <label htmlFor="inbox-context">Original sentence</label>
                <textarea
                  id="inbox-context"
                  onChange={(event) =>
                    updateInboxActivityItem(selectedItem, {
                      context: event.target.value,
                    })
                  }
                  value={selectedItem.context ?? ""}
                />
              </div>

              <div className="desk-context-block">
                <label htmlFor="inbox-notes">Notes</label>
                <textarea
                  id="inbox-notes"
                  onChange={(event) =>
                    updateInboxDraft(selectedItem, {
                      notes: sanitizeParagraphText(event.target.value),
                    })
                  }
                  value={selectedEditor.notes}
                />
              </div>

              {renderReferenceTagsEditor({
                tags: selectedEditor.referenceTags,
                customDraft: customTagDraft,
                customMessage: customTagMessage,
                onCustomDraftChange: (value) => {
                  setCustomTagDraft(value);
                  setCustomTagMessage(null);
                },
                onCommitCustom: () => {
                  const next = appendReferenceTags(selectedEditor.referenceTags, customTagDraft);
                  if (next.nextTags !== selectedEditor.referenceTags) {
                    updateInboxDraft(selectedItem, {
                      referenceTags: next.nextTags,
                    });
                  }
                  setCustomTagMessage(next.message);
                  if (next.nextTags !== selectedEditor.referenceTags) {
                    setCustomTagDraft("");
                  }
                },
                onRemove: (index) =>
                  updateInboxDraft(selectedItem, {
                    referenceTags: selectedEditor.referenceTags.filter((_, tagIndex) => tagIndex !== index),
                  }),
              })}

              {renderEnglishDefinitionBlock({ englishDefinitions: selectedEditor.englishDefinitions })}

              {selectedEditor.inflectionLines.length > 0 ? (
                <div className="desk-info-block">
                  <h3>Inflection / Form Notes</h3>
                  <ul className="desk-plain-list">
                    {selectedEditor.inflectionLines.map((line) => (
                      <li key={line}>{line}</li>
                    ))}
                  </ul>
                </div>
              ) : null}

              {selectedEditor.referenceTags.length > 0 ? (
                <div className="desk-info-block">
                  <h3>Dictionary Tags</h3>
                  <div className="desk-chip-row">
                    {selectedEditor.referenceTags.map((tag) => (
                      <span className="soft-tag" key={tag}>
                        {tag}
                      </span>
                    ))}
                  </div>
                </div>
              ) : null}

            </>
          ) : selectedItem ? (
            <>
              <div className="desk-detail-header">
                <div>
                  <h2>{selectedItem.term}</h2>
                  <p className="desk-subtle">Selected from History</p>
                </div>
                <div className="desk-detail-actions">
                  <Link
                    className="secondary-button"
                    href={buildWorkspaceHref({
                      section: "lookup",
                      q: selectedItem.term,
                      source: kind,
                      kind: inferLookupKindFromTerm(selectedItem.term, "word"),
                      context: selectedItem.context,
                    })}
                  >
                    Open in Lookup
                  </Link>
                  <button className="secondary-button" onClick={() => openHistoryItemInQuickCapture(selectedItem)} type="button">
                    {matchingQuickCaptureDraft ? "Draft in Quick Capture" : "Edit in Quick Capture"}
                  </button>
                  <button className="secondary-button" onClick={() => moveHistoryItemToLibrary(selectedItem)} type="button">
                    {matchingLibraryEntry ? "Update Library Entry" : "Add to Library"}
                  </button>
                  {matchingLibraryEntry ? (
                    <Link
                      className="secondary-button"
                      href={buildWorkspaceHref({
                        section: "library",
                        q: matchingLibraryEntry.term,
                        source: "history",
                        kind: inferLookupKindFromTerm(matchingLibraryEntry.term, "word"),
                        context: matchingLibraryEntry.context,
                        entryId: matchingLibraryEntry.id,
                      })}
                    >
                      Open in Library
                    </Link>
                  ) : null}
                </div>
              </div>

              <div className="desk-chip-row">
                <span className="soft-tag">{reviewLevelLabel(selectedReviewState.level)}</span>
                {matchingLibraryEntry ? <span className="soft-tag">Also in Library</span> : null}
                {selectedItem.meta?.status ? (
                  <span className="soft-tag">{historyStatusLabels[selectedItem.meta.status]}</span>
                ) : null}
              </div>

              <div className="desk-info-block">
                <h3>Lookup Record</h3>
                <p {...cjkTextProps(selectedItem.detail)}>{selectedItem.detail}</p>
                {selectedItem.context ? <small {...cjkTextProps(selectedItem.context)}>{selectedItem.context}</small> : null}
              </div>

              {selectedItem.meta ? (
                <div className="desk-info-block">
                  <h3>This Lookup Record</h3>
                  <ul className="desk-plain-list">
                    {selectedItem.meta.originalQuery &&
                    normalizedTerm(selectedItem.meta.originalQuery) !== normalizedTerm(selectedItem.term) ? (
                      <li>Original query: {selectedItem.meta.originalQuery}</li>
                    ) : null}
                    {selectedItem.meta.sourceLabel ? <li>Source: {selectedItem.meta.sourceLabel}</li> : null}
                    {selectedItem.meta.lookupKind ? <li>Lookup kind: {lookupKindLabels[selectedItem.meta.lookupKind]}</li> : null}
                    {selectedItem.meta.lookupMode ? <li>Lookup mode: {historyLookupModeLabels[selectedItem.meta.lookupMode]}</li> : null}
                    {selectedItem.meta.inboxAction ? (
                      <li>Study action: {historyStudyActionLabels[selectedItem.meta.inboxAction]}</li>
                    ) : null}
                    {selectedItem.meta.modelName ? <li>Model: {selectedItem.meta.modelName}</li> : null}
                    {selectedItem.meta.status ? (
                      <li>Status: {historyStatusLabels[selectedItem.meta.status]}</li>
                    ) : null}
                    {selectedItem.meta.statusMessage ? <li>Note: {selectedItem.meta.statusMessage}</li> : null}
                  </ul>
                </div>
              ) : null}

              {relatedHistoryItems.length > 0 ? (
                <div className="desk-info-block">
                  <h3>Related lookup trail</h3>
                  <div className="desk-review-history">
                    {relatedHistoryItems.map((item) => (
                      <Link
                        className="desk-review-history-card desk-review-history-button"
                        href={buildWorkspaceHref({
                          section: "history",
                          q: item.term,
                          source: "history",
                          kind: inferLookupKindFromTerm(item.term, "word"),
                          context: item.context,
                          itemId: item.id,
                        })}
                        key={item.id}
                      >
                        <strong>{item.meta?.originalQuery || item.term}</strong>
                        <span>{formatRelativeTime(item.savedAt)}</span>
                        <p {...cjkTextProps(item.detail)}>{item.detail}</p>
                        {item.meta?.status ? (
                          <small>
                            {historyStatusLabels[item.meta.status]}
                            {item.meta.statusMessage ? ` · ${item.meta.statusMessage}` : ""}
                          </small>
                        ) : null}
                      </Link>
                    ))}
                  </div>
                </div>
              ) : null}

              {renderSnapshotBlocks(selectedSnapshot, {
                status: lookupStatusForTerm(selectedItem.term),
                fallbackDetail: selectedItem.detail,
                context: selectedItem.context,
              })}
            </>
          ) : (
            renderNativeEmptyPanel(
              items.length > 0 ? "Select an item" : "No item selected",
              kind === "inbox"
                ? "Select an Inbox entry."
                : "Select a History record.",
              firstVisibleItem ? (
                <Link
                  className="secondary-button"
                  href={buildWorkspaceHref({
                    section: kind,
                    q: firstVisibleItem.term,
                    source: kind,
                    kind: inferLookupKindFromTerm(firstVisibleItem.term, "word"),
                    context: firstVisibleItem.context,
                    itemId: firstVisibleItem.id,
                  })}
                >
                  Open First Visible
                </Link>
              ) : null,
            )
          )}
        </section>
      </WorkspaceContentGrid>
    );
  }

  function renderLibrarySection(): ReactNode {
    const selectedReviewState = selectedLibraryEntry
      ? reviewStateForTerm(selectedLibraryEntry.term, reviewStateMap)
      : defaultReviewState();
    const hasLibrarySearch = librarySearch.trim().length > 0;
    const hasLibraryLevelFilter = libraryLevelFilter !== "all";
    const visibleDuplicateCount = filteredLibraryEntries.filter(
      (entry) => (libraryDuplicateCounts.get(entry.id) ?? 0) > 0,
    ).length;
    const featuredLibraryEntry = selectedLibraryEntry ?? filteredLibraryEntries[0] ?? null;
    const featuredLibraryDigest = featuredLibraryEntry ? libraryDigestById[featuredLibraryEntry.id] ?? null : null;
    const selectedLibraryDigest = selectedLibraryEntry ? libraryDigestById[selectedLibraryEntry.id] ?? null : null;

    return (
      <WorkspaceContentGrid
        layoutPreference={workspacePreferences.workspacePaneLayoutPreference}
        onResetLayout={resetWorkspaceLayout}
        onResizeStart={(event) => beginWorkspaceResize(event, "contentRailWidth")}
      >
        <section className="app-panel desk-form-panel">
          <div className="desk-native-field-grid">
            <label htmlFor="library-collection">Phrase</label>
            <select
              id="library-collection"
              onChange={(event) => setLibraryFilter(event.target.value as LibraryFilter)}
              value={libraryFilter}
            >
              <option value="all">{libraryFilterLabels.all} · {libraryEntries.length}</option>
              <option value="favorites">{libraryFilterLabels.favorites} · {reviewSourceCounts.favorites}</option>
              {customLibraryCollections.length > 0 ? (
                <optgroup label="Custom collections">
                  {customLibraryCollections.map((arrangement) => (
                    <option key={arrangement.id} value={`saved:${arrangement.id}`}>
                      {arrangement.name} · {arrangement.entryIds.length}
                    </option>
                  ))}
                </optgroup>
              ) : null}
              {savedReadingArrangements.length > 0 ? (
                <optgroup label="Saved reading orders">
                  {savedReadingArrangements.map((arrangement) => (
                    <option key={arrangement.id} value={`saved:${arrangement.id}`}>
                      {arrangement.name} · {arrangement.entryIds.length}
                    </option>
                  ))}
                </optgroup>
              ) : null}
            </select>
          </div>

          <div className="desk-input-row">
            <input
              onChange={(event) => setLibrarySearch(event.target.value)}
              placeholder="Search English or Chinese meaning"
              value={librarySearch}
            />
          </div>

          <div className="desk-native-control-row desk-native-control-row--wrap">
            <label className="desk-sort-label" htmlFor="library-level-filter">
              Familiarity filter
            </label>
            <select
              id="library-level-filter"
              onChange={(event) => setLibraryLevelFilter(event.target.value as LibraryLevelFilter)}
              value={libraryLevelFilter}
            >
              <option value="all">All</option>
              {reviewLevelOptions.map((level) => (
                <option key={level} value={String(level)}>
                  {reviewLevelLabel(level)}
                </option>
              ))}
            </select>

            <label className="desk-sort-label" htmlFor="library-sort">
              Sort
            </label>
            <select
              disabled={Boolean(arrangementFilterId(libraryFilter))}
              id="library-sort"
              onChange={(event) => setLibrarySort(event.target.value as LibrarySortOption)}
              value={librarySort}
            >
              <option value="updatedNewest">Recently updated</option>
              <option value="updatedOldest">Oldest updated</option>
              <option value="weakestFirst">Weakest first</option>
              <option value="alphabetical">Alphabetical</option>
            </select>
            {arrangementFilterId(libraryFilter) ? (
              <small>Fixed order</small>
            ) : null}

            <label className="desk-checkbox-row" htmlFor="library-clean-mode-toggle">
              <input
                checked={workspacePreferences.isLibraryCleanMode}
                id="library-clean-mode-toggle"
                onChange={(event) => setLibraryCleanMode(event.target.checked)}
                type="checkbox"
              />
              <span>Clean view</span>
            </label>

            <details className="desk-native-menu desk-native-menu--compact">
              <summary>
                <span>Save</span>
                <strong>Current arrangement</strong>
              </summary>
              <div className="desk-native-menu-panel">
                <input
                  onChange={(event) => setArrangementNameDraft(event.target.value)}
                  placeholder={
                    activeSavedArrangement
                      ? activeSavedArrangement.name
                      : `Arrangement ${savedLibraryArrangements.length + 1}`
                  }
                  value={arrangementNameDraft}
                />
                <button
                  className="secondary-button"
                  disabled={filteredLibraryEntries.length === 0}
                  onClick={saveCurrentLibraryArrangement}
                  type="button"
                >
                  Save
                </button>
              </div>
            </details>

            {libraryEntries.length > 0 && !workspacePreferences.isLibraryCleanMode ? (
              <button
                className="secondary-button"
                onClick={() => {
                  setIsLibrarySelecting((current) => !current);
                  setSelectedLibraryIds(new Set());
                }}
                type="button"
              >
                {isLibrarySelecting ? "Done" : "Multi-select"}
              </button>
            ) : null}
          </div>

          {activeSavedArrangement ? (
            <details className="desk-native-menu">
              <summary>
                <span>{activeCustomCollection ? "Custom collection" : "Saved arrangement"}</span>
                <strong>{activeSavedArrangement.name}</strong>
              </summary>
              <div className="desk-native-menu-panel">
                {activeSavedArrangement.mode === "arrangement" ? (
                  <button
                    className="secondary-button"
                    disabled={filteredLibraryEntries.length === 0 || hasLibrarySearch}
                    onClick={updateActiveLibraryArrangement}
                    type="button"
                  >
                    Update
                  </button>
                ) : null}
                <button className="secondary-button" onClick={renameActiveLibraryArrangement} type="button">
                  Rename
                </button>
                <button className="secondary-button" onClick={deleteActiveLibraryArrangement} type="button">
                  Delete
                </button>
              </div>
            </details>
          ) : null}

          {isLibrarySelecting ? (
            <div className="desk-batch-bar">
              <span>
                {selectedLibraryIds.size} selected · {filteredLibraryEntries.length} visible
              </span>
              <div className="desk-chip-row">
                <button className="secondary-button" onClick={toggleSelectAllLibrary} type="button">
                  {selectedLibraryIds.size === filteredLibraryEntries.length && filteredLibraryEntries.length > 0
                    ? "Clear all"
                    : "Select all"}
                </button>
                <button
                  className="secondary-button"
                  disabled={selectedLibraryIds.size === 0}
                  onClick={deleteLibrarySelection}
                  type="button"
                >
                  Delete Selected
                </button>
              </div>
            </div>
          ) : null}

          {filteredLibraryEntries.length > 0 ? (
            <div className="desk-review-picker">
              {filteredLibraryEntries.map((entry) => {
                const reviewState = reviewStateForTerm(entry.term, reviewStateMap);
                const duplicateCount = libraryDuplicateCounts.get(entry.id) ?? 0;
                const digest = libraryDigestById[entry.id];

                return (
                  <div className="desk-selectable-row" key={entry.id}>
                    {isLibrarySelecting ? (
                      <button
                        className={selectedLibraryIds.has(entry.id) ? "desk-select-toggle is-selected" : "desk-select-toggle"}
                        onClick={() => toggleLibrarySelection(entry.id)}
                        type="button"
                      >
                        {selectedLibraryIds.has(entry.id) ? "Selected" : "Select"}
                      </button>
                    ) : null}
                    <Link
                      className={
                        selectedLibraryEntry?.id === entry.id
                          ? "desk-review-picker-row is-selected"
                          : "desk-review-picker-row"
                      }
                      href={buildWorkspaceHref({
                        section: "library",
                        q: entry.term,
                        source: "library",
                        kind: inferLookupKindFromTerm(entry.term, "word"),
                        context: entry.context,
                        entryId: entry.id,
                      })}
                    >
                      <div className="desk-review-picker-head">
                        <strong>{entry.term}</strong>
                        <span>{reviewLevelLabel(reviewState.level)}</span>
                      </div>
                      <p {...cjkTextProps(digest?.primaryMeaning ?? entry.detail)}>
                        {digest?.primaryMeaning ?? entry.detail}
                      </p>
                      {digest?.primaryExample ? (
                        <small>Example: {digest.primaryExample}</small>
                      ) : entry.context ? (
                        <small {...cjkTextProps(entry.context)}>{entry.context}</small>
                      ) : null}
                      {entry.favorite ? <small>Favorite</small> : null}
                      {duplicateCount > 0 ? <small>{duplicateCount} duplicate{duplicateCount === 1 ? "" : "s"}</small> : null}
                    </Link>
                  </div>
                );
              })}
            </div>
          ) : (
            renderNativeEmptyPanel(
              hasLibrarySearch
                ? "This shelf view is filtered down to nothing."
                : hasLibraryLevelFilter
                  ? `No ${reviewLevelLabel(Number(libraryLevelFilter) as ReviewLevel)} entries are visible.`
                : libraryFilter === "favorites"
                  ? "No favorites are visible yet."
                  : activeSavedArrangement
                    ? activeCustomCollection
                      ? "This collection is empty right now."
                      : "This saved arrangement has no visible entries."
                    : "Library has nothing visible yet.",
              hasLibrarySearch
                ? "Clear the current search to bring the matching shelf items back."
                : hasLibraryLevelFilter
                  ? "Clear the familiarity filter to show the full shelf again."
                : activeSavedArrangement
                  ? "Switch back to the full shelf or refill this saved view from current Library entries."
                  : "Add something from Lookup or Quick Capture and it will arrive here as a curated entry with context, examples, and review state.",
              (
                <>
                  {hasLibrarySearch ? (
                    <button className="secondary-button" onClick={() => setLibrarySearch("")} type="button">
                      Clear Search
                    </button>
                  ) : null}
                  {libraryFilter !== "all" ? (
                    <button className="secondary-button" onClick={() => setLibraryFilter("all")} type="button">
                      Show All Library
                    </button>
                  ) : null}
                  {hasLibraryLevelFilter ? (
                    <button className="secondary-button" onClick={() => setLibraryLevelFilter("all")} type="button">
                      Clear Familiarity
                    </button>
                  ) : null}
                  <button className="secondary-button" onClick={openQuickCapture} type="button">
                    Open Quick Capture
                  </button>
                </>
              ),
            )
          )}
        </section>

        <section className="app-panel desk-detail-panel">
          {selectedLibraryEntry ? (
            workspacePreferences.isLibraryCleanMode ? (
              <>
                <div className="desk-detail-header">
                  <div>
                    <h2>{selectedLibraryEntry.term}</h2>
                    <p className="desk-subtle">
                      {lookupKindLabels[selectedLibraryEntry.kind]} · {reviewLevelLabel(selectedReviewState.level)}
                    </p>
                  </div>
                  {selectedLibraryEntry.favorite ? <span className="soft-tag">Favorite</span> : null}
                </div>

                <div className="desk-chip-row">
                  <span className="soft-tag">{reviewLevelLabel(selectedReviewState.level)}</span>
                  <span className="soft-tag">
                    {selectedReviewState.reviewCount > 0
                      ? `${selectedReviewState.reviewCount} review${selectedReviewState.reviewCount === 1 ? "" : "s"}`
                      : "Not reviewed yet"}
                  </span>
                  {selectedReviewState.lastReviewedAt ? (
                    <span className="soft-tag">Last reviewed {formatRelativeTime(selectedReviewState.lastReviewedAt)}</span>
                  ) : null}
                </div>

                {libraryStudyMeaningLines(selectedLibraryEntry).length > 0 ? (
                  <div className="desk-info-block">
                    <h3>Current Study Meanings</h3>
                    <ul className="desk-plain-list">
                      {libraryStudyMeaningLines(selectedLibraryEntry).map((line) => (
                        <li key={line} {...cjkTextProps(line)}>
                          {line}
                        </li>
                      ))}
                    </ul>
                  </div>
                ) : null}

                {libraryStudyExampleLines(selectedLibraryEntry).length > 0 ? (
                  <div className="desk-info-block">
                    <h3>Current Study Examples</h3>
                    <div className="desk-plain-list">
                      {libraryStudyExampleLines(selectedLibraryEntry).map((line) => (
                        <p key={line} {...cjkTextProps(line)}>
                          {line}
                        </p>
                      ))}
                    </div>
                  </div>
                ) : null}

                {selectedLibraryEntry.context.trim() ? (
                  <div className="desk-info-block">
                    <h3>Original Context</h3>
                    <p {...cjkTextProps(selectedLibraryEntry.context)}>{selectedLibraryEntry.context}</p>
                  </div>
                ) : null}

                {renderEnglishDefinitionBlock({ englishDefinitions: selectedLibraryEntry.englishDefinitions })}

                {selectedLibraryEntry.inflectionLines.length > 0 ? (
                  <div className="desk-info-block">
                    <h3>Inflection / Form Notes</h3>
                    <ul className="desk-plain-list">
                      {selectedLibraryEntry.inflectionLines.map((line) => (
                        <li key={line}>{line}</li>
                      ))}
                    </ul>
                  </div>
                ) : null}

                {selectedLibraryEntry.notes.trim() ? (
                  <div className="desk-info-block">
                    <h3>Notes</h3>
                    <p {...cjkTextProps(selectedLibraryEntry.notes)}>{selectedLibraryEntry.notes}</p>
                  </div>
                ) : null}
              </>
            ) : (
            <>
              <div className="desk-detail-header">
                <div>
                  <h2>{selectedLibraryEntry.term}</h2>
                  <p className="desk-subtle">
                    {selectedLibraryEntry.favorite ? "Favorite entry" : "Confirmed library entry"}
                  </p>
                </div>
                <div className="desk-detail-actions">
                  {isPronounceableEnglish(selectedLibraryEntry.term) ? (
                    <button
                      className="secondary-button"
                      onClick={() => playPronunciation(selectedLibraryEntry.term)}
                      type="button"
                    >
                      Play Audio
                    </button>
                  ) : null}
                  <Link
                    className="secondary-button"
                    href={buildWorkspaceHref({
                      section: "lookup",
                      q: selectedLibraryEntry.term,
                      source: "library",
                      kind: inferLookupKindFromTerm(selectedLibraryEntry.term, "word"),
                      context: selectedLibraryEntry.context,
                    })}
                  >
                    Open in Lookup
                  </Link>
                  <button
                    className="secondary-button"
                    onClick={() => refreshLibraryEntryFromSnapshot(selectedLibraryEntry)}
                    type="button"
                  >
                    Refresh Candidates
                  </button>
                  <button
                    className="secondary-button"
                    onClick={() =>
                      updateLibraryField(selectedLibraryEntry.id, {
                        favorite: !selectedLibraryEntry.favorite,
                      })
                    }
                    type="button"
                  >
                    {selectedLibraryEntry.favorite ? "Unfavorite" : "Favorite"}
                  </button>
                  <button
                    className="secondary-button"
                    onClick={() => openLibraryEntryInQuickCapture(selectedLibraryEntry)}
                    type="button"
                  >
                    Open in Quick Capture
                  </button>
                  {selectedLibraryDuplicates.length > 0 ? (
                    <button
                      className="secondary-button"
                      onClick={() => mergeLibraryDuplicates(selectedLibraryEntry.id)}
                      type="button"
                    >
                      Merge {selectedLibraryDuplicates.length} duplicate
                      {selectedLibraryDuplicates.length === 1 ? "" : "s"}
                    </button>
                  ) : null}
                  {activeSavedArrangement ? (
                    <>
                      <button
                        className="secondary-button"
                        onClick={() => moveSelectedLibraryEntryWithinArrangement(-1)}
                        type="button"
                      >
                        Move Up
                      </button>
                      <button
                        className="secondary-button"
                        onClick={() => moveSelectedLibraryEntryWithinArrangement(1)}
                        type="button"
                      >
                        Move Down
                      </button>
                    </>
                  ) : null}
                  <button className="secondary-button" onClick={() => deleteLibraryEntry(selectedLibraryEntry.id)} type="button">
                    Remove
                  </button>
                </div>
              </div>

              <div className="desk-entry-editor-meta">
                <div className="desk-segment-row" role="tablist" aria-label="Library entry type">
                  {(["word", "phrase", "sentence"] as LookupKind[]).map((entryKind) => (
                    <button
                      aria-pressed={selectedLibraryEntry.kind === entryKind}
                      className={selectedLibraryEntry.kind === entryKind ? "desk-segment is-active" : "desk-segment"}
                      key={entryKind}
                      onClick={() =>
                        updateLibraryField(selectedLibraryEntry.id, {
                          kind: entryKind,
                        })
                      }
                      type="button"
                    >
                      {lookupKindLabels[entryKind]}
                    </button>
                  ))}
                </div>
                <div className="desk-entry-select-group">
                  <label htmlFor="library-familiarity">Familiarity</label>
                  <select
                    id="library-familiarity"
                    onChange={(event) =>
                      setReviewLevelForTerm(selectedLibraryEntry.term, Number(event.target.value) as ReviewLevel)
                    }
                    value={selectedReviewState.level}
                  >
                    {reviewLevelOptions.map((level) => (
                      <option key={level} value={level}>
                        {reviewLevelLabel(level)}
                      </option>
                    ))}
                  </select>
                </div>
              </div>

              <div className="desk-chip-row">
                {selectedLibraryEntry.favorite ? <span className="soft-tag">Favorite</span> : null}
                {selectedLibraryEntry.partOfSpeech ? <span className="soft-tag">{selectedLibraryEntry.partOfSpeech}</span> : null}
                <span className="soft-tag">{reviewLevelLabel(selectedReviewState.level)}</span>
                <span className="soft-tag">{selectedReviewState.reviewCount} reviews</span>
                {selectedLibraryDuplicates.length > 0 ? (
                  <span className="soft-tag">
                    {selectedLibraryDuplicates.length} duplicate
                    {selectedLibraryDuplicates.length === 1 ? "" : "s"}
                  </span>
                ) : null}
                {selectedReviewState.lastReviewedAt ? (
                  <span className="soft-tag">Last reviewed {formatRelativeTime(selectedReviewState.lastReviewedAt)}</span>
                ) : (
                  <span className="soft-tag">Not reviewed yet</span>
                )}
              </div>

              {selectedLibraryDuplicates.length > 0 ? (
                <div className="desk-info-block">
                  <h3>Duplicate entries</h3>
                  <p>
                    {selectedLibraryDuplicates.length} other library entr
                    {selectedLibraryDuplicates.length === 1 ? "y shares" : "ies share"} this headword.
                    Merge will keep the current card and fold in meanings, examples, notes, tags, and favorite state.
                  </p>
                  <div className="desk-duplicate-list">
                    {selectedLibraryDuplicates.map((duplicate) => (
                      <div className="desk-duplicate-card" key={duplicate.id}>
                        <strong>{duplicate.detail}</strong>
                        {duplicate.context ? <small>{duplicate.context}</small> : null}
                        <div className="desk-chip-row">
                          <span className="soft-tag">Updated {formatRelativeTime(duplicate.updatedAt)}</span>
                          {duplicate.favorite ? <span className="soft-tag">Favorite</span> : null}
                          <Link
                            className="secondary-button"
                            href={buildWorkspaceHref({
                              section: "library",
                              q: duplicate.term,
                              source: "library",
                              kind: inferLookupKindFromTerm(duplicate.term, "word"),
                              context: duplicate.context,
                              entryId: duplicate.id,
                            })}
                          >
                            Open This Duplicate
                          </Link>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              ) : null}

              {activeSavedArrangement ? (
                <div className="desk-info-block">
                  <h3>{activeCustomCollection ? "Custom collection" : "Saved arrangement"}</h3>
                  <p>
                    {activeCustomCollection
                      ? `You are editing the custom collection "${activeCustomCollection.name}". Move this entry up or down to tune the order inside this collection.`
                      : `You are editing the saved arrangement "${activeSavedArrangement.name}". Move this entry up or down to tune the reading order for this collection.`}
                  </p>
                </div>
              ) : null}

              {customLibraryCollections.length > 0 ? (
                <div className="desk-info-block">
                  <h3>Collection membership</h3>
                  <details className="desk-native-menu">
                    <summary>
                      <span>Collections</span>
                      <strong>
                        {customLibraryCollections
                          .filter((collection) => collection.entryIds.includes(selectedLibraryEntry.id))
                          .map((collection) => collection.name)
                          .join(" · ") || "None"}
                      </strong>
                    </summary>
                    <div className="desk-native-menu-panel">
                      {customLibraryCollections.map((collection) => {
                        const includesEntry = collection.entryIds.includes(selectedLibraryEntry.id);

                        return (
                          <label className="desk-menu-check-row" key={collection.id}>
                            <input
                              checked={includesEntry}
                              onChange={() => toggleLibraryEntryInCollection(selectedLibraryEntry.id, collection.id)}
                              type="checkbox"
                            />
                            <span>{collection.name}</span>
                          </label>
                        );
                      })}
                    </div>
                  </details>
                </div>
              ) : null}

              <div className="desk-info-block">
                <div className="desk-detail-header">
                  <div>
                    <h3>Saved Meaning Candidates</h3>
                    <p className="desk-subtle">Edit each saved sense directly. The Library keeps the confirmed study meanings only.</p>
                  </div>
                  <button
                    className="secondary-button"
                    onClick={() => addLibraryMeaningCandidate(selectedLibraryEntry)}
                    type="button"
                  >
                    Add Candidate
                  </button>
                </div>
                <div className="desk-example-stack">
                  {editableMeaningCandidatesForEntry(selectedLibraryEntry).map((candidate, index, candidates) => (
                    <div className="desk-example-card" key={candidate.id}>
                      <div className="desk-chip-row">
                        <span className="soft-tag">Saved</span>
                        <input
                          aria-label={`Library POS ${index + 1}`}
                          onChange={(event) =>
                            updateLibraryMeaningCandidate(selectedLibraryEntry, index, {
                              partOfSpeech: sanitizeInlineText(event.target.value),
                            })
                          }
                          placeholder="POS"
                          value={candidate.partOfSpeech}
                        />
                      </div>
                      <textarea
                        aria-label={`Library meaning ${index + 1}`}
                        onChange={(event) =>
                          updateLibraryMeaningCandidate(selectedLibraryEntry, index, {
                            meaning: event.target.value,
                          })
                        }
                        placeholder="Refine this meaning."
                        value={candidate.meaning}
                      />
                      <div className="desk-chip-row">
                        <button
                          className="secondary-button"
                          disabled={index === 0}
                          onClick={() => moveLibraryMeaningCandidate(selectedLibraryEntry, index, -1)}
                          type="button"
                        >
                          Move Up
                        </button>
                        <button
                          className="secondary-button"
                          disabled={index === candidates.length - 1}
                          onClick={() => moveLibraryMeaningCandidate(selectedLibraryEntry, index, 1)}
                          type="button"
                        >
                          Move Down
                        </button>
                        <button
                          className="secondary-button"
                          onClick={() => removeLibraryMeaningCandidate(selectedLibraryEntry, index)}
                          type="button"
                        >
                          Delete
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
                {customMeaningMessage ? <p className="desk-footer-note">{customMeaningMessage}</p> : null}
              </div>

              {renderEditableChoicesSection({
                title: "Saved Example Sentences",
                selectedTitle: "Saved examples",
                choices: selectedLibraryEntry.exampleChoices,
                selectedIndexes: selectedLibraryEntry.selectedExampleIndexes,
                emptyMessage: "No saved examples on this entry yet.",
                customDraft: customExampleDraft,
                customMessage: customExampleMessage,
                customPlaceholder: "(Custom example)",
                lockedSelection: true,
                onCustomDraftChange: (value) => {
                  setCustomExampleDraft(value);
                  setCustomExampleMessage(null);
                },
                onCommitCustom: () => {
                  const cleaned = sanitizeParagraphText(customExampleDraft);
                  if (!cleaned) {
                    setCustomExampleMessage(null);
                    return;
                  }

                  const existingIndex = selectedLibraryEntry.exampleChoices.findIndex(
                    (choice) => normalizedTerm(choice) === normalizedTerm(cleaned),
                  );
                  if (existingIndex >= 0) {
                    updateLibraryField(selectedLibraryEntry.id, {
                      selectedExampleIndexes: ensuredSelection(
                        selectedLibraryEntry.selectedExampleIndexes,
                        existingIndex,
                      ),
                    });
                    setCustomExampleDraft("");
                    setCustomExampleMessage(null);
                    return;
                  }

                  if (selectedLibraryEntry.exampleChoices.length >= editableExampleChoiceCount) {
                    setCustomExampleMessage("You can keep up to 3 example sentences.");
                    return;
                  }

                  updateLibraryField(selectedLibraryEntry.id, {
                    exampleChoices: [...selectedLibraryEntry.exampleChoices, cleaned],
                    selectedExampleIndexes: [
                      ...selectedLibraryEntry.selectedExampleIndexes,
                      selectedLibraryEntry.exampleChoices.length,
                    ],
                  });
                  setCustomExampleDraft("");
                  setCustomExampleMessage(null);
                },
                onToggle: (index) =>
                  updateLibraryField(selectedLibraryEntry.id, {
                    selectedExampleIndexes: toggledSelection(
                      selectedLibraryEntry.selectedExampleIndexes,
                      index,
                    ),
                  }),
                onPromoteSelection: (index) =>
                  updateLibraryField(selectedLibraryEntry.id, {
                    selectedExampleIndexes: promotedSelection(
                      selectedLibraryEntry.selectedExampleIndexes,
                      index,
                    ),
                  }),
                onMoveSelection: (index, direction) =>
                  updateLibraryField(selectedLibraryEntry.id, {
                    selectedExampleIndexes: movedSelection(
                      selectedLibraryEntry.selectedExampleIndexes,
                      index,
                      direction,
                    ),
                  }),
                onRemove: (index) => {
                  const nextExampleState = removeIndexedChoice(
                    selectedLibraryEntry.exampleChoices,
                    selectedLibraryEntry.selectedExampleIndexes,
                    index,
                  );
                  updateLibraryField(selectedLibraryEntry.id, {
                    exampleChoices: nextExampleState.choices,
                    selectedExampleIndexes: nextExampleState.selectedIndexes,
                  });
                },
                onSelectAll: () =>
                  applyLibraryChoiceSectionState(selectedLibraryEntry.id, "example", {
                    ...editableChoiceSectionState(selectedLibraryEntry, "example"),
                    selectedIndexes: selectedLibraryEntry.exampleChoices.map((_, index) => index),
                  }),
                onKeepSelected: () =>
                  applyLibraryChoiceSectionState(
                    selectedLibraryEntry.id,
                    "example",
                    keepOnlySelectedEditableChoices(editableChoiceSectionState(selectedLibraryEntry, "example")),
                  ),
                onDedupe: () =>
                  applyLibraryChoiceSectionState(
                    selectedLibraryEntry.id,
                    "example",
                    dedupeEditableChoiceState(editableChoiceSectionState(selectedLibraryEntry, "example")),
                  ),
                onMoveChoice: (index, direction) =>
                  applyLibraryChoiceSectionState(
                    selectedLibraryEntry.id,
                    "example",
                    reorderEditableChoiceState(
                      editableChoiceSectionState(selectedLibraryEntry, "example"),
                      index,
                      index + direction,
                    ),
                  ),
              })}

              <div className="desk-context-block">
                <label htmlFor="library-context">Original context</label>
                <textarea
                  id="library-context"
                  onChange={(event) =>
                    updateLibraryField(selectedLibraryEntry.id, {
                      context: sanitizeParagraphText(event.target.value),
                    })
                  }
                  value={selectedLibraryEntry.context}
                />
              </div>

              <div className="desk-context-block">
                <label htmlFor="library-notes">Notes</label>
                <textarea
                  id="library-notes"
                  onChange={(event) =>
                    updateLibraryField(selectedLibraryEntry.id, {
                      notes: sanitizeParagraphText(event.target.value),
                    })
                  }
                  value={selectedLibraryEntry.notes}
                />
              </div>

              {renderReferenceTagsEditor({
                tags: selectedLibraryEntry.referenceTags,
                customDraft: customTagDraft,
                customMessage: customTagMessage,
                onCustomDraftChange: (value) => {
                  setCustomTagDraft(value);
                  setCustomTagMessage(null);
                },
                onCommitCustom: () => {
                  const next = appendReferenceTags(selectedLibraryEntry.referenceTags, customTagDraft);
                  if (next.nextTags !== selectedLibraryEntry.referenceTags) {
                    updateLibraryField(selectedLibraryEntry.id, {
                      referenceTags: next.nextTags,
                    });
                  }
                  setCustomTagMessage(next.message);
                  if (next.nextTags !== selectedLibraryEntry.referenceTags) {
                    setCustomTagDraft("");
                  }
                },
                onRemove: (index) =>
                  updateLibraryField(selectedLibraryEntry.id, {
                    referenceTags: selectedLibraryEntry.referenceTags.filter((_, tagIndex) => tagIndex !== index),
                  }),
              })}

              {renderEnglishDefinitionBlock({ englishDefinitions: selectedLibraryEntry.englishDefinitions })}

              {selectedLibraryEntry.inflectionLines.length > 0 ? (
                <div className="desk-info-block">
                  <h3>Inflection / Form Notes</h3>
                  <ul className="desk-plain-list">
                    {selectedLibraryEntry.inflectionLines.map((line) => (
                      <li key={line}>{line}</li>
                    ))}
                  </ul>
                </div>
              ) : null}

              {selectedLibraryEntry.referenceTags.length > 0 ? (
                <div className="desk-info-block">
                  <h3>Dictionary Tags</h3>
                  <div className="desk-chip-row">
                    {selectedLibraryEntry.referenceTags.map((tag) => (
                      <span className="soft-tag" key={tag}>
                        {tag}
                      </span>
                    ))}
                  </div>
                </div>
              ) : null}

            </>
            )
          ) : (
            renderNativeEmptyPanel(
              featuredLibraryEntry ? "Select a library entry" : "Library is empty",
              featuredLibraryEntry
                ? "Select a saved entry."
                : "Add something from Lookup or Quick Capture.",
              featuredLibraryEntry ? (
                <Link
                  className="secondary-button"
                  href={buildWorkspaceHref({
                    section: "library",
                    q: featuredLibraryEntry.term,
                    source: "library",
                    kind: inferLookupKindFromTerm(featuredLibraryEntry.term, "word"),
                    context: featuredLibraryEntry.context,
                    entryId: featuredLibraryEntry.id,
                  })}
                >
                  Open First Visible
                </Link>
              ) : (
                <button className="secondary-button" onClick={openQuickCapture} type="button">
                  Open Quick Capture
                </button>
              ),
            )
          )}
        </section>
      </WorkspaceContentGrid>
    );
  }

  function renderReviewHistoryPanel(): ReactNode {
    const hasActiveHistoryFilters =
      reviewHistorySearch.trim().length > 0 ||
      reviewHistorySourceFilter !== "all" ||
      reviewHistoryDecisionFilter !== "all";
    const weakHistoryCount = reviewHistory.filter(isWeakReviewRecord).length;
    const stableHistoryCount = reviewHistory.filter((record) => isStableReviewDecision(record.decision)).length;
    const latestWeakRecord = reviewHistory.find(isWeakReviewRecord) ?? null;

    if (filteredReviewHistory.length === 0) {
      return renderNativeEmptyPanel(
        reviewHistory.length === 0 ? "No review rounds yet" : "No review rounds match",
        reviewHistory.length === 0
          ? "Complete a round first."
          : "Clear the filters.",
        hasActiveHistoryFilters ? (
          <button
            className="secondary-button"
            onClick={() => {
              setReviewHistorySearch("");
              setReviewHistorySourceFilter("all");
              setReviewHistoryDecisionFilter("all");
            }}
            type="button"
          >
            Clear Filters
          </button>
        ) : null,
      );
    }

    if (selectedReviewRound) {
      return (
        <div className="desk-review-history-detail">
          <button className="secondary-button" onClick={() => setSelectedReviewRoundId(null)} type="button">
            Back to rounds
          </button>
          <div className="desk-info-block">
            <h3>Round summary</h3>
            <p>
              {selectedReviewRound.items.length} cards · {reviewSourceSummary(selectedReviewRound.sourceKinds)}
            </p>
          </div>
          <div className="desk-review-history">
            {selectedReviewRound.items.map((record, index) => (
              <article className="desk-review-history-card" key={`${record.sessionId}-${record.candidateId}-${record.answeredAt}`}>
                <strong>
                  {index + 1}. {record.term}
                </strong>
                <span>{record.promptTitle}</span>
                <p>
                  {reviewDecisionLabel(record.decision)} ·{" "}
                  {record.isHistoryOnly
                    ? "history only"
                    : `${reviewLevelLabel(record.reviewLevelBefore ?? 0)} -> ${reviewLevelLabel(record.reviewLevelAfter ?? 0)}`}
                </p>
                <small {...cjkTextProps(record.meaning)}>
                  {record.partOfSpeech ? `${record.partOfSpeech} · ${record.meaning}` : record.meaning}
                </small>
                {record.submittedAnswer ? <small>Your answer: {record.submittedAnswer}</small> : null}
                {record.example ? <small>Example: {record.example}</small> : null}
                {record.context ? <small>Context: {record.context}</small> : null}
                {record.notes ? <small>Notes: {record.notes}</small> : null}
              </article>
            ))}
          </div>
        </div>
      );
    }

    return (
      <>
        {reviewHistory.length > 0 ? (
          <div className="desk-info-block">
            <h3>History analysis</h3>
            <div className="desk-library-trait-grid">
              <div className="desk-mini-stat-card">
                <span>Cards</span>
                <strong>{reviewHistory.length}</strong>
              </div>
              <div className="desk-mini-stat-card">
                <span>Stable</span>
                <strong>{stableHistoryCount}</strong>
              </div>
              <div className="desk-mini-stat-card">
                <span>Weak</span>
                <strong>{weakHistoryCount}</strong>
              </div>
              <div className="desk-mini-stat-card">
                <span>Rounds</span>
                <strong>{groupedReviewHistory.length}</strong>
              </div>
            </div>
            {latestWeakRecord ? (
              <p className="desk-library-caption">
                Latest weak card: {latestWeakRecord.term} · {reviewDecisionLabel(latestWeakRecord.decision)}
              </p>
            ) : null}
            {reviewMistakeClusters.length > 0 ? (
              <div className="desk-chip-row">
                {reviewMistakeClusters.map((cluster) => (
                  <span className="soft-tag" key={`${cluster.detail}-${cluster.label}`}>
                    {cluster.detail}: {cluster.label} · {cluster.count}
                  </span>
                ))}
              </div>
            ) : null}
          </div>
        ) : null}

        <div className="desk-review-history">
          {filteredReviewHistory.slice(0, 10).map((round) => (
            <button
              className="desk-review-history-card desk-review-history-button"
              key={round.sessionId}
              onClick={() => setSelectedReviewRoundId(round.sessionId)}
              type="button"
            >
              <strong>{round.items[0]?.term ?? "Review round"}</strong>
              <span>{formatRelativeTime(round.answeredAt)}</span>
              <p>
                {round.items.length} cards · {round.items.filter((item) => item.decision === "again").length} again ·{" "}
                {round.items.filter((item) => item.decision === "hard").length} hard ·{" "}
                {round.items.filter((item) => item.decision === "good").length} good ·{" "}
                {round.items.filter((item) => item.decision === "easy").length} easy
              </p>
              <small>{reviewSourceSummary(round.sourceKinds)}</small>
              {round.items[0]?.example ? <small>Example: {round.items[0].example}</small> : null}
            </button>
          ))}
        </div>
      </>
    );
  }

  function renderReviewSection(): ReactNode {
    const sessionFinished = reviewSession ? reviewSession.index >= reviewSession.queue.length : false;
    const sessionPaused = reviewSession ? !sessionFinished && reviewSession.pausedAt !== null : false;
    const weakerCardCount = reviewSession
      ? reviewSession.records.filter(isWeakReviewRecord).length
      : 0;
    const hasCandidateSearch = reviewCandidateSearch.trim().length > 0;
    const sessionCompletedAt = reviewSession?.records[reviewSession.records.length - 1]?.answeredAt ?? null;

    if (reviewSession && sessionFinished) {
      return (
        <WorkspaceContentGrid
          layoutPreference={workspacePreferences.workspacePaneLayoutPreference}
          onResetLayout={resetWorkspaceLayout}
          onResizeStart={(event) => beginWorkspaceResize(event, "contentRailWidth")}
        >
          <section className="app-panel desk-form-panel">
            <p className="desk-section-title">Review</p>
            <h2>Round finished</h2>
            <p className="desk-panel-copy">
              {reviewSession.records.length} cards completed. Undo the last rating below if you need to reopen the final card.
            </p>
            {activeReviewSessionDigest ? (
              <div className="desk-review-showcase-card">
                <div className="desk-review-showcase-head">
                  <div>
                    <p className="desk-kicker">Round recap</p>
                    <h3>{activeReviewSessionDigest.momentumLabel}</h3>
                  </div>
                  <span className="soft-tag soft-tag--accent">{reviewSession.styleTitle}</span>
                </div>
                <p className="desk-library-summary">{activeReviewSessionDigest.reviewPulse}</p>
                <div className="desk-library-trait-grid">
                  <div className="desk-mini-stat-card">
                    <span>Answered</span>
                    <strong>{activeReviewSessionDigest.answeredCount}</strong>
                  </div>
                  <div className="desk-mini-stat-card">
                    <span>Good</span>
                    <strong>{activeReviewSessionDigest.goodCount}</strong>
                  </div>
                  <div className="desk-mini-stat-card">
                    <span>Again</span>
                    <strong>{activeReviewSessionDigest.againCount}</strong>
                  </div>
                  <div className="desk-mini-stat-card">
                    <span>Completed</span>
                    <strong>{activeReviewSessionDigest.completionPercent}%</strong>
                  </div>
                </div>
                {sessionCompletedAt ? (
                  <p className="desk-library-caption">
                    {reviewSourceSummary(reviewSession.sourceKinds)} · {formatElapsedDuration(reviewSession.startedAt, sessionCompletedAt)}
                  </p>
                ) : null}
              </div>
            ) : null}
            <div className="desk-info-block">
              <h3>Ratings this round</h3>
              <ul className="desk-plain-list">
                <li>Again: {reviewSession.records.filter((record) => record.decision === "again").length}</li>
                <li>Hard: {reviewSession.records.filter((record) => record.decision === "hard").length}</li>
                <li>Good: {reviewSession.records.filter((record) => record.decision === "good").length}</li>
                <li>Easy: {reviewSession.records.filter((record) => record.decision === "easy").length}</li>
              </ul>
            </div>
            <div className="desk-info-block">
              <h3>Round style</h3>
              <p>{reviewSession.styleTitle}</p>
              <small>{reviewSession.styleDetail}</small>
            </div>
            <div className="desk-info-block">
              <h3>Round sources</h3>
              <p>{reviewSourceSummary(reviewSession.sourceKinds)}</p>
              {sessionCompletedAt ? (
                <small>Elapsed time: {formatElapsedDuration(reviewSession.startedAt, sessionCompletedAt)}</small>
              ) : null}
            </div>
            <div className="desk-info-block">
              <h3>Next due queue</h3>
              <div className="desk-library-trait-grid">
                <div className="desk-mini-stat-card">
                  <span>Due now</span>
                  <strong>{reviewDueDigest.dueNow}</strong>
                </div>
                <div className="desk-mini-stat-card">
                  <span>Due soon</span>
                  <strong>{reviewDueDigest.dueSoon}</strong>
                </div>
                <div className="desk-mini-stat-card">
                  <span>Fresh</span>
                  <strong>{reviewDueDigest.fresh}</strong>
                </div>
                <div className="desk-mini-stat-card">
                  <span>Scheduled</span>
                  <strong>{reviewDueDigest.scheduled}</strong>
                </div>
              </div>
            </div>
            <div className="desk-review-actions">
              {reviewSession.records.length > 0 ? (
                <button className="secondary-button" onClick={undoLastReviewDecision} type="button">
                  Undo Last Rating · Reopen Card
                </button>
              ) : null}
              <button className="desk-primary-button" onClick={endReviewSession} type="button">
                Back to Review Queue
              </button>
              {weakerCardCount > 0 ? (
                <button className="secondary-button" onClick={retryWeakerReviewCards} type="button">
                  Retry {weakerCardCount} weaker card{weakerCardCount === 1 ? "" : "s"}
                </button>
              ) : null}
            </div>
          </section>

          <section className="app-panel desk-detail-panel">
            <div className="desk-detail-header">
              <div>
                <h2>Round log</h2>
              </div>
            </div>
            <div className="desk-review-history">
              {reviewSession.records
                .slice()
                .reverse()
                .map((record) => (
                  <article className="desk-review-history-card" key={`${record.sessionId}-${record.candidateId}-${record.answeredAt}`}>
                    <strong>{record.term}</strong>
                    <span>{record.promptTitle}</span>
                    <p>
                      {reviewDecisionLabel(record.decision)} · {reviewSourceSummary(record.sourceKinds)} ·{" "}
                      {formatRelativeTime(record.answeredAt)}
                    </p>
                    <small>{record.partOfSpeech ? `${record.partOfSpeech} · ${record.meaning}` : record.meaning}</small>
                    {record.example ? <small>Example: {record.example}</small> : null}
                  </article>
                ))}
            </div>
          </section>
        </WorkspaceContentGrid>
      );
    }

    if (reviewSession && !sessionPaused) {
      const currentReviewState = currentReviewCandidate
        ? reviewStateForTerm(currentReviewCandidate.term, reviewStateMap)
        : defaultReviewState();
      const defaultDecision: ReviewDecision =
        currentReviewCard?.family === "flashcards"
          ? "good"
          : currentReviewCorrect
            ? "good"
            : "again";
      const remainingCardsAfterCurrent = Math.max(0, reviewSession.queue.length - reviewSession.index - 1);

      return (
        <WorkspaceContentGrid
          layoutPreference={workspacePreferences.workspacePaneLayoutPreference}
          onResetLayout={resetWorkspaceLayout}
          onResizeStart={(event) => beginWorkspaceResize(event, "contentRailWidth")}
        >
          <section className="app-panel desk-form-panel">
            <div className="desk-detail-header">
              <div>
                <p className="desk-section-title">Review Session</p>
                <h2>
                  Card {Math.min((reviewSession.index ?? 0) + 1, reviewSession.queue.length)} / {reviewSession.queue.length}
                </h2>
              </div>
              <div className="desk-chip-row">
                {reviewSession.records.length > 0 ? (
                  <button className="secondary-button" onClick={undoLastReviewDecision} type="button">
                    Undo Last Rating
                  </button>
                ) : null}
                <button className="secondary-button" onClick={() => setReviewExitIntent(true)} type="button">
                  End Round
                </button>
              </div>
            </div>

            {currentReviewCandidate && currentReviewCard ? (
              <>
                <div className="desk-chip-row">
                  <span className="soft-tag">{reviewQuestionTypeLabels[currentReviewCard.questionType].title}</span>
                  <span className="soft-tag">{reviewSession.styleTitle}</span>
                  <span className="soft-tag">{reviewSourceSummary(currentReviewCandidate.sourceKinds)}</span>
                  <span className="soft-tag">
                    {currentReviewCandidate.hasBackingEntry ? reviewLevelLabel(currentReviewState.level) : "History only"}
                  </span>
                  {currentReviewCandidate.hasBackingEntry ? (
                    <span className="soft-tag soft-tag--accent">{reviewAvailabilityLabel(currentReviewState)}</span>
                  ) : null}
                  {currentReviewCandidate.partOfSpeech ? (
                    <span className="soft-tag">{currentReviewCandidate.partOfSpeech}</span>
                  ) : null}
                  {currentReviewCandidate.favorite ? <span className="soft-tag">Favorite</span> : null}
                  {currentReviewState.lapseCount > 0 ? (
                    <span className="soft-tag">
                      {currentReviewState.lapseCount} lapse{currentReviewState.lapseCount === 1 ? "" : "s"}
                    </span>
                  ) : null}
                </div>

                {reviewExitIntent ? (
                  <div className="desk-info-block">
                    <h3>Leave this round?</h3>
                    <p>
                      Pause to resume later from this exact card, or discard the round if you want to start fresh.
                    </p>
                    <div className="desk-chip-row">
                      <button className="secondary-button" onClick={pauseReviewSession} type="button">
                        Pause and Continue Later
                      </button>
                      <button className="secondary-button" onClick={endReviewSession} type="button">
                        Discard Round
                      </button>
                      <button className="secondary-button" onClick={() => setReviewExitIntent(false)} type="button">
                        Keep Working
                      </button>
                    </div>
                  </div>
                ) : null}

                {activeReviewSessionDigest ? (
                  <div className="desk-review-momentum-card">
                    <div className="desk-review-showcase-head">
                      <div>
                        <p className="desk-kicker">Round momentum</p>
                        <h3>{activeReviewSessionDigest.momentumLabel}</h3>
                      </div>
                      <span className="soft-tag soft-tag--accent">
                        {activeReviewSessionDigest.answeredCount} / {reviewSession.queue.length} locked
                      </span>
                    </div>
                    <div className="desk-progress-rail">
                      <span
                        className="desk-progress-fill"
                        style={{ width: `${activeReviewSessionDigest.completionPercent}%` }}
                      />
                    </div>
                    <p className="desk-review-progress-copy">{activeReviewSessionDigest.reviewPulse}</p>
                    <div className="desk-library-trait-grid">
                      <div className="desk-mini-stat-card">
                        <span>Again</span>
                        <strong>{activeReviewSessionDigest.againCount}</strong>
                      </div>
                      <div className="desk-mini-stat-card">
                        <span>Hard</span>
                        <strong>{activeReviewSessionDigest.hardCount}</strong>
                      </div>
                      <div className="desk-mini-stat-card">
                        <span>Good</span>
                        <strong>{activeReviewSessionDigest.goodCount}</strong>
                      </div>
                      <div className="desk-mini-stat-card">
                        <span>Easy</span>
                        <strong>{activeReviewSessionDigest.easyCount}</strong>
                      </div>
                    </div>
                    {upcomingReviewCandidates.length > 0 ? (
                      <div className="desk-chip-row">
                        {upcomingReviewCandidates.slice(0, 3).map((candidate) => (
                          <span className="soft-tag" key={candidate.id}>
                            Up next: {candidate.term}
                          </span>
                        ))}
                      </div>
                    ) : null}
                  </div>
                ) : null}

                <div className="desk-review-card">
                  <p className="desk-kicker">{currentReviewCard.promptTitle}</p>
                  <h3>{currentReviewCard.prompt}</h3>
                  <p>{reviewSession.styleDetail}</p>
                  <small>{currentReviewCard.promptHint}</small>
                </div>

                <div className="desk-info-block">
                  <h3>Study payload</h3>
                  <div className="desk-review-payload-list">
                    <div>
                      <strong>Selected meaning</strong>
                      <p>{currentReviewCandidate.selectedMeanings.join(" / ") || currentReviewCandidate.detail}</p>
                    </div>
                    {currentReviewCandidate.selectedExamples.length > 0 ? (
                      <div>
                        <strong>Selected examples</strong>
                        <p>{currentReviewCandidate.selectedExamples.join(" / ")}</p>
                      </div>
                    ) : null}
                    {currentReviewCandidate.referenceTags.length > 0 ? (
                      <div>
                        <strong>Reference tags</strong>
                        <div className="desk-chip-row">
                          {currentReviewCandidate.referenceTags.map((tag) => (
                            <span className="soft-tag" key={`${currentReviewCandidate.id}-${tag}`}>
                              {tag}
                            </span>
                          ))}
                        </div>
                      </div>
                    ) : null}
                  </div>
                </div>

                {currentReviewCard.supportingText ? (
                  <div className="desk-info-block">
                    <h3>{currentReviewCandidate.example ? "Selected example" : currentReviewCandidate.context ? "Original context" : "Study note"}</h3>
                    <p>{currentReviewCard.supportingText}</p>
                  </div>
                ) : null}

                {currentReviewCard.family === "multipleChoice" ? (
                  <div className="desk-review-options">
                    {currentReviewCard.distractors.map((option) => (
                      <button
                        className={
                          reviewSelectedChoice === option
                            ? "desk-review-option is-selected"
                            : "desk-review-option"
                        }
                        disabled={reviewAnswerSubmitted}
                        key={option}
                        onClick={() => updateReviewSelectedChoice(option)}
                        type="button"
                      >
                        {option}
                      </button>
                    ))}
                  </div>
                ) : null}

                {currentReviewCard.family === "fillIn" ? (
                  <div className="desk-context-block">
                    <label htmlFor="review-answer">Type the English term</label>
                    <input
                      id="review-answer"
                      onChange={(event) => updateReviewDraftAnswer(event.target.value)}
                      placeholder="Type your answer before revealing"
                      value={reviewDraftAnswer}
                    />
                  </div>
                ) : null}

                {currentReviewCard.family === "flashcards" ? (
                  <button className="desk-review-flashcard" onClick={submitReviewAnswer} type="button">
                    {reviewAnswerSubmitted ? currentReviewCard.answer : "Flip to reveal the answer"}
                  </button>
                ) : null}

                {!reviewAnswerSubmitted && currentReviewCard.family !== "flashcards" ? (
                  <button className="desk-primary-button" onClick={submitReviewAnswer} type="button">
                    Submit Answer
                  </button>
                ) : null}

                {reviewAnswerSubmitted ? (
                  <>
                    <div
                      className={
                        currentReviewCard.family === "flashcards"
                          ? "desk-review-feedback"
                          : currentReviewCorrect
                            ? "desk-review-feedback is-positive"
                            : "desk-review-feedback is-negative"
                      }
                    >
                      <strong>
                        {currentReviewCard.family === "flashcards"
                          ? "Answer revealed."
                          : currentReviewCorrect
                            ? "Stable recall."
                            : "Needs another pass."}
                      </strong>
                      <p>
                        {reviewAdvanceSummary({
                          decision: defaultDecision,
                          family: currentReviewCard.family,
                          correct: currentReviewCorrect,
                          remainingCardsAfterCurrent,
                        })}
                      </p>
                    </div>

                    <div className="desk-info-block">
                      <h3>Answer</h3>
                      <p>{currentReviewCard.answer}</p>
                      {currentReviewCard.family !== "flashcards" ? (
                        <p className="desk-answer-status">
                          {currentReviewCorrect ? "Marked correct." : "Marked incorrect."}
                        </p>
                      ) : null}
                    </div>

                    {currentReviewCard.family === "fillIn" ? (
                      <div className="desk-info-block">
                        <h3>Your response</h3>
                        <p>{reviewDraftAnswer || "No response entered."}</p>
                      </div>
                    ) : null}

                    {currentReviewCandidate.context ? (
                      <div className="desk-info-block">
                        <h3>Original context</h3>
                        <p>{currentReviewCandidate.context}</p>
                      </div>
                    ) : null}

                    {currentReviewCandidate.example && currentReviewCandidate.example !== currentReviewCandidate.context ? (
                      <div className="desk-info-block">
                        <h3>Selected example</h3>
                        <p>{currentReviewCandidate.example}</p>
                      </div>
                    ) : null}

                    {currentReviewCandidate.notes ? (
                      <div className="desk-info-block">
                        <h3>Notes</h3>
                        <p>{currentReviewCandidate.notes}</p>
                      </div>
                    ) : null}

                    <div className="desk-review-actions">
                      <button className="desk-primary-button" onClick={() => applyReviewDecision(defaultDecision)} type="button">
                        {reviewAdvanceButtonLabel(defaultDecision, remainingCardsAfterCurrent)}
                      </button>
                      <div className="desk-chip-row">
                        <button
                          className="secondary-button"
                          onClick={() => applyReviewDecision("again")}
                          title={reviewDecisionLabels.again.detail}
                          type="button"
                        >
                          Again
                        </button>
                        <button
                          className="secondary-button"
                          onClick={() => applyReviewDecision("hard")}
                          title={reviewDecisionLabels.hard.detail}
                          type="button"
                        >
                          Hard
                        </button>
                        <button
                          className="secondary-button"
                          onClick={() => applyReviewDecision("good")}
                          title={reviewDecisionLabels.good.detail}
                          type="button"
                        >
                          Good
                        </button>
                        <button
                          className="secondary-button"
                          onClick={() => applyReviewDecision("easy")}
                          title={reviewDecisionLabels.easy.detail}
                          type="button"
                        >
                          Easy
                        </button>
                      </div>
                    </div>
                  </>
                ) : null}
              </>
            ) : (
              renderRecoveryLane({
                kicker: "Review Session",
                title: "Loading the next card…",
                body: "Preparing the next review card so the round can keep moving without resetting.",
                tone: "accent",
                stats: [
                  { label: "Queue", value: String(reviewSession.queue.length) },
                  { label: "Answered", value: String(reviewSession.records.length) },
                  { label: "Remaining", value: String(Math.max(0, reviewSession.queue.length - reviewSession.records.length)) },
                ],
              })
            )}
          </section>

          <section className="app-panel desk-detail-panel">
            {currentReviewCandidate ? (
              <>
                <div className="desk-detail-header">
                  <div>
                    <h2>{currentReviewCandidate.term}</h2>
                    <p className="desk-subtle">Session context</p>
                  </div>
                </div>

                <div className="desk-info-block">
                  <h3>Current study state</h3>
                  <p>
                    {currentReviewCandidate.hasBackingEntry
                      ? reviewStateSummaryText(currentReviewState)
                      : "History only · this round will not change a stored review level"}
                  </p>
                  {currentReviewCandidate.hasBackingEntry && reviewStateSecondaryText(currentReviewState) ? (
                    <small>{reviewStateSecondaryText(currentReviewState)}</small>
                  ) : null}
                </div>

                <div className="desk-info-block">
                  <h3>Round status</h3>
                  <p>
                    {reviewSession.records.length} answered · {reviewSession.queue.length - reviewSession.index - 1} still queued after this card
                  </p>
                  <small>{reviewSourceSummary(currentReviewCandidate.sourceKinds)}</small>
                </div>

                {currentReviewCandidate.example ? (
                  <div className="desk-info-block">
                    <h3>Selected example</h3>
                    <p>{currentReviewCandidate.example}</p>
                  </div>
                ) : null}

                {renderSnapshotBlocks(currentReviewLookup, {
                  status: lookupStatusForTerm(currentReviewCandidate.term),
                  fallbackDetail: currentReviewCandidate.detail,
                  context: currentReviewCandidate.context,
                  notes: currentReviewCandidate.notes,
                })}

                <div className="desk-info-block">
                  <h3>Upcoming terms</h3>
                  <div className="desk-review-history">
                    {upcomingReviewCandidates.map((candidate) => (
                      <article className="desk-review-history-card" key={candidate.id}>
                        <strong>{candidate.term}</strong>
                        <span>{reviewSourceSummary(candidate.sourceKinds)}</span>
                        <p>{candidate.detail}</p>
                        {candidate.example ? <small>Example: {candidate.example}</small> : null}
                        {candidate.context ? <small>{candidate.context}</small> : null}
                      </article>
                    ))}
                  </div>
                </div>
              </>
            ) : (
              renderRecoveryLane({
                kicker: "Review",
                title: "No active card.",
                body: "Rebuild the round from Library, Favorites, History, or migrated legacy data.",
                tone: "warning",
                stats: [
                  { label: "Ready now", value: String(reviewCandidates.length) },
                  { label: "Answered", value: String(reviewSession.records.length) },
                  { label: "History", value: String(reviewHistory.length) },
                ],
                actions: (
                  <>
                    <button className="secondary-button" onClick={endReviewSession} type="button">
                      Back
                    </button>
                    <Link className="secondary-button" href={buildWorkspaceHref({ section: "lookup", kind: "word" })}>
                      Open Lookup
                    </Link>
                  </>
                ),
              })
            )}
          </section>
        </WorkspaceContentGrid>
      );
    }

    return (
      <WorkspaceContentGrid
        layoutPreference={workspacePreferences.workspacePaneLayoutPreference}
        onResetLayout={resetWorkspaceLayout}
        onResizeStart={(event) => beginWorkspaceResize(event, "contentRailWidth")}
      >
        <section className="app-panel desk-form-panel">
          {sessionPaused && reviewSession ? (
            <div className="desk-info-block">
              <h3>Paused round ready</h3>
              <p>
                {reviewSession.queue.length} cards · paused {formatRelativeTime(reviewSession.pausedAt ?? reviewSession.startedAt)}
              </p>
              <small>
                {reviewSourceSummary(reviewSession.sourceKinds)} · {reviewSession.styleTitle} · answered{" "}
                {reviewSession.records.length}
              </small>
              <div className="desk-review-actions">
                <button className="desk-primary-button" onClick={resumeReviewSession} type="button">
                  Resume Previous Round
                </button>
                <button className="secondary-button" onClick={endReviewSession} type="button">
                  Discard Paused Round
                </button>
              </div>
            </div>
          ) : null}

          <div className="desk-info-block">
            <div className="desk-native-menu-grid">
              <details className="desk-native-menu">
                <summary>
                  <span>Mode</span>
                  <strong>{reviewQuestionStrategyLabels[reviewQuestionStrategy].title}</strong>
                </summary>
                <div className="desk-native-menu-panel">
                  {(["smart", "custom"] as ReviewQuestionStrategy[]).map((strategy) => (
                    <label className="desk-menu-check-row desk-menu-check-row--stacked" key={strategy}>
                      <input
                        checked={reviewQuestionStrategy === strategy}
                        name="review-question-strategy"
                        onChange={() => updateReviewQuestionStrategy(strategy)}
                        type="radio"
                      />
                      <span>
                        <strong>{reviewQuestionStrategyLabels[strategy].title}</strong>
                        <small>{reviewQuestionStrategyLabels[strategy].detail}</small>
                      </span>
                    </label>
                  ))}
                  <button className="secondary-button" onClick={resetReviewSmartDefaults} type="button">
                    Reset Smart Default
                  </button>
                </div>
              </details>

              <details className="desk-native-menu">
                <summary>
                  <span>Sources</span>
                  <strong>{reviewSourceSelectionLabel(reviewSources)}</strong>
                </summary>
                <div className="desk-native-menu-panel">
                  {reviewSourceOrder.map((source) => (
                    <label className="desk-menu-check-row" key={source}>
                      <input
                        checked={reviewSources.has(source)}
                        onChange={() => toggleReviewSource(source)}
                        type="checkbox"
                      />
                      <span>{reviewSourceLabels[source]}</span>
                      <em>{reviewSourceCounts[source]}</em>
                    </label>
                  ))}
                </div>
              </details>

              <details className="desk-native-menu">
                <summary>
                  <span>Question types</span>
                  <strong>{orderedReviewQuestionTypes(reviewQuestionTypes).length} enabled</strong>
                </summary>
                <div className="desk-native-menu-panel">
                  <p className="desk-menu-note">
                    {reviewQuestionStrategy === "smart"
                      ? "Smart Mix treats these as the allowed formats for each familiarity level."
                      : "Custom Mix rotates only these selected formats across the round."}
                  </p>
                  {([
                    "multipleChoice",
                    "fillIn",
                    "flashcards",
                  ] as ReviewQuestionType[]).map((type) => (
                    <label className="desk-menu-check-row desk-menu-check-row--stacked" key={type}>
                      <input
                        checked={reviewQuestionTypes.has(type)}
                        onChange={() => toggleReviewQuestionType(type)}
                        type="checkbox"
                      />
                      <span>
                        <strong>{reviewQuestionTypeLabels[type].title}</strong>
                        <small>{reviewQuestionTypeLabels[type].detail}</small>
                      </span>
                    </label>
                  ))}
                </div>
              </details>
            </div>
          </div>

          <div className="desk-info-block">
            <h3>Queue focus</h3>
            <div className="desk-chip-row">
              {(["all", "dueNow", "unknown", "needsWork", "recentMistakes", "favoritesOnly", "historyOnly"] as ReviewQuickFilter[]).map((filter) => (
                <button
                  className={reviewQuickFilter === filter ? "secondary-button is-active" : "secondary-button"}
                  disabled={reviewQuickFilterCounts[filter] === 0 && filter !== "all"}
                  key={filter}
                  onClick={() => applyReviewQuickFilter(filter)}
                  type="button"
                >
                  {reviewQuickFilterLabels[filter]} · {reviewQuickFilterCounts[filter]}
                </button>
              ))}
            </div>
            <div className="desk-chip-row">
              <button
                className="secondary-button"
                disabled={reviewQuickFilterCounts.dueNow === 0}
                onClick={() => queueReviewFilter("dueNow")}
                type="button"
              >
                Queue Due Now
              </button>
              <button
                className="secondary-button"
                disabled={reviewQuickFilterCounts.needsWork === 0}
                onClick={() => queueReviewFilter("needsWork")}
                type="button"
              >
                Queue Weak Terms
              </button>
              <button
                className="secondary-button"
                disabled={reviewQuickFilterCounts.recentMistakes === 0}
                onClick={() => queueReviewFilter("recentMistakes")}
                type="button"
              >
                Queue Recent Mistakes
              </button>
            </div>
          </div>

          <div className="desk-review-toolbar">
            <label className="desk-sort-label" htmlFor="review-sort">
              Sort
            </label>
            <select
              id="review-sort"
              onChange={(event) => setReviewSort(event.target.value as ReviewSortOption)}
              value={reviewSort}
            >
              <option value="recommended">Recommended</option>
              <option value="newestFirst">Newest first</option>
              <option value="leastRecentlyReviewed">Least recently reviewed</option>
              <option value="alphabetical">Alphabetical</option>
            </select>

            <button className="secondary-button" onClick={toggleSelectAllReview} type="button">
              {selectedReviewIds.size === filteredReviewCandidates.length && filteredReviewCandidates.length > 0
                ? "Clear selection"
                : "Select all"}
            </button>
            {selectedReviewIds.size > 0 ? (
              <button className="secondary-button" onClick={() => setSelectedReviewIds(new Set())} type="button">
                Clear Selection
              </button>
            ) : null}

            <button
              className="desk-primary-button"
              disabled={filteredReviewCandidates.length === 0 || reviewQuestionTypes.size === 0}
              onClick={startReviewSession}
              type="button"
            >
              {selectedReviewIds.size === 0
                ? `Start ${reviewLaunchCandidates.length} terms`
                : `Start ${reviewLaunchCandidates.length} selected`}
            </button>
          </div>

          {filteredReviewCandidates.length > 0 ? (
            <div className="desk-review-picker">
              {filteredReviewCandidates.map((candidate) => {
                const isSelected = selectedReviewIds.has(candidate.id);

                return (
                  <button
                    className={isSelected ? "desk-review-picker-row is-selected" : "desk-review-picker-row"}
                    key={candidate.id}
                    onClick={() => toggleReviewSelection(candidate.id)}
                    type="button"
                  >
                    <div className="desk-review-picker-head">
                      <strong>{candidate.term}</strong>
                      <span>{candidate.hasBackingEntry ? reviewLevelLabel(candidate.reviewLevel) : "History only"}</span>
                    </div>
                    <div className="desk-chip-row">
                      {candidate.sourceKinds.map((source) => (
                        <span className="soft-tag" key={`${candidate.id}-${source}`}>
                          {reviewSourceLabels[source]}
                        </span>
                      ))}
                      <span className="soft-tag soft-tag--accent">
                        {reviewAvailabilityLabel(reviewStateForTerm(candidate.term, reviewStateMap))}
                      </span>
                      {candidate.partOfSpeech ? <span className="soft-tag">{candidate.partOfSpeech}</span> : null}
                      {candidate.favorite ? <span className="soft-tag">Favorite</span> : null}
                      {reviewStateForTerm(candidate.term, reviewStateMap).lapseCount > 0 ? (
                        <span className="soft-tag">
                          {reviewStateForTerm(candidate.term, reviewStateMap).lapseCount} lapse
                          {reviewStateForTerm(candidate.term, reviewStateMap).lapseCount === 1 ? "" : "s"}
                        </span>
                      ) : null}
                      {candidate.referenceTags.slice(0, 3).map((tag) => (
                        <span className="soft-tag" key={`${candidate.id}-${tag}`}>
                          {tag}
                        </span>
                      ))}
                    </div>
                    <p {...cjkTextProps(candidate.detail)}>{candidate.detail}</p>
                    {candidate.selectedMeanings.length > 1 ? (
                      <small>Selected meanings: {candidate.selectedMeanings.join(" / ")}</small>
                    ) : null}
                    {candidate.example ? <small>Example: {candidate.example}</small> : null}
                    {candidate.selectedExamples.length > 1 ? (
                      <small>More examples: {candidate.selectedExamples.slice(1).join(" / ")}</small>
                    ) : null}
                    {candidate.context ? <small {...cjkTextProps(candidate.context)}>{candidate.context}</small> : null}
                    {candidate.notes ? <small>Notes: {candidate.notes}</small> : null}
                  </button>
                );
              })}
            </div>
          ) : (
            renderNativeEmptyPanel(
              reviewSources.size === 0
                ? "Turn on at least one source"
                : hasCandidateSearch
                  ? "No reviewable items match"
                  : "No reviewable items",
              reviewSources.size === 0
                ? "Select a source."
                : hasCandidateSearch
                  ? "Clear the candidate search."
                  : "Add entries from Lookup, Quick Capture, or Library.",
              <>
                {hasCandidateSearch ? (
                  <button className="secondary-button" onClick={() => setReviewCandidateSearch("")} type="button">
                    Clear Search
                  </button>
                ) : null}
                {reviewSources.size === 0 ? (
                  <button
                    className="secondary-button"
                    onClick={() => setReviewSources(defaultReviewSourceSet())}
                    type="button"
                  >
                    Use Library Source
                  </button>
                ) : null}
                <button className="secondary-button" onClick={openQuickCapture} type="button">
                  Open Quick Capture
                </button>
              </>,
            )
          )}
        </section>

        <section className="app-panel desk-detail-panel">
          <div className="desk-detail-header">
            <div>
              <h2>Review history</h2>
            </div>
          </div>

          {renderReviewHistoryPanel()}
        </section>
      </WorkspaceContentGrid>
    );
  }

  function renderQuickCaptureDialog(): ReactNode {
    if (!isQuickCaptureOpen) {
      return null;
    }

    const captureKey = normalizedTerm(captureTermDraft);
    const matchingCaptureDraft = captureKey ? quickCaptureDrafts[captureKey] ?? null : null;
    const matchingLibraryEntry = captureKey
      ? libraryEntries.find((entry) => normalizedTerm(entry.term) === captureKey) ?? null
      : null;

    return (
      <div className="desk-modal-backdrop" role="presentation">
        <section aria-label="Quick Capture" className="app-panel desk-modal-panel desk-modal-wide">
          <div className="desk-detail-header">
            <div>
              <p className="desk-section-title">SparrowWord Capture</p>
              <h2>Quick Capture</h2>
              <p className="desk-subtle">
                Save a Quick Capture draft now, or write the confirmed study entry straight into Library.
              </p>
            </div>
            <div className="desk-chip-row">
              <button className="secondary-button" onClick={startFreshQuickCaptureDraft} type="button">
                New
              </button>
              <button className="secondary-button" onClick={closeQuickCapture} type="button">
                Close
              </button>
            </div>
          </div>

          <form className="desk-modal-stack" onSubmit={saveQuickCaptureToLibrary}>
            {quickCapturePresets.length > 0 ? (
              <details className="desk-native-menu">
                <summary>
                  <span>Capture Seeds</span>
                  <strong>{quickCapturePresets.length} ready</strong>
                </summary>
                <div className="desk-native-menu-panel">
                  <div className="desk-chip-row">
                    {quickCapturePresets.map((preset) => (
                      <button
                        className="secondary-button"
                        key={preset.id}
                        onClick={() => applyQuickCapturePreset(preset)}
                        type="button"
                      >
                        {preset.label}: {preset.term}
                      </button>
                    ))}
                  </div>
                </div>
              </details>
            ) : null}

            <div className="desk-segment-row" role="tablist" aria-label="Capture type">
              {(["word", "phrase", "sentence"] as LookupKind[]).map((kind) => (
                <button
                  aria-pressed={captureKindDraft === kind}
                  className={captureKindDraft === kind ? "desk-segment is-active" : "desk-segment"}
                  key={kind}
                  onClick={() => {
                    setCaptureKindDraft(kind);
                    setCaptureMeaningCandidatesDirty(false);
                    setCaptureExampleChoicesDirty(false);
                  }}
                  type="button"
                >
                  {lookupKindLabels[kind]}
                </button>
              ))}
            </div>

            <div className="desk-context-block">
              <label htmlFor="capture-term">Term</label>
              <input
                id="capture-term"
                onChange={(event) => {
                  setCaptureTermDraft(event.target.value);
                  setCaptureMeaningCandidatesDirty(false);
                  setCaptureExampleChoicesDirty(false);
                  setCaptureSeedMode("typed");
                }}
                placeholder={lookupPlaceholder(captureKindDraft)}
                value={captureTermDraft}
              />
            </div>

            {matchingLibraryEntry ? (
              <div className="desk-info-block">
                <p>
                  “{matchingLibraryEntry.term}” is already in Library. Saving now will update the confirmed study entry
                  instead of creating a duplicate.
                </p>
              </div>
            ) : null}

            <div className="desk-modal-actions">
              <button className="secondary-button" disabled={!captureTermDraft.trim()} onClick={saveQuickCaptureAsDraft} type="button">
                Save as Draft
              </button>
              <button className="desk-primary-button" disabled={!captureTermDraft.trim()} type="submit">
                {matchingLibraryEntry ? "Update Library Entry" : "Save to Library"}
              </button>
            </div>

            <div className="desk-info-block">
              <h3>Initial study state</h3>
              <div className="desk-native-field-grid">
                <label htmlFor="capture-familiarity">Familiarity</label>
                <select
                  id="capture-familiarity"
                  onChange={(event) => setCaptureReviewLevelDraft(Number(event.target.value) as ReviewLevel)}
                  value={captureReviewLevelDraft}
                >
                  {reviewLevelOptions.map((level) => (
                    <option key={level} value={level}>
                      {reviewLevelLabel(level)}
                    </option>
                  ))}
                </select>
                <button className="secondary-button" onClick={refillQuickCaptureSuggestions} type="button">
                  Fill Suggestions
                </button>
              </div>
              <p className="desk-subtle">
                {matchingLibraryEntry
                  ? "`Save as Draft` keeps this out of Review. `Update Library Entry` refreshes the confirmed study entry."
                  : "`Save as Draft` keeps this out of Review. `Save to Library` creates the formal study entry."}
              </p>
            </div>

            <div className="desk-context-block">
              <label htmlFor="capture-context">Original context</label>
              <textarea
                id="capture-context"
                onChange={(event) => setCaptureContextDraft(event.target.value)}
                placeholder="Paste the sentence or note you want to keep with this item."
                value={captureContextDraft}
              />
            </div>

            <div className="desk-info-block">
              <div className="desk-detail-header">
                <div>
                  <h3>Meaning Candidates</h3>
                  <p className="desk-subtle">Select the senses you want to keep, and adjust POS or wording per sense.</p>
                </div>
                <button className="secondary-button" onClick={addQuickCaptureMeaningCandidate} type="button">
                  Add Candidate
                </button>
              </div>
              <div className="desk-example-stack">
                {captureMeaningCandidatesDraft.map((candidate, index) => (
                  <div className="desk-entry-choice-row" key={candidate.id}>
                    <button
                      aria-pressed={candidate.selected}
                      className={candidate.selected ? "desk-choice-radio is-selected" : "desk-choice-radio"}
                      onClick={() => toggleQuickCaptureMeaningCandidate(index)}
                      type="button"
                    >
                      {candidate.selected ? "✓" : ""}
                    </button>
                    <div className="desk-entry-choice-main has-pos-editor">
                      <textarea
                        aria-label={`Capture meaning ${index + 1}`}
                        className={candidate.selected ? "desk-entry-choice-card is-selected" : "desk-entry-choice-card"}
                        onChange={(event) =>
                          updateQuickCaptureMeaningCandidate(index, {
                            meaning: event.target.value,
                          })
                        }
                        placeholder="Refine this Chinese meaning."
                        value={candidate.meaning}
                      />
                      <input
                        aria-label={`Capture POS ${index + 1}`}
                        className="desk-entry-choice-input"
                        onChange={(event) =>
                          updateQuickCaptureMeaningCandidate(index, {
                            partOfSpeech: sanitizeInlineText(event.target.value),
                          })
                        }
                        placeholder="POS"
                        value={candidate.partOfSpeech}
                      />
                    </div>
                    <button className="activity-remove" onClick={() => removeQuickCaptureMeaningCandidate(index)} type="button">
                      Delete
                    </button>
                  </div>
                ))}
              </div>
            </div>

            {renderEditableChoicesSection({
              title: "Example Candidates",
              selectedTitle: "Selected examples",
              choices: captureExampleChoicesDraft,
              selectedIndexes: captureSelectedExampleIndexesDraft,
              emptyMessage: "No example candidates yet.",
              customDraft: captureCustomExampleDraft,
              customMessage: captureCustomExampleMessage,
              customPlaceholder: "(Custom example)",
              onCustomDraftChange: (value) => {
                setCaptureCustomExampleDraft(value);
                setCaptureCustomExampleMessage(null);
              },
              onCommitCustom: commitQuickCaptureCustomExample,
              onToggle: (index) =>
                updateQuickCaptureExampleChoices(
                  captureExampleChoicesDraft,
                  toggledSelection(captureSelectedExampleIndexesDraft, index),
                ),
              onRemove: (index) => {
                const nextExampleState = removeIndexedChoice(
                  captureExampleChoicesDraft,
                  captureSelectedExampleIndexesDraft,
                  index,
                );
                updateQuickCaptureExampleChoices(nextExampleState.choices, nextExampleState.selectedIndexes);
              },
            })}

            <div className="desk-native-field-grid">
              <label htmlFor="capture-notes">Notes</label>
              <textarea
                id="capture-notes"
                onChange={(event) => setCaptureNotesDraft(event.target.value)}
                placeholder="Optional note, memory hook, or usage reminder."
                value={captureNotesDraft}
              />
            </div>

            {captureStatusMessage ? (
              <p className="desk-subtle">{captureStatusMessage}</p>
            ) : null}

            <details className="desk-native-menu">
              <summary>
                <span>Bulk Import to Drafts</span>
                <strong>{bulkCapturePreviewItems.length > 0 ? `${bulkCapturePreviewItems.length} parsed` : "Optional"}</strong>
              </summary>
              <div className="desk-native-menu-panel">
                <textarea
                  aria-label="Bulk import"
                  onChange={(event) => setCaptureImportDraft(event.target.value)}
                  placeholder={`abandon :: They had to abandon the original plan.\ncharge :: The bank may charge a small fee.`}
                  value={captureImportDraft}
                />
                <div className="desk-chip-row">
                  <button className="secondary-button" onClick={pasteClipboardIntoCaptureImport} type="button">
                    Paste Clipboard
                  </button>
                  <button
                    className="secondary-button"
                    onClick={() => captureImportFileInputRef.current?.click()}
                    type="button"
                  >
                    Load File
                  </button>
                  <button
                    className="secondary-button"
                    disabled={bulkCapturePreviewItems.length === 0}
                    onClick={importQuickCaptureDrafts}
                    type="button"
                  >
                    Save Imported as Drafts
                  </button>
                </div>
                {captureImportMessage ? <p className="desk-subtle">{captureImportMessage}</p> : null}
                {bulkCapturePreviewItems.length > 0 ? (
                  <ul className="desk-plain-list">
                    {bulkCapturePreviewItems.slice(0, 4).map((item) => (
                      <li key={item.id}>
                        {item.term}
                        {item.context ? ` · ${item.context}` : ""}
                      </li>
                    ))}
                  </ul>
                ) : null}
                <input
                  accept=".txt,.md,.csv"
                  hidden
                  onChange={importCaptureFile}
                  ref={captureImportFileInputRef}
                  type="file"
                />
              </div>
            </details>

            <button className="secondary-button" onClick={closeQuickCapture} type="button">
              Cancel
            </button>
          </form>
        </section>
      </div>
    );
  }

  function renderSettingsPanelContent(): ReactNode {
    if (activeSettingsPanel === "general") {
      return (
        <div className="desk-modal-stack">
          <div className="desk-info-block">
            <h3>Main workspace layout</h3>
            <p className="desk-subtle">
              Automatic switches to a top-and-bottom workspace when the window gets narrow.
            </p>
            <label htmlFor="general-workspace-layout">Layout preference</label>
            <select
              id="general-workspace-layout"
              onChange={(event) =>
                updateWorkspacePreference(
                  "workspacePaneLayoutPreference",
                  event.target.value as WorkspacePaneLayoutPreference,
                )
              }
              value={workspacePreferences.workspacePaneLayoutPreference}
            >
              {(["automatic", "horizontal", "vertical"] as WorkspacePaneLayoutPreference[]).map((preference) => (
                <option key={preference} value={preference}>
                  {workspacePaneLayoutLabels[preference]}
                </option>
              ))}
            </select>
          </div>

          <div className="desk-info-block">
            <h3>Library</h3>
            <label className="desk-checkbox-row" htmlFor="review-settings-library-clean-mode">
              <input
                checked={workspacePreferences.isLibraryCleanMode}
                id="review-settings-library-clean-mode"
                onChange={(event) => setLibraryCleanMode(event.target.checked)}
                type="checkbox"
              />
              <span>Use clean view for Library details</span>
            </label>
          </div>

          <div className="desk-info-block">
            <h3>Pronunciation</h3>
            <label className="desk-checkbox-row" htmlFor="general-show-lookup-tags">
              <input
                checked={workspacePreferences.showLookupReferenceTags}
                id="general-show-lookup-tags"
                onChange={(event) => updateWorkspacePreference("showLookupReferenceTags", event.target.checked)}
                type="checkbox"
              />
              <span>Show frequency and dictionary tags in Lookup</span>
            </label>
          </div>

          <div className="desk-info-block">
            <h3>Pronunciation voice</h3>
            <select
              onChange={(event) => updateWorkspacePreference("pronunciationVoiceURI", event.target.value)}
              value={workspacePreferences.pronunciationVoiceURI}
            >
              <option value={automaticPronunciationVoiceURI}>Automatic</option>
              {availableVoices.map((voice) => (
                <option key={voice.voiceURI} value={voice.voiceURI}>
                  {voice.name} · {voice.lang}
                </option>
              ))}
            </select>
          </div>
        </div>
      );
    }

    if (activeSettingsPanel === "study") {
      return (
        <div className="desk-modal-stack">
          <div className="desk-info-block">
            <h3>Review defaults</h3>
            <label className="desk-checkbox-row" htmlFor="review-settings-exclude-mastered">
              <input
                checked={workspacePreferences.excludeMasteredFromReview}
                id="review-settings-exclude-mastered"
                onChange={(event) =>
                  updateWorkspacePreference("excludeMasteredFromReview", event.target.checked)
                }
                type="checkbox"
              />
              <span>Exclude mastered terms from review rounds</span>
            </label>
          </div>

          <div className="desk-info-block">
            <h3>Question mix</h3>
            <p>{currentReviewStyle.title}</p>
            <small>{currentReviewStyle.detail}</small>
          </div>
        </div>
      );
    }

    if (activeSettingsPanel === "resources") {
      return (
        <div className="desk-modal-stack">
          <div className="desk-info-block">
            <h3>Dictionary service</h3>
            <p>
              {dictHealthStatus === "loading"
                ? "Checking the dict-api service…"
                : dictHealthStatus === "error"
                  ? "The web client could not load dictionary health just now."
                  : dictHealth
                    ? `${dictHealth.service} · ${dictHealth.phase}`
                    : "Open this panel to refresh dictionary health."}
            </p>
          </div>

          {dictHealth ? (
            <>
              <div className="desk-info-block">
                <h3>Readiness</h3>
                <p>{dictHealth.ready === false ? "Not ready for production traffic." : "Ready for local use."}</p>
                {dictHealth.missing_required_dictionaries?.length ? (
                  <small>Missing required dictionaries: {dictHealth.missing_required_dictionaries.join(", ")}</small>
                ) : (
                  <small>
                    Required dictionaries:{" "}
                    {dictHealth.required_dictionaries?.length
                      ? dictHealth.required_dictionaries.join(", ")
                      : "none configured"}
                  </small>
                )}
              </div>

              <div className="desk-info-block">
                <h3>Offline resources</h3>
                <ul className="desk-plain-list">
                  <li>ECDICT: {dictHealth.dictionaries.ecdict ? "Ready" : "Missing"}</li>
                  <li>CEDICT: {dictHealth.dictionaries.cedict ? "Ready" : "Missing"}</li>
                  <li>OEWN: {dictHealth.dictionaries.oewn ? "Ready" : "Missing"}</li>
                  <li>Tatoeba: {dictHealth.dictionaries.tatoeba ? "Ready" : "Missing"}</li>
                </ul>
              </div>

              <div className="desk-info-block">
                <h3>Storage</h3>
                <ul className="desk-plain-list">
                  <li>
                    Activity store:{" "}
                    {dictHealth.storage.activity_store?.available ? "Ready" : "Unavailable"}
                  </li>
                  {dictHealth.storage.activity_store?.path ? (
                    <li>Activity DB: {dictHealth.storage.activity_store.path}</li>
                  ) : null}
                  {dictHealth.storage.feedback_log?.path ? (
                    <li>Feedback log: {dictHealth.storage.feedback_log.path}</li>
                  ) : null}
                </ul>
              </div>
            </>
          ) : null}

          <div className="desk-info-block">
            <h3>Sentence mode</h3>
            <p>{dictHealth?.phase ?? "Local dictionary service"}</p>
          </div>

          {dictHealth?.runtime ? (
            <div className="desk-info-block">
              <h3>Runtime caches</h3>
              <ul className="desk-plain-list">
                <li>Reverse lookup cache: {dictHealth.runtime.reverse_lookup_cache?.entries ?? 0}</li>
                <li>Sentence study cache: {dictHealth.runtime.sentence_study_cache?.entries ?? 0}</li>
              </ul>
            </div>
          ) : null}
        </div>
      );
    }

    if (activeSettingsPanel === "recovery") {
      return (
        <div className="desk-modal-stack">
          <div className="desk-info-block">
            <h3>Workspace totals</h3>
            <ul className="desk-plain-list">
              <li>Legacy draft rows: {inboxItems.length}</li>
              <li>History: {historyItems.length}</li>
              <li>Library: {libraryEntries.length}</li>
              <li>Favorites: {libraryEntries.filter((entry) => entry.favorite).length}</li>
              <li>Custom collections: {customLibraryCollections.length}</li>
              <li>Saved arrangements: {savedReadingArrangements.length}</li>
              <li>Trash: {trashItems.length}</li>
              <li>Review rounds: {groupedReviewHistory.length}</li>
            </ul>
          </div>

          <div className="desk-info-block">
            <h3>Runtime</h3>
            <ul className="desk-plain-list">
              <li>Client id: {activityClientId || "not available"}</li>
              <li>Speech voices detected: {availableVoices.length}</li>
              <li>
                Workspace state sync:{" "}
                {workspacePersistenceReady ? workspacePersistenceSyncState : "Hydrating"}
              </li>
              <li>Workspace footprint: {workspaceStateFootprint}</li>
              <li>
                Last workspace sync:{" "}
                {workspacePersistenceLastSyncedAt ? formatRelativeTime(workspacePersistenceLastSyncedAt) : "Not yet"}
              </li>
              <li>
                Dict service:{" "}
                {dictHealthStatus === "loading"
                  ? "Checking"
                  : dictHealthStatus === "error"
                    ? "Unavailable"
                    : dictHealth?.ok
                      ? "Ready"
                      : "Unknown"}
              </li>
              <li>
                Active review session:{" "}
                {reviewSession
                  ? reviewSession.pausedAt
                    ? `Paused · ${reviewSession.records.length}/${reviewSession.queue.length} answered`
                    : `Running · card ${Math.min(reviewSession.index + 1, reviewSession.queue.length)} / ${reviewSession.queue.length}`
                  : "None"}
              </li>
              <li>
                Sentence study:{" "}
                {initialWorkspace.kind === "sentence"
                  ? sentenceStudyStatus === "loading"
                    ? "Loading live candidates"
                    : sentenceStudySource === "live"
                      ? `Live lane · ${sentenceStudyMatchedEntryCount} matched · ${sentenceStudyElapsedMs ?? 0}ms${
                          sentenceStudyCached ? " cached" : ""
                        }`
                      : sentenceStudyStatus === "error"
                        ? "Local lane"
                        : "Local lane"
                  : "Inactive"}
              </li>
            </ul>
          </div>

          <div className="desk-info-block">
            <h3>Review engine</h3>
            <div className="desk-diagnostic-grid">
              <div className="desk-diagnostic-card">
                <strong>Due queue</strong>
                <p>
                  {reviewDueDigest.dueNow} due now · {reviewDueDigest.dueSoon} due soon
                </p>
                <small>{reviewDueDigest.fresh} fresh · {reviewDueDigest.scheduled} scheduled later</small>
              </div>
              <div className="desk-diagnostic-card">
                <strong>Weak clusters</strong>
                <p>
                  {reviewMistakeClusters.length > 0
                    ? reviewMistakeClusters.map((cluster) => `${cluster.label} (${cluster.count})`).join(" · ")
                    : "No repeat weak spot detected yet."}
                </p>
                <small>Based on the most recent Again, Hard, or incorrect review records.</small>
              </div>
            </div>
          </div>

          <div className="desk-info-block">
            <h3>Current route context</h3>
            <ul className="desk-plain-list">
              <li>Section: {sectionLabels[initialSection]}</li>
              <li>Lookup kind: {lookupKindLabels[initialKind]}</li>
              <li>Query: {initialWorkspace.query || "empty"}</li>
              <li>Mode: {historyLookupModeLabels[initialWorkspace.mode]}</li>
            </ul>
            <div className="desk-chip-row">
              <button
                className="secondary-button"
                onClick={() => {
                  closeSettings();
                  openQuickCapture();
                }}
                type="button"
              >
                Open Quick Capture
              </button>
              <button
                className="secondary-button"
                onClick={() => {
                  closeSettings();
                  router.push(buildWorkspaceHref({ section: "library" }));
                }}
                type="button"
              >
                Open Library
              </button>
              <button
                className="secondary-button"
                onClick={() => {
                  closeSettings();
                  router.push(buildWorkspaceHref({ section: "review" }));
                }}
                type="button"
              >
                Open Review
              </button>
            </div>
          </div>

          <div className="desk-info-block">
            <h3>Export diagnostics</h3>
            <div className="desk-chip-row">
              <button
                className="secondary-button"
                onClick={() => copyDiagnosticsPayload(diagnosticsSnapshot, "Copied diagnostics snapshot.")}
                type="button"
              >
                Copy Diagnostics JSON
              </button>
              <button
                className="secondary-button"
                onClick={() =>
                  copyDiagnosticsPayload(workspacePersistenceSnapshot, "Copied workspace state snapshot.")
                }
                type="button"
              >
                Copy Workspace State
              </button>
            </div>
          </div>

          <div className="desk-info-block">
            <div className="desk-detail-header">
              <div>
                <h3>Back up workspace</h3>
                <p className="desk-meta-line">
                  Download a full browser backup or import one to replace the current Quick Capture Drafts,
                  History, Library, Review, Preferences, and Trash state.
                </p>
              </div>
              <button className="secondary-button" onClick={downloadWorkspaceBackup} type="button">
                Download Backup
              </button>
            </div>
            <input
              accept="application/json,.json"
              hidden
              onChange={importWorkspaceBackupFile}
              ref={workspaceBackupFileInputRef}
              type="file"
            />
            <div className="desk-chip-row">
              <button
                className="secondary-button"
                onClick={() => workspaceBackupFileInputRef.current?.click()}
                type="button"
              >
                Import Backup
              </button>
              <button className="secondary-button" onClick={resetWorkspaceBackup} type="button">
                Reset Workspace
              </button>
            </div>
            {diagnosticsMessage ? <p className="desk-footer-note">{diagnosticsMessage}</p> : null}
          </div>

          <div className="desk-info-block">
            <div className="desk-batch-bar">
              <span>{selectedTrashIds.size} selected</span>
              <div className="desk-chip-row">
                <button className="secondary-button" onClick={toggleSelectAllTrash} type="button">
                  {selectedTrashIds.size === trashItems.length && trashItems.length > 0 ? "Clear all" : "Select all"}
                </button>
                <button
                  className="secondary-button"
                  disabled={selectedTrashIds.size === 0}
                  onClick={restoreSelectedTrashItems}
                  type="button"
                >
                  Restore
                </button>
                <button
                  className="secondary-button"
                  disabled={selectedTrashIds.size === 0}
                  onClick={deleteSelectedTrashItems}
                  type="button"
                >
                  Delete permanently
                </button>
              </div>
            </div>

            {trashItems.length > 0 ? (
              <div className="desk-review-history">
                {trashItems.map((item) => (
                  <article className="desk-trash-card" key={item.id}>
                    <label className="desk-checkbox-row">
                      <input
                        checked={selectedTrashIds.has(item.id)}
                        onChange={() => toggleTrashSelection(item.id)}
                        type="checkbox"
                      />
                      <span>{item.term}</span>
                    </label>
                    <p>
                      {trashSourceLabels[item.source]} · deleted {formatRelativeTime(item.deletedAt)}
                    </p>
                    <div className="desk-chip-row">
                      <span className="soft-tag">{trashSourceLabels[item.source]}</span>
                      {item.source !== "library" && item.entry.meta?.status ? (
                        <span className="soft-tag">{historyStatusLabels[item.entry.meta.status]}</span>
                      ) : null}
                      {item.source !== "library" && item.entry.meta?.inboxAction ? (
                        <span className="soft-tag">{historyStudyActionLabels[item.entry.meta.inboxAction]}</span>
                      ) : null}
                      {item.source === "library" && item.entry.favorite ? (
                        <span className="soft-tag">Favorite</span>
                      ) : null}
                    </div>
                    <small>{item.entry.detail}</small>
                    {item.entry.context ? <small>{item.entry.context}</small> : null}
                  </article>
                ))}
              </div>
            ) : (
              <div className="desk-empty-inline">
                <p>The trash is empty.</p>
              </div>
            )}
          </div>
        </div>
      );
    }

    return null;
  }

  function renderSettingsDialog(): ReactNode {
    if (!isSettingsOpen) {
      return null;
    }

    return (
      <div className="desk-modal-backdrop" role="presentation">
        <section aria-label="Workspace Settings" className="app-panel desk-modal-panel">
          <div className="desk-detail-header">
            <div>
              <p className="desk-section-title">Settings</p>
              <h2>Workspace Settings</h2>
            </div>
            <button className="secondary-button" onClick={closeSettings} type="button">
              Close
            </button>
          </div>

          <div className="desk-settings-layout">
            <nav className="desk-settings-nav">
              <input
                aria-label="Settings search"
                onChange={(event) => setSettingsSearchDraft(event.target.value)}
                placeholder="Search settings"
                value={settingsSearchDraft}
              />
              {visibleSettingsPanels.map((panel) => (
                <button
                  className={activeSettingsPanel === panel ? "desk-settings-link is-active" : "desk-settings-link"}
                  key={panel}
                  onClick={() => setActiveSettingsPanel(panel)}
                  type="button"
                >
                  {settingsPanelLabels[panel]}
                  {panel === "recovery" ? <em>{trashItems.length}</em> : null}
                </button>
              ))}
            </nav>

            <div>
              {visibleSettingsPanels.length > 0 ? (
                renderSettingsPanelContent()
              ) : (
                <div className="desk-empty-inline">
                  <p>No settings panel matches “{settingsSearchDraft.trim()}”.</p>
                </div>
              )}
            </div>
          </div>
        </section>
      </div>
    );
  }

  let mainContent: ReactNode;
  if (initialSection === "lookup") {
    mainContent = renderLookupSection();
  } else if (initialSection === "history") {
    mainContent = renderActivitySection("history");
  } else if (initialSection === "library") {
    mainContent = renderLibrarySection();
  } else {
    mainContent = renderReviewSection();
  }

  return (
    <main className="workspace-shell desk-workspace-shell" data-section={initialSection} style={workspaceLayoutStyle}>
      <div className="desk-app-frame">
        <aside className="desk-sidebar">
          <div className="desk-sidebar-panel">
            <div className="desk-brand-card">
              <h1>SparrowWord</h1>
            </div>

            <nav className="desk-nav">
              {navigationItems.map((item) => (
                <Link
                  className={item.section === initialSection ? "desk-nav-link is-active" : "desk-nav-link"}
                  href={item.href}
                  key={item.section}
                >
                  <div className="desk-nav-copy">
                    <strong>{item.label}</strong>
                  </div>
                  {item.count !== null ? <em>{item.count}</em> : null}
                </Link>
              ))}
            </nav>

          </div>
        </aside>

        <div
          aria-label="Resize sidebar"
          aria-orientation="vertical"
          className="desk-layout-resizer desk-sidebar-resizer"
          onDoubleClick={resetWorkspaceLayout}
          onPointerDown={(event) => beginWorkspaceResize(event, "sidebarWidth")}
          role="separator"
          tabIndex={0}
          title="Drag to resize. Double-click to reset layout."
        />

        <section className="desk-main">
          <div className="desk-native-topbar">
            <h1>{sectionLabels[initialSection]}</h1>
            <div className="desk-workspace-actions" aria-label="Workspace actions">
              <button className="secondary-button" onClick={openQuickCapture} type="button">
                Quick Capture
              </button>
              <button className="secondary-button" onClick={() => openSettings("general")} type="button">
                Settings
              </button>
            </div>
          </div>
          {mainContent}
        </section>
      </div>
      {renderQuickCaptureDialog()}
      {renderSettingsDialog()}
    </main>
  );
}
