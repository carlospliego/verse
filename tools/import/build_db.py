"""Build bible.sqlite (read-only app bundle database) from the three sources.

Usage:
    python3 build_db.py OUTPUT.sqlite

Validates before writing and refuses to produce a database that fails the
structural checks in SPEC.md §4.
"""

import os
import re
import sqlite3
import sys

import parse_json
import parse_usfx
from books import BOOKS, BY_ID

SOURCES = {
    "WEB": ("../seven1m_open-bibles/eng-web.usfx.xml", parse_usfx.parse,
            "World English Bible", 2000),
    "KJV": ("../raw/KJV.json", parse_json.parse,
            "King James Version", 1769),
    "ASV": ("../raw/ASV.json", parse_json.parse,
            "American Standard Version", 1901),
}

SCHEMA = """
PRAGMA journal_mode = DELETE;

CREATE TABLE translations (
    code            TEXT PRIMARY KEY,
    name            TEXT NOT NULL,
    year            INTEGER,
    license         TEXT NOT NULL
);

CREATE TABLE books (
    id              INTEGER PRIMARY KEY,
    name            TEXT NOT NULL,
    abbreviation    TEXT NOT NULL,
    testament       TEXT NOT NULL,
    chapter_count   INTEGER NOT NULL
);

CREATE TABLE verses (
    id                INTEGER PRIMARY KEY,
    translation_code  TEXT NOT NULL REFERENCES translations(code),
    book_id           INTEGER NOT NULL REFERENCES books(id),
    chapter           INTEGER NOT NULL,
    verse             INTEGER NOT NULL,
    text              TEXT NOT NULL
);

CREATE UNIQUE INDEX idx_verses_lookup
    ON verses(translation_code, book_id, chapter, verse);

CREATE TABLE curated_verses (
    id              INTEGER PRIMARY KEY,
    book_id         INTEGER NOT NULL REFERENCES books(id),
    chapter         INTEGER NOT NULL,
    verse_start     INTEGER NOT NULL,
    verse_end       INTEGER NOT NULL
);

CREATE UNIQUE INDEX idx_curated_ref
    ON curated_verses(book_id, chapter, verse_start, verse_end);

CREATE TABLE tags (
    id              INTEGER PRIMARY KEY,
    slug            TEXT NOT NULL UNIQUE,
    display_name    TEXT NOT NULL,
    sort_order      INTEGER NOT NULL
);

CREATE TABLE curated_verse_tags (
    curated_verse_id  INTEGER NOT NULL REFERENCES curated_verses(id),
    tag_id            INTEGER NOT NULL REFERENCES tags(id),
    PRIMARY KEY (curated_verse_id, tag_id)
);

CREATE INDEX idx_cvt_tag ON curated_verse_tags(tag_id);
"""

BAD_MARKUP = re.compile(r"[<>]|&[a-z]+;|\{|\}")


def load_source(code):
    path, parser, _name, _year = SOURCES[code]
    rows = list(parser(path))
    if not rows:
        raise SystemExit(f"{code}: parser returned no rows")
    return rows


def validate(code, rows, problems):
    seen = set()
    books_seen = set()
    max_chapter = {}

    for book_id, chapter, verse, text in rows:
        key = (book_id, chapter, verse)
        if key in seen:
            problems.append(f"{code}: duplicate verse {key}")
        seen.add(key)
        books_seen.add(book_id)
        max_chapter[book_id] = max(max_chapter.get(book_id, 0), chapter)

        if not text.strip():
            problems.append(f"{code}: empty text at {key}")
        if BAD_MARKUP.search(text):
            problems.append(f"{code}: markup artifact at {key}: {text[:60]!r}")
        if chapter < 1 or verse < 1:
            problems.append(f"{code}: non-positive index at {key}")

    missing = {b[0] for b in BOOKS} - books_seen
    if missing:
        names = ", ".join(BY_ID[i][2] for i in sorted(missing))
        problems.append(f"{code}: missing books: {names}")

    for book in BOOKS:
        bid, _usfx, name, _ab, _t, expected = book
        found = max_chapter.get(bid, 0)
        if found != expected:
            problems.append(
                f"{code}: {name} has {found} chapters, expected {expected}")

    return seen


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "bible.sqlite"

    problems = []
    parsed = {}
    keysets = {}

    for code in SOURCES:
        rows = load_source(code)
        parsed[code] = rows
        keysets[code] = validate(code, rows, problems)
        print(f"{code}: {len(rows):,} verses")

    # Cross-translation coverage report (differences are expected, not fatal).
    union = set().union(*keysets.values())
    print(f"\nunion of all references: {len(union):,}")
    for code, keys in keysets.items():
        gap = len(union - keys)
        print(f"  {code}: {len(keys):,} present, {gap} not in this translation")

    if problems:
        print("\nVALIDATION FAILED")
        for p in problems[:40]:
            print("  -", p)
        if len(problems) > 40:
            print(f"  ... and {len(problems) - 40} more")
        raise SystemExit(1)
    print("\nvalidation passed")

    if os.path.exists(out):
        os.remove(out)
    db = sqlite3.connect(out)
    db.executescript(SCHEMA)

    db.executemany(
        "INSERT INTO translations (code, name, year, license) VALUES (?,?,?,?)",
        [(c, SOURCES[c][2], SOURCES[c][3], "public-domain") for c in SOURCES])

    db.executemany(
        "INSERT INTO books (id, name, abbreviation, testament, chapter_count) "
        "VALUES (?,?,?,?,?)",
        [(b[0], b[2], b[3], b[4], b[5]) for b in BOOKS])

    for code, rows in parsed.items():
        db.executemany(
            "INSERT INTO verses (translation_code, book_id, chapter, verse, text) "
            "VALUES (?,?,?,?,?)",
            [(code, b, c, v, t) for b, c, v, t in rows])

    db.commit()
    db.execute("VACUUM")
    db.close()

    size = os.path.getsize(out) / (1024 * 1024)
    print(f"\nwrote {out} ({size:.1f} MB)")


if __name__ == "__main__":
    main()
