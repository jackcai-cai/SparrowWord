import { appendFile, mkdir, readFile } from "node:fs/promises";
import { dirname } from "node:path";
import { fileURLToPath } from "node:url";

export type FeedbackEntry = {
  id: string;
  received_at: string;
  payload: {
    message?: string;
    query?: string;
    mode?: string;
    client_id?: string;
    source_label?: string | null;
    headword?: string | null;
    url?: string | null;
    [key: string]: unknown;
  } | null;
};

export type FeedbackQueryBucket = {
  query: string;
  count: number;
};

export type FeedbackSummary = {
  totalEntries: number;
  withMessageCount: number;
  topQueries: FeedbackQueryBucket[];
  latestReceivedAt: string | null;
};

const feedbackLogPath =
  process.env.SPARROWWORD_FEEDBACK_LOG?.trim() ||
  fileURLToPath(new URL("../../data/feedback-log.jsonl", import.meta.url));

export function getFeedbackLogPath(): string {
  return feedbackLogPath;
}

export async function persistFeedback(requestId: string, payload: unknown) {
  await mkdir(dirname(feedbackLogPath), { recursive: true });
  await appendFile(
    feedbackLogPath,
    `${JSON.stringify({
      id: requestId,
      received_at: new Date().toISOString(),
      payload,
    })}\n`,
    "utf8",
  );
}

export async function listRecentFeedback(limit = 24): Promise<FeedbackEntry[]> {
  try {
    const raw = await readFile(feedbackLogPath, "utf8");
    const lines = raw
      .split("\n")
      .map((line) => line.trim())
      .filter(Boolean)
      .slice(-Math.max(1, limit));

    return lines
      .map((line) => {
        try {
          return JSON.parse(line) as FeedbackEntry;
        } catch {
          return null;
        }
      })
      .filter((entry): entry is FeedbackEntry => {
        return (
          entry !== null &&
          typeof entry.id === "string" &&
          typeof entry.received_at === "string"
        );
      })
      .reverse();
  } catch (error) {
    if (
      typeof error === "object" &&
      error !== null &&
      "code" in error &&
      error.code === "ENOENT"
    ) {
      return [];
    }

    throw error;
  }
}

export async function summarizeFeedback(limit = 200): Promise<FeedbackSummary> {
  const entries = await listRecentFeedback(limit);
  const queryCounts = new Map<string, number>();

  for (const entry of entries) {
    const query = entry.payload?.query?.trim();
    if (!query) {
      continue;
    }

    queryCounts.set(query, (queryCounts.get(query) ?? 0) + 1);
  }

  const topQueries = [...queryCounts.entries()]
    .sort((left, right) => {
      if (right[1] !== left[1]) {
        return right[1] - left[1];
      }

      return left[0].localeCompare(right[0]);
    })
    .slice(0, 6)
    .map(([query, count]) => ({ query, count }));

  return {
    totalEntries: entries.length,
    withMessageCount: entries.filter((entry) => typeof entry.payload?.message === "string" && entry.payload.message.trim()).length,
    topQueries,
    latestReceivedAt: entries[0]?.received_at ?? null,
  };
}
