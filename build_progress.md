# Menu Bar Bible — Build Progress

Phased plan for implementing `Verse_SPEC.md` using the dataset in `files.zip`.

**Status legend:** `[ ]` not started · `[~]` in progress · `[x]` done · `[!]` blocked/deferred

---

## Context: what the dataset already gives us

`files.zip` ships a **fully built, pre-validated `bible.sqlite`**. Verified on intake:

| Check | Expected (DATA.md) | Actual | |
|---|---|---|---|
| Schema | matches SPEC §5.1 exactly | matches, incl. `idx_verses_lookup` | ✅ |
| translations | 3 (WEB/KJV/ASV) | 3 | ✅ |
| books | 66, ids 1–66 | 66 | ✅ |
| verses | 93,286 (31,102 KJV / 31,098 WEB / 31,086 ASV) | 93,286, same split | ✅ |
| curated_verses | 329 | 329 | ✅ |
| multi-verse entries | 76 | 76 | ✅ |
| OT / NT split | 161 / 168 | 161 / 168 | ✅ |
| tags | 12 | 12 | ✅ |
| curated_verse_tags | — | 621 | ✅ |
| empty verse text | 0 | 0 | ✅ |
| markup artifacts (`<` `>`) | 0 | 0 | ✅ |
| `MAX(chapter)` vs `books.chapter_count` | 0 mismatches | 0 | ✅ |

**Consequence:** SPEC §10 build-order steps **1 and 2 are already complete**. The ETL scripts
(`build_db.py`, `build_curated.py`, `parse_usfx.py`, `parse_json.py`, `books.py`) and
`curated_pool.tsv` are kept in `tools/` as build artifacts — **not shipped in the app**.

**Carried forward from DATA.md — the one real hazard:** verse numbering differs between
translations (31,102 / 31,098 / 31,086). The chapter view must query the verses that *exist*
for the selected translation rather than iterating `1...n`, and must tolerate a curated range
whose endpoint is missing in the selected translation. All 329 curated refs resolve in all
three translations, so the daily-verse path is safe; free chapter browsing is where this bites.

---

## Technical decisions

| Decision | Choice | Why |
|---|---|---|
| Build system | Swift Package Manager + `Scripts/build_app.sh` | No XcodeGen/Tuist on this machine; hand-written `.xcodeproj` is fragile. `Package.swift` opens directly in Xcode. |
| SQLite access | Raw `SQLite3` C API (system lib) | SPEC §3 permits it. Zero external dependencies → zero package resolution, zero network, guaranteed offline. |
| Test framework | XCTest via `swift test` | Runs headlessly from CLI. |
| Core/app split | `MenuBarBibleCore` (library) + `MenuBarBible` (executable) | Steps 3–4 are testable with no UI, exactly as SPEC §10 demands. |
| Resource lookup | `BibleStore(url:)` injected; app resolves `Bundle.main`, tests pass a path | Keeps the data layer testable outside an app bundle. |
| Status item | `MenuBarExtra` + `.menuBarExtraStyle(.window)` first | SPEC §3: "Do not start with `NSStatusItem` — try the simple path first." |
| Stable hash | FNV-1a 64-bit | SPEC §6 requires a fixed algorithm, not `Hasher`. |

---

## Phase 0 — Scaffold & data intake `[x]`

- [x] Extract `files.zip`, validate `bible.sqlite` against DATA.md claims
- [x] Create SPM package layout mirroring SPEC §9
- [x] Vendor `bible.sqlite` into `Resources/`, ETL scripts into `tools/`
- [x] Confirm the two-store split (§5) exists structurally from the first commit
- [x] `swift build` succeeds on an empty skeleton

**Done when:** `swift build` is green and the tree matches SPEC §9.

## Phase 1 — Models + `BibleStore` (read-only) `[x]`

