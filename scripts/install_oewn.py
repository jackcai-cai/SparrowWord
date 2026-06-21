#!/usr/bin/env python3

from __future__ import annotations

import json
import subprocess
import shutil
import sqlite3
import tempfile
import urllib.request
import zipfile
from pathlib import Path


ZIP_URL = "https://en-word.net/static/english-wordnet-2025-json.zip"


def main() -> None:
    resources_dir = Path.home() / "Library" / "Application Support" / "SparrowWord" / "OfflineResources"
    raw_dir = resources_dir / "raw" / "oewn"
    oewn_dir = resources_dir / "oewn"
    zip_path = raw_dir / "english-wordnet-2025-json.zip"
    db_path = oewn_dir / "oewn.sqlite"

    raw_dir.mkdir(parents=True, exist_ok=True)
    oewn_dir.mkdir(parents=True, exist_ok=True)

    if not zip_path.exists():
        print(f"Downloading {ZIP_URL} -> {zip_path}")
        download_archive(zip_path)
    else:
        print(f"Using existing archive: {zip_path}")

    with tempfile.TemporaryDirectory(prefix="oewn-build-") as temp_dir:
        temp_db = Path(temp_dir) / "oewn.sqlite"
        build_database(zip_path, temp_db)
        shutil.move(temp_db, db_path)

    print(f"Installed Open English WordNet database at: {db_path}")


def build_database(zip_path: Path, db_path: Path) -> None:
    if db_path.exists():
        db_path.unlink()

    connection = sqlite3.connect(db_path)
    try:
        connection.execute("PRAGMA journal_mode = WAL;")
        connection.execute("PRAGMA synchronous = NORMAL;")
        connection.executescript(
            """
            CREATE TABLE oewn_entries (
                lemma TEXT NOT NULL COLLATE NOCASE,
                part_of_speech TEXT NOT NULL,
                pronunciations_json TEXT NOT NULL,
                forms_json TEXT NOT NULL,
                synsets_json TEXT NOT NULL,
                PRIMARY KEY (lemma, part_of_speech)
            );

            CREATE TABLE oewn_forms (
                form TEXT NOT NULL COLLATE NOCASE,
                lemma TEXT NOT NULL COLLATE NOCASE,
                part_of_speech TEXT NOT NULL
            );

            CREATE TABLE oewn_synsets (
                synset_id TEXT PRIMARY KEY,
                part_of_speech TEXT NOT NULL,
                definitions_json TEXT NOT NULL,
                members_json TEXT NOT NULL
            );

            CREATE INDEX idx_oewn_entries_lemma ON oewn_entries (lemma COLLATE NOCASE);
            CREATE INDEX idx_oewn_forms_form ON oewn_forms (form COLLATE NOCASE);
            """
        )

        with zipfile.ZipFile(zip_path) as archive:
            synset_files = sorted(
                name
                for name in archive.namelist()
                if name.endswith(".json")
                and (name.startswith("noun.") or name.startswith("verb.") or name.startswith("adj.") or name.startswith("adv."))
            )
            entry_files = sorted(
                name
                for name in archive.namelist()
                if name.startswith("entries-") and name.endswith(".json")
            )

            insert_synset = connection.cursor()
            insert_entry = connection.cursor()
            insert_form = connection.cursor()

            connection.execute("BEGIN TRANSACTION;")
            try:
                for filename in synset_files:
                    print(f"Importing synsets from {filename}")
                    payload = json.loads(archive.read(filename))
                    for synset_id, data in payload.items():
                        insert_synset.execute(
                            """
                            INSERT OR REPLACE INTO oewn_synsets (
                                synset_id,
                                part_of_speech,
                                definitions_json,
                                members_json
                            ) VALUES (?, ?, ?, ?);
                            """,
                            (
                                synset_id,
                                normalize_string(data.get("partOfSpeech", "")),
                                json.dumps(normalize_string_list(data.get("definition", [])), ensure_ascii=False),
                                json.dumps(normalize_string_list(data.get("members", [])), ensure_ascii=False),
                            ),
                        )

                for filename in entry_files:
                    print(f"Importing entries from {filename}")
                    payload = json.loads(archive.read(filename))
                    for lemma, parts_of_speech in payload.items():
                        normalized_lemma = normalize_string(lemma)
                        if not normalized_lemma:
                            continue

                        for part_of_speech, data in parts_of_speech.items():
                            normalized_pos = normalize_string(part_of_speech)
                            pronunciations = normalize_pronunciations(data.get("pronunciation", []))
                            forms = normalize_string_list(data.get("form", []))
                            synsets = [
                                normalize_string(sense.get("synset", ""))
                                for sense in data.get("sense", [])
                                if isinstance(sense, dict)
                            ]
                            synsets = [synset for synset in synsets if synset]

                            insert_entry.execute(
                                """
                                INSERT OR REPLACE INTO oewn_entries (
                                    lemma,
                                    part_of_speech,
                                    pronunciations_json,
                                    forms_json,
                                    synsets_json
                                ) VALUES (?, ?, ?, ?, ?);
                                """,
                                (
                                    normalized_lemma,
                                    normalized_pos,
                                    json.dumps(pronunciations, ensure_ascii=False),
                                    json.dumps(forms, ensure_ascii=False),
                                    json.dumps(synsets, ensure_ascii=False),
                                ),
                            )

                            for form in forms:
                                if form.casefold() == normalized_lemma.casefold():
                                    continue
                                insert_form.execute(
                                    """
                                    INSERT INTO oewn_forms (
                                        form,
                                        lemma,
                                        part_of_speech
                                    ) VALUES (?, ?, ?);
                                    """,
                                    (form, normalized_lemma, normalized_pos),
                                )

                connection.execute("COMMIT;")
            except Exception:
                connection.execute("ROLLBACK;")
                raise
    finally:
        connection.close()


def download_archive(zip_path: Path) -> None:
    try:
        urllib.request.urlretrieve(ZIP_URL, zip_path)
        return
    except Exception as error:
        print(f"urllib download failed ({error}); falling back to curl")

    subprocess.run(
        ["curl", "-L", ZIP_URL, "-o", str(zip_path)],
        check=True,
    )


def normalize_string(value: str) -> str:
    if not isinstance(value, str):
        return ""
    return value.strip()


def normalize_string_list(values: list[str]) -> list[str]:
    normalized: list[str] = []
    seen: set[str] = set()

    for value in values:
        cleaned = normalize_string(value)
        if not cleaned:
            continue
        key = cleaned.casefold()
        if key in seen:
            continue
        seen.add(key)
        normalized.append(cleaned)

    return normalized


def normalize_pronunciations(values: list[dict]) -> list[str]:
    normalized: list[str] = []
    seen: set[str] = set()

    for value in values:
        if not isinstance(value, dict):
            continue

        ipa = normalize_string(value.get("value", ""))
        if not ipa:
            continue

        variety = normalize_string(value.get("variety", ""))
        if variety == "GB":
            rendered = f"BrE /{ipa}/"
        elif variety == "US":
            rendered = f"AmE /{ipa}/"
        else:
            rendered = f"/{ipa}/"

        key = rendered.casefold()
        if key in seen:
            continue
        seen.add(key)
        normalized.append(rendered)

    return normalized


if __name__ == "__main__":
    main()
