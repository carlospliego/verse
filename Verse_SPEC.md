# Menu Bar Bible — Product Spec (v1)

A macOS menu bar app that shows a daily verse, drawn from a hand-curated pool, readable in context, fully offline.

---

## 1. Product summary

**What it is:** A status bar app. Click the icon, get today's verse in a popover. Click the verse, expand into the surrounding chapter with the verse highlighted.

**Who it's for:** People who want scripture in their peripheral vision during a workday without opening a Bible study app.

**Why it's different:** The daily verse is chosen from a small, hand-curated, tagged pool — not scraped, not randomly drawn from all 31,000 verses. The curation is the product.

**Business model:** Free at launch. No paid tier in v1. Storage is split so a paid tier can be added later without migration (see §5).

---

## 2. Non-goals for v1

Explicitly out of scope. Do not build these, do not add abstractions in anticipation of them:

- Full-text search
- Notifications / reminders
- Notes, highlighting, or annotation
- Reading plans or streak tracking
- iCloud or cross-device sync
- Any network calls whatsoever
- Sharing / export
- iOS companion
- Any non-public-domain translation
- Accounts, login, or telemetry

---

## 3. Platform and stack

| Decision | Value |
|---|---|
| Language | Swift |
| UI | SwiftUI, `MenuBarExtra` with `.menuBarExtraStyle(.window)` |
| Minimum OS | macOS 14.0 |
| Persistence | SQLite (GRDB.swift or raw SQLite3) |
| Networking | None |
| Sandbox | Enabled |
| Distribution | Developer ID, signed + notarized, direct download |

**Note on `MenuBarExtra`:** it is the right default and covers everything except fine-grained control of the status item title. If the scrolling ticker (§7) proves too constrained under `MenuBarExtra`, drop to `NSStatusItem` in AppKit for the status item only and keep SwiftUI for the popover content. Do not start with `NSStatusItem` — try the simple path first.

Do not use Electron, Tauri, or any web-based shell.

---

## 4. Content

### Translations (all public domain, all bundled)

| Code | Name | Role |
|---|---|---|
| `WEB` | World English Bible | **Default.** Public domain and modern English. |
| `KJV` | King James Version | Alternate |
| `ASV` | American Standard Version | Alternate |

No licensing review is required for any of these. This is why they were chosen.

### Import task

Write a one-time build script (`tools/import.swift` or a Python script, your call) that ingests public domain source texts and produces `bible.sqlite`. Source texts are available from ebible.org and similar public domain archives in USFM or OSIS format. The script is a build artifact, not part of the shipped app.

The resulting database must be verified: correct book count (66), correct chapter counts per book, no empty verse rows, no HTML or markup artifacts in verse text.

### Curated pool

A hand-authored set of **300–500 verse references**, each tagged with one or more themes. Target roughly a dozen tags — for example: comfort, anxiety, gratitude, courage, forgiveness, patience, hope, wisdom, humility, provision, rest, purpose.

Critical design point: **the curated pool stores references, not text.** A pool entry is `(book, chapter, verse_start, verse_end)`. The text is rendered from whichever translation the user has selected. This means the curation is written once and works across all three translations.

Pool entries may span multiple verses (e.g. Philippians 4:6–7) where a single verse would lack sense on its own.

The pool ships as seed data inside the read-only bundle. It is authored by hand, not generated.

---

## 5. Data architecture

Two separate stores. This split is non-negotiable and must exist from the first commit.

### 5.1 Read-only bundle — `bible.sqlite`

Ships inside the app bundle. Replaced wholesale on every app update. Never written to at runtime.