- [x] `Book`, `Verse`, `CuratedVerse`, `Tag`, `Translation`, `VerseReference` (+ reference formatting with en-dash: "Philippians 4:6–7")
- [x] `SQLiteDatabase` — thin read-only wrapper, prepared statements, error handling
- [x] `BibleStore`: open read-only (`SQLITE_OPEN_READONLY`), never written at runtime
  - [x] `books()`, `book(id:)`, `translations()`
  - [x] `text(for:translation:)` — joins a curated range into display text
  - [x] `chapter(bookId:chapter:translation:)` — **returns only rows that exist**, no `1...n` loop
  - [x] `curatedVerses()`, `tags(forCuratedVerse:)`
- [x] Tests: 66 books, all 3 translations resolve, Philippians 4:6–7 renders in each

**Done when:** tests pass; chapter query provably tolerates translation gaps.

## Phase 2 — `UserStore` (read-write) `[x]`

- [x] Path: `~/Library/Application Support/<bundle-id>/user.sqlite`, created on first launch
- [x] Schema from §5.2 — `pick_history`, `favorites` (favorites created but unused in v1)
- [x] `pick(for:)`, `record(_:for:)`, `recentPicks(limit: 60)`
- [x] Migration-safe `CREATE TABLE IF NOT EXISTS`; survives bundle replacement
- [x] Tests: fresh-file creation, idempotent re-open, deleting the file is a clean first run (no crash)

**Done when:** tests pass against a temp-dir store.

## Phase 3 — `VersePicker` (SPEC §6) `[x]`

- [x] FNV-1a 64-bit stable hash of `"YYYY-MM-DD"` (local calendar)
- [x] Seeded PRNG (SplitMix64) — no `Hasher`, no `Int.random`
- [x] Algorithm steps 1–9 verbatim, incl. empty-eligible fallback
- [x] `NSCalendarDayChangedNotification` observer for live midnight rollover
- [x] Tests:
  - [x] Same date → same verse across fresh processes (determinism)
  - [x] Different date → different verse
  - [x] No repeat within 60 days (seed `pick_history`, sweep 60+ days)
  - [x] Empty-eligible fallback when pool ≤ 60 entries
  - [x] Existing `pick_history` row short-circuits (step 2)

**Done when:** all determinism/exclusion tests pass. **Everything after depends on this being correct.**

## Phase 4 — `MenuBarExtra` shell + app bundle `[x]`

- [x] `MenuBarBibleApp` scene, `.menuBarExtraStyle(.window)`
- [x] Icon-only status item (template image, SF Symbol — icon design is SPEC §11 open question)
- [x] `AppState` observable: today's verse, selected translation, view mode
- [x] `Info.plist` with `LSUIElement=1`, `LSMinimumSystemVersion=14.0`
- [x] `Scripts/build_app.sh`: `swift build` → assemble `.app` → copy `bible.sqlite` → sign
- [x] Static popover renders

**Done when:** `MenuBarBible.app` launches, shows an icon, opens a popover.

## Phase 5 — Verse view `[x]`

- [x] Reference, verse text (generous spacing, considered typography), translation abbreviation
- [x] `TagChip` row for the verse's themes
- [x] Expand-to-chapter affordance, settings access
- [x] Popover renders in **under 200ms**

## Phase 6 — Chapter view `[x]`

- [x] Full chapter in selected translation, queried from existing rows only
- [x] Curated range highlighted; **tolerates a missing verse number rather than crashing**
- [x] `ScrollViewReader` positions the highlight visible on open
- [x] Superscript / de-emphasized verse numbers, back to verse view
- [x] Boundary tests: Psalm 119, Obadiah, Jude, Philemon, 2 & 3 John

## Phase 7 — Settings `[x]`

- [x] Translation picker (WEB/KJV/ASV) → re-renders **the same reference**, never re-picks
- [x] Ticker toggle, launch-at-login (`SMAppService.mainApp`), Quit
- [x] Prefs in `UserDefaults`, not SQLite (§5.2)

## Phase 8 — Ticker mode `[x]`

