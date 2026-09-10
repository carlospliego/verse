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

**2026-09-06 — Ticker: text only, and a speed setting (post-v1).**

Two changes, and the second turned on a constraint worth writing down.

**Reference dropped from the ticker.** It now scrolls the verse text alone. The menu bar is a
peripheral-vision surface; prefixing "1 Peter 5:8–9 — " meant every cycle spent several seconds
scrolling a citation past instead of scripture. The reference is still in the popover, and now also
as the heading of the right-click menu.

**Speed is characters per tick, not ticks per second.** This is the whole design, and it exists
because §7.1's two numbers collide: the advance interval must be **≥300ms**, and idle CPU must stay
**under 1%** — but at a 300ms tick this machine measured 1.10%. The cost is dominated by
`CA::Transaction::commit`, redrawing the menu bar text, and is near-linear in the *tick rate*. So the
tick rate stays pinned at 500ms and speed varies by how far the window moves each tick:

| Speed | Step | Rate | Measured CPU |
|---|---|---|---|
| Leisurely | 1 char/tick | 2 char/s | 0.627% |
| Steady *(default)* | 2 char/tick | 4 char/s | — |
| Brisk | 3 char/tick | 6 char/s | **0.516%** |

Brisk is three times faster than the old behaviour and costs *no more CPU* — the difference between
those two figures is measurement noise, not a trend. That is the property worth having: the redraw
rate is identical at every setting, so the speed control cannot be used to blow the power budget.
The step is capped at 3 deliberately; at four or more the jump stops reading as scrolling and starts
reading as the text being replaced.

Exposed in both places a user would look: a segmented picker in Settings (shown only when the ticker
is on) and a **Ticker Speed** submenu in the right-click menu. Persisted in `UserDefaults` by raw
string, so the raw values are now part of the stored format — there is a test pinning them.

**One memory observation, unresolved and recorded rather than explained away.** During the first
Brisk measurement one instance showed a transient jump — RSS 40 → 60.8 MB, `phys_footprint_peak`
163 MB — with a matching CPU bump in that minute. It did not recur: a 5-minute follow-up on that
same instance showed RSS flat and *falling* (−2.9 MB), and a fresh launch traced from t=0 stays at
**13 MB footprint, 13 MB peak, RSS settling to 40 MB** over two minutes at Brisk. So it is not a leak
and not attributable to the ticker, but I could not reproduce it and cannot say what caused it —
most likely a system-initiated transient. Worth watching if it shows up again.

**2026-09-06 (later) — Smoothness, and a measurement method that was quietly lying.**

Two user-visible fixes:

- **The middle dot is gone.** `TickerWindow`'s separator was `"   ·   "`, a U+00B7 marking the loop
  point. In the menu bar it read as debris — a stray punctuation mark drifting through the
  scripture with no explanation. Now five plain spaces: a gap says "this wrapped" just as well, and
  five is far short of the 30-character window so the status item never goes blank. There is a test
  asserting no glyph outside the verse's own characters ever appears in the title.

- **Scrolling is smooth, not jumpy.** The previous design varied speed by *step size* (1–3 characters
  per 500ms tick) because that keeps CPU flat across settings. It was wrong. Three characters
  arriving twice a second does not read as scrolling, it reads as the text being retyped, and no
  amount of CPU headroom compensates. The step is now always **one character** — the smallest the
  medium allows — and speed is the *interval*.

**The cost of that reversal, measured on the shipping build:**

| Speed | Interval | char/s | CPU (release, sandboxed, 2 min) |
|---|---|---|---|
| *(icon mode baseline)* | — | — | 0.000% |
| Leisurely | 500ms | 2.0 | **0.34%** |
| Steady *(default)* | 400ms | 2.5 | **0.73%** |
| Brisk | 200ms | 5.0 | **1.50%** — over the ceiling |

`brisk` genuinely exceeds §7.1's 1% and is marked as such everywhere it is offered. The two
in-budget settings sit at 400ms and 500ms because the cost curve crosses 1% at roughly 340ms.

Worth stating plainly, because it is a real conflict in the spec rather than an implementation
shortfall: **§7.1's two ticker limits cannot both be met on this hardware.** 300ms is the *floor* it
names for the advance interval, and 300ms costs 1.12% against a 1% ceiling. Honouring the CPU limit
means running slower than the stated floor. The in-budget settings do exactly that.

**Three bad measurements in a row, each with a different cause:**

1. A `defaults`-driven sweep reported `leisurely 0.02%`. A 300ms tick had measured 1.12% minutes
   earlier; 0.02% is an idle process. The preference never reached the app and the ticker was off.
