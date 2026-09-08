# CLAUDE.md

Guidance for Claude Code sessions working in this repo.

## What this is

Shosh — a native macOS push-to-talk dictation app (SwiftUI, macOS 26+). Forked from
per-simmons/murmur-youtube and rebranded, then substantially extended (arbitrary
push-to-talk key, toggle mode, cancel shortcut, microphone/mute settings, a third
transcription engine for Arabic, a native usage dashboard, a full visual redesign from a
Pencil design file, light/dark theme). See README.md for the feature list and architecture
overview.

## Build & run

```sh
swift build -c debug     # plain SwiftPM build, fastest for compile-error checking
make install              # build, bundle, sign, install to /Applications, launch
make run                  # same but installs to a staging dir instead of /Applications
```

Always `make install` (not just `swift build`) before telling the user to test something —
a raw SwiftPM binary has no bundle identity and can't hold Accessibility/Microphone
permissions.

## Code signing — the one gotcha that will burn you

TCC (Accessibility, Microphone) keys its grant to the app's exact code signature. The
Makefile prefers a real "Developer ID Application" identity, then a self-signed
**"Shosh Local Dev"** certificate (set up once per machine in the login keychain — not
committed, nothing to check in), then falls back to ad-hoc (`-`).

If `security find-identity -v -p codesigning` shows no usable identity, every rebuild gets a
new ad-hoc signature and the user's Accessibility grant silently breaks — the hotkey stops
firing with `tapCreate failed — Accessibility permission missing?` in the log
(`log show --predicate 'subsystem == "ai.pivotstudio.shosh"' --style compact --last 5m`).
Fix: set up the local cert once (self-signed, `codeSigning` extended key usage, imported and
trusted via `security add-trusted-cert -p codeSign`), which the Makefile then picks up
automatically. After any resign, if this is a fresh machine or the cert doesn't exist yet,
tell the user to re-grant Accessibility — don't assume it silently still works.

## Design system

Every color/type/spacing/radius/shadow value lives in `Sources/Shosh/UI/DesignSystem.swift`
(`DS.Color`, `DS.Font`, `DS.Space`, `DS.Radius`, `DS.Border`, `DS.Motion`). Views never
declare ad-hoc colors or hardcoded pixel values — extend `DS` instead. Colors are
appearance-aware (`face(light:dark:)`, an `NSColor` dynamic provider), and
`Settings.appearance` drives `.preferredColorScheme` at each window root, so the same tokens
serve system-follow, forced-light, and forced-dark without per-view branching.

The current visual language comes from a Pencil (pen.dev) design file the user shared
(`shosh_app.pen`, local at `~/Documents/pencile designs/`) — sidebar nav, flat white/gray
cards, blue accent (`#3B82F6` light / `#60A5FA` dark). If asked to adjust the design, prefer
reading that file's variables/screens (via the `mcp__pencil__*` tools) over guessing at
values — it's the source of truth, including the dark-theme hex pairs.

## Engines

Three `TranscriptionEngine` implementations (`Sources/Shosh/Transcription/`):
`AppleSpeechEngine` (streaming, on-device, no download), `ParakeetEngine` (batch, NVIDIA
Parakeet via FluidAudio), `CohereEngine` (batch, also FluidAudio — the only one covering
Arabic + 13 other languages). Before assuming an engine supports a language, check
`SpeechTranscriber.supportedLocales` / FluidAudio's own docs rather than guessing — Apple's
list is narrower than it looks (no Arabic, heavy on Indian/East Asian languages) and
Parakeet v3's "multilingual" is 25 European languages + Japanese only.

## Dictionary

The correction/bias logic (`DictionaryCorrector`) lives in a separate `ShoshDictionary`
SwiftPM target, not in the main `Shosh` target — it's unit tested independently and shares
`shared/dictionary-test-vectors.json`-style test vectors with the (not-present-in-this-repo)
Windows port's C# reimplementation. Keep new correction logic there, not inline in the app
target.

## Conventions carried over from the original project

- No comments explaining *what* code does — only *why*, for non-obvious constraints
  (see existing doc comments for the tone/density to match).
- Settings persist via `UserDefaults` directly on the `Settings` class (`@Observable`,
  `didSet` writes) — no separate persistence layer.
- Every new setting needs: a property with `didSet`, a `Keys` entry, and an init-time read
  with a sensible default — `Settings.swift` is the single place all three live.