Hard constraints from §7.1 — must never block a release:
- [x] Title window capped at **30 characters**
- [x] Advance interval **≥ 300ms**, no per-frame animation
- [x] Timer suspends when not frontmost / display asleep / screen locked
- [x] Idle CPU **< 1%** over 10 minutes
- [x] Toggle takes effect immediately, no restart
- [x] Fallback to `NSStatusItem` — **taken**, with a measurement to justify it
- [x] If not solid → ship with the toggle hidden — *not needed; CPU now passes, toggle ships visible*

## Phase 9 — Package & verify `[x]`

- [x] Sandbox entitlement, no network entitlement — enforce §2 "no network calls whatsoever"
- [x] Codesign (ad-hoc locally; Developer ID + notarize documented for release)
- [x] Walk the full SPEC §8 acceptance checklist and record results here
- [x] Cold launch < 1s, RSS < 60MB, idle CPU ≈ 0% in icon mode

---

## Acceptance criteria ledger (SPEC §8)

Measured on macOS 26.6.2, Apple silicon, release build unless noted.

| Group | Criterion | Result |
|---|---|---|
| Daily verse | Popover opens with today's verse < 200ms | ✅ **2–3 ms** to open both stores and pick the verse; **25–35 ms** to render the verse view (debug build, incl. PNG rasterisation). Popover content is preloaded and `animates = false`. |
| Daily verse | Relaunch same day → same verse | ✅ Quit + relaunch → `2026-08-31\|165`, unchanged. Also holds after deleting `user.sqlite` entirely — same verse re-derived from the date. |
| Daily verse | Clock past midnight → different verse | ✅ **Observed live.** The app ran untouched from 23:26 through the real 2026-08-31 → 09-01 boundary and repicked on its own at 00:03:08: Matthew 5:14–16 → Luke 6:37. Also unit-tested. |
| Daily verse | No repeat within 60 days | ✅ 365 consecutive days walked, every sliding 60-day window checked for duplicates. Plus the spec's own method — seeding `pick_history` by hand. |
| Daily verse | Switching translation re-renders same reference | ✅ WEB/KJV/ASV all render `Matthew 5:14–16`, same curated id, genuinely different text. |
| Chapter | Full chapter, range highlighted | ✅ Verified by rendering the rows: 14–16 tinted and weighted, neighbours de-emphasised. |
| Chapter | Highlight visible without manual scrolling | ✅ `ChapterHighlight.scrollAnchor`, tested over all 329 entries × 3 translations. Uses an eager `VStack` — `scrollTo` cannot reach a row a `LazyVStack` has not built. |
| Chapter | Correct at Psalm 119, Obadiah, Jude, Philemon, 2 & 3 John | ✅ All covered in `ChapterHighlightTests`, in all three translations, including anchoring on the last verse. |
| Offline | Functions fully with networking disabled | ✅ Structural, not a promise: sandboxed **without** `network.client`, so the sandbox would refuse a connection. |
| Offline | No outbound connections | ✅ `otool -L`: 0 networking frameworks linked. `nm -u`: 0 network symbols. Nothing to observe in Little Snitch because nothing can open a socket. |
| Ticker | Toggle without restart | ✅ off → on → off drives the title `''` → 30 chars → `''` with no relaunch. |
| Ticker | Idle CPU < 1% over 10 min | ✅ **0.746%** sustained over a full 10 minutes. Was 3.0% under `MenuBarExtra` — see the log below. |
| Ticker | Title never exceeds 30 characters | ✅ Exhaustive: all 329 entries × 3 translations × every scroll position. |
| Ticker | Notched display, 12+ menu bar items | ⚠️ **Not verified — needs eyes on hardware.** 30-char cap and pinned status item width are the mitigation; `tickerToggleIsVisible` hides the feature if it fails. |
| Persistence | `user.sqlite` created at correct path | ✅ Created on first launch in **573 ms**. Under the sandbox this resolves to the app container, which is correct behaviour. |
| Persistence | Bundle replacement preserves history + prefs | ✅ Seeded 3 rows + set translation to KJV, replaced the bundle wholesale, relaunched — both intact. |
| Persistence | Deleting `user.sqlite` → clean first run, not a crash | ✅ Deleted and relaunched: no crash, schema recreated, both tables present. |
| Performance | Cold launch < 1s | ✅ **573–593 ms** from `open` to the day's verse selected and recorded. |
| Performance | RSS < 60MB with popover open | ✅ **13 MB** `phys_footprint` (what macOS actually accounts to the app). Raw RSS is 46–48 MB, most of it shared framework pages. Both under 60 MB; was 71.6 MB before dropping `MenuBarExtra`. |
| Performance | Idle CPU ≈ 0% in icon mode | ✅ **0.000%** held across a 9-minute sample — in icon mode no timer is ever created. |

