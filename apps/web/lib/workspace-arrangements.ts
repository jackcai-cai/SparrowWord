import type { LibraryEntry } from "./workspace-library";

export type SavedLibraryArrangement = {
  id: string;
  name: string;
  entryIds: string[];
  createdAt: number;
  updatedAt: number;
  mode: "arrangement" | "collection";
};

function sortArrangementsByUpdatedAt(arrangements: SavedLibraryArrangement[]): SavedLibraryArrangement[] {
  return [...arrangements].sort((left, right) => right.updatedAt - left.updatedAt);
}

function uniqueEntryIds(entryIds: string[]): string[] {
  return Array.from(
    new Set(
      entryIds
        .filter((entryId) => typeof entryId === "string")
        .map((entryId) => entryId.trim())
        .filter(Boolean),
    ),
  );
}

function arrangementName(value: string, fallbackIndex: number): string {
  const trimmed = value.trim();
  return trimmed || `Arrangement ${fallbackIndex}`;
}

export function parseStoredLibraryArrangements(value: unknown): SavedLibraryArrangement[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value
    .filter((item) => item && typeof item === "object")
    .map((item, index) => {
      const record = item as Record<string, unknown>;
      const id = typeof record.id === "string" ? record.id.trim() : "";
      const entryIds = uniqueEntryIds(Array.isArray(record.entryIds) ? record.entryIds as string[] : []);
      if (!id || entryIds.length === 0) {
        return null;
      }

      const createdAt =
        typeof record.createdAt === "number" && Number.isFinite(record.createdAt)
          ? record.createdAt
          : Date.now();
      const updatedAt =
        typeof record.updatedAt === "number" && Number.isFinite(record.updatedAt)
          ? record.updatedAt
          : createdAt;

      return {
        id,
        name: arrangementName(typeof record.name === "string" ? record.name : "", index + 1),
        entryIds,
        createdAt,
        updatedAt,
        mode: record.mode === "collection" ? "collection" : "arrangement",
      } satisfies SavedLibraryArrangement;
    })
    .filter((item): item is SavedLibraryArrangement => item !== null)
    .sort((left, right) => right.updatedAt - left.updatedAt);
}

export function createLibraryArrangement(
  arrangements: SavedLibraryArrangement[],
  name: string,
  entryIds: string[],
  mode: SavedLibraryArrangement["mode"] = "arrangement",
): SavedLibraryArrangement[] {
  const cleanedEntryIds = uniqueEntryIds(entryIds);
  if (cleanedEntryIds.length === 0) {
    return arrangements;
  }

  const now = Date.now();
  const arrangement: SavedLibraryArrangement = {
    id: `saved-arrangement-${now}-${Math.random().toString(36).slice(2, 8)}`,
    name: arrangementName(name, arrangements.length + 1),
    entryIds: cleanedEntryIds,
    createdAt: now,
    updatedAt: now,
    mode,
  };

  return sortArrangementsByUpdatedAt([arrangement, ...arrangements]);
}

export function addEntriesToLibraryArrangement(
  arrangements: SavedLibraryArrangement[],
  arrangementId: string,
  entryIds: string[],
): SavedLibraryArrangement[] {
  const cleanedEntryIds = uniqueEntryIds(entryIds);
  if (cleanedEntryIds.length === 0) {
    return arrangements;
  }

  return sortArrangementsByUpdatedAt(
    arrangements.map((arrangement) =>
      arrangement.id === arrangementId
        ? {
            ...arrangement,
            entryIds: uniqueEntryIds([...arrangement.entryIds, ...cleanedEntryIds]),
            updatedAt: Date.now(),
          }
        : arrangement,
    ),
  );
}