2. Adding a "is it burning CPU?" guard caught that — but the next sweep then reported **brisk
   (5 char/s) at 0.05%, cheaper than leisurely (2 char/s) at 0.10%**. Physically impossible: 2.5×
   the redraws cannot cost half the CPU. The guard's 0.10% threshold was inside the noise, so it
   passed runs where the ticker was still off.
3. The root cause both times was `defaults write` not reaching the app — the exact failure already
   documented in this file weeks ago, which I then re-introduced by using `defaults` for
   convenience.

Fixed by making the harness prove the thing it is measuring: `--ticker-speed <name>` sets the speed
through `AppState` (the same path as the settings picker), and `--report-title` prints the live status
item title to stderr every five seconds.

**And then that harness lied too — the most instructive failure of the three.** It reported a tidy,
monotonic, plausible table: 500ms → 0.14%, 400ms → 0.21%, 200ms → 0.33%, every row backed by 21
distinct observed titles. All well inside budget, and flatly contradicting two earlier release
measurements. I was one step from loosening the speed limits on the strength of it.

The release build then measured **1.495% at 200ms** against a 0.000% icon-mode baseline — five times
the debug figure. The harness ran the binary *directly* rather than through LaunchServices, so it was
unsandboxed and its status item was never composited into the real menu bar. `--report-title` proved
the ticker's *logic* was running, which it was; it could not prove the menu bar was *redrawing*,
which is the entire cost. The instrument measured everything except the expensive part.

The earlier release numbers were right all along, and my "busy machine inflated them" explanation was
wrong — 500ms/0.70%, 300ms/1.12% and 200ms/1.50% fit one clean curve. **Measure the artefact you
ship, the way users run it.** A proxy that omits the costly half of the work will happily hand you a
consistent, monotonic, entirely fictional table.

**2026-09-08 — Smooth scrolling: Core Animation instead of a timer.**

The character-stepping ticker was still jumpy at every speed, and it was never going to stop being
jumpy. The reason is arithmetic, not tuning: **the smallest step available to text is one character
— about seven points in the menu bar font — so every advance is a seven-point jump however often it
fires.** Raising the rate buys more jumps per second, not smaller ones. I had already spent two
rounds tuning the wrong variable.

Replaced the whole mechanism. `TickerView` puts a `CATextLayer` over the status button and gives the
window server one instruction: translate at a constant rate, forever. Interpolation happens outside
this process, in fractions of a point, at the display's refresh rate.

That also dissolves the CPU conflict this file has been circling for days. Measured on the release
build:

| Config | App CPU |
|---|---|
| icon mode | 0.000% |
| ticker, leisurely (20pt/s) | 0.000% |
| ticker, steady (35pt/s) | 0.000% |
| ticker, brisk (55pt/s) | 0.011% |

There is no timer, so there is nothing to tick: §7.1's 300ms interval floor no longer applies, and
none of the speeds trades against power.

**And the work did not simply move to the window server, which was the obvious way for that table to
be a lie.** Claiming "free" on the strength of our own process reading zero would have repeated the
exact error of the fictional CPU table — measuring the cheap half. So `WindowServer` was A/B'd with
two long-lived processes, one scrolling at brisk and one in icon mode, four 20-second samples each:

```
ticker on  (brisk): 43.9  43.4  43.0  43.5   median 43.43%
ticker off (icon):  43.3  43.9  43.6  43.5   median 43.55%
                                             difference -0.12pp
```

Indistinguishable, and the samples are tight enough for that to mean something. (The ~43% is this
machine's ambient window-server load, not the app's.) An earlier attempt that killed and relaunched
the app between samples produced garbage — a 45% baseline that *fell* to 14% with the ticker on —
because relaunching drags process launch and window creation into the numbers. Interleaving two
already-running processes is what made the comparison hold still. `TickerSpeed` is points per second now, and
`isWithinPowerBudget` is gone — every setting is free in-process.

