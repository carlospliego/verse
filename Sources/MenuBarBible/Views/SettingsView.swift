import SwiftUI
import ServiceManagement
import MenuBarBibleCore

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            VStack(alignment: .leading, spacing: 16) {
                translationPicker

                if tickerToggleIsVisible {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Show verse in the menu bar", isOn: $state.tickerEnabled)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .font(.system(size: 12))

                        if state.tickerEnabled {
                            VStack(alignment: .leading, spacing: 4) {
                                Picker("Speed", selection: $state.tickerSpeed) {
                                    ForEach(TickerSpeed.allCases, id: \.self) { speed in
                                        Text(speed.displayName).tag(speed)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .controlSize(.small)
                                .font(.system(size: 11))
                                .labelsHidden()

                                Text("Scroll speed.")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .font(.system(size: 12))
                        .onChange(of: launchAtLogin) { _, newValue in
                            setLaunchAtLogin(newValue)
                        }
                    if let launchAtLoginError {
                        Text(launchAtLoginError)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)

            Divider()
            toolbar
        }
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }

    private var header: some View {
        Text("Settings")
            .font(.system(size: 12, weight: .semibold))
            .kerning(0.6)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var translationPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Changing this re-renders today's verse. It does not re-pick it.
            Picker("Translation", selection: $state.translationCode) {
                ForEach(state.availableTranslations) { translation in
                    Text("\(translation.code) — \(translation.name)").tag(translation.code)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .font(.system(size: 12))

            Text("All three are public domain.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 0) {
            Button {
                state.screen = .verse
            } label: {
                Label("Back", systemImage: "chevron.left").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    /// Registration fails while the app runs from a build directory. Report that rather
    /// than leaving the toggle showing a state the system did not accept.
    private func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = LaunchAtLogin.set(enabled)
        if launchAtLoginError != nil {
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}