```sql
CREATE TABLE translations (
    code            TEXT PRIMARY KEY,   -- 'WEB', 'KJV', 'ASV'
    name            TEXT NOT NULL,
    year            INTEGER,
    license         TEXT NOT NULL       -- 'public-domain'
);

CREATE TABLE books (
    id              INTEGER PRIMARY KEY,  -- 1..66, canonical order
    name            TEXT NOT NULL,        -- 'Philippians'
    abbreviation    TEXT NOT NULL,        -- 'Phil'
    testament       TEXT NOT NULL,        -- 'OT' | 'NT'
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
    verse_end       INTEGER NOT NULL      -- equals verse_start for single verses
);

CREATE TABLE tags (
    id              INTEGER PRIMARY KEY,
    slug            TEXT NOT NULL UNIQUE,  -- 'anxiety'
    display_name    TEXT NOT NULL,         -- 'Anxiety'
    sort_order      INTEGER NOT NULL
);

CREATE TABLE curated_verse_tags (
    curated_verse_id  INTEGER NOT NULL REFERENCES curated_verses(id),
    tag_id            INTEGER NOT NULL REFERENCES tags(id),
    PRIMARY KEY (curated_verse_id, tag_id)
);
```

### 5.2 User store — `user.sqlite`

Lives at `~/Library/Application Support/<bundle-id>/user.sqlite`. Created on first launch. Survives app updates.

```sql
CREATE TABLE pick_history (
    pick_date         TEXT PRIMARY KEY,     -- 'YYYY-MM-DD', local calendar
    curated_verse_id  INTEGER NOT NULL,
    created_at        INTEGER NOT NULL      -- unix epoch
);

CREATE TABLE favorites (
    curated_verse_id  INTEGER PRIMARY KEY,
    created_at        INTEGER NOT NULL
);
```

`favorites` is unused by v1 UI. Create the table anyway; it costs nothing and reserves the shape.

Simple preferences (selected translation, ticker on/off, launch at login) live in `UserDefaults`, not SQLite.

---

## 6. Verse selection

Deterministic per local calendar day. The same day always yields the same verse, and relaunching the app does not reshuffle.

```
func verseForToday() -> CuratedVerse

1. dateKey = current local date as "YYYY-MM-DD"
2. If pick_history has a row for dateKey, return that curated_verse_id. Done.
3. recent = last 60 curated_verse_ids from pick_history, ordered by pick_date desc
4. eligible = all curated_verses NOT IN recent
5. If eligible is empty, eligible = all curated_verses
6. seed = stable hash of dateKey  (use a fixed algorithm — NOT Swift's
   Hasher, which is randomly seeded per process)
7. index = seed % eligible.count, using a seeded PRNG
8. Insert (dateKey, chosen id) into pick_history
9. Return chosen
```

**Requirements:**
- Step 6 must use a stable hash. `Hasher` is seeded per-process and will produce different results across launches. Use FNV-1a or SHA-256 truncated to 64 bits.
- Rolling over midnight while the app is running must produce a new verse. Observe `NSCalendarDayChangedNotification`.
- Changing translation must not change which verse is shown — only the text rendering.

Tag filtering (letting the user restrict the pool to selected tags) is **v1.1**. The schema supports it; the UI does not ship it.

---

## 7. UI

### 7.1 Status item

**Default: icon only.** A simple monochrome template image that respects light/dark mode and menu bar tinting.

**Ticker mode (off by default, behind a preference toggle):** the verse text scrolls horizontally in the menu bar itself.

Ticker constraints — treat these as hard requirements, not suggestions:

- Title window capped at **30 characters**
- Advance interval **300ms** minimum. Do not animate per-frame.
- Timer suspends when the app is not frontmost and the popover is closed — or at minimum, suspends when the display sleeps or the screen is locked
- Idle CPU in ticker mode must stay under 1%
- Toggling the preference takes effect immediately without restart

Build and ship icon mode first. Ticker mode must never be able to block a release — if it is not solid, ship with the toggle hidden.

Context worth knowing: macOS gives status items whatever horizontal space is left over, and on notched displays a long title can be truncated or pushed under the notch entirely. Test on a 14" MacBook Pro with a crowded menu bar before considering this done.

### 7.2 Popover — verse view (default)

