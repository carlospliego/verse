# Menu Bar Bible

A macOS menu bar app that shows a daily verse, drawn from a hand-curated pool, readable
in context, fully offline.

Built to `Verse_SPEC.md`. Dataset documented in `DATA.md`. Build progress and the
acceptance-criteria ledger are in `build_progress.md`.

## Build

```bash
swift test                      # 52 tests, no UI needed
./Scripts/build_app.sh          # debug build  -> build/MenuBarBible.app
./Scripts/build_app.sh release  # release build
open build/MenuBarBible.app
```

`Package.swift` opens directly in Xcode if you prefer that.

For distribution, pass a Developer ID identity as the second argument; the script
prints the notarisation steps.

## Layout

```
Sources/
  MenuBarBibleCore/       library — no UI, fully testable headlessly
    Models/               Book, Verse, CuratedVerse, Tag, BibleTranslation, VerseReference
    Data/                 SQLiteDatabase, BibleStore, UserStore, VersePicker,
                          StableHash, ChapterHighlight, TickerWindow
  MenuBarBible/           the app
    App/                  MenuBarBibleApp (MenuBarExtra scene), AppState, DailyVerse
    Views/                VerseView, ChapterView, SettingsView, Components/
    MenuBar/              Ticker, StatusItemTitle
Tests/                    XCTest over the core
Resources/                bible.sqlite, Info.plist, entitlements, AppIcon.icns
tools/                    build artifacts — ETL and icon generation, never shipped
Scripts/build_app.sh      assembles and signs the .app
```

## The two stores

Non-negotiable split, present from the first commit:

- **`bible.sqlite`** ships in the bundle, opened `SQLITE_OPEN_READONLY`, replaced
  wholesale on every update. 66 books, 93,286 verses across WEB/KJV/ASV, 329 curated
  references, 12 tags.
- **`user.sqlite`** lives in Application Support, created on first launch, survives
  updates. Holds `pick_history` and `favorites`.

Preferences (translation, ticker, launch at login) are in `UserDefaults`, not SQLite.

Under the sandbox, Application Support resolves inside the app's container:
`~/Library/Containers/com.menubarbible.MenuBarBible/Data/Library/Application Support/`.

## Offline

There are no network calls, and the build makes that structural rather than a promise:
the app is sandboxed **without** `com.apple.security.network.client`, so the sandbox
would refuse a connection even if code tried to open one. No networking framework is
linked and no network symbol is referenced — `otool -L` and `nm -u` on the shipped
binary come back empty.

## Curation

`tools/import/curated_pool.tsv` is the source of truth for the pool — references and
tags, one per line. `build_curated.py` refuses to load an unparseable reference, an
unknown book or tag, a duplicate, or a reference that does not resolve in all three
translations, so a bad edit fails the build instead of shipping silently.

The pool stores **references, not text**. The curation was authored once and renders in
whichever translation the reader selects.

## Using it

**Left-click** the book icon for today's verse. Click the verse text's "Read in context"
to expand into the surrounding chapter, with the verse highlighted.

**Right-click** (or control-click) for a menu: today's reference, jump straight to the
verse or the chapter, a translation submenu, the ticker and launch-at-login toggles,
Settings, and Quit.

There is no Dock icon and no window — the status item is the whole visible app.

## Checking it without clicking

Screen capture is not always available (CI, a remote session), and a menu bar app is
hard to inspect without it. Three DEBUG-only entry points cover that. None of them exist
in a release build.

```bash
# render the popover screens to PNGs, then report startup timing,
# translation switching, and the ticker toggle
MenuBarBible.app/Contents/MacOS/MenuBarBible --render-previews /tmp/out

# drive the status item the way a click does and report what happened
MenuBarBible.app/Contents/MacOS/MenuBarBible --self-test

# turn ticker mode on through the same property the settings switch is bound to,
# for CPU measurement
MenuBarBible.app/Contents/MacOS/MenuBarBible --ticker-on
```

Two things to know about `--render-previews`: `ScrollView` contents do not rasterise
through `ImageRenderer` (which is why the chapter rows render separately as
`chapter-rows.png`), and AppKit-backed controls such as `Picker` and `Toggle` come out as
placeholder swatches. Both are artefacts of the renderer, not the app.

Do not set preferences with the `defaults` CLI to test the app — cfprefsd will serve the
CLI and the app different snapshots of the same domain, which silently invalidates
whatever you were measuring. Use `--ticker-on`, or the settings UI.
