import type { ActivityItem } from "./mock-workspace";
import { parseStoredLibraryEntries, type LibraryEntry } from "./workspace-library";
import { parseStoredEditableEntryMap, type WorkspaceEditableEntry } from "./workspace-entry";

export type TrashSourceKind = "inbox" | "history" | "library";

type ActivityTrashItem<Source extends "inbox" | "history"> = {
  id: string;
  source: Source;
  term: string;
  deletedAt: number;
  entry: ActivityItem;
  draft?: WorkspaceEditableEntry | null;
};

type LibraryTrashItem = {
  id: string;
  source: "library";
  term: string;
  deletedAt: number;
  entry: LibraryEntry;
};

export type WorkspaceTrashItem =
  | ActivityTrashItem<"inbox">
  | ActivityTrashItem<"history">
  | LibraryTrashItem;

function sanitizeTrashTimestamp(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : Date.now();
}

export function trashItemFromActivity(
  source: "inbox" | "history",
  entry: ActivityItem,
  draft?: WorkspaceEditableEntry | null,
): WorkspaceTrashItem {
  return {
    id: `trash-${source}-${entry.id}-${Date.now()}`,
    source,
    term: entry.term,
    deletedAt: Date.now(),
    entry,
    draft: draft ?? null,
  };
}

export function trashItemFromLibrary(entry: LibraryEntry): WorkspaceTrashItem {
  return {
    id: `trash-library-${entry.id}-${Date.now()}`,
    source: "library",
    term: entry.term,
    deletedAt: Date.now(),
    entry,
  };
}

export function appendTrashItems(
  current: WorkspaceTrashItem[],
  additions: WorkspaceTrashItem[],
): WorkspaceTrashItem[] {
  if (additions.length === 0) {
    return current;
  }

  return [...additions, ...current]
    .sort((left, right) => right.deletedAt - left.deletedAt)
    .slice(0, 240);
}

export function removeTrashItems(current: WorkspaceTrashItem[], itemIds: Set<string>): WorkspaceTrashItem[] {
  if (itemIds.size === 0) {
    return current;
  }

  return current.filter((item) => !itemIds.has(item.id));
}

function isActivityEntry(value: unknown): value is ActivityItem {
  return Boolean(
    value &&
      typeof value === "object" &&
      typeof (value as ActivityItem).id === "string" &&
      typeof (value as ActivityItem).term === "string" &&
      typeof (value as ActivityItem).detail === "string" &&
      typeof (value as ActivityItem).context === "string" &&
      typeof (value as ActivityItem).savedAt === "number",
  );
}

export function parseStoredTrashItems(value: unknown): WorkspaceTrashItem[] {
  if (!Array.isArray(value)) {
    return [];
  }

  const parsed: WorkspaceTrashItem[] = [];

  for (const item of value) {
    if (!item || typeof item !== "object") {
      continue;
    }

    const record = item as Record<string, unknown>;
    const deletedAt = sanitizeTrashTimestamp(record.deletedAt);
    const term = typeof record.term === "string" ? record.term : "";
    const id = typeof record.id === "string" ? record.id : "";

    if ((record.source === "inbox" || record.source === "history") && isActivityEntry(record.entry)) {
      const parsedDraft = record.draft
        ? parseStoredEditableEntryMap({ restored: record.draft }).restored ?? null
        : null;
      parsed.push({
        id,
        source: record.source,
        term: term || record.entry.term,
        deletedAt,
        entry: record.entry,
        draft: parsedDraft,
      });
      continue;
    }

    const parsedLibraryEntry = parseStoredLibraryEntries([record.entry])[0];
    if (record.source === "library" && parsedLibraryEntry) {
      parsed.push({
        id,
        source: "library",
        term: term || parsedLibraryEntry.term,
        deletedAt,
        entry: parsedLibraryEntry,
      });
    }
  }

  return parsed.sort((left, right) => right.deletedAt - left.deletedAt);
}
