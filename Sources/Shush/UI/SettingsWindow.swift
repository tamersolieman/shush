import AppKit
import Carbon.HIToolbox
import FluidAudio
import ShushDictionary
import Speech
import SwiftUI

/// One settings section, as a destination in the main window's sidebar. Order here is the
/// order sub-items appear under the sidebar's "Settings" group.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general, account, appearance, dictation, model, speechRecognition, transcription, audio, cleanup, history, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .account: "Account"
        case .appearance: "Appearance"
        case .dictation: "Dictation"
        case .model: "Model"
        case .speechRecognition: "Speech Recognition"
        case .transcription: "Transcription"
        case .audio: "Audio"
        case .cleanup: "Cleanup"
        case .history: "History"
        case .about: "About"
        }
    }

    var icon: String {
        switch self {
        case .general: "switch.2"
        case .account: "person.crop.circle"
        case .appearance: "paintbrush"
        case .dictation: "keyboard"
        case .model: "cpu"
        case .speechRecognition: "waveform"
        case .transcription: "text.bubble"
        case .audio: "speaker.wave.2"
        case .cleanup: "sparkles"
        case .history: "clock.arrow.circlepath"
        case .about: "info.circle"
        }
    }
}

/// One section's settings, shown as a single always-open card — the main window's sidebar
/// already picked this section, so there's nothing left to collapse.
struct SettingsSectionPage: View {
    @Bindable var controller: DictationController
    let section: SettingsSection
    @State private var settings = Settings.shared

    var body: some View {
        ScrollView {
            SettingsCard(title: section.title) {
                switch section {
                case .general: GeneralSection(settings: settings)
                case .account: AccountSection(settings: settings)
                case .appearance: AppearanceSection(settings: settings)
                case .dictation: DictationSection(controller: controller, settings: settings)
                case .model: ModelSection(settings: settings)
                case .speechRecognition: SpeechRecognitionSection(settings: settings)
                case .transcription: TranscriptionSection(settings: settings)
                case .audio: AudioSection(settings: settings)
                case .cleanup: CleanupSection(settings: settings)
                case .history: HistorySection(settings: settings)
                case .about: AboutSection(settings: settings)
                }
            }
            .padding(DS.Space.panel)
        }
    }
}

/// Settings, embedded both as a sidebar page in the main window and — for the standard
/// ⌘, shortcut — its own window. Each section is its own collapsible card (background,
/// border, tappable header) rather than a flat run of rows, so a screen with this many
/// sections stays scannable instead of blurring into one long list.
struct SettingsPageView: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.base) {
                CollapsibleSection(title: "General", id: "general") {
                    GeneralSection(settings: settings)
                }
                CollapsibleSection(title: "Account", id: "account") {
                    AccountSection(settings: settings)
                }
                CollapsibleSection(title: "Appearance", id: "appearance") {
                    AppearanceSection(settings: settings)
                }
                CollapsibleSection(title: "Dictation", id: "dictation") {
                    DictationSection(controller: controller, settings: settings)
                }
                CollapsibleSection(title: "Model", id: "model") {
                    ModelSection(settings: settings)
                }
                CollapsibleSection(title: "Speech Recognition", id: "speechRecognition") {
                    SpeechRecognitionSection(settings: settings)
                }
                CollapsibleSection(title: "Transcription", id: "transcription") {
                    TranscriptionSection(settings: settings)
                }
                CollapsibleSection(title: "Audio", id: "audio") {
                    AudioSection(settings: settings)
                }
                CollapsibleSection(title: "Cleanup", id: "cleanup") {
                    CleanupSection(settings: settings)
                }
                CollapsibleSection(title: "History", id: "history") {
                    HistorySection(settings: settings)
                }
                CollapsibleSection(title: "About", id: "about") {
                    AboutSection(settings: settings)
                }
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

/// A collapsible, highlighted card for one settings section — background, border, and a
/// tappable header (title + chevron) that toggles the body. Expansion state persists per
/// section across launches (`@AppStorage`), defaulting to expanded so nothing looks hidden the
/// first time someone opens Settings.
private struct CollapsibleSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @AppStorage private var isExpanded: Bool

    init(title: String, id: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
        self._isExpanded = AppStorage(wrappedValue: true, "settingsSectionExpanded.\(id)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(DS.Motion.fast) { isExpanded.toggle() }
            } label: {
                HStack(spacing: DS.Space.snug) {
                    Text(title.uppercased())
                        .font(DS.Font.sectionHeader)
                        .foregroundStyle(DS.Color.textPrimary)
                    Spacer(minLength: DS.Space.roomy)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Color.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.horizontal, DS.Space.base)
                .frame(height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                CardDivider()
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
            }
        }
        .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card)
                .strokeBorder(DS.Color.border, lineWidth: DS.Border.hairline)
        )
    }
}

