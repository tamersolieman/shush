# Shosh

A native macOS push-to-talk dictation app. Hold a key, talk, release — the text lands wherever your cursor is. Everything runs on-device.

Forked from [per-simmons/murmur-youtube](https://github.com/per-simmons/murmur-youtube) and rebranded/rebuilt from there.

## Features

- **Push-to-talk or toggle mode**, with any key or modifier as the shortcut (not a fixed list — press whatever you want to record with, and it's captured live).
- **Three speech engines**, switchable in Settings:
  - **Apple** — macOS 26's on-device `SpeechTranscriber`. Streams text live, no download.
  - **Parakeet** (NVIDIA, via [FluidAudio](https://github.com/FluidInference/FluidAudio)) — batch, resolves on release, ~470 MB model.
  - **Cohere Transcribe** (also via FluidAudio) — the only engine here that covers Arabic, plus French, German, Spanish, Italian, Portuguese, Dutch, Polish, Greek, Japanese, Chinese, Vietnamese, Korean.
- **On-device translation** — translate a non-English dictation to English before it's typed, when a specific source language is selected.
- **Dictionary** — teach it words and phrases it keeps getting wrong, plus "when you hear X, write Y" corrections. Runs both as a bias pass before transcription and a guaranteed find-and-replace pass after.
- **Dashboard** — words per minute, dictionary fixes, total words dictated, per-app usage breakdown, and a GitHub-style streak calendar, all computed from your own dictation history.
- **Engine comparison mode** — record with every engine at once and see the results side by side (nothing is injected in this mode).
- **Cancel shortcut** (Escape) — discards the current recording without typing anything.
- **Mute-while-recording**, **microphone selection**, and **audio feedback** toggles.
- **Light/dark theme**, independent of the system setting.

## Requirements

- macOS 26 (Apple's `SpeechTranscriber` requires it)
- Xcode 26 / Swift 6.2 toolchain
- Apple Silicon (Parakeet and Cohere Transcribe run on the Neural Engine)

## Building

```sh
make run       # build, sign, install to a staging dir, and launch
make install   # same, but install to /Applications
make build     # just build with SwiftPM
make clean     # remove build artifacts
```

The app needs **Accessibility** and **Microphone** permission (System Settings → Privacy & Security). macOS ties the Accessibility grant to the app's code signature — the Makefile signs with a stable local certificate (`Shosh Local Dev`, set up once per machine, not committed) rather than ad-hoc, so the grant survives rebuilds. Without that cert it falls back to ad-hoc signing, which means re-granting Accessibility after every `make install`.

## Architecture

- `Sources/Shosh/Core/` — hotkey capture (`HotkeyMonitor`, `KeyRecorder`), audio (`AudioCapture`, `MicrophoneDevices`, `SystemAudio`), the dictation state machine (`DictationController`), text injection.
- `Sources/Shosh/Transcription/` — the `TranscriptionEngine` protocol and its three implementations (`AppleSpeechEngine`, `ParakeetEngine`, `CohereEngine`).
- `Sources/Shosh/Dictionary/` — the dictionary store; the correction/bias logic itself lives in the separate `ShoshDictionary` target (`Sources/ShoshDictionary/`) so it can be unit tested and shares test vectors with the Windows port.
- `Sources/Shosh/Formatting/` — cleanup (rule-based and on-device LLM) and translation.
- `Sources/Shosh/UI/` — `MainWindow` (sidebar nav: Dashboard / Transcripts / Dictionary / Settings), `DesignSystem` (all color/type/spacing tokens), the floating HUD, the Settings page, the engine-comparison window.
- `Sources/Shosh/Support/` — `Settings` (all persisted preferences), logging, permissions, run history.