export function removeEntriesFromLibraryArrangement(
  arrangements: SavedLibraryArrangement[],
  arrangementId: string,
  entryIds: string[],
): SavedLibraryArrangement[] {
  const removedIds = new Set(uniqueEntryIds(entryIds));
  if (removedIds.size === 0) {
    return arrangements;
  }

  return sortArrangementsByUpdatedAt(
    arrangements
      .map((arrangement) =>
        arrangement.id === arrangementId
          ? {
              ...arrangement,
              entryIds: arrangement.entryIds.filter((entryId) => !removedIds.has(entryId)),
              updatedAt: Date.now(),
            }
          : arrangement,
      )
      .filter((arrangement) => arrangement.entryIds.length > 0),
  );
}

export function removeLibraryArrangement(
  arrangements: SavedLibraryArrangement[],
  arrangementId: string,
): SavedLibraryArrangement[] {
  return arrangements.filter((arrangement) => arrangement.id !== arrangementId);
}

export function renameLibraryArrangement(
  arrangements: SavedLibraryArrangement[],
  arrangementId: string,
  name: string,
): SavedLibraryArrangement[] {
  const trimmedName = name.trim();
  if (!trimmedName) {
    return arrangements;
  }

  return sortArrangementsByUpdatedAt(
    arrangements.map((arrangement) =>
      arrangement.id === arrangementId
        ? {
            ...arrangement,
            name: trimmedName,
            updatedAt: Date.now(),
          }
        : arrangement,
    ),
  );
}

export function replaceLibraryArrangementEntries(
  arrangements: SavedLibraryArrangement[],
  arrangementId: string,
  entryIds: string[],
): SavedLibraryArrangement[] {
  const cleanedEntryIds = uniqueEntryIds(entryIds);
  if (cleanedEntryIds.length === 0) {
    return arrangements;
  }

  return sortArrangementsByUpdatedAt(
    arrangements.map((arrangement) =>
      arrangement.id === arrangementId
        ? {
            ...arrangement,
            entryIds: cleanedEntryIds,
            updatedAt: Date.now(),
          }
        : arrangement,
    ),
  );
}

export function moveEntryInLibraryArrangement(
  arrangements: SavedLibraryArrangement[],
  arrangementId: string,
  entryId: string,
  direction: -1 | 1,
): SavedLibraryArrangement[] {
  return sortArrangementsByUpdatedAt(
    arrangements.map((arrangement) => {
      if (arrangement.id !== arrangementId) {
        return arrangement;
      }

      const currentIndex = arrangement.entryIds.findIndex((candidate) => candidate === entryId);
      if (currentIndex < 0) {
        return arrangement;
      }

      const nextIndex = currentIndex + direction;
      if (nextIndex < 0 || nextIndex >= arrangement.entryIds.length) {
        return arrangement;
      }

      const nextEntryIds = [...arrangement.entryIds];
      [nextEntryIds[currentIndex], nextEntryIds[nextIndex]] = [nextEntryIds[nextIndex]!, nextEntryIds[currentIndex]!];

      return {
        ...arrangement,
        entryIds: nextEntryIds,
        updatedAt: Date.now(),
      };
    }),
  );
}

export function normalizeLibraryArrangements(
  arrangements: SavedLibraryArrangement[],
  entries: LibraryEntry[],
): SavedLibraryArrangement[] {
  const validIds = new Set(entries.map((entry) => entry.id));

  return arrangements
    .map((arrangement) => ({
      ...arrangement,
      entryIds: arrangement.entryIds.filter((entryId) => validIds.has(entryId)),
    }))
    .filter((arrangement) => arrangement.entryIds.length > 0);
}

export function entriesForLibraryArrangement(
  entries: LibraryEntry[],
  arrangement: SavedLibraryArrangement | null | undefined,
): LibraryEntry[] {
  if (!arrangement) {
    return [];
  }

  const lookup = new Map(entries.map((entry) => [entry.id, entry]));
  return arrangement.entryIds
    .map((entryId) => lookup.get(entryId) ?? null)
    .filter((entry): entry is LibraryEntry => entry !== null);
}
