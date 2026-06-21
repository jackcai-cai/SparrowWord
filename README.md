# SparrowWord

> A fast, offline-first vocabulary companion for English readers — look up a word, keep it, and review it later, without breaking your reading flow.

SparrowWord is a vocabulary-learning project I designed and built end-to-end: a native **macOS app**, a **web app**, and the **dictionary API** behind them. It turns the usual scattered routine — dictionary in one app, notes in another, flashcards in a third — into a single loop: **look up → capture → review.**

## Highlights

- 🔎 **Offline English lookup, zero setup** — the macOS app ships with a bundled dictionary, so English word → Chinese meaning works the moment you open it. No downloads, no imports.
- ⚡ **Quick Capture** — save a word with its context, example, and notes in seconds.
- 🔁 **Spaced-repetition review** — multiple question types with Again / Hard / Good / Easy.
- 🗂️ **Personal library & history** — everything you look up and keep, organized.
- 🧩 **Three surfaces, one model** — native macOS, web, and a shared Node.js + SQLite dictionary service.

### Optional / advanced

These light up once you import the matching open datasets (see [Dictionaries](#dictionaries)):

- 🀄 Chinese → English reverse lookup (CC-CEDICT)
- 📚 Example sentences (Tatoeba) and fuller English definitions (Open English WordNet)
- 🧠 AI-assisted definitions via OpenAI (optional; falls back to offline)

## Download (macOS)

Get the latest build from **[Releases](../../releases)**.

> Not notarized yet — on first launch, **right-click the app → Open → Open**.

## Why I built it

I was learning English mostly by reading, and I was tired of bouncing between a dictionary, a notes app, and a flashcard app. SparrowWord is the tool I wished existed — and building it end-to-end (native app, web, backend, and offline data) was how I taught myself to ship a real product.

## Built with

- **macOS app:** Swift / SwiftUI
- **Web app:** Next.js (React, TypeScript)
- **Dictionary API:** Node.js (Fastify) + SQLite
- **Data:** ECDICT (a bundled lite subset) and, optionally, CC-CEDICT / Tatoeba / Open English WordNet

## Build from source

macOS app:

```bash
xcodebuild -project "SparrowWord/SparrowWord.xcodeproj" -scheme SparrowWord -configuration Release build
```

Web app + dictionary API:

```bash
npm install
npm run dev    # web workspace: http://127.0.0.1:3000/workspace
```

## Dictionaries

The macOS app bundles a reduced **ECDICT** subset (common words, their inflections, and common phrases) so English lookup works offline with zero setup. For Chinese reverse lookup, example sentences, and fuller English definitions, import the full open datasets from **Settings → Offline Dictionaries**. All third-party data stays under its own license — see [docs/THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md).

## Roadmap

This is the first public release. Planned next:

- Hosted web demo (try without installing)
- Accounts + cross-device sync
- Mobile

## License

[MIT](LICENSE). Bundled and third-party dictionary data is governed by the licenses in [docs/THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md).

## Author

Built by [Jack Cai](https://github.com/jackcai-cai).