**One criterion is genuinely outstanding**, and it is the one the spec says needs a person:
ticker behaviour on a notched display with a crowded menu bar. Everything else above was measured.

## Explicit non-goals (SPEC §2) — not built, no abstractions added for them

Search · notifications · notes/highlighting · reading plans/streaks · sync · **any network call** ·
sharing/export · iOS companion · non-public-domain translations · accounts/login/telemetry.

Tag filtering is v1.1: the schema supports it, the UI does not ship it.

---

## Log

_Newest last._

**2026-08-31 — Phases 0–3 complete.**

Scaffold, models, `BibleStore`, `UserStore`, `VersePicker`. **35/35 tests pass** (`swift test`).

Two failures found and fixed during the run, both in code written this session:
- `BibleStore.translations()` ordered by year after WEB, giving WEB/ASV/KJV. Replaced with an
  explicit `CASE` ordering so the picker shows WEB/KJV/ASV, the order the spec lists.
- `testSeedingPickHistoryDirectlyExcludesThoseVerses` asserted against a *fixed* excluded set.
  The 60-day window is a **rolling** 60: each new pick pushes the oldest seeded row out, making it
  eligible again — correct behaviour, wrong assertion. Test now checks each pick against the window
  as it stood at that moment.

Notable: `testFNV1aIsFixedForever` pins three hard-coded FNV-1a values. If a refactor ever changes
them, every user's daily verse changes with them — that is what the test is there to catch.

**2026-08-31 — Phases 4–7 complete.** App shell, verse view, chapter view, settings.
**52/52 tests pass.** `MenuBarBible.app` builds, signs, launches, and works.

Three defects found and fixed by actually looking at the output rather than trusting the build:

1. **`ChapterView` loaded its rows in `.onAppear` into local `@State`.** That gave an empty first
   frame and a second source of truth. Chapter rows now live in `AppState`, refreshed alongside the
   verse and the translation, so the view has them on frame one.
2. **`LazyVStack` + `scrollTo` could not reach the highlight.** `scrollTo` only reaches a row that
   has been built; the highlighted range is often far down a long chapter — Psalm 119:176 is exactly
   the case that fails. Switched to an eager `VStack`: a chapter is at most 176 short rows.
3. **A blind rename leaked into a user-facing string** — the settings picker read "BibleTranslation".
   The rename itself was necessary: the model type `Translation` collides with the system
   `Translation` framework that SwiftUI pulls in, which is a type-lookup error at every use site in
   the app target. Caught by rendering the settings screen and reading it.

Verification approach: screen recording is not permitted for this session, so the UI is checked by
rendering the real SwiftUI views through `ImageRenderer` (`--render-previews`, DEBUG-only).
Two limits of that method, both confirmed as artefacts rather than app bugs: `ScrollView` contents
do not rasterise (hence the separate `ChapterVerseList` render, which shows the highlight correctly),
and AppKit-backed controls render as placeholder swatches.

Logic that carries a real hazard was pulled out of the views into `MenuBarBibleCore` so it could be
tested: `ChapterHighlight` (highlight + scroll anchor, incl. translation gaps) and `TickerWindow`
(the 30-character cap).

