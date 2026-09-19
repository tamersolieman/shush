# Shush

Shush is a native macOS dictation app built around one idea: talking should be as fast as typing, anywhere on your Mac. Hold a key, speak, let go — your words appear right where your cursor already is. No copy-paste, no dedicated window to switch into, no cloud round-trip. It runs quietly in the menu bar, and everything happens on your own machine.

## The experience

Press and hold your chosen key (or tap it once, if you'd rather toggle recording on and off) from inside any app — Mail, Slack, a code editor, a terminal, a browser form. A small heads-up display appears to show you're being heard. Let go, and a moment later your words are typed exactly where you were working. That's the whole interaction. No app to bring to the front, no menu to click through first.

Shush stays out of the way between dictations. Closing its window doesn't close the app — it keeps living in the menu bar, ready for the next hold of the key, and can launch automatically the moment you log in so it's always there without a second thought.

## Features

### Dictation, your way

- **Push-to-talk or toggle mode** — hold to record and release to stop, or press once to start and again to finish, whichever fits how you work.
- **Any key you like as the shortcut** — there's no fixed list to pick from. Press the key or combination you want, and Shush learns it on the spot.
- **A cancel shortcut** (Escape) for when you change your mind mid-sentence — nothing gets typed.
- Fine control over the microphone: choose the input device, mute your speakers while recording so Shush doesn't pick up whatever's playing, and toggle an audio cue for start/stop.

### Speech recognition that fits the moment

Three engines, switchable any time in Settings, so you can trade speed for language coverage as needed:

- **Apple's on-device engine** — starts instantly, shows your words as you speak, no download required.
- **Parakeet** — a higher-accuracy engine for English, resolving your full sentence the moment you release the key.
- **Cohere Transcribe** — the one to reach for beyond English: covers Arabic along with French, German, Spanish, Italian, Portuguese, Dutch, Polish, Greek, Japanese, Chinese, Vietnamese, and Korean.

Voice activity detection trims silence automatically, and filler words like "um" and "uh" can be stripped out before the text ever reaches you.

### Cleanup, translation, and a dictionary that learns

- **Automatic cleanup** tidies punctuation and spacing so dictated text reads like it was typed with care.
- **On-device translation** turns a dictation in another language into English text before it lands, when you tell Shush what language you're speaking.
- **A personal dictionary** for the words Shush keeps getting wrong — names, jargon, whatever's specific to you — plus simple "when you hear X, write Y" corrections. It biases the engine toward your vocabulary before transcription and double-checks with a find-and-replace pass afterward, so it sticks even when the model second-guesses itself.
- **Learn from your own corrections** (opt-in) — fix a word right after Shush types it, and it can offer to remember that fix for next time, so the same mistake doesn't happen twice.

### A dashboard for your own dictation habits

- See your words-per-minute trend, how many dictionary fixes you've needed, and how much you've dictated in total, all pulled from your own history.
- A breakdown of which apps you dictate into most, and a streak calendar that shows how consistently you've been using it.
- Decide how long individual transcripts stick around; your lifetime stats keep counting regardless.

### Sync across your Macs

Sign in with Google and Shush keeps your settings, your personal dictionary, and your lifetime stats in step across every Mac you use it on, stored privately in your own Google Drive — nothing shared, nothing third-party. Settings and dictionary changes carry over cleanly between machines, and your usage stats add up rather than overwrite, so switching computers never costs you your history.

### Built to stay out of your way

- A collapsible sidebar takes you between Dashboard, Transcripts, Dictionary, and Settings — and Settings itself is organized into focused sub-pages (General, Account, Appearance, Dictation, Model, Speech Recognition, Transcription, Audio, Cleanup, History, About) rather than one long page to scroll through.
- Lives in the menu bar with a simple menu — open the app, jump to Settings, or quit — and can launch automatically at login.
- A clean light/dark theme that you can set independently of your system appearance.
- A considered visual design, redesigned end-to-end for a consistent look in both themes.

## Getting started

Shush needs **Accessibility** and **Microphone** permission to type into other apps and hear you (System Settings → Privacy & Security) — it'll prompt for both the first time it needs them.

- macOS 26 or later
- Apple Silicon (for the Parakeet and Cohere Transcribe engines)

```sh
make install   # build, sign, and install to /Applications
make run       # same, but to a staging folder instead — handy for testing a build
```

## Download

[![Download for macOS](docs/download-macos.svg)](https://github.com/tamersolieman/shush/raw/main/versions/Shush.dmg)

`make release` publishes the latest signed DMG to `versions/Shush.dmg` — same file on every
release, so this link never needs updating. This repo is private, so the link only resolves
while signed in to a GitHub account with access; there's no public-facing release page.

Universal binary. macOS 26 or later. To build and install a copy from source instead, see
[Getting started](#getting-started) above.
