import Carbon.HIToolbox
import FluidAudio
import Speech
import SwiftUI

/// Settings, embedded both as a sidebar page in the main window and — for the standard
/// ⌘, shortcut — its own window. Matches the Pencil design: section header, thin divider,
/// flat rows (label left, value/chevron or a toggle right), no card chrome.
struct SettingsPageView: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AppearanceSection(settings: settings)
                DictationSection(controller: controller, settings: settings)
                SpeechRecognitionSection(settings: settings)
                AudioSection(settings: settings)
                ModelSection(settings: settings)
                CleanupSection(settings: settings)
            }
            .padding(DS.Space.panel)
        }
    }
}

/// The standalone ⌘, window — a thin wrapper around `SettingsPageView` so both entry points
/// share one implementation.
struct SettingsWindow: View {
    @Bindable var controller: DictationController

    @State private var settings = Settings.shared

    var body: some View {
        SettingsPageView(controller: controller)
            .background(DS.Color.background)
            .frame(width: 640, height: 720)
            .preferredColorScheme(settings.appearance.colorScheme)
    }
}

// MARK: - Shared row scaffolding

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(DS.Font.sectionHeader)
            .foregroundStyle(DS.Color.textTertiary)
            .padding(.top, DS.Space.section)
            .padding(.bottom, DS.Space.snug)
        Rectangle().fill(DS.Color.divider).frame(height: DS.Border.hairline)
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    var value: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.roomy) {
            Text(title)
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.textPrimary)
            Spacer(minLength: DS.Space.roomy)
            control
        }
        .padding(.horizontal, DS.Space.base)
        .frame(height: 52)
    }
}

/// A settings row whose control is "value text + chevron" — the whole row opens a menu.
private struct MenuRow<MenuItems: View>: View {
    let title: String
    let value: String
    @ViewBuilder var menuItems: MenuItems

