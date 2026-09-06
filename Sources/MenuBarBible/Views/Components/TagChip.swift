import SwiftUI
import MenuBarBibleCore

/// A theme chip. Quiet by design — the verse is the subject, these are a footnote.
struct TagChip: View {
    let tag: Tag

    var body: some View {
        Text(tag.displayName)
            .font(.system(size: 10, weight: .medium))
            .kerning(0.3)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.primary.opacity(0.06))
            )
            .overlay(
                Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
    }
}
