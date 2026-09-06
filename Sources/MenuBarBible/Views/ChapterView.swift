import SwiftUI
import MenuBarBibleCore

/// The full chapter around today's verse, with the curated range highlighted.
struct ChapterView: View {
    @EnvironmentObject private var state: AppState

    private var curated: CuratedVerse? { state.today?.curated }
    private var verses: [Verse] { state.chapterVerses }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            chapterBody
            Divider()
            toolbar
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(chapterTitle)
                .font(.system(size: 12, weight: .semibold))
                .kerning(0.6)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(state.translationCode)
                .font(.system(size: 10, weight: .medium))
                .kerning(0.5)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var chapterBody: some View {
        if verses.isEmpty {
            // A chapter can legitimately come back empty in one translation but not
            // another. Say so; do not crash and do not show a blank panel.
            Text("This chapter isn't present in \(state.translationCode).")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    // Eager, not lazy. `scrollTo` can only reach a row that has been
                    // built, and the highlighted range is often far down a long chapter
                    // — verse 176 of Psalm 119 is exactly the case that fails. A chapter
                    // tops out at 176 short rows, so building them all is cheap.
                    ChapterVerseList(verses: verses, curated: curated)
                }
                .frame(maxHeight: 420)
                .onAppear { scrollToHighlight(using: proxy) }
                .onChange(of: verses) { _, _ in scrollToHighlight(using: proxy) }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            Button {
                state.screen = .verse
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                state.screen = .settings
            } label: {
                Image(systemName: "gearshape").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    // MARK: - Highlighting

    private var chapterTitle: String {
        guard let curated, let book = state.bible?.book(id: curated.bookId) else { return "" }
        // Single-chapter books read as "Jude", not "Jude 1".
        return book.chapterCount == 1 ? book.name : "\(book.name) \(curated.chapter)"
    }


    /// Scrolls so the highlighted range is visible on open.
    ///
    /// The anchor choice lives in `ChapterHighlight`, where it is tested: the exact
    /// verse number the curation names may be absent from this translation, and that
    /// must be tolerated rather than leave the view stranded at the top of the chapter.
    private func scrollToHighlight(using proxy: ScrollViewProxy) {
        guard let curated,
              let anchor = ChapterHighlight.scrollAnchor(in: verses, for: curated)
        else { return }

        // A beat for the lazy stack to build its rows before scrolling into them.
        DispatchQueue.main.async {
            withAnimation(.none) {
                proxy.scrollTo(anchor, anchor: .center)
            }
        }
    }
}

/// The chapter's rows. Split out from `ChapterView` so it can be rendered and checked
/// on its own — `ScrollView` contents do not come through `ImageRenderer`.
struct ChapterVerseList: View {
    let verses: [Verse]
    let curated: CuratedVerse?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(verses) { verse in
                ChapterVerseRow(verse: verse,
                                isHighlighted: curated?.contains(verse: verse.verse) ?? false)
                    .id(verse.verse)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }
}