**2026-08-31 — Phase 8, the ticker. This is where the work was.**

Measured under `MenuBarExtra`: **~3.0% CPU, sustained** (3.83% first pass, 3.00% after a fix,
stable across a multi-minute sample) against a hard requirement of **under 1%**.

Two causes, found in order:

1. **Scene-wide invalidation.** `MenuBarBibleApp.body` read `state.statusTitle`, so each 300ms tick
   published on `AppState` and invalidated the *entire scene* — the whole popover view tree
   included, open or not, three times a second. Moved the title into `StatusItemTitle`, a separate
   observable that only the label observes. That took 3.83% → 3.00%: real, but not the main cost.

2. **`MenuBarExtra` renders its label through SwiftUI.** The remaining ~3% is the per-tick cost of a
   SwiftUI update plus an `NSHostingView` re-measure plus a menu bar re-layout. It does not get
   cheaper by being asked more politely, and it is exactly the constraint the spec anticipates:

   > *If the scrolling ticker (§7) proves too constrained under `MenuBarExtra`, drop to
   > `NSStatusItem` in AppKit for the status item only and keep SwiftUI for the popover content.*

   Took that route. `StatusItemController` now owns an `NSStatusItem` and an `NSPopover`; a tick is
   one `NSStatusBarButton` title assignment. **Every view is unchanged** — `PopoverRootView` and
   everything under it is still SwiftUI, hosted in the popover.

The order the spec prescribes was followed and was worth following: `MenuBarExtra` first, drop to
AppKit only once there was a measurement proving it was necessary.

**A trap worth recording, because it nearly produced a false pass.** Replacing `MenuBarExtra` left
the SwiftUI `App` with no scene to declare, so it got an inert `Settings { EmptyView() }`. That
silently does not work: with no real scene the app never finishes launching,
`applicationDidFinishLaunching` never fires, and no status item is ever created — a menu bar app
that starts, shows nothing, and reports no error. It then measured **0.000% CPU**, which looks like
a triumphant pass and is really an app that isn't running. Replaced with a plain AppKit entry point
(`@main enum Main`), which is unambiguous.

Three measurement methods turned out to be unreliable and are recorded so they are not trusted again:
- **`CGWindowList` does not show this app's status item** even when the item exists. Verified the
  item directly instead (`statusItem.button != nil`) — it was there the whole time.
- **Buffered stdout is lost when the process is killed.** An early diagnostic printed nothing and
  looked like proof of failure; it was proof of buffering. Diagnostics write to stderr unbuffered.
- **`defaults` CLI writes do not reliably reach the app.** cfprefsd served the CLI and the app
  different snapshots of the same domain — the app read `tickerEnabled=nil` while `defaults read`
  showed `1`. Ticker measurements now drive the real toggle through `AppState` (DEBUG `--ticker-on`),
  which is also the path a user's switch takes.

**2026-08-31 — Phase 8 resolved, Phase 9 complete. 52/52 tests pass.**

Getting the ticker under 1% took four measured steps, each one profiled rather than guessed:

| Change | CPU |
|---|---|
| `MenuBarExtra`, title published on `AppState` | 3.83% |
| Title moved to its own observable (`StatusItemTitle`) | 3.00% |
| Status item dropped to AppKit (`NSStatusItem`) | 1.60% |
| Status item width pinned while ticking | 1.47% |
| **SF Symbol removed from the button while ticking** | 1.10% |
| Advance interval 300ms → 500ms | **0.746%** ✅ |

The fourth line is the one worth keeping. `sample` showed the tick dominated by
`-[NSButtonCell _resolvedImage]` → `-[NSImage _imageWithFallbackSymbolConfiguration:]` →
`bestRepresentationForHints:`. `book.closed` is an SF Symbol — a *vector* image re-resolved on
every redraw — and assigning the title redraws the button. The app was re-resolving a symbol
several times a second to draw an icon that never changed. Dropping the icon while text is
scrolling is also the better design: the text already says what it is.

