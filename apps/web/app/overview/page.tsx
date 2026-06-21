import Link from "next/link";

const pillars = [
  {
    label: "Lookup",
    title: "Fast answers while reading",
    body: "Find words, phrases, and near-miss spellings without breaking your reading rhythm.",
  },
  {
    label: "Inbox",
    title: "Collect first, organize later",
    body: "Throw useful words into a lightweight inbox so curiosity does not become friction.",
  },
  {
    label: "History",
    title: "Learn from your own trail",
    body: "Turn actual lookup behavior into the beginning of a personal review system.",
  },
];

export default function OverviewPage() {
  return (
    <main className="shell">
      <section className="hero">
        <div className="hero-copy">
          <p className="eyebrow">SparrowWord Web</p>
          <h1>A desktop reading workspace, not just another dictionary tab.</h1>
          <p className="lead">
            The first web phase is focused on one thing: making lookup, inbox, and
            history feel natural on a wide screen before we expand into mobile and
            cloud sync.
          </p>
          <div className="status-row">
            <span className="status-chip">Phase 3: live lookup workspace</span>
            <span className="status-note">Next.js web app + Node.js dict API</span>
          </div>
          <div className="cta-row">
            <Link className="primary-link" href="/workspace">
              Open desktop workspace
            </Link>
            <Link className="workspace-link" href="/signals">
              Review feedback
            </Link>
            <Link className="workspace-link" href="/playtest">
              Tester script
            </Link>
            <span className="inline-note">Current step: live dictionaries + anonymous session activity</span>
          </div>
        </div>
        <div className="hero-panel">
          <p className="panel-label">Current Build Focus</p>
          <ul className="panel-list">
            <li>Desktop-first search workspace</li>
            <li>Lookup, suggest, reverse lookup</li>
            <li>Inbox and recent-history foundations</li>
            <li>Feedback-first iteration loop</li>
          </ul>
        </div>
      </section>

      <section className="grid-section">
        {pillars.map((pillar) => (
          <article className="card" key={pillar.label}>
            <p className="card-label">{pillar.label}</p>
            <h2>{pillar.title}</h2>
            <p>{pillar.body}</p>
          </article>
        ))}
      </section>

      <section className="preview-strip">
        <article className="preview-card">
          <p className="card-label">Next Step</p>
          <h2>The workspace is where the product starts to feel real.</h2>
          <p>
            Instead of another landing page, SparrowWord now moves toward a wide-screen
            layout where lookup, suggestions, inbox, and recent history live together.
          </p>
        </article>
      </section>
    </main>
  );
}
