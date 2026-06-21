import Fastify from "fastify";

import {
  type ActivityMeta,
  type ActivityItem as StoredActivityItem,
  type ActivityTermBucket,
  clearActivityItems,
  getActivityStoreHealth,
  listActivityItems,
  readWorkspaceClientState,
  removeActivityItem,
  summarizeActivity,
  upsertActivityItem,
  writeWorkspaceClientState,
} from "./lib/activity-store.js";
import {
  getFeedbackLogPath,
  listRecentFeedback,
  persistFeedback,
  summarizeFeedback,
} from "./lib/feedback-store.js";
import {
  getDictionaryHealth,
  lookupDictionaryEntry,
  reverseLookupDictionaryEntries,
  studySentenceCandidates,
  suggestDictionaryEntries,
} from "./lib/offline-dictionary.js";

type ApiResp<T> = {
  request_id: string;
  ok: boolean;
  data: T | null;
  error: {
    code: string;
    message: string;
  } | null;
};

type RuntimeCacheEntry<T> = {
  payload: T;
  expiresAt: number;
  computedInMs: number;
  lastAccessedAt: number;
};

type RuntimeCache<T> = {
  ttlMs: number;
  limit: number;
  hits: number;
  misses: number;
  entries: Map<string, RuntimeCacheEntry<T>>;
};

function ok<T>(requestId: string, data: T): ApiResp<T> {
  return {
    request_id: requestId,
    ok: true,
    data,
    error: null,
  };
}

function fail(
  requestId: string,
  code: string,
  message: string,
): ApiResp<null> {
  return {
    request_id: requestId,
    ok: false,
    data: null,
    error: {
      code,
      message,
    },
  };
}

function createRuntimeCache<T>(ttlMs: number, limit: number): RuntimeCache<T> {
  return {
    ttlMs,
    limit,
    hits: 0,
    misses: 0,
    entries: new Map<string, RuntimeCacheEntry<T>>(),
  };
}

function readRuntimeCache<T>(cache: RuntimeCache<T>, key: string): RuntimeCacheEntry<T> | null {
  const entry = cache.entries.get(key);
  if (!entry) {
    cache.misses += 1;
    return null;
  }

  if (entry.expiresAt <= Date.now()) {
    cache.entries.delete(key);
    cache.misses += 1;
    return null;
  }

  entry.lastAccessedAt = Date.now();
  cache.entries.delete(key);
  cache.entries.set(key, entry);
  cache.hits += 1;
  return entry;
}

function writeRuntimeCache<T>(
  cache: RuntimeCache<T>,
  key: string,
  payload: T,
  computedInMs: number,
): RuntimeCacheEntry<T> {
  if (cache.entries.size >= cache.limit) {
    const oldestKey = cache.entries.keys().next().value;
    if (typeof oldestKey === "string") {
      cache.entries.delete(oldestKey);
    }
  }

  const entry: RuntimeCacheEntry<T> = {
    payload,
    expiresAt: Date.now() + cache.ttlMs,
    computedInMs,
    lastAccessedAt: Date.now(),
  };

  cache.entries.set(key, entry);
  return entry;
}

function runtimeCacheHealth(cache: RuntimeCache<unknown>) {
  return {
    entries: cache.entries.size,
    hits: cache.hits,
    misses: cache.misses,
    ttl_seconds: Math.round(cache.ttlMs / 1000),
  };
}

type ActivityRequestBody = {
  client_id?: string;
  item_id?: string;
  term?: string;
  detail?: string;
  context?: string;
  saved_at?: number;
  meta?: ActivityMeta | null;
};

type WorkspaceStateRequestBody = {
  client_id?: string;
  snapshot?: unknown;
};

function readClientId(value: unknown): string {
  if (typeof value !== "string") {
    return "";
  }

  return value.trim().slice(0, 128);
}

function readActivityBody(body: unknown): ActivityRequestBody {
  if (!body || typeof body !== "object") {
    return {};
  }

  return body as ActivityRequestBody;
}

function readWorkspaceStateBody(body: unknown): WorkspaceStateRequestBody {
  if (!body || typeof body !== "object") {
    return {};
  }

  return body as WorkspaceStateRequestBody;
}

function readItemId(value: unknown): string {
  if (typeof value !== "string") {
    return "";
  }

  return value.trim().slice(0, 128);
}

function mapActivityItems(items: StoredActivityItem[]) {
  return items.map((item) => ({
    id: item.id,
    term: item.term,
    detail: item.detail,
    context: item.context,
    saved_at: item.savedAt,
    meta: item.meta ?? null,
  }));
}

