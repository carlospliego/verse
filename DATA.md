# Menu Bar Bible — Data

Everything in `bible.sqlite` is public domain. No licensing review, no attribution requirement, no runtime API.

## Contents

| File | What it is |
|---|---|
| `bible.sqlite` | The read-only app bundle database. Ships inside the app. 15.4 MB. |
| `curated_pool.tsv` | Source of truth for the curated pool. Edit this, then rebuild. |
| `tools/` | ETL scripts. Build artifacts — do not ship these in the app. |

## Provenance

| Translation | Source | Status |
|---|---|---|
| WEB — World English Bible | `seven1m/open-bibles`, `eng-web.usfx.xml` (USFX XML, originating from eBible.org) | Dedicated to the public domain by its producers |
| KJV — King James Version (1769) | `scrollmapper/bible_databases`, `formats/json/KJV.json` | Public domain in the US by age |
| ASV — American Standard Version (1901) | `scrollmapper/bible_databases`, `formats/json/ASV.json` | Public domain by age |

WEB is the intended default: it is the only one of the three in modern English, which matters for a verse people glance at for a few seconds.

## Verse counts

```
KJV  31,102
WEB  31,098
ASV  31,086
```

These differ, and the difference is real, not a parsing bug. Translations disagree about where verse boundaries fall — some merge adjacent verses that others keep separate, and a few passages with weak manuscript support are bracketed or omitted in the later translations. The union of all references across the three is 31,105.

**This matters for your chapter view.** Do not assume a verse number present in one translation exists in another. When rendering a chapter, query the verses that exist for the selected translation rather than iterating a fixed range. When highlighting a curated range, tolerate a missing verse number rather than crashing.

Every one of the 329 curated references was verified to resolve in all three translations, so the daily verse path is safe. The risk is confined to free chapter browsing.

## Schema

Matches SPEC.md §5.1 exactly:

- `translations` — code, name, year, license
- `books` — 66 rows, canonical order, id 1–66
- `verses` — one row per translation/book/chapter/verse, unique index on the lookup tuple
- `curated_verses` — references only, no text
- `tags` — 12 themes with display names and sort order
- `curated_verse_tags` — join table

The `user.sqlite` store described in SPEC.md §5.2 is created by the app at runtime. It is not part of this dataset.

## Curated pool

329 entries, 12 tags, 76 of them multi-verse passages. Split 161 Old Testament / 168 New Testament.

```
Comfort      69     Forgiveness  39
Anxiety      31     Patience     55
Hope         89     Humility     48
Courage      67     Wisdom       42
Rest         35     Provision    29
Gratitude    38     Purpose      79
```

Counts exceed 329 because entries carry more than one tag.

Entries store **references, not text** — `(book_id, chapter, verse_start, verse_end)`. The text renders from whichever translation is selected, so the curation was authored once and works across all three.

Treat this pool as a starting point, not a finished product. It leans toward the familiar, which is reasonable for a v1 but is also the thing that makes these apps feel interchangeable. The distribution is uneven on purpose — hope and comfort carry more weight than provision — but you may want that flatter. This is the part of the app worth your own editing time.

## Rebuilding

The source texts are not vendored here. To rebuild from scratch:

```bash
# fetch sources
curl -L -o raw/KJV.json https://raw.githubusercontent.com/scrollmapper/bible_databases/master/formats/json/KJV.json
curl -L -o raw/ASV.json https://raw.githubusercontent.com/scrollmapper/bible_databases/master/formats/json/ASV.json
git clone --filter=blob:none --no-checkout --depth 1 https://github.com/seven1m/open-bibles.git
cd open-bibles && git checkout HEAD -- eng-web.usfx.xml && cd ..

# build (requires python3 + lxml)
cd tools
python3 build_db.py ../bible.sqlite
python3 build_curated.py ../bible.sqlite ../curated_pool.tsv
```

`build_db.py` refuses to write a database that fails validation: all 66 books present, chapter counts matching canonical expectations, no duplicate verse keys, no empty text, no markup artifacts.

`build_curated.py` refuses to load a pool containing an unparseable reference, an unknown book name, an unknown tag, a duplicate entry, or a reference pointing at a verse that does not exist in all three translations. Edit `curated_pool.tsv` freely — a bad reference fails the build rather than shipping silently.

## Editing the pool

One entry per line, tab-separated:

```
Philippians 4:6-7	anxiety,rest,gratitude
```

Book names accept `1 Samuel`, `I Samuel`, or `First Samuel`. Ranges use a hyphen. Lines beginning with `#` are comments.

To add a tag, add it to `TAG_ORDER` in `tools/build_curated.py` and rebuild.
