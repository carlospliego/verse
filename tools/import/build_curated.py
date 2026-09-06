"""Load curated_pool.tsv into bible.sqlite, validating every reference.

Usage:
    python3 build_curated.py bible.sqlite curated_pool.tsv

Refuses to load if any reference names an unknown book or points at a
chapter/verse that does not exist in all three translations.
"""

import re
import sqlite3
import sys

from books import book_by_name

TAG_ORDER = [
    ("comfort",     "Comfort"),
    ("anxiety",     "Anxiety"),
    ("hope",        "Hope"),
    ("courage",     "Courage"),
    ("rest",        "Rest"),
    ("gratitude",   "Gratitude"),
    ("forgiveness", "Forgiveness"),
    ("patience",    "Patience"),
    ("humility",    "Humility"),
    ("wisdom",      "Wisdom"),
    ("provision",   "Provision"),
    ("purpose",     "Purpose"),
]
VALID_TAGS = {slug for slug, _ in TAG_ORDER}

REF = re.compile(r"^(.+?)\s+(\d+):(\d+)(?:\s*[-–]\s*(\d+))?$")


def parse_reference(raw):
    m = REF.match(raw.strip())
    if not m:
        raise ValueError(f"unparseable reference: {raw!r}")
    name, chapter, start, end = m.groups()
    meta = book_by_name(name)
    start, chapter = int(start), int(chapter)
    end = int(end) if end else start
    if end < start:
        raise ValueError(f"reversed verse range: {raw!r}")
    return meta[0], chapter, start, end


def read_pool(path):
    entries = []
    errors = []
    seen = set()

    with open(path, encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, 1):
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) != 2:
                errors.append(f"line {lineno}: expected 2 tab-separated fields")
                continue
            raw_ref, raw_tags = parts

            try:
                ref = parse_reference(raw_ref)
            except (ValueError, KeyError) as exc:
                errors.append(f"line {lineno}: {exc}")
                continue

            tags = [t.strip() for t in raw_tags.split(",") if t.strip()]
            if not tags:
                errors.append(f"line {lineno}: no tags on {raw_ref!r}")
                continue
            bad = [t for t in tags if t not in VALID_TAGS]
            if bad:
                errors.append(f"line {lineno}: unknown tag(s) {bad} on {raw_ref!r}")
                continue

            if ref in seen:
                errors.append(f"line {lineno}: duplicate reference {raw_ref!r}")
                continue
            seen.add(ref)

            entries.append((ref, tags, raw_ref))

    return entries, errors


def verify_against_db(db, entries):
    """Every verse in every range must exist in all three translations."""
    codes = [r[0] for r in db.execute("SELECT code FROM translations")]
    problems = []

    for (book_id, chapter, start, end), _tags, raw in entries:
        for v in range(start, end + 1):
            for code in codes:
                hit = db.execute(
                    "SELECT 1 FROM verses WHERE translation_code=? AND book_id=? "
                    "AND chapter=? AND verse=?",
                    (code, book_id, chapter, v)).fetchone()
                if not hit:
                    problems.append(f"{raw}: verse {v} missing in {code}")
    return problems


def main():
    db_path = sys.argv[1]
    pool_path = sys.argv[2]

    entries, errors = read_pool(pool_path)
    if errors:
        print("POOL PARSE FAILED")
        for e in errors:
            print("  -", e)
        raise SystemExit(1)
    print(f"parsed {len(entries)} curated entries")

    db = sqlite3.connect(db_path)

    problems = verify_against_db(db, entries)
    if problems:
        print("\nREFERENCE VALIDATION FAILED")
        for p in problems:
            print("  -", p)
        raise SystemExit(1)
    print("all references resolve in all three translations")

    db.execute("DELETE FROM curated_verse_tags")
    db.execute("DELETE FROM curated_verses")
    db.execute("DELETE FROM tags")

    db.executemany(
        "INSERT INTO tags (id, slug, display_name, sort_order) VALUES (?,?,?,?)",
        [(i + 1, slug, name, i + 1) for i, (slug, name) in enumerate(TAG_ORDER)])
    tag_id = {slug: i + 1 for i, (slug, _) in enumerate(TAG_ORDER)}

    for i, ((book_id, chapter, start, end), tags, _raw) in enumerate(entries, 1):
        db.execute(
            "INSERT INTO curated_verses (id, book_id, chapter, verse_start, verse_end) "
            "VALUES (?,?,?,?,?)", (i, book_id, chapter, start, end))
        db.executemany(
            "INSERT INTO curated_verse_tags (curated_verse_id, tag_id) VALUES (?,?)",
            [(i, tag_id[t]) for t in tags])

    db.commit()

    print("\ntag distribution:")
    rows = db.execute(
        "SELECT t.display_name, COUNT(*) FROM tags t "
        "JOIN curated_verse_tags c ON c.tag_id = t.id "
        "GROUP BY t.id ORDER BY t.sort_order").fetchall()
    for name, count in rows:
        print(f"  {name:<12} {count}")

    ot, nt = db.execute(
        "SELECT SUM(b.testament='OT'), SUM(b.testament='NT') "
        "FROM curated_verses c JOIN books b ON b.id = c.book_id").fetchone()
    print(f"\nOT entries: {ot}   NT entries: {nt}")

    multi = db.execute(
        "SELECT COUNT(*) FROM curated_verses WHERE verse_end > verse_start"
    ).fetchone()[0]
    print(f"multi-verse passages: {multi}")

    db.execute("VACUUM")
    db.close()


if __name__ == "__main__":
    main()
