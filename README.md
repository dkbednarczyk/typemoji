# typemoji

A macOS menu bar app that expands Discord-style emoji codes (`:sob:`, `:fire:`) in any app, with Tab
completion that learns which emoji you use most. See [REQUIREMENTS.md](REQUIREMENTS.md) for the behaviour.

## Building

Needs Xcode's Swift toolchain (Swift 6).

```sh
make test     # unit tests for the engine
make run      # build, bundle, sign and launch build/typemoji.app
make stop     # quit the running app
```

On first launch macOS asks for the Accessibility permission. The icon stays dimmed until it is granted.

The app is signed ad-hoc by default, so macOS may ask for the permission again after a rebuild. To keep
the grant, sign with a real identity:

```sh
CODESIGN_IDENTITY="Apple Development: you@example.com" make run
```

## Layout

- `Sources/TypemojiCore` — the engine: arming, matching, ranking, undo. No AppKit, fully unit tested.
- `Sources/typemoji` — the app: event tap, menu bar, hot key, storage.
- `Resources/emoji.json` — generated emoji names, skin tones and popularity ranks. Committed.
- `tools/` — the generator for `emoji.json` (`make emoji`, needs [bun](https://bun.sh)). Names come from
  `discord-emoji` and emojibase's Slack, GitHub, JoyPixels and CLDR shortcode sets; the popularity
  baseline is `tools/baseline.txt`.
- `scripts/bundle.sh` — wraps the SwiftPM binary into a signed `.app`.

Settings and scores are stored as JSON in `~/Library/Application Support/typemoji/`.