What remained after that was `CA::Transaction::commit` — actually drawing the moved text — which is
irreducible for a scroll, and very nearly linear in the tick rate. §7.1 sets 300ms as a **floor** on
the interval and 1% as a **ceiling** on CPU; 500ms is the smallest round value that satisfies both,
and it still reads as a scroll. The rate is a tuning knob the spec left open; the CPU limit is not.

Two guesses were wrong along the way and are recorded as such: pinning the status item width barely
helped (1.60% → 1.47%), and scene invalidation, while real, was not the main cost. Profiling found
the actual cause in one pass after two rounds of reasoning had not.

**Verification note.** `--self-test` drives the status item the way a click does and confirms the
popover end to end: button present with image and action wired, popover opens, content 380×311,
popover closes. That was worth building — the status item had already been wrongly declared missing
once, on the strength of a `CGWindowList` query that does not see it.

**2026-09-01 00:0x — the midnight rollover verified itself.**

The app was left running in icon mode across the real 2026-08-31 → 2026-09-01 boundary while a CPU
measurement ran. It observed `NSCalendarDayChanged`, repicked, and wrote a new row unprompted:

```
2026-08-31 | 165 | 2026-08-31 23:26:42   Matthew 5:14–16
2026-09-01 | 191 | 2026-09-01 00:03:08   Luke 6:37
```

Better evidence than the unit test, which can only simulate the boundary. Worth noting the timing:
the notification arrived at **00:03**, not 00:00 — the system coalesces it and delivers a few
minutes late. That is normal and the right behaviour to expect; nothing in the app should assume the
verse changes on the stroke of midnight.

**Footnote on the icon-mode sample.** It ran 9 of an intended 10 minutes: the final release rebuild
killed and relaunched the app before the last sample. Minutes 6–9 print as `-0.000%`, and a negative
CPU delta is of course impossible for a single process — the sampler matches on the command line
rather than the pid, so it silently picked up the fresh process whose CPU time had reset. The
reading is still sound (zero either side of the restart), but the script should pin the pid at the
start. Noted so the sign is not mistaken for a measurement anomaly.

**2026-09-06 — Status item context menu (post-v1 addition).**

Right-clicking the icon did nothing: `NSStatusBarButton` sends its action on left-mouse-up only.
Added `sendAction(on: [.leftMouseUp, .rightMouseUp])` and a `handleClick` that routes left clicks to
the popover and right clicks — including control-click, which macOS reports as a right click — to a
menu:

```
1 Peter 5:8–9              (heading, today's reference)
─────────────
Today's Verse
Read in Context
─────────────
Translation ▸  WEB / KJV / ASV   (checkmark on the current one)
Show Verse in Menu Bar           (checkmark, hidden when tickerToggleIsVisible is false)
Launch at Login                  (checkmark)
─────────────
Settings…
─────────────
Quit Menu Bar Bible        ⌘Q
```

The menu is rebuilt on every open so its checkmarks reflect live state rather than a startup
snapshot — verified by `--self-test`, which dumps the menu, changes translation and the ticker, and
dumps it again.

Two details worth keeping:

- **The menu is attached, clicked, then detached** (`statusItem.menu = menu` → `performClick` →
  `= nil`) rather than shown with `popUp(positioning:…)`. That is what makes the item highlight and
  the menu track like every other menu bar item. Detaching matters: leaving the menu attached would
  make a *left* click open the menu instead of the popover. `performClick` blocks while menu
  tracking runs, so the detach lands after the menu closes.
- **`LaunchAtLogin` was extracted** into its own type. The settings screen and the menu both offer
  the toggle and must not drift apart, particularly on failure — `SMAppService` refuses while the app
  runs from a build directory. The menu ignores the error because a menu has nowhere to show one;
  settings still explains it.

Also fixed: `--self-test` persisted the translation and ticker preferences it changed. A diagnostic
must not leave the user's settings somewhere they did not put them. It now restores both, verified by
running it twice.