- Verse reference (e.g. "Philippians 4:6–7")
- Verse text, generously spaced, readable typography
- Translation abbreviation, subtle
- Tag chips for the verse's themes
- Affordance to expand into chapter context
- Settings access

Typography carries this screen. It displays roughly forty words; make them look considered.

### 7.3 Popover — chapter view

- Full chapter in the selected translation
- The curated verse range visually highlighted
- Scrolled so the highlighted range is visible on open
- Verse numbers rendered as superscript or otherwise de-emphasized
- Back to verse view

### 7.4 Settings

- Translation picker (WEB / KJV / ASV)
- Ticker mode toggle
- Launch at login toggle (`SMAppService.mainApp`)
- Quit

---

## 8. Acceptance criteria

**Daily verse**
- [ ] Clicking the status item opens a popover showing today's verse in under 200ms
- [ ] Quitting and relaunching on the same day shows the same verse
- [ ] Advancing the system clock past midnight yields a different verse
- [ ] A verse is not repeated within 60 days, verified by seeding pick_history
- [ ] Switching translation re-renders the same verse reference in the new text

**Chapter context**
- [ ] Expanding shows the full chapter with the verse range highlighted
- [ ] The highlighted range is visible without manual scrolling on open
- [ ] Chapter view is correct at chapter boundaries (Psalm 119, single-verse books like Obadiah, Jude, Philemon, 2 & 3 John)

**Offline**
- [ ] The app functions fully with networking disabled
- [ ] No outbound connections appear in Little Snitch or Charles during a full session

**Ticker**
- [ ] Toggling ticker mode takes effect without restart
- [ ] Idle CPU stays under 1% with ticker running for 10 minutes
- [ ] Title never exceeds 30 characters
- [ ] Behaves acceptably on a notched display with 12+ other menu bar items

**Persistence**
- [ ] `user.sqlite` is created on first launch at the correct path
- [ ] Replacing the app bundle preserves pick history and preferences
- [ ] Deleting `user.sqlite` results in a clean first-run state, not a crash

**Performance**
- [ ] Cold launch to usable status item under 1 second
- [ ] Resident memory under 60MB with popover open
- [ ] Idle CPU effectively 0% in icon mode

---

## 9. Suggested project structure

```
MenuBarBible/
├── App/
│   ├── MenuBarBibleApp.swift        # MenuBarExtra scene
│   └── AppState.swift               # observable app state
├── Views/
│   ├── VerseView.swift
│   ├── ChapterView.swift
│   ├── SettingsView.swift
│   └── Components/
│       ├── TagChip.swift
│       └── VerseText.swift
├── Models/
│   ├── Verse.swift
│   ├── CuratedVerse.swift
│   ├── Book.swift
│   └── Tag.swift
├── Data/
│   ├── BibleStore.swift             # read-only bundle access
│   ├── UserStore.swift              # user.sqlite access
│   └── VersePicker.swift            # §6 selection algorithm
├── MenuBar/
│   ├── StatusItemController.swift
│   └── Ticker.swift
├── Resources/
│   ├── bible.sqlite
│   └── Assets.xcassets
└── tools/
    └── import/                      # build-time text import, not shipped
```

---

## 10. Build order

1. Import script → verified `bible.sqlite` with all three translations
2. Author the curated pool and tags; load as seed data
3. `BibleStore` + `UserStore` with tests
4. `VersePicker` with tests covering determinism, exclusion window, and midnight rollover
5. `MenuBarExtra` shell with icon and a static popover
6. Verse view
7. Chapter view with highlighting and scroll positioning
8. Settings: translation, launch at login
9. Ticker mode behind its toggle
10. Sign, notarize, package

Steps 1–4 have no UI and are fully testable. Do them first and do them properly; everything after depends on them being correct.

---

## 11. Open questions

- Exact tag list and pool composition — how many verses per tag, and what spread across OT/NT
- Icon design
- App name
- Whether the ticker should show the reference, the verse text, or alternate between them
