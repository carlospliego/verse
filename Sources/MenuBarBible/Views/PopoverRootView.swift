import SwiftUI

/// Routes between the three screens and fixes the popover's width.
struct PopoverRootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Group {
            if let failure = state.loadFailure {
                LoadFailureView(message: failure)
            } else {
                switch state.screen {
                case .verse:    VerseView()
                case .chapter:  ChapterView()
                case .settings: SettingsView()
                }
            }
        }
        .frame(width: 380)
        .background(.regularMaterial)
    }
}

struct LoadFailureView: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Couldn't load the verse", systemImage: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
