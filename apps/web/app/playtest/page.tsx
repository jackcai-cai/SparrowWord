import Link from "next/link";

const missions = [
  {
    label: "Mission 1",
    title: "Look up one English word you would actually pause on",
    body: "Use the desktop workspace to search a word you recently saw in an article, class note, or video subtitle. Do not overthink it.",
    starter: "Try `abandon` if you need a quick starting point.",
  },
  {
    label: "Mission 2",
    title: "Recover from a miss or typo",
    body: "Search something slightly wrong and see whether the product helps you get back on track without feeling lost.",
    starter: "Try `abnadon` and see whether the suggestion path feels obvious.",
  },
  {
    label: "Mission 3",
    title: "Save one useful word and check whether that step feels worth it",
    body: "Use reverse lookup or a normal result, then save one item to Inbox. The point is not just whether saving works, but whether it feels meaningful.",
    starter: "Try Chinese-first with `放弃`, then jump into the English result.",
  },
];

const prompts = [
  "What was the first step that felt unclear or slightly awkward?",
  "Did saving to Inbox feel useful, or did it feel like extra work?",
  "If you would not use this again, what is the main reason?",
];

export default function PlaytestPage() {
  return (
    <main className="shell">
      <section className="hero">
        <div className="hero-copy">
          <p className="eyebrow">Playtest</p>
          <h1>A three-minute script for early SparrowWord testers.</h1>
          <p className="lead">
            This page is the easiest way to ask a friend or classmate for useful
            product feedback without dumping the whole project on them.
          </p>
          <div className="status-row">
            <span className="status-chip">3 missions</span>
            <span className="status-note">Built for quick desktop testing</span>
          </div>
          <div className="cta-row">
            <Link className="primary-link" href="/workspace">
              Open workspace
            </Link>
            <Link className="workspace-link" href="/signals">
              Review signals
            </Link>
          </div>
        </div>

        <div className="hero-panel">
          <p className="panel-label">How To Ask</p>
          <ul className="panel-list">
            <li>Ask for three minutes, not a full product review.</li>
            <li>Tell them honesty is more useful than praise.</li>
            <li>Watch where they hesitate before they explain anything.</li>
          </ul>
        </div>
      </section>

      <section className="grid-section">
        {missions.map((mission) => (
          <article className="card" key={mission.label}>
            <p className="card-label">{mission.label}</p>
            <h2>{mission.title}</h2>
            <p>{mission.body}</p>
            <p className="mission-note">{mission.starter}</p>
          </article>
        ))}
      </section>

      <section className="preview-strip">
        <article className="preview-card">
          <p className="card-label">Feedback Prompts</p>
          <div className="feedback-feed">
            {prompts.map((prompt) => (
              <article className="feedback-card" key={prompt}>
                <p>{prompt}</p>
              </article>
            ))}
          </div>
        </article>
      </section>
    </main>
  );
}
