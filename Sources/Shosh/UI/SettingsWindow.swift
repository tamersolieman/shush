import Carbon.HIToolbox
import SwiftUI

/// Settings — hotkey and model, per the brief. Opens on ⌘, via the standard `Settings` scene,
/// so the system wires up the menu item and the shortcut.
struct SettingsWindow: View {
    @Bindable var controller: DictationController
    @State private var settings = Settings.shared

    var body: some View {
        ZStack {
            DS.Color.chassis.ignoresSafeArea()

            VStack(alignment: .leading, spacing: DS.Space.wide) {
                DictationCard(controller: controller, settings: settings)

                panel(label: "Model") {
                    HStack(spacing: DS.Space.snug) {
                        ForEach(SpeechEngineChoice.allCases, id: \.self) { choice in
                            TransportKey(
                                title: choice == .apple ? "Apple" : "Parakeet",
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
                    note(settings.engine == .apple
                        ? "Apple's on-device transcriber. Streams text while you speak; no download."
                        : "Parakeet on the Neural Engine. Resolves on release; ~470 MB model.")
                }

                panel(label: "Cleanup") {
                    Toggle(isOn: $settings.cleanupEnabled) {
                        Silkscreen(text: "Clean up transcripts")
                    }
                    .toggleStyle(.switch)
                    note("Strips fillers, fixes spacing and punctuation. The dictionary's "
                        + "corrections run either way.")
                }

                Spacer()
            }
            .padding(DS.Space.panel)
        }
        .frame(width: 520, height: 460)
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