/// Same card chrome as `CollapsibleSection` but always open and without the tappable
/// header — used where navigation (the sidebar) already identifies the section, so
/// collapsing it would just hide the thing you came here to see.
private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(DS.Font.sectionHeader)
                .foregroundStyle(DS.Color.textPrimary)
                .padding(.horizontal, DS.Space.base)
                .frame(height: 44, alignment: .leading)
            CardDivider()
            VStack(alignment: .leading, spacing: 0) {
                content
            }
        }
        .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card)
                .strokeBorder(DS.Color.border, lineWidth: DS.Border.hairline)
        )
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

// MARK: - General

private struct GeneralSection: View {
    @Bindable var settings: Settings

    var body: some View {
        ToggleRow(title: "Launch at Login", isOn: $settings.launchAtLogin)
    }
}

// MARK: - Appearance

private struct AppearanceSection: View {
    @Bindable var settings: Settings

    var body: some View {
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

// MARK: - Transcription

private struct TranscriptionSection: View {
    @Bindable var settings: Settings
    @State private var store = DictionaryStore.shared
    @State private var newWord = ""

    var body: some View {
        ToggleRow(title: "Voice Activity Detection", isOn: $settings.vadEnabled)
        RowSubtitle(
            "Filter silence from recordings. Streaming-capable models use a longer VAD "
                + "tail; disabling VAD records raw audio."
        )
        CardDivider()

        ToggleRow(title: "Remove Filler Words", isOn: $settings.removeFillerWords)
        RowSubtitle("Removes common hesitation words from transcriptions. Turn off to keep them.")
        CardDivider()

        ToggleRow(title: "Learn From Corrections", isOn: $settings.learnFromCorrectionsEnabled)
        RowSubtitle(
            "After Shush types something, watch briefly for you fixing a word by hand and "
                + "offer to save it as a dictionary correction. Off by default — this reads "
                + "text from whatever app you're typing in right after dictation."
        )
        CardDivider()

        VStack(alignment: .leading, spacing: DS.Space.tight) {
            Text("Custom Words")
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.textPrimary)
            Text(
                "Help supported models recognize names and specialized terms. Fuzzy "
                    + "correction is currently limited to words using A–Z and numbers."
            )
            .font(DS.Font.meta)
            .foregroundStyle(DS.Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DS.Space.base)
        .padding(.top, DS.Space.base)

        HStack(spacing: DS.Space.snug) {
            TextField("Add a word", text: $newWord)
                .textFieldStyle(.plain)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textPrimary)
                .padding(.horizontal, DS.Space.base)
                .frame(height: 32)
                .background(DS.Color.surface, in: .rect(cornerRadius: DS.Radius.control))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.control)
                        .strokeBorder(DS.Color.border, lineWidth: DS.Border.hairline)
                )
                .onSubmit(addWord)

            Button("Add", action: addWord)
                .buttonStyle(.plain)
                .padding(.horizontal, DS.Space.roomy)
                .frame(height: 32)
                .background(DS.Color.surfaceSecondary, in: .rect(cornerRadius: DS.Radius.control))
                .foregroundStyle(DS.Color.textPrimary)
                .disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, DS.Space.base)
        .padding(.vertical, DS.Space.base)
    }

    private func addWord() {
        let word = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        store.add(.term(word))
        newWord = ""
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

// MARK: - History

private struct HistorySection: View {
    @Bindable var settings: Settings

    var body: some View {
        SettingsRow(title: "History Limit") {
            HStack(spacing: DS.Space.snug) {
                Stepper(value: $settings.historyLimit, in: 1...1000) {
                    Text("\(settings.historyLimit)")
                        .font(DS.Font.value)
                        .foregroundStyle(DS.Color.textPrimary)
                        .frame(width: 32, alignment: .trailing)
                }
                Text("entries")
                    .font(DS.Font.value)
                    .foregroundStyle(DS.Color.textTertiary)
            }
        }
        CardDivider()

        HStack {
            Text("Maximum number of history entries to keep")
                .font(DS.Font.meta)
                .foregroundStyle(DS.Color.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.base)
        .padding(.bottom, DS.Space.snug)
        CardDivider()

        SettingsRow(title: "Auto-Delete Recordings") {
            Menu {
                ForEach(AutoDeleteInterval.allCases, id: \.self) { interval in
                    Button(interval.displayName) { settings.autoDeleteInterval = interval }
                }
            } label: {
                HStack(spacing: DS.Space.tight) {
                    Text(settings.autoDeleteInterval.displayName)
                        .font(DS.Font.value)
                        .foregroundStyle(DS.Color.textTertiary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }

        HStack {
            Text("Automatically delete old recordings to save space")
                .font(DS.Font.meta)
                .foregroundStyle(DS.Color.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.base)
        .padding(.vertical, DS.Space.base)
    }
}

// MARK: - Account

private struct AccountSection: View {
    @Bindable var settings: Settings
    @State private var auth = GoogleAuthService.shared
    @State private var isConnecting = false

    var body: some View {
        if let email = settings.googleAccountEmail {
            SettingsRow(title: "Signed In") {
                Text(email)
                    .font(DS.Font.value)
                    .foregroundStyle(DS.Color.textTertiary)
            }
            CardDivider()

            ToggleRow(title: "Sync Settings, Dictionary & Stats", isOn: $settings.syncEnabled)
            RowSubtitle("Synced via a private, app-only folder in your Google Drive.")
            CardDivider()

            SettingsRow(title: "Last Synced") {
                Button("Sync Now") { Task { await SyncEngine.shared.syncNow() } }
                    .buttonStyle(.plain)
                    .font(DS.Font.button)
                    .foregroundStyle(DS.Color.primary)
            }
            RowSubtitle(lastSyncSubtitle, isError: settings.lastSyncError != nil)
            CardDivider()

            SettingsRow(title: "Disconnect") {
                Button("Disconnect") { Task { await auth.disconnect() } }
                    .buttonStyle(.plain)
                    .font(DS.Font.button)
                    .foregroundStyle(DS.Color.danger)
            }
        } else {
            SettingsRow(title: "Google Account") {
                Button(isConnecting ? "Connecting…" : "Connect") {
                    Task {
                        isConnecting = true
                        defer { isConnecting = false }
                        try? await auth.signIn()
                    }
                }
                .buttonStyle(.plain)
                .font(DS.Font.button)
                .foregroundStyle(DS.Color.primary)
                .disabled(isConnecting)
            }
            RowSubtitle("Sync Settings, Dictionary and lifetime stats across your Macs via a private, app-only Drive folder.")
        }
    }

    private var lastSyncSubtitle: String {
        if let error = settings.lastSyncError {
            return "Sync failed: \(error)"
        }
        if let date = settings.lastSyncDate {
            return "Synced \(date.formatted(.relative(presentation: .named)))"
        }
        return "Not synced yet"
    }
}

// MARK: - About

private struct AboutSection: View {
    @Bindable var settings: Settings

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    var body: some View {
        // No localization exists yet — English is the only option, kept here as the slot
        // this setting will live in once Shush ships more than one language.
        SettingsRow(title: "Application Language") {
            Text("English")
                .font(DS.Font.value)
                .foregroundStyle(DS.Color.textTertiary)
        }
        RowSubtitle("Change the language of the Shush interface")
        CardDivider()

        SettingsRow(title: "Version") {
            Text("v\(appVersion)")
                .font(DS.Font.value)
                .foregroundStyle(DS.Color.textTertiary)
        }
        RowSubtitle("Current version of Shush")
        CardDivider()

        ToggleRow(title: "Show What's New", isOn: $settings.showWhatsNew)
        RowSubtitle("Show release notes after Shush updates")
        CardDivider()

        SettingsRow(title: "Website") {
            Button {
                NSWorkspace.shared.open(URL(string: "https://www.tamersolieman.com")!)
            } label: {
                Text("Visit Website")
                    .font(DS.Font.button)
                    .foregroundStyle(DS.Color.textPrimary)
                    .padding(.horizontal, DS.Space.roomy)
                    .frame(height: 32)
                    .background(DS.Color.surfaceSecondary, in: .rect(cornerRadius: DS.Radius.pill))
            }
            .buttonStyle(.plain)
        }
        RowSubtitle("Visit the Shush website")
        CardDivider()

        DirectoryRow(
            title: "App Data Directory",
            subtitle: "Location where Shush stores its data",
            path: RunLog.directory.path
        ) {
            NSWorkspace.shared.activateFileViewerSelecting([RunLog.directory])
        }
        CardDivider()

        // Shush logs through the unified logging system rather than plain files, so there's
        // no directory to open — Console is the equivalent "Open" destination, prefiltered
        // to Shush's own subsystem.
        DirectoryRow(
            title: "Log Directory",
            subtitle: "Shush logs to Console, not a file — no on-disk log directory",
            path: "log stream --predicate 'subsystem == \"ai.pivotstudio.shush\"'"
        ) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Console.app"))
        }
    }
}

private struct RowSubtitle: View {
    let text: String
    let isError: Bool
    init(_ text: String, isError: Bool = false) {
        self.text = text
        self.isError = isError
    }

    var body: some View {
        HStack {
            Text(text)
                .font(DS.Font.meta)
                .foregroundStyle(isError ? DS.Color.danger : DS.Color.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.base)
        .padding(.bottom, DS.Space.base)
    }
}

private struct DirectoryRow: View {
    let title: String
    let subtitle: String
    let path: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.tight) {
            Text(title)
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.textPrimary)
            Text(subtitle)
                .font(DS.Font.meta)
                .foregroundStyle(DS.Color.textTertiary)
        }
        .padding(.horizontal, DS.Space.base)
        .padding(.top, DS.Space.base)

        HStack(spacing: DS.Space.snug) {
            Text(path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DS.Color.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.base)
                .frame(height: 36)
                .background(DS.Color.surfaceSecondary, in: .rect(cornerRadius: DS.Radius.control))

            Button(action: action) {
                Text("Open")
                    .font(DS.Font.button)
                    .foregroundStyle(DS.Color.textPrimary)
                    .padding(.horizontal, DS.Space.roomy)
                    .frame(height: 32)
                    .background(DS.Color.surfaceSecondary, in: .rect(cornerRadius: DS.Radius.pill))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Space.base)
        .padding(.bottom, DS.Space.base)
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
