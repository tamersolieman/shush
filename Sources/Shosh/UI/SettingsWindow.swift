import Carbon.HIToolbox
import FluidAudio
import Speech
import SwiftUI

/// Settings — hotkey and model, per the brief. Opens on ⌘, via the standard `Settings` scene,
/// so the system wires up the menu item and the shortcut.
struct SettingsWindow: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared

    var body: some View {
        ZStack {
            DS.Color.chassis.ignoresSafeArea()

            ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.wide) {
                DictationCard(controller: controller, settings: settings)
                SpeechRecognitionCard(settings: settings)
                AudioSettingsCard(settings: settings)

                panel(label: "Model") {
                    HStack(spacing: DS.Space.snug) {
                        ForEach(SpeechEngineChoice.allCases, id: \.self) { choice in
                            TransportKey(
                                title: modelKeyTitle(choice),
                                isEngaged: settings.engine == choice,
                                engagedColor: DS.Color.ink
                            ) {
                                settings.engine = choice
                            }
                            .background {
                                if settings.engine == choice {
                                    RoundedRectangle(cornerRadius: DS.Radius.control)
                                        .fill(DS.Color.selection)
                                }
                            }
                        }
                    }
                    note(modelNote(settings.engine))
                }

                panel(label: "Cleanup") {
                    Toggle(isOn: $settings.cleanupEnabled) {
                        Silkscreen(text: "Clean up transcripts")
                    }
                    .toggleStyle(.switch)
                    note("Strips fillers, fixes spacing and punctuation. The dictionary's "
                        + "corrections run either way.")
                }

            }
            .padding(DS.Space.panel)
            }
        }
        .frame(width: 520, height: 640)
    }

    private func panel<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.base) {
            Silkscreen(text: label, large: true)
            content()
        }
        .padding(DS.Space.roomy)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BrushedPanel())
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(DS.Font.label)
            .foregroundStyle(DS.Color.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func modelKeyTitle(_ choice: SpeechEngineChoice) -> String {
        switch choice {
        case .apple: "Apple"
        case .parakeet: "Parakeet"
        case .cohere: "Cohere"
        }
    }

    private func modelNote(_ choice: SpeechEngineChoice) -> String {
        switch choice {
        case .apple: "Apple's on-device transcriber. Streams text while you speak; no download."
        case .parakeet: "Parakeet on the Neural Engine. Resolves on release; ~470 MB model."
        case .cohere: "Cohere Transcribe. Covers Arabic and 13 other languages Apple and Parakeet don't. Resolves on release."
        }
    }
}

// MARK: - Dictation card

/// A grouped settings card in the style of a shortcut-recorder panel: a section label, then
/// rows — title and subtitle on the left, a single control on the right — divided by
/// hairlines. Same panel/ink tokens as the rest of Settings, so it follows the app's own
/// light/dark face rather than forcing one.
private struct DictationCard: View {
    @Bindable var controller: DictationController
    @Bindable var settings: Settings

    @State private var recorder = KeyRecorder()
    @State private var isRecording = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Silkscreen(text: "Dictation", large: true)
                .padding(.horizontal, DS.Space.roomy)
                .padding(.top, DS.Space.roomy)
                .padding(.bottom, DS.Space.base)

            DictationRow(
                title: "Transcribe Shortcut",
                subtitle: isRecording
                    ? "Press any key or modifier — Escape cancels without changing it."
                    : "The keyboard shortcut to record and transcribe your voice."
            ) {
                HStack(spacing: DS.Space.snug) {
                    ShortcutPill(
                        text: isRecording ? "Press any key…" : settings.pushToTalkKey.displayName,
                        isActive: isRecording
                    ) {
                        beginRecording()
                    }
                    if !isRecording, settings.pushToTalkKey != .default {
                        ResetButton {
                            settings.pushToTalkKey = .default
                            controller.reloadHotkey()
                        }
                    }
                }
            }

            divider

            DictationRow(
                title: "Push To Talk",
                subtitle: "Hold to record, release to stop"
            ) {
                Toggle("", isOn: $settings.pushToTalkEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            divider

            DictationRow(
                title: "Cancel Shortcut",
                subtitle: "The keyboard shortcut to cancel the current recording."
            ) {
                ShortcutPill(text: "Escape", isStatic: true) {}
            }
        }
        .background(BrushedPanel())
    }

    private var divider: some View {
        Rectangle()
            .fill(DS.Color.seam)
            .frame(height: DS.Border.hairline)
            .opacity(0.5)
            .padding(.leading, DS.Space.roomy)
    }

    private func beginRecording() {
        isRecording = true
        recorder.start { captured in
            isRecording = false
            // Escape is the universal "never mind" key — capturing it reassigns nothing,
            // it just backs out of recording.
            guard captured.keyCode != Int64(kVK_Escape) else { return }
            settings.pushToTalkKey = captured
            controller.reloadHotkey()
        }
    }
}

private struct DictationRow<Control: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.roomy) {
            VStack(alignment: .leading, spacing: DS.Space.hair) {
                Text(title)
                    .font(DS.Font.bodyEmphasis)
                    .foregroundStyle(DS.Color.ink)
                Text(subtitle)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DS.Space.roomy)
            control
        }
        .padding(.horizontal, DS.Space.roomy)
        .padding(.vertical, DS.Space.base)
    }
}