    var body: some View {
        SettingsRow(title: title) {
            Menu {
                menuItems
            } label: {
                HStack(spacing: DS.Space.tight) {
                    Text(value)
                        .font(DS.Font.value)
                        .foregroundStyle(DS.Color.textTertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

private struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(DS.Color.primary)
        }
    }
}

// MARK: - Appearance

private struct AppearanceSection: View {
    @Bindable var settings: Settings

    var body: some View {
        SectionHeader(title: "Appearance")

        SettingsRow(title: "Theme") {
            Menu {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Button(mode.displayName) { settings.appearance = mode }
                }
            } label: {
                HStack(spacing: DS.Space.tight) {
                    Text(settings.appearance.displayName)
                        .font(DS.Font.value)
                        .foregroundStyle(DS.Color.textTertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }
}

// MARK: - Dictation

private struct DictationSection: View {
    @Bindable var controller: DictationController
    @Bindable var settings: Settings

    @State private var recorder = KeyRecorder()
    @State private var isRecording = false

    var body: some View {
        SectionHeader(title: "Dictation")

        SettingsRow(title: "Transcribe Shortcut") {
            HStack(spacing: DS.Space.snug) {
                Button {
                    beginRecording()
                } label: {
                    Text(isRecording ? "Press any key…" : settings.pushToTalkKey.displayName)
                        .font(DS.Font.value)
                        .foregroundStyle(isRecording ? DS.Color.primary : DS.Color.textTertiary)
                }
                .buttonStyle(.plain)
                if !isRecording, settings.pushToTalkKey != .default {
                    ResetButton {
                        settings.pushToTalkKey = .default
                        controller.reloadHotkey()
                    }
                }
            }
        }
        CardDivider()

        ToggleRow(title: "Push To Talk", isOn: $settings.pushToTalkEnabled)
        CardDivider()

        SettingsRow(title: "Cancel Shortcut") {
            Text("Escape")
                .font(DS.Font.value)
                .foregroundStyle(DS.Color.textTertiary)
        }
    }

    private func beginRecording() {
        isRecording = true
        recorder.start { captured in
            isRecording = false
            guard captured.keyCode != Int64(kVK_Escape) else { return }
            settings.pushToTalkKey = captured
            controller.reloadHotkey()
        }
    }
}

// MARK: - Speech recognition

private struct SpeechRecognitionSection: View {
    @Bindable var settings: Settings
    @State private var availableLocales: [Locale] = []

    private var cohereLanguages: [CohereAsrConfig.Language] {
        CohereAsrConfig.Language.allCases.sorted { $0.englishName < $1.englishName }
    }

    private var currentLabel: String {
        if settings.engine == .cohere {
            let code = String(settings.speechLanguage.prefix(2)).lowercased()
            return (CohereAsrConfig.Language(rawValue: code) ?? .english).englishName
        }
        return settings.speechLanguage == "auto" ? "Auto Detect" : displayName(for: settings.speechLanguage)
    }

    var body: some View {
        SectionHeader(title: "Speech Recognition")

        SettingsRow(title: "Language") {
            HStack(spacing: DS.Space.snug) {
                if settings.engine == .cohere {
                    MenuRow(title: "", value: currentLabel) {
                        ForEach(cohereLanguages, id: \.rawValue) { language in
                            Button(language.englishName) { settings.speechLanguage = language.rawValue }
                        }
                    }
                } else if settings.engine == .parakeet {
                    Text("Not supported").font(DS.Font.value).foregroundStyle(DS.Color.textTertiary)
                } else {
                    Menu {
                        Button("Auto Detect") { settings.speechLanguage = "auto" }
                        if !availableLocales.isEmpty { Divider() }
                        ForEach(availableLocales, id: \.identifier) { locale in
                            Button(displayName(for: locale.identifier)) {
                                settings.speechLanguage = locale.identifier
                            }
                        }
                    } label: {
                        HStack(spacing: DS.Space.tight) {
                            Text(currentLabel).font(DS.Font.value).foregroundStyle(DS.Color.textTertiary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(DS.Color.textSecondary)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                if settings.speechLanguage != "auto", settings.engine != .parakeet {
                    ResetButton { settings.speechLanguage = "auto" }
                }
            }
        }
        CardDivider()

        ToggleRow(title: "Translate to English", isOn: $settings.translateToEnglish)
            .disabled(settings.speechLanguage == "auto")
            .opacity(settings.speechLanguage == "auto" ? 0.5 : 1)
        .task {
            let locales = await SpeechTranscriber.supportedLocales
            availableLocales = locales.sorted { displayName(for: $0.identifier) < displayName(for: $1.identifier) }
        }
    }

    private func displayName(for identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier)?.capitalized ?? identifier
    }
}

// MARK: - Audio

private struct AudioSection: View {
    @Bindable var settings: Settings
    @State private var availableMicrophones: [MicrophoneDevice] = []

    private var currentMicName: String {
        guard let id = settings.microphoneDeviceID,
              let device = availableMicrophones.first(where: { $0.id == id })
        else { return "Default" }
        return device.name
    }

    var body: some View {
        SectionHeader(title: "Audio")

        SettingsRow(title: "Microphone") {
            HStack(spacing: DS.Space.snug) {
                Menu {
                    Button("Default") { settings.microphoneDeviceID = nil }
                    if !availableMicrophones.isEmpty { Divider() }
                    ForEach(availableMicrophones) { device in
                        Button(device.name) { settings.microphoneDeviceID = device.id }
                    }
                } label: {
                    HStack(spacing: DS.Space.tight) {
                        Text(currentMicName).font(DS.Font.value).foregroundStyle(DS.Color.textTertiary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                if settings.microphoneDeviceID != nil {
                    ResetButton { settings.microphoneDeviceID = nil }
                }
            }
        }
        CardDivider()

        ToggleRow(title: "Mute While Recording", isOn: $settings.muteWhileRecording)
        CardDivider()

        ToggleRow(title: "Audio Feedback", isOn: $settings.soundEnabled)
            .task { availableMicrophones = MicrophoneDevices.available() }
    }
}

// MARK: - Model

private struct ModelSection: View {
    @Bindable var settings: Settings

    var body: some View {
        SectionHeader(title: "Model")

        SettingsRow(title: "Speech Engine") {
            Menu {
                ForEach(SpeechEngineChoice.allCases, id: \.self) { choice in
                    Button(choice.displayName) { settings.engine = choice }
                }
            } label: {
                HStack(spacing: DS.Space.tight) {
                    Text(settings.engine.displayName).font(DS.Font.value).foregroundStyle(DS.Color.textTertiary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        CardDivider()

        HStack {
            Text(modelNote(settings.engine))
                .font(DS.Font.meta)
                .foregroundStyle(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.base)
        .padding(.vertical, DS.Space.base)
    }

    private func modelNote(_ choice: SpeechEngineChoice) -> String {
        switch choice {
        case .apple: "Apple's on-device transcriber. Streams text while you speak; no download."
        case .parakeet: "Parakeet on the Neural Engine. Resolves on release; ~470 MB model."
        case .cohere: "Cohere Transcribe. Covers Arabic and 13 other languages Apple and Parakeet don't. Resolves on release."
        }
    }
}

// MARK: - Cleanup

private struct CleanupSection: View {
    @Bindable var settings: Settings

    var body: some View {
        SectionHeader(title: "Cleanup")

        ToggleRow(title: "Clean Up Transcripts", isOn: $settings.cleanupEnabled)

        HStack {
            Text("Strips fillers, fixes spacing and punctuation. The dictionary's corrections run either way.")
                .font(DS.Font.meta)
                .foregroundStyle(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.base)
        .padding(.vertical, DS.Space.base)
    }
}

// MARK: - Small shared pieces

private struct CardDivider: View {
    var body: some View {
        Rectangle().fill(DS.Color.divider).frame(height: DS.Border.hairline)
    }
}

private struct ResetButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.Color.textSecondary)
        }
        .buttonStyle(.plain)
        .help("Reset to default")
    }
}
