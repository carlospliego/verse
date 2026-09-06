import SwiftUI
import MenuBarBibleCore

/// The verse itself.
///
/// This screen shows roughly forty words and nothing else, so the typography is the
/// screen: a serif face at a size you read rather than scan, line spacing well above
/// the default, and a measure that keeps lines from running long.
struct VerseText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 16, weight: .regular, design: .serif))
            .lineSpacing(7)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
            .textSelection(.enabled)
    }
}

/// A single verse inside the chapter view, with its number set small and quiet.
struct ChapterVerseRow: View {
    let verse: Verse
    let isHighlighted: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(verse.verse)")
                .font(.system(size: 9, weight: .medium, design: .serif))
                .foregroundStyle(.tertiary)
                .baselineOffset(4)
                .frame(width: 18, alignment: .trailing)

            Text(verse.text)
                .font(.system(size: 14, weight: isHighlighted ? .medium : .regular, design: .serif))
                .lineSpacing(5)
                .foregroundStyle(isHighlighted ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isHighlighted ? Color.accentColor.opacity(0.13) : .clear)
        )
        .textSelection(.enabled)
    }
}