/// A shortcut-recorder-style pill: rounded, bordered, the key name centered. `isActive`
/// draws it with the selection edge color while it's listening for a key.
private struct ShortcutPill: View {
    let text: String
    var isActive = false
    var isStatic = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(DS.Font.bodyEmphasis)
                .foregroundStyle(isActive ? DS.Color.selectionEdge : DS.Color.ink)
                .padding(.horizontal, DS.Space.base)
                .padding(.vertical, DS.Space.tight)
                .frame(minWidth: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.control)
                        .strokeBorder(isActive ? DS.Color.selectionEdge : DS.Color.panelShade, lineWidth: DS.Border.hairline)
                )
        }
        .buttonStyle(.plain)
        .disabled(isStatic)
    }
}

private struct ResetButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.Color.inkSecondary)
        }
        .buttonStyle(.plain)
        .help("Reset to default")
    }
}

private struct CardDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.Color.seam)
            .frame(height: DS.Border.hairline)
            .opacity(0.5)
            .padding(.leading, DS.Space.roomy)
    }
}

/// A dropdown, styled like `ShortcutPill` — bordered, rounded, a chevron in place of an
/// active-recording state.
private struct PickerPill<MenuItems: View>: View {
    let text: String
    @ViewBuilder var menuItems: MenuItems

    var body: some View {
        Menu {
            menuItems
        } label: {
            HStack(spacing: DS.Space.tight) {
                Text(text)
                    .font(DS.Font.bodyEmphasis)
                    .foregroundStyle(DS.Color.ink)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DS.Color.inkSecondary)
            }
            .padding(.horizontal, DS.Space.base)
            .padding(.vertical, DS.Space.tight)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.control)
                    .strokeBorder(DS.Color.panelShade, lineWidth: DS.Border.hairline)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - Speech recognition card

private struct SpeechRecognitionCard: View {
    @Bindable var settings: Settings
    @State private var availableLocales: [Locale] = []

    /// Cohere has its own fixed 14-language set (Arabic among them) with its own codes —
    /// nothing to fetch, unlike Apple's list which depends on the OS build.
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

    private var languageSubtitle: String {
        switch settings.engine {
        case .apple: "Which language the recognizer listens for. Auto follows your Mac's language."
        case .parakeet: "Parakeet doesn't take a language setting — switch engines above to change this."
        case .cohere: "Which language Cohere Transcribe listens for — includes Arabic."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Silkscreen(text: "Speech Recognition", large: true)
                .padding(.horizontal, DS.Space.roomy)
                .padding(.top, DS.Space.roomy)
                .padding(.bottom, DS.Space.base)

            DictationRow(title: "Language", subtitle: languageSubtitle) {
                HStack(spacing: DS.Space.snug) {
                    if settings.engine == .cohere {
                        PickerPill(text: currentLabel) {
                            ForEach(cohereLanguages, id: \.rawValue) { language in
                                Button(language.englishName) { settings.speechLanguage = language.rawValue }
                            }
                        }
                    } else {
                        PickerPill(text: currentLabel) {
                            Button("Auto Detect") { settings.speechLanguage = "auto" }
                            if !availableLocales.isEmpty { Divider() }
                            ForEach(availableLocales, id: \.identifier) { locale in
                                Button(displayName(for: locale.identifier)) {
                                    settings.speechLanguage = locale.identifier
                                }
                            }
                        }
                        .disabled(settings.engine == .parakeet)
                    }
                    if settings.speechLanguage != "auto", settings.engine != .parakeet {
                        ResetButton { settings.speechLanguage = "auto" }
                    }
                }
            }

            CardDivider()

            DictationRow(
                title: "Translate to English",
                subtitle: settings.speechLanguage == "auto"
                    ? "Pick a specific language above first — translation needs to know the source."
                    : "Runs the transcript through on-device translation before it's typed."
            ) {
                Toggle("", isOn: $settings.translateToEnglish)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(settings.speechLanguage == "auto")
            }
        }
        .background(BrushedPanel())
        .task {
            let locales = await SpeechTranscriber.supportedLocales
            availableLocales = locales.sorted { displayName(for: $0.identifier) < displayName(for: $1.identifier) }
        }
    }

    private func displayName(for identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier)?.capitalized ?? identifier
    }
}

// MARK: - Audio card

private struct AudioSettingsCard: View {
    @Bindable var settings: Settings
    @State private var availableMicrophones: [MicrophoneDevice] = []

    private var currentMicName: String {
        guard let id = settings.microphoneDeviceID,
              let device = availableMicrophones.first(where: { $0.id == id })
        else { return "Default" }
        return device.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Silkscreen(text: "Audio", large: true)
                .padding(.horizontal, DS.Space.roomy)
                .padding(.top, DS.Space.roomy)
                .padding(.bottom, DS.Space.base)

            DictationRow(
                title: "Microphone",
                subtitle: "Select your preferred microphone device."
            ) {
                HStack(spacing: DS.Space.snug) {
                    PickerPill(text: currentMicName) {
                        Button("Default") { settings.microphoneDeviceID = nil }
                        if !availableMicrophones.isEmpty { Divider() }
                        ForEach(availableMicrophones) { device in
                            Button(device.name) { settings.microphoneDeviceID = device.id }
                        }
                    }
                    if settings.microphoneDeviceID != nil {
                        ResetButton { settings.microphoneDeviceID = nil }
                    }
                }
            }

            CardDivider()

            DictationRow(
                title: "Mute While Recording",
                subtitle: "Mute system audio during recording, so it isn't picked up."
            ) {
                Toggle("", isOn: $settings.muteWhileRecording)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            CardDivider()

            DictationRow(
                title: "Audio Feedback",
                subtitle: "Play a sound when recording starts and stops."
            ) {
                Toggle("", isOn: $settings.soundEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
        .background(BrushedPanel())
        .task {
            availableMicrophones = MicrophoneDevices.available()
        }
    }
}
