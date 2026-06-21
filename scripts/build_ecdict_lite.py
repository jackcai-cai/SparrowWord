#!/usr/bin/env python3
"""
Build a small, app-compatible ECDICT "lite" database from the full 812MB ECDICT.

Strategy (keeps the SAME `stardict` schema, only fewer rows — gate C/H):
  1. Common words: rows with a frequency/exam tag/Collins/Oxford signal (~59k).
  2. Inflections: expand each common lemma's `exchange` field (p/d/i/3/s/r/t forms)
     so "ran", "studies", "better", "went", "children" come in even with frq=0.
  3. Common phrases: 2-3 word phrases whose every token is a common single word
     (captures "look up", "set up", "take off" — which have no frequency data).
  4. Acceptance list: explicitly force-include the verification words.

Then: new empty DB -> INSERT ... SELECT join on keep-set -> indexes -> VACUUM; ANALYZE.

Usage: python3 build_ecdict_lite.py [SOURCE_DB] [OUT_DB]
"""
import os
import sqlite3
import sys

DEFAULT_SOURCE = os.environ.get("ECDICT_SOURCE", "stardict.db")
DEFAULT_OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build", "ecdict-lite.sqlite")

COLUMNS = ["id", "word", "sw", "phonetic", "definition", "translation",
           "pos", "collins", "oxford", "tag", "bnc", "frq", "exchange", "detail", "audio"]

# Particles/function words that may lack frequency flags but are needed for phrasal verbs.
PARTICLES = {"up", "off", "on", "in", "out", "down", "over", "away", "back", "through",
             "about", "around", "along", "across", "by", "for", "to", "with", "of",
             "into", "onto", "upon", "after", "apart", "aside", "ahead", "forward"}

# Force-include verification words (and a few common forms) — belt & suspenders.
ACCEPTANCE = {"resilient", "ubiquitous", "mitigate", "ambiguous", "sophisticated",
              "take off", "look up", "set up", "studies", "ran", "better",
              "study", "run", "good", "go", "child"}

INFLECTION_TYPES = {"p", "d", "i", "3", "s", "r", "t"}


def parse_inflections(exchange: str):
    """From a lemma's exchange string, yield inflected-form words."""
    if not exchange:
        return
    for pair in exchange.split("/"):
        if ":" not in pair:
            continue
        kind, _, value = pair.partition(":")
        value = value.strip()
        if kind in INFLECTION_TYPES and value:
            yield value.lower()


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SOURCE
    out = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_OUT

    if not os.path.exists(source):
        sys.exit(f"ERROR: source DB not found: {source}")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    if os.path.exists(out):
        os.remove(out)

    src = sqlite3.connect(f"file:{source}?mode=ro", uri=True)
    src.text_factory = str

    print("1) loading common words (frq/bnc/tag/collins/oxford) ...")
    common_rows = src.execute(
        "SELECT word, exchange FROM stardict "
        "WHERE frq>0 OR bnc>0 OR collins>0 OR oxford>0 OR (tag IS NOT NULL AND tag!='')"
    ).fetchall()
    keep = set()
    single_vocab = set(PARTICLES)
    for word, exchange in common_rows:
        wl = word.lower()
        keep.add(wl)
        if " " not in wl:
            single_vocab.add(wl)
        for form in parse_inflections(exchange):
            keep.add(form)
    print(f"   common rows: {len(common_rows)}  | keep after inflections: {len(keep)}  | single vocab: {len(single_vocab)}")

    print("2) scanning phrases (every token must be a common single word) ...")
    phrase_added = 0
    for (word,) in src.execute("SELECT word FROM stardict WHERE word LIKE '% %'"):
        wl = word.lower()
        tokens = wl.split()
        # Phrasal-verb pattern: a common head word followed by particle(s).
        if 2 <= len(tokens) <= 3 and tokens[0] in single_vocab and all(t in PARTICLES for t in tokens[1:]):
            if wl not in keep:
                keep.add(wl)
                phrase_added += 1
    print(f"   common phrases added: {phrase_added}")

    keep |= {w.lower() for w in ACCEPTANCE}
    print(f"3) total keep-set: {len(keep)}")

    print("4) creating lite DB and copying matching rows ...")
    dst = sqlite3.connect(out)
    dst.executescript("""
        PRAGMA journal_mode = OFF;
        PRAGMA synchronous = OFF;
        CREATE TABLE "stardict" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL UNIQUE,
          "word" VARCHAR(64) COLLATE NOCASE NOT NULL UNIQUE,
          "sw" VARCHAR(64) COLLATE NOCASE NOT NULL,
          "phonetic" VARCHAR(64),
          "definition" TEXT,
          "translation" TEXT,
          "pos" VARCHAR(16),
          "collins" INTEGER DEFAULT(0),
          "oxford" INTEGER DEFAULT(0),
          "tag" VARCHAR(64),
          "bnc" INTEGER DEFAULT(NULL),
          "frq" INTEGER DEFAULT(NULL),
          "exchange" TEXT,
          "detail" TEXT,
          "audio" TEXT
        );
        CREATE TEMP TABLE keep(word TEXT COLLATE NOCASE PRIMARY KEY);
    """)
    dst.executemany("INSERT OR IGNORE INTO keep(word) VALUES (?)", ((w,) for w in keep))

    dst.execute(f"ATTACH DATABASE '{source}' AS src")
    col_list = ", ".join(f'"{c}"' for c in COLUMNS)
    src_cols = ", ".join(f's."{c}"' for c in COLUMNS)
    dst.execute(
        f'INSERT INTO "stardict" ({col_list}) '
        f'SELECT {src_cols} FROM src."stardict" s '
        f'JOIN keep k ON s."word" = k.word'
    )
    dst.commit()
    dst.execute("DETACH DATABASE src")
    dst.execute("DROP TABLE keep")

    print("5) indexes + VACUUM + ANALYZE ...")
    dst.executescript("""
        CREATE UNIQUE INDEX "stardict_2" ON "stardict" (word);
        CREATE INDEX "sd_1" ON "stardict" (word COLLATE NOCASE);
    """)
    dst.commit()
    dst.execute("VACUUM")
    dst.execute("ANALYZE")
    dst.commit()

    count = dst.execute('SELECT count(*) FROM "stardict"').fetchone()[0]
    dst.close()
    src.close()

    size_mb = os.path.getsize(out) / 1048576.0
    print(f"\nDONE: {out}")
    print(f"rows: {count}  | size: {size_mb:.1f} MB")
    if size_mb >= 50:
        print("WARNING: >=50MB (gate C). Tighten the frequency threshold or drop a column.")
        sys.exit(2)


if __name__ == "__main__":
    main()