function mapActivityTermBuckets(items: ActivityTermBucket[]) {
  return items.map((item) => ({
    term: item.term,
    count: item.count,
    last_saved_at: item.lastSavedAt,
  }));
}

function containsChineseCharacters(text: string): boolean {
  return /[\u3400-\u9fff]/u.test(text);
}

const dictionaryKeys = ["ecdict", "cedict", "oewn", "tatoeba"] as const;
type DictionaryKey = (typeof dictionaryKeys)[number];

function parseRequiredDictionaries(value: string | undefined): DictionaryKey[] {
  if (!value?.trim()) {
    return [];
  }

  const normalized = value
    .split(",")
    .map((item) => item.trim().toLowerCase())
    .filter(Boolean);

  if (normalized.includes("all")) {
    return [...dictionaryKeys];
  }

  return dictionaryKeys.filter((key) => normalized.includes(key));
}

const requiredDictionaries = parseRequiredDictionaries(process.env.SPARROWWORD_REQUIRED_DICTIONARIES);
const failOnMissingDictionaries = process.env.SPARROWWORD_FAIL_ON_MISSING_DICTIONARIES === "true";
const corsOrigin = process.env.SPARROWWORD_CORS_ORIGIN?.trim() || "*";

function dictionaryReadiness() {
  const dictionaries = getDictionaryHealth();
  const missingRequiredDictionaries = requiredDictionaries.filter((key) => !dictionaries[key]);

  return {
    ready: missingRequiredDictionaries.length === 0,
    required_dictionaries: requiredDictionaries,
    missing_required_dictionaries: missingRequiredDictionaries,
    dictionaries,
  };
}

const server = Fastify({
  logger: true,
});

const reverseLookupCache = createRuntimeCache<{
  query: string;
  items: Array<{
    id: string;
    headword: string;
    lemma: string;
    pos: string;
    gloss_zh: string;
    score: number;
    note: string;
  }>;
}>(15 * 60 * 1000, 180);

const sentenceStudyCache = createRuntimeCache<ReturnType<typeof studySentenceCandidates>>(
  10 * 60 * 1000,
  180,
);

server.addHook("onSend", async (_request, reply, payload) => {
  reply.header("Access-Control-Allow-Origin", corsOrigin);
  reply.header("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS");
  reply.header("Access-Control-Allow-Headers", "Content-Type, Accept, x-sparrowword-client-id");
  reply.header("Access-Control-Max-Age", "86400");
  return payload;
});

server.options("/history", async (_request, reply) => reply.code(204).send());
server.options("/inbox", async (_request, reply) => reply.code(204).send());
server.options("/feedback", async (_request, reply) => reply.code(204).send());
server.options("/workspace-state", async (_request, reply) => reply.code(204).send());
server.options("/ready", async (_request, reply) => reply.code(204).send());

server.get("/health", async () => {
  const readiness = dictionaryReadiness();
  return {
    service: "dict-api",
    ok: true,
    phase: "sqlite-backed-offline-resources",
    ready: readiness.ready,
    required_dictionaries: readiness.required_dictionaries,
    missing_required_dictionaries: readiness.missing_required_dictionaries,
    dictionaries: readiness.dictionaries,
    storage: {
      activity_store: getActivityStoreHealth(),
      feedback_log: {
        path: getFeedbackLogPath(),
      },
    },
    runtime: {
      reverse_lookup_cache: runtimeCacheHealth(reverseLookupCache),
      sentence_study_cache: runtimeCacheHealth(sentenceStudyCache),
    },
  };
});

server.get("/ready", async (_request, reply) => {
  const readiness = dictionaryReadiness();
  const activityStore = getActivityStoreHealth();
  const ready = readiness.ready && activityStore.available;

  return reply.code(ready ? 200 : 503).send({
    service: "dict-api",
    ok: ready,
    ready,
    required_dictionaries: readiness.required_dictionaries,
    missing_required_dictionaries: readiness.missing_required_dictionaries,
    dictionaries: readiness.dictionaries,
    storage: {
      activity_store: activityStore,
    },
  });
});

server.get("/lookup", async (request) => {
  const query = String((request.query as { q?: string }).q ?? "").trim();
  if (containsChineseCharacters(query)) {
    const matches = reverseLookupDictionaryEntries(query);
    return ok(request.id, {
      query,
      mode: matches.length > 0 ? "reverse" : "no-result",
      entry: null,
      reverse_items: matches.map((item, index) => ({
        id: `reverse-${index + 1}`,
        headword: item.term,
        lemma: item.term,
        pos: item.pos,
        gloss_zh: item.gloss_zh,
        score: item.score,
        note: item.note,
      })),
    });
  }

  const entry = lookupDictionaryEntry(query);

  return ok(request.id, {
    query,
    mode: entry ? "lookup" : "no-result",
    entry: entry
      ? {
          id: `entry-${entry.headword.toLowerCase().replace(/\s+/g, "-")}`,
          headword: entry.headword,
          lemma: entry.headword,
          phonetic: entry.phonetic,
          level: entry.level,
          summary: entry.summary,
          source_tags: entry.sourceTags,
          meaning_groups: entry.meaningGroups,
          senses: entry.senses,
          english_definitions: entry.englishDefinitions,
          inflection_lines: entry.inflectionLines,
          collocations: entry.collocations,
          related_terms: entry.relatedTerms,
          examples: entry.examples,
        }
      : null,
  });
});

