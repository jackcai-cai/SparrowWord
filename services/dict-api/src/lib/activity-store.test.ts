import test from "node:test";
import assert from "node:assert/strict";

import { mergeWorkspaceStateSnapshots } from "./activity-store.js";

test("mergeWorkspaceStateSnapshots accepts explicit review rollback from the latest snapshot", () => {
  const existing = {
    libraryEntries: [],
    savedLibraryArrangements: [],
    inboxEntryDrafts: {},
    reviewStateMap: {
      abandon: {
        level: 1,
        reviewCount: 1,
        lastReviewedAt: 1000,
        dueAt: 2000,
        streak: 0,
        lapseCount: 1,
        lastDecision: "again",
      },
    },
    reviewHistory: [
      {
        sessionId: "session-1",
        candidateId: "candidate-1",
        term: "abandon",
        answeredAt: 1000,
        decision: "again",
      },
    ],
    reviewSession: {
      sessionId: "session-1",
      queue: ["candidate-1"],
      index: 1,
      records: [
        {
          sessionId: "session-1",
          candidateId: "candidate-1",
          term: "abandon",
          answeredAt: 1000,
          decision: "again",
        },
      ],
      pausedAt: 1000,
    },
  };

  const incoming = {
    libraryEntries: [],
    savedLibraryArrangements: [],
    inboxEntryDrafts: {},
    reviewStateMap: {
      abandon: {
        level: 2,
        reviewCount: 0,
        lastReviewedAt: null,
        dueAt: null,
        streak: 0,
        lapseCount: 0,
        lastDecision: null,
      },
    },
    reviewHistory: [],
    reviewSession: {
      sessionId: "session-1",
      queue: ["candidate-1"],
      index: 0,
      records: [],
      pausedAt: null,
    },
  };

  const merged = mergeWorkspaceStateSnapshots(existing, incoming) as {
    reviewStateMap: Record<string, { level: number; reviewCount: number; lastReviewedAt: number | null }>;
    reviewHistory: Array<{ term: string; answeredAt: number }>;
    reviewSession: { index: number; records: Array<{ term: string }> };
  };

  assert.equal(merged.reviewHistory.length, 0);
  assert.equal(merged.reviewStateMap.abandon?.reviewCount, 0);
  assert.equal(merged.reviewStateMap.abandon?.level, 2);
  assert.equal(merged.reviewSession.index, 0);
  assert.equal(merged.reviewSession.records.length, 0);
});
