import SwiftUI
import MenuBarBibleCore

/// The default screen: today's verse, and very little else.
struct VerseView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let today = state.today {
                content(for: today)
            } else {
                Text("No verse for today.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(24)
            }
            Divider()
            toolbar
        }
    }

    @ViewBuilder
    private func content(for today: DailyVerse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(today.referenceText)
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 8)

                Text(today.translationCode)
                    .font(.system(size: 10, weight: .medium))
                    .kerning(0.5)
                    .foregroundStyle(.tertiary)
            }

            VerseText(text: today.text)

            if !today.tags.isEmpty {
                // Wraps rather than clips: a verse can carry four or five themes.
                FlowLayout(spacing: 5) {
                    ForEach(today.tags) { TagChip(tag: $0) }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 18)
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            Button {
                state.screen = .chapter
            } label: {
                Label("Read in context", systemImage: "text.alignleft")
                    .font(.system(size: 11))
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(state.today == nil)

            Spacer()

            Button {
                state.screen = .settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}
