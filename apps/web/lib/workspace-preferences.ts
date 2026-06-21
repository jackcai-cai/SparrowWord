import type { ReviewQuestionStrategy, ReviewQuestionType } from "./review";

export const automaticPronunciationVoiceURI = "automatic";

export const workspaceLayoutLimits = {
  sidebarWidth: {
    min: 168,
    max: 300,
  },
  contentRailWidth: {
    min: 300,
    max: 580,
  },
} as const;

export type WorkspaceLayoutPreferences = {
  sidebarWidth: number;
  contentRailWidth: number;
};

export type WorkspacePaneLayoutPreference = "automatic" | "horizontal" | "vertical";

export type WorkspaceReviewPreferences = {
  questionStrategy: ReviewQuestionStrategy;
  questionTypes: ReviewQuestionType[];
};

export type WorkspacePreferences = {
  excludeMasteredFromReview: boolean;
  isLibraryCleanMode: boolean;
  layout: WorkspaceLayoutPreferences;
  workspacePaneLayoutPreference: WorkspacePaneLayoutPreference;
  showLookupReferenceTags: boolean;
  pronunciationVoiceURI: string;
  review: WorkspaceReviewPreferences;
};

export function defaultWorkspacePreferences(): WorkspacePreferences {
  return {
    excludeMasteredFromReview: true,
    isLibraryCleanMode: false,
    layout: {
      sidebarWidth: 196,
      contentRailWidth: 386,
    },
    workspacePaneLayoutPreference: "automatic",
    showLookupReferenceTags: false,
    pronunciationVoiceURI: automaticPronunciationVoiceURI,
    review: {
      questionStrategy: "smart",
      questionTypes: ["multipleChoice", "fillIn", "flashcards"],
    },
  };
}

function clampLayoutValue(value: unknown, min: number, max: number, fallback: number): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return fallback;
  }

  return Math.min(Math.max(Math.round(value), min), max);
}

function sanitizeVoiceURI(value: unknown): string {
  if (typeof value !== "string") {
    return automaticPronunciationVoiceURI;
  }

  const trimmed = value.trim();
  return trimmed || automaticPronunciationVoiceURI;
}

function parseStoredReviewQuestionStrategy(value: unknown): ReviewQuestionStrategy {
  return value === "custom" ? "custom" : "smart";
}

function parseStoredWorkspacePaneLayoutPreference(value: unknown): WorkspacePaneLayoutPreference {
  return value === "horizontal" || value === "vertical" ? value : "automatic";
}

function parseStoredReviewQuestionTypes(value: unknown): ReviewQuestionType[] {
  const defaults = defaultWorkspacePreferences().review.questionTypes;
  if (!Array.isArray(value)) {
    return defaults;
  }

  const next: ReviewQuestionType[] = [];
  for (const item of value) {
    if (
      (item === "multipleChoice" || item === "fillIn" || item === "flashcards") &&
      !next.includes(item)
    ) {
      next.push(item);
    }
  }

  return next.length > 0 ? next : defaults;
}

export function parseStoredWorkspaceReviewPreferences(value: unknown): WorkspaceReviewPreferences {
  const defaults = defaultWorkspacePreferences().review;
  if (!value || typeof value !== "object") {
    return defaults;
  }

  const record = value as Record<string, unknown>;
  return {
    questionStrategy: parseStoredReviewQuestionStrategy(record.questionStrategy),
    questionTypes: parseStoredReviewQuestionTypes(record.questionTypes),
  };
}

export function parseStoredWorkspaceLayoutPreferences(value: unknown): WorkspaceLayoutPreferences {
  const defaults = defaultWorkspacePreferences().layout;
  if (!value || typeof value !== "object") {
    return defaults;
  }

  const record = value as Record<string, unknown>;
  return {
    sidebarWidth: clampLayoutValue(
      record.sidebarWidth,
      workspaceLayoutLimits.sidebarWidth.min,
      workspaceLayoutLimits.sidebarWidth.max,
      defaults.sidebarWidth,
    ),
    contentRailWidth: clampLayoutValue(
      record.contentRailWidth,
      workspaceLayoutLimits.contentRailWidth.min,
      workspaceLayoutLimits.contentRailWidth.max,
      defaults.contentRailWidth,
    ),
  };
}

export function parseStoredWorkspacePreferences(value: unknown): WorkspacePreferences {
  const defaults = defaultWorkspacePreferences();
  if (!value || typeof value !== "object") {
    return defaults;
  }

  const record = value as Record<string, unknown>;
  return {
    excludeMasteredFromReview:
      typeof record.excludeMasteredFromReview === "boolean"
        ? record.excludeMasteredFromReview
        : defaults.excludeMasteredFromReview,
    isLibraryCleanMode:
      typeof record.isLibraryCleanMode === "boolean"
        ? record.isLibraryCleanMode
        : defaults.isLibraryCleanMode,
    layout: parseStoredWorkspaceLayoutPreferences(record.layout),
    workspacePaneLayoutPreference: parseStoredWorkspacePaneLayoutPreference(record.workspacePaneLayoutPreference),
    showLookupReferenceTags:
      typeof record.showLookupReferenceTags === "boolean"
        ? record.showLookupReferenceTags
        : defaults.showLookupReferenceTags,
    pronunciationVoiceURI: sanitizeVoiceURI(record.pronunciationVoiceURI),
    review: parseStoredWorkspaceReviewPreferences(record.review),
  };
}
