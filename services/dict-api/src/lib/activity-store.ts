import { randomUUID } from "node:crypto";
import { existsSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";
import Database from "better-sqlite3";

export type ActivityKind = "history" | "inbox";

export type ActivityHistoryStatus = "inProgress" | "completed" | "cancelled" | "failed";

export type ActivityInboxAction =
  | "createdInbox"
  | "updatedInbox"
  | "skippedExistingLibrary"
  | "historyOnly"
  | "awaitingCandidateSelection";

export type ActivityMeta = {
  originalQuery?: string;
  sourceLabel?: string;
  modelName?: string | null;
  lookupKind?: "word" | "phrase" | "sentence";
  lookupMode?: "empty" | "lookup" | "reverse" | "no-result";
  inboxAction?: ActivityInboxAction;
  status?: ActivityHistoryStatus;
  statusMessage?: string | null;
};

export type ActivityItem = {
  id: string;
  term: string;
  detail: string;
  context: string;
  savedAt: number;
  meta?: ActivityMeta | null;
};

export type ActivityStoreHealth = {
  available: boolean;
  path: string;
};

export type ActivityTermBucket = {
  term: string;
  count: number;
  lastSavedAt: number;
};

export type ActivitySummary = {
  kind: ActivityKind;
  totalEntries: number;
  uniqueClients: number;
  topTerms: ActivityTermBucket[];
};

export type WorkspaceClientState = {
  snapshot: unknown | null;
  updatedAt: number | null;
};

type WorkspaceStatePayload = Record<string, unknown>;

type ActivityRow = {
  id: string;
  term: string;
  detail: string;
  context: string;
  saved_at: number;
  meta_json: string | null;
};

type CountRow = {
  count: number;
};

type TopTermRow = {
  term: string;
  count: number;
  last_saved_at: number;
};

type WorkspaceStateRow = {
  payload_json: string | null;
  updated_at: number;
};

type ActivityPayload = {
  term: string;
  detail?: string;
  context?: string;
  savedAt?: number;
  meta?: ActivityMeta | null;
};

const inboxMaxItemsPerFeed = 24;
const historyMaxItemsPerFeed = 160;

const activityDbPath =
  process.env.SPARROWWORD_ACTIVITY_DB?.trim() ||
  fileURLToPath(new URL("../../data/workspace-state.sqlite", import.meta.url));

type SQLiteDatabase = Database.Database;
let activityDb: SQLiteDatabase | null | undefined;

function normalizeClientId(clientId: string): string {
  return clientId.trim().slice(0, 128);
}

function normalizeTerm(term: string): string {
  return term
    .trim()
    .replace(/\s+/g, " ")
    .toLowerCase()
    .slice(0, 160);
}

function sanitizeTerm(term: string): string {
  return term.trim().replace(/\s+/g, " ").slice(0, 160);
}

function sanitizeDetail(detail: string | undefined, kind: ActivityKind): string {
  const fallback = kind === "history" ? "lookup result visited" : "saved from workspace";
  const normalized = detail?.trim().replace(/\s+/g, " ") ?? "";
  return (normalized || fallback).slice(0, 280);
}

function sanitizeContext(context: string | undefined): string {
  const normalized = context?.trim().replace(/\s+/g, " ") ?? "";
  return normalized.slice(0, 1200);
}

function sanitizeSavedAt(savedAt: number | undefined): number {
  if (typeof savedAt !== "number" || !Number.isFinite(savedAt)) {
    return Date.now();
  }

  const rounded = Math.round(savedAt);
  return rounded > 0 ? rounded : Date.now();
}

function maxItemsPerFeed(kind: ActivityKind): number {
  return kind === "history" ? historyMaxItemsPerFeed : inboxMaxItemsPerFeed;
}

function storageNormalizedTerm(kind: ActivityKind, term: string, savedAt: number): string {
  const normalized = normalizeTerm(term);
  if (kind === "inbox") {
    return normalized;
  }

  return `${normalized}::${savedAt}::${randomUUID().slice(0, 8)}`;
}

function sanitizeOptionalText(value: unknown, maxLength: number): string | null {
  if (typeof value !== "string") {
    return null;
  }

  const normalized = value.trim().replace(/\s+/g, " ");
  return normalized ? normalized.slice(0, maxLength) : null;
}

function sanitizeActivityMeta(meta: ActivityMeta | null | undefined): string | null {
  if (!meta || typeof meta !== "object") {
    return null;
  }

  const sanitized: ActivityMeta = {};
  const originalQuery = sanitizeOptionalText(meta.originalQuery, 160);
  const sourceLabel = sanitizeOptionalText(meta.sourceLabel, 120);
  const modelName = sanitizeOptionalText(meta.modelName, 120);
  const statusMessage = sanitizeOptionalText(meta.statusMessage, 320);
  const lookupKind = sanitizeOptionalText(meta.lookupKind, 24);
  const lookupMode = sanitizeOptionalText(meta.lookupMode, 24);

  if (originalQuery) {
    sanitized.originalQuery = originalQuery;
  }

  if (sourceLabel) {
    sanitized.sourceLabel = sourceLabel;
  }

  if (modelName) {
    sanitized.modelName = modelName;
  }

  if (lookupKind === "word" || lookupKind === "phrase" || lookupKind === "sentence") {
    sanitized.lookupKind = lookupKind;
  }

  if (lookupMode === "empty" || lookupMode === "lookup" || lookupMode === "reverse" || lookupMode === "no-result") {
    sanitized.lookupMode = lookupMode;
  }

  if (
    meta.inboxAction === "createdInbox" ||
    meta.inboxAction === "updatedInbox" ||
    meta.inboxAction === "skippedExistingLibrary" ||
    meta.inboxAction === "historyOnly" ||
    meta.inboxAction === "awaitingCandidateSelection"
  ) {
    sanitized.inboxAction = meta.inboxAction;
  }

  if (
    meta.status === "inProgress" ||
    meta.status === "completed" ||
    meta.status === "cancelled" ||
    meta.status === "failed"
  ) {
    sanitized.status = meta.status;
  }

  if (statusMessage) {
    sanitized.statusMessage = statusMessage;
  }

  return Object.keys(sanitized).length > 0 ? JSON.stringify(sanitized) : null;
}

function sanitizeWorkspaceStatePayload(payload: unknown): string | null {
  if (!payload || typeof payload !== "object") {
    return null;
  }

  try {
    const json = JSON.stringify(payload);
    if (!json || json === "{}" || json === "[]") {
      return null;
    }

    return json.length <= 2_000_000 ? json : null;
  } catch {
    return null;
  }
}

function parseWorkspaceStatePayload(payloadJson: string | null): unknown | null {
  if (!payloadJson) {
    return null;
  }

  try {
    return JSON.parse(payloadJson);
  } catch {
    return null;
  }
}

function isRecord(value: unknown): value is WorkspaceStatePayload {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function numericField(value: unknown, ...keys: string[]): number {
  if (!isRecord(value)) {
    return 0;
  }

  for (const key of keys) {
    const candidate = value[key];
    if (typeof candidate === "number" && Number.isFinite(candidate)) {
      return candidate;
    }
  }

  return 0;
}

function libraryEntryKey(value: unknown): string {
  if (!isRecord(value)) {
    return "";
  }

  const id = typeof value.id === "string" ? value.id.trim() : "";
  if (id) {
    return id;
  }

  const term = typeof value.term === "string" ? value.term.trim().replace(/\s+/g, " ").toLowerCase() : "";
  return term;
}

function mergeLibraryEntries(existing: unknown, incoming: unknown): unknown[] | undefined {
  if (!Array.isArray(existing) && !Array.isArray(incoming)) {
    return undefined;
  }

  const merged = new Map<string, unknown>();
  for (const item of [...(Array.isArray(existing) ? existing : []), ...(Array.isArray(incoming) ? incoming : [])]) {
    const key = libraryEntryKey(item);
    if (!key) {
      continue;
    }

    const current = merged.get(key);
    if (!current) {
      merged.set(key, item);
      continue;
    }

    const currentUpdatedAt = numericField(current, "updatedAt", "savedAt");
    const nextUpdatedAt = numericField(item, "updatedAt", "savedAt");
    if (nextUpdatedAt >= currentUpdatedAt) {
      merged.set(key, item);
    }
  }

  return Array.from(merged.values()).sort(
    (left, right) => numericField(right, "updatedAt", "savedAt") - numericField(left, "updatedAt", "savedAt"),
  );
}

function reviewRecordKey(value: unknown): string {
  if (!isRecord(value)) {
    return "";
  }

  const sessionId = typeof value.sessionId === "string" ? value.sessionId : "";
  const candidateId = typeof value.candidateId === "string" ? value.candidateId : "";
  const term = typeof value.term === "string" ? value.term : "";
  const answeredAt = numericField(value, "answeredAt");
  if (!sessionId || !candidateId || !term || !answeredAt) {
    return "";
  }

  return `${sessionId}::${candidateId}::${term}::${answeredAt}`;
}

function mergeReviewHistory(existing: unknown, incoming: unknown): unknown[] | undefined {
  if (!Array.isArray(incoming)) {
    return Array.isArray(existing) ? existing : undefined;
  }

  return incoming
    .filter((item) => reviewRecordKey(item))
    .sort((left, right) => numericField(right, "answeredAt") - numericField(left, "answeredAt"))
    .slice(0, 160);
}

function mergeReviewStateMaps(existing: unknown, incoming: unknown): Record<string, unknown> | undefined {
  if (isRecord(incoming)) {
    return incoming;
  }

  return isRecord(existing) ? existing : undefined;
}

function mergeReviewSession(existing: unknown, incoming: unknown): unknown {
  return incoming ?? existing;
}

export function mergeWorkspaceStateSnapshots(
  existingPayload: unknown,
  incomingPayload: unknown,
): unknown {
  if (!isRecord(existingPayload)) {
    return incomingPayload;
  }
  if (!isRecord(incomingPayload)) {
    return existingPayload;
  }

  const merged: WorkspaceStatePayload = {
    ...existingPayload,
    ...incomingPayload,
  };

  const mergedLibraryEntries = mergeLibraryEntries(existingPayload.libraryEntries, incomingPayload.libraryEntries);
  if (mergedLibraryEntries) {
    merged.libraryEntries = mergedLibraryEntries;
  }

  const mergedReviewHistory = mergeReviewHistory(existingPayload.reviewHistory, incomingPayload.reviewHistory);
  if (mergedReviewHistory) {
    merged.reviewHistory = mergedReviewHistory;
  }

  const mergedReviewStateMap = mergeReviewStateMaps(existingPayload.reviewStateMap, incomingPayload.reviewStateMap);
  if (mergedReviewStateMap) {
    merged.reviewStateMap = mergedReviewStateMap;
  }

  merged.reviewSession = mergeReviewSession(existingPayload.reviewSession, incomingPayload.reviewSession);
  return merged;
}

function parseActivityMeta(metaJson: string | null): ActivityMeta | null {
  if (!metaJson) {
    return null;
  }

  try {
    const parsed = JSON.parse(metaJson) as ActivityMeta;
    return {
      originalQuery: sanitizeOptionalText(parsed.originalQuery, 160) ?? undefined,
      sourceLabel: sanitizeOptionalText(parsed.sourceLabel, 120) ?? undefined,
      modelName: sanitizeOptionalText(parsed.modelName, 120),
      lookupKind:
        parsed.lookupKind === "word" ||
        parsed.lookupKind === "phrase" ||
        parsed.lookupKind === "sentence"
          ? parsed.lookupKind
          : undefined,
      lookupMode:
        parsed.lookupMode === "empty" ||
        parsed.lookupMode === "lookup" ||
        parsed.lookupMode === "reverse" ||
        parsed.lookupMode === "no-result"
          ? parsed.lookupMode
          : undefined,
      inboxAction:
        parsed.inboxAction === "createdInbox" ||
        parsed.inboxAction === "updatedInbox" ||
        parsed.inboxAction === "skippedExistingLibrary" ||
        parsed.inboxAction === "historyOnly" ||
        parsed.inboxAction === "awaitingCandidateSelection"
          ? parsed.inboxAction
          : undefined,
      status:
        parsed.status === "inProgress" ||
        parsed.status === "completed" ||
        parsed.status === "cancelled" ||
        parsed.status === "failed"
          ? parsed.status
          : undefined,
      statusMessage: sanitizeOptionalText(parsed.statusMessage, 320),
    };
  } catch {
    return null;
  }
}

function getActivityDb(): SQLiteDatabase {
  if (activityDb) {
    return activityDb;
  }

  const dbDir = dirname(activityDbPath);
  if (!existsSync(dbDir)) {
    mkdirSync(dbDir, { recursive: true });
  }

  const db = new Database(activityDbPath);
  db.exec(`
    PRAGMA journal_mode = WAL;

    CREATE TABLE IF NOT EXISTS activity_entries (
      id TEXT PRIMARY KEY,
      kind TEXT NOT NULL CHECK(kind IN ('history', 'inbox')),
      client_id TEXT NOT NULL,
      term TEXT NOT NULL,
      normalized_term TEXT NOT NULL,
      detail TEXT NOT NULL,
      context TEXT NOT NULL DEFAULT '',
      meta_json TEXT,
      saved_at INTEGER NOT NULL,
      created_at INTEGER NOT NULL DEFAULT (unixepoch() * 1000),
      UNIQUE(kind, client_id, normalized_term)
    );

    CREATE INDEX IF NOT EXISTS activity_entries_feed_idx
      ON activity_entries(kind, client_id, saved_at DESC);

    CREATE TABLE IF NOT EXISTS workspace_client_state (
      client_id TEXT PRIMARY KEY,
      payload_json TEXT,
      updated_at INTEGER NOT NULL
    );
  `);

  const tableColumns = db
    .prepare("PRAGMA table_info(activity_entries)")
    .all() as Array<{ name: string }>;
  const hasContextColumn = tableColumns.some((column) => column.name === "context");
  if (!hasContextColumn) {
    db.exec("ALTER TABLE activity_entries ADD COLUMN context TEXT NOT NULL DEFAULT '';");
  }
  const hasMetaColumn = tableColumns.some((column) => column.name === "meta_json");
  if (!hasMetaColumn) {
    db.exec("ALTER TABLE activity_entries ADD COLUMN meta_json TEXT;");
  }

  activityDb = db;
  return db;
}

function mapActivityRows(rows: ActivityRow[]): ActivityItem[] {
  return rows.map((row) => ({
    id: row.id,
    term: row.term,
    detail: row.detail,
    context: row.context,
    savedAt: row.saved_at,
    meta: parseActivityMeta(row.meta_json),
  }));
}

function trimActivityFeed(
  db: SQLiteDatabase,
  kind: ActivityKind,
  clientId: string,
  limit: number,
) {
  db.prepare(`
    DELETE FROM activity_entries
    WHERE kind = ?
      AND client_id = ?
      AND id NOT IN (
        SELECT id
        FROM activity_entries
        WHERE kind = ?
          AND client_id = ?
        ORDER BY saved_at DESC, rowid DESC
        LIMIT ?
      )
  `).run(kind, clientId, kind, clientId, limit);
}

export function getActivityStoreHealth(): ActivityStoreHealth {
  return {
    available: true,
    path: activityDbPath,
  };
}

export function readWorkspaceClientState(clientId: string): WorkspaceClientState {
  const normalizedClientId = normalizeClientId(clientId);
  if (!normalizedClientId) {
    return {
      snapshot: null,
      updatedAt: null,
    };
  }

  const db = getActivityDb();
  const row = db
    .prepare(`
      SELECT payload_json, updated_at
      FROM workspace_client_state
      WHERE client_id = ?
      LIMIT 1
    `)
    .get(normalizedClientId) as WorkspaceStateRow | undefined;

  if (!row) {
    return {
      snapshot: null,
      updatedAt: null,
    };
  }

  return {
    snapshot: parseWorkspaceStatePayload(row.payload_json),
    updatedAt: typeof row.updated_at === "number" ? row.updated_at : null,
  };
}

export function writeWorkspaceClientState(clientId: string, payload: unknown): WorkspaceClientState {
  const normalizedClientId = normalizeClientId(clientId);
  if (!normalizedClientId) {
    return {
      snapshot: null,
      updatedAt: null,
    };
  }

  const existingState = readWorkspaceClientState(normalizedClientId);
  const mergedPayload = mergeWorkspaceStateSnapshots(existingState.snapshot, payload);
  const payloadJson = sanitizeWorkspaceStatePayload(mergedPayload);
  const updatedAt = Date.now();
  const db = getActivityDb();
  db.prepare(`
    INSERT INTO workspace_client_state (
      client_id,
      payload_json,
      updated_at
    )
    VALUES (?, ?, ?)
    ON CONFLICT(client_id)
    DO UPDATE SET
      payload_json = excluded.payload_json,
      updated_at = excluded.updated_at
  `).run(normalizedClientId, payloadJson, updatedAt);

  return {
    snapshot: parseWorkspaceStatePayload(payloadJson),
    updatedAt,
  };
}

export function listActivityItems(
  kind: ActivityKind,
  clientId: string,
  limit = maxItemsPerFeed(kind),
): ActivityItem[] {
  const normalizedClientId = normalizeClientId(clientId);
  if (!normalizedClientId) {
    return [];
  }

  const db = getActivityDb();
  const rows = db
    .prepare(`
      SELECT id, term, detail, saved_at
      , context, meta_json
      FROM activity_entries
      WHERE kind = ?
        AND client_id = ?
      ORDER BY saved_at DESC, rowid DESC
      LIMIT ?
    `)
    .all(kind, normalizedClientId, limit) as ActivityRow[];

  return mapActivityRows(rows);
}

export function upsertActivityItem(
  kind: ActivityKind,
  clientId: string,
  payload: ActivityPayload,
  limit = maxItemsPerFeed(kind),
): ActivityItem[] {
  const normalizedClientId = normalizeClientId(clientId);
  const term = sanitizeTerm(payload.term);

  if (!normalizedClientId || !term) {
    return [];
  }

  const savedAt = sanitizeSavedAt(payload.savedAt);
  const db = getActivityDb();
  db.prepare(`
    INSERT INTO activity_entries (
      id,
      kind,
      client_id,
      term,
      normalized_term,
      detail,
      context,
      meta_json,
      saved_at
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(kind, client_id, normalized_term)
    DO UPDATE SET
      term = excluded.term,
      detail = excluded.detail,
      context = excluded.context,
      meta_json = excluded.meta_json,
      saved_at = excluded.saved_at
  `).run(
    randomUUID(),
    kind,
    normalizedClientId,
    term,
    storageNormalizedTerm(kind, term, savedAt),
    sanitizeDetail(payload.detail, kind),
    sanitizeContext(payload.context),
    sanitizeActivityMeta(payload.meta),
    savedAt,
  );

  trimActivityFeed(db, kind, normalizedClientId, limit);
  return listActivityItems(kind, normalizedClientId, limit);
}

export function removeActivityItem(
  kind: ActivityKind,
  clientId: string,
  itemId: string,
  limit = maxItemsPerFeed(kind),
): ActivityItem[] {
  const normalizedClientId = normalizeClientId(clientId);
  const normalizedItemId = itemId.trim().slice(0, 128);

  if (!normalizedClientId || !normalizedItemId) {
    return [];
  }

  const db = getActivityDb();
  db.prepare(`
    DELETE FROM activity_entries
    WHERE kind = ?
      AND client_id = ?
      AND id = ?
  `).run(kind, normalizedClientId, normalizedItemId);

  return listActivityItems(kind, normalizedClientId, limit);
}

export function clearActivityItems(
  kind: ActivityKind,
  clientId: string,
): ActivityItem[] {
  const normalizedClientId = normalizeClientId(clientId);
  if (!normalizedClientId) {
    return [];
  }

  const db = getActivityDb();
  db.prepare(`
    DELETE FROM activity_entries
    WHERE kind = ?
      AND client_id = ?
  `).run(kind, normalizedClientId);

  return [];
}

export function summarizeActivity(
  kind: ActivityKind,
  limit = 6,
): ActivitySummary {
  const db = getActivityDb();
  const totalEntriesRow = db
    .prepare(`
      SELECT COUNT(*) AS count
      FROM activity_entries
      WHERE kind = ?
    `)
    .get(kind) as CountRow | undefined;

  const uniqueClientsRow = db
    .prepare(`
      SELECT COUNT(DISTINCT client_id) AS count
      FROM activity_entries
      WHERE kind = ?
    `)
    .get(kind) as CountRow | undefined;

  const topTerms = (
    db
      .prepare(`
        SELECT term, COUNT(*) AS count, MAX(saved_at) AS last_saved_at
        FROM activity_entries
        WHERE kind = ?
        GROUP BY normalized_term
        ORDER BY count DESC, last_saved_at DESC, term ASC
        LIMIT ?
      `)
      .all(kind, limit) as TopTermRow[]
  ).map((row) => ({
    term: row.term,
    count: row.count,
    lastSavedAt: row.last_saved_at,
  }));

  return {
    kind,
    totalEntries: totalEntriesRow?.count ?? 0,
    uniqueClients: uniqueClientsRow?.count ?? 0,
    topTerms,
  };
}