server.get("/suggest", async (request) => {
  const query = String((request.query as { q?: string }).q ?? "").trim();
  const suggestions = suggestDictionaryEntries(query);

  return ok(request.id, {
    query,
    items: suggestions.map((item, index) => ({
      id: `suggest-${index + 1}`,
      headword: item.term,
      lemma: item.term,
      pos: item.kind,
      gloss_zh: item.hint,
    })),
  });
});

server.get("/reverse-lookup", async (request) => {
  const query = String((request.query as { q?: string }).q ?? "").trim();
  const cacheKey = query.toLowerCase();
  const cached = readRuntimeCache(reverseLookupCache, cacheKey);
  if (cached) {
    return ok(request.id, {
      ...cached.payload,
      elapsed_ms: cached.computedInMs,
      cached: true,
    });
  }

  const startedAt = Date.now();
  const matches = reverseLookupDictionaryEntries(query);
  const computedInMs = Date.now() - startedAt;
  const payload = {
    query,
    items: matches.map((item, index) => ({
      id: `reverse-${index + 1}`,
      headword: item.term,
      lemma: item.term,
      pos: item.pos,
      gloss_zh: item.gloss_zh,
      score: item.score,
      note: item.note,
    })),
  };
  writeRuntimeCache(reverseLookupCache, cacheKey, payload, computedInMs);

  return ok(request.id, {
    ...payload,
    elapsed_ms: computedInMs,
    cached: false,
  });
});

server.get("/sentence-study", async (request) => {
  const query = String((request.query as { q?: string }).q ?? "").trim();
  const cacheKey = query.toLowerCase();
  const cached = readRuntimeCache(sentenceStudyCache, cacheKey);
  if (cached) {
    return ok(request.id, {
      ...cached.payload,
      elapsed_ms: cached.computedInMs,
      cached: true,
    });
  }

  const startedAt = Date.now();
  const payload = studySentenceCandidates(query);
  const computedInMs = Date.now() - startedAt;
  writeRuntimeCache(sentenceStudyCache, cacheKey, payload, computedInMs);

  return ok(request.id, {
    ...payload,
    elapsed_ms: computedInMs,
    cached: false,
  });
});

server.get("/history", async (request, reply) => {
  const clientId = readClientId((request.query as { client_id?: string }).client_id);
  if (!clientId) {
    return reply
      .code(400)
      .send(fail(request.id, "missing_client_id", "Anonymous client id is required."));
  }

  return ok(request.id, {
    client_id: clientId,
    items: mapActivityItems(listActivityItems("history", clientId)),
  });
});

server.post("/history", async (request, reply) => {
  const body = readActivityBody(request.body);
  const clientId = readClientId(body.client_id);
  if (!clientId) {
    return reply
      .code(400)
      .send(fail(request.id, "missing_client_id", "Anonymous client id is required."));
  }

  if (typeof body.term !== "string" || !body.term.trim()) {
    return reply
      .code(400)
      .send(fail(request.id, "missing_term", "A non-empty term is required."));
  }

  return ok(request.id, {
    client_id: clientId,
    items: mapActivityItems(
      upsertActivityItem("history", clientId, {
        term: body.term,
        detail: body.detail,
        context: body.context,
        meta: body.meta,
        savedAt: body.saved_at,
      }),
    ),
  });
});

server.delete("/history", async (request, reply) => {
  const body = readActivityBody(request.body);
  const clientId = readClientId(body.client_id);
  if (!clientId) {
    return reply
      .code(400)
      .send(fail(request.id, "missing_client_id", "Anonymous client id is required."));
  }

  const itemId = readItemId(body.item_id);
  const items = itemId
    ? removeActivityItem("history", clientId, itemId)
    : clearActivityItems("history", clientId);

  return ok(request.id, {
    client_id: clientId,
    items: mapActivityItems(items),
  });
});

server.get("/inbox", async (request, reply) => {
  const clientId = readClientId((request.query as { client_id?: string }).client_id);
  if (!clientId) {
    return reply
      .code(400)
      .send(fail(request.id, "missing_client_id", "Anonymous client id is required."));
  }

  return ok(request.id, {
    client_id: clientId,
    items: mapActivityItems(listActivityItems("inbox", clientId)),
  });
});