**Removed:** `TickerWindow`, `Ticker`, `StatusItemTitle` and their tests. All three existed to make
character-stepping cheap, and character-stepping is gone. Replaced by `TickerLayout` (seamless
looping, the whitespace gap, the 30-character width cap — now expressed as the item's *width*, which
is what §7.1's cap was always really about) and `TickerSpeed`, both still in the testable core.

**The verification is finally direct, and it caught a real mistake.** A layer-backed view can be
rasterised, so for the first time the ticker's *appearance* is checkable without looking at the menu
bar. The first attempt reported `ink=0.0%` — apparently a ticker drawing nothing:

1. `cacheDisplay(in:to:)` renders a view's own `draw(_:)` and silently ignores manually added
   sublayers. It returned a blank bitmap for a view whose entire content is a sublayer. Fixed by
   going through `CALayer.render(in:)`.
2. Then it still read 0.0%, because the diagnostic dump showed `foreground=1 1 1` — `labelColor`
   resolves to near-**white** for a dark menu bar, and I was rendering it onto a white ground.
   White on white. The ticker had been fine the second time; the check was wrong.

It now renders in both appearances against contrasting grounds and counts pixels that differ from
the ground: **12.0% ink in light, 13.4% in dark**, with the PNGs confirming clean text clipped to the
226pt item. Two failed checks in a row that both looked like broken features — the same shape of
error as the fictional CPU table, and the reason a diagnostic needs checking as carefully as the code.

**Also verified:** the popover and context menu still open with the view covering the button —
`hitTest` returns nil so clicks pass through to the `NSStatusBarButton` underneath. Without that,
laying a subview over the button would have swallowed every click.

**2026-09-09 — Popover sat too far below the menu bar.**

`NSPopover` opened **81pt** below the menu bar, which reads as detached from the item it belongs to.
There is no API for that distance. Two approaches, one of which does not work:

- **Raising the positioning rect does nothing.** `show(relativeTo:of:preferredEdge:)` clamps the
  rect, so a 20pt lift changed the result not at all, and past ~40pt the popover declined to appear.
- **Moving the window after `show` works**, and done in the same turn — before the window is drawn —
  there is no visible jump.

**The distance is measured, not hard-coded.** A 75pt lift happened to land correctly here, and
shipping that constant would have been a bug on any other display: the default spacing and the menu
bar's own height both vary. The correction now reads back where the window actually landed and
closes the difference to a 6pt target. It is self-limiting — once the gap is right the correction is
zero — which is what makes it safe to re-apply.

Re-applying matters, because switching between the verse, chapter and settings screens resizes the
popover and `NSPopover` re-positions itself when it does, undoing the lift. An observer on the
window's resize notification re-runs the correction. Verified across all three screens, including
settings at a different height: **6pt, 6pt, 6pt, 6pt**, window `maxY` identical each time.

**Two measurement traps here, both caught before they became the answer:**

1. `NSStatusBar.system.thickness` reports **22pt**, but the real menu bar on this display is **34pt**
   — `screen.frame.maxY - screen.visibleFrame.maxY`. Sizing against the status bar thickness would
   have left the popover 12pt lower than intended. `visibleFrame` is the authority.
2. The `--self-test` geometry is not real. It measures 0.5s after launch, before macOS has placed
   the status item, and reported a button at x=483 on a 1512pt-wide screen — far too left for a menu
   bar item. `--report-popover` waits for the item to settle before measuring.

**2026-09-09 (later) — Ticker rests still, scrolls on hover.**

The verse now sits still showing its opening words, and only scrolls while the pointer is over it.
Cheap to implement on top of the Core Animation marquee: removing the animation returns the layer to
its model position, which *is* the start of the verse, so "stop" and "return to rest" are the same
operation with no extra bookkeeping.

Hover comes from an `NSTrackingArea` on the status button — attached to the button rather than to
`TickerView`, because that view returns nil from `hitTest` (so clicks reach the button) and a view
invisible to hit testing is not a sound place to hang tracking.

**What is verified, and what is not.** Verified: at rest `animating=false`, offset 0; on hover the
animation attaches; on exit it detaches and the offset returns to 0; the tracking area is installed;
resting CPU is **0.022%**. Not verified: that macOS actually delivers enter/exit to a tracking area
on a status item. Synthetic pointer events are filtered on this machine — the cursor either ignores
the target or freezes outright — so a hover test here proves nothing either way.

**A fallback was built, measured, and then deliberately removed.** Global and local `.mouseMoved`
monitors did the same job by watching the pointer's position, and unlike the tracking area they were
provably firing (an event counter went 35 → 155 as the pointer moved). But they wake the process on
every mouse move anywhere on the system, and the cost was real: **0.822% CPU at rest** versus
**0.022%** without them — on a feature whose whole selling point is that it costs nothing when still.

Paying that permanently to insure against a risk I could not price was the wrong trade, so the
monitors are gone and the standard mechanism ships alone. If hover turns out not to fire, the fix is
to put them back — but that should be a response to evidence, not to my inability to test.
