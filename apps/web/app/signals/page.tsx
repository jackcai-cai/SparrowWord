import Link from "next/link";

import { loadRecentFeedback } from "../../lib/feedback-feed";
import { loadSignalsSummary } from "../../lib/signals-feed";

export const dynamic = "force-dynamic";

function formatTimestamp(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return new Intl.DateTimeFormat("en-US", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

function buildNextMoves(summary: Awaited<ReturnType<typeof loadSignalsSummary>>, feedbackCount: number): string[] {
  const moves: string[] = [];

  if (feedbackCount < 5) {
    moves.push("Collect at least five concrete feedback notes before changing the product story again.");
  }

  if ((summary?.activity.history.total_entries ?? 0) > 0 && (summary?.activity.inbox.total_entries ?? 0) === 0) {
    moves.push("Make the value of Inbox clearer, because people are looking up words but not saving them yet.");
  }

  if ((summary?.activity.history.total_entries ?? 0) >= 3 * Math.max(summary?.activity.inbox.total_entries ?? 0, 1)) {
    moves.push("Reduce the gap between lookup and save so useful words move into Inbox more often.");
  }

  if ((summary?.feedback.top_queries.length ?? 0) > 0) {
    moves.push(`Strengthen the result quality around “${summary?.feedback.top_queries[0]?.query}”, because it is already showing up in feedback.`);
  }

  if (moves.length === 0) {
    moves.push("Keep running short user tests and look for the first repeated complaint rather than broad praise.");
  }

  return moves.slice(0, 4);
}

export default async function SignalsPage() {
  const [feedbackItems, summary] = await Promise.all([
    loadRecentFeedback(24),
    loadSignalsSummary(6),
  ]);
  const groupedQueries = new Map<string, number>();

  for (const item of feedbackItems) {
    const query = item.payload?.query?.trim();
    if (!query) {
      continue;
    }

    groupedQueries.set(query, (groupedQueries.get(query) ?? 0) + 1);
  }

  const topQueries = [...groupedQueries.entries()]
    .sort((left, right) => {
      if (right[1] !== left[1]) {
        return right[1] - left[1];
      }

      return left[0].localeCompare(right[0]);
    })
    .slice(0, 6);

  const nextMoves = buildNextMoves(summary, feedbackItems.length);
  const topLookupTerms = summary?.activity.history.top_terms ?? [];
  const topInboxTerms = summary?.activity.inbox.top_terms ?? [];

  return (
    <main className="shell">
      <section className="hero">
        <div className="hero-copy">
          <p className="eyebrow">Signals</p>
          <h1>See what early users actually struggled with.</h1>
          <p className="lead">
            Feedback only matters if we can read it, cluster it, and decide what to
            change next. This page keeps the first iteration loop visible.
          </p>
          <div className="status-row">
            <span className="status-chip">Feedback review</span>
            <span className="status-note">
              {summary?.feedback.total_entries ?? feedbackItems.length} notes, {summary?.activity.history.total_entries ?? 0} lookups, {summary?.activity.inbox.total_entries ?? 0} saves
            </span>
          </div>
          <div className="cta-row">
            <Link className="primary-link" href="/workspace">
              Back to workspace
            </Link>
            <Link className="workspace-link" href="/playtest">
              Tester script
            </Link>
            <Link className="workspace-link" href="/overview">
              Product overview
            </Link>
          </div>
        </div>

        <div className="hero-panel">
          <p className="panel-label">Current Pattern Hints</p>
          {topQueries.length > 0 ? (
            <ul className="panel-list">
              {topQueries.map(([query, count]) => (
                <li key={query}>
                  <strong>{query}</strong> appeared in {count} feedback note{count > 1 ? "s" : ""}.
                </li>
              ))}
            </ul>
          ) : (
            <p className="stack-copy">
              Once feedback starts coming in, repeated queries and friction points will
              surface here first.
            </p>
          )}
        </div>
      </section>

      <section className="grid-section signals-grid">
        <article className="card metric-card">
          <p className="card-label">Feedback</p>
          <h2>{summary?.feedback.total_entries ?? feedbackItems.length}</h2>
          <p>Saved notes we can actually review and turn into product decisions.</p>
        </article>

        <article className="card metric-card">
          <p className="card-label">Lookups</p>
          <h2>{summary?.activity.history.total_entries ?? 0}</h2>
          <p>Tracked lookup visits across anonymous sessions so we can spot repeated terms.</p>
        </article>

        <article className="card metric-card">
          <p className="card-label">Inbox Saves</p>
          <h2>{summary?.activity.inbox.total_entries ?? 0}</h2>
          <p>Words important enough to keep, not just glance at once.</p>
        </article>

        <article className="card metric-card">
          <p className="card-label">Active Sessions</p>
          <h2>{Math.max(summary?.activity.history.unique_clients ?? 0, summary?.activity.inbox.unique_clients ?? 0)}</h2>
          <p>Anonymous browsers that have left enough trail for us to learn from.</p>
        </article>
      </section>

      <section className="grid-section signals-grid">
        <article className="preview-card">
          <p className="card-label">Top Lookup Terms</p>
          {topLookupTerms.length > 0 ? (
            <div className="signal-list">
              {topLookupTerms.map((item) => (
                <div className="signal-row" key={`history-${item.term}`}>
                  <strong>{item.term}</strong>
                  <span>{item.count} visits</span>
                </div>
              ))}
            </div>
          ) : (
            <p>No aggregated lookup signal yet.</p>
          )}
        </article>

        <article className="preview-card">
          <p className="card-label">Top Inbox Terms</p>
          {topInboxTerms.length > 0 ? (
            <div className="signal-list">
              {topInboxTerms.map((item) => (
                <div className="signal-row" key={`inbox-${item.term}`}>
                  <strong>{item.term}</strong>
                  <span>{item.count} saves</span>
                </div>
              ))}
            </div>
          ) : (
            <p>No aggregated save signal yet.</p>
          )}
        </article>
      </section>

      <section className="preview-strip">
        <article className="preview-card">
          <p className="card-label">Next Moves</p>
          <div className="feedback-feed">
            {nextMoves.map((move) => (
              <article className="feedback-card" key={move}>
                <p>{move}</p>
              </article>
            ))}
          </div>
        </article>
      </section>

      <section className="preview-strip">
        <article className="preview-card">
          <p className="card-label">Recent Feedback</p>
          {feedbackItems.length > 0 ? (
            <div className="feedback-feed">
              {feedbackItems.map((item) => (
                <article className="feedback-card" key={item.id}>
                  <div className="feedback-meta">
                    <strong>{item.payload?.query || item.payload?.headword || "General note"}</strong>
                    <span>{formatTimestamp(item.received_at)}</span>
                  </div>
                  <p>{item.payload?.message || "No message body was captured for this note."}</p>
                  <div className="tag-row">
                    {item.payload?.mode ? <span className="soft-tag">{item.payload.mode}</span> : null}
                    {item.payload?.source_label ? (
                      <span className="soft-tag">{String(item.payload.source_label)}</span>
                    ) : null}
                    {item.payload?.client_id ? <span className="soft-tag">anonymous session</span> : null}
                  </div>
                </article>
              ))}
            </div>
          ) : (
            <p>
              No saved feedback yet. Once someone submits a note from the workspace, it
              will show up here.
            </p>
          )}
        </article>
      </section>
    </main>
  );
}