server.post("/inbox", async (request, reply) => {
  const body = readActivityBody(request.body);
  const clientId = readClientId(body.client_id);
  if (!clientId) {
    return reply
      .code(400)
      .send(fail(request.id, "missing_client_id", "Anonymous client id is required."));
  }

  if (typeof body.term !== "string" || !body.term.trim()) {
    return reply
      .code(400)
      .send(fail(request.id, "missing_term", "A non-empty term is required."));
  }

  return ok(request.id, {
    client_id: clientId,
    items: mapActivityItems(
      upsertActivityItem("inbox", clientId, {
        term: body.term,
        detail: body.detail,
        context: body.context,
        meta: body.meta,
        savedAt: body.saved_at,
      }),
    ),
  });
});

server.delete("/inbox", async (request, reply) => {
  const body = readActivityBody(request.body);
  const clientId = readClientId(body.client_id);
  if (!clientId) {
    return reply
      .code(400)
      .send(fail(request.id, "missing_client_id", "Anonymous client id is required."));
  }

  const itemId = readItemId(body.item_id);
  const items = itemId
    ? removeActivityItem("inbox", clientId, itemId)
    : clearActivityItems("inbox", clientId);

  return ok(request.id, {
    client_id: clientId,
    items: mapActivityItems(items),
  });
});

server.get("/workspace-state", async (request, reply) => {
  const clientId = readClientId((request.query as { client_id?: string }).client_id);
  if (!clientId) {
    return reply
      .code(400)
      .send(fail(request.id, "missing_client_id", "Anonymous client id is required."));
  }

  const state = readWorkspaceClientState(clientId);
  return ok(request.id, {
    client_id: clientId,
    snapshot: state.snapshot,
    updated_at: state.updatedAt,
  });
});

server.put("/workspace-state", async (request, reply) => {
  const body = readWorkspaceStateBody(request.body);
  const clientId = readClientId(body.client_id);
  if (!clientId) {
    return reply
      .code(400)
      .send(fail(request.id, "missing_client_id", "Anonymous client id is required."));
  }

  const state = writeWorkspaceClientState(clientId, body.snapshot ?? null);
  return ok(request.id, {
    client_id: clientId,
    snapshot: state.snapshot,
    updated_at: state.updatedAt,
  });
});

server.post("/feedback", async (request) => {
  await persistFeedback(request.id, request.body ?? null);

  return ok(request.id, {
    stored: true,
    received: request.body ?? null,
  });
});

server.get("/feedback/recent", async (request) => {
  const rawLimit = Number((request.query as { limit?: string }).limit ?? "24");
  const limit = Number.isFinite(rawLimit) ? Math.min(Math.max(rawLimit, 1), 100) : 24;

  return ok(request.id, {
    items: await listRecentFeedback(limit),
  });
});

server.get("/signals/summary", async (request) => {
  const rawLimit = Number((request.query as { limit?: string }).limit ?? "6");
  const limit = Number.isFinite(rawLimit) ? Math.min(Math.max(rawLimit, 1), 12) : 6;

  const [feedback, history, inbox] = await Promise.all([
    summarizeFeedback(200),
    Promise.resolve(summarizeActivity("history", limit)),
    Promise.resolve(summarizeActivity("inbox", limit)),
  ]);

  return ok(request.id, {
    feedback: {
      total_entries: feedback.totalEntries,
      with_message_count: feedback.withMessageCount,
      latest_received_at: feedback.latestReceivedAt,
      top_queries: feedback.topQueries,
    },
    activity: {
      history: {
        total_entries: history.totalEntries,
        unique_clients: history.uniqueClients,
        top_terms: mapActivityTermBuckets(history.topTerms),
      },
      inbox: {
        total_entries: inbox.totalEntries,
        unique_clients: inbox.uniqueClients,
        top_terms: mapActivityTermBuckets(inbox.topTerms),
      },
    },
  });
});

const port = Number(process.env.PORT ?? 3001);
const host = process.env.HOST ?? "127.0.0.1";

if (failOnMissingDictionaries) {
  const readiness = dictionaryReadiness();
  if (!readiness.ready) {
    server.log.error(
      {
        missing_required_dictionaries: readiness.missing_required_dictionaries,
        required_dictionaries: readiness.required_dictionaries,
        paths: readiness.dictionaries.paths,
      },
      "Missing required dictionary resources.",
    );
    process.exit(1);
  }
}

server.listen({ port, host }).catch((error) => {
  server.log.error(error);
  process.exit(1);
});
