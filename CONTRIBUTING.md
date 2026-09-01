# Contributing to Abendrot

Thanks for your interest. Abendrot is early and in active development, so issues, ideas, and pull requests are all welcome.

## Getting set up

Requirements: **macOS 26 "Tahoe"**, **Xcode 26**, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
# Engine package (pure logic — fastest feedback loop)
cd WarmthKit
swift build
swift test

# The app
xcodegen generate
open Abendrot.xcodeproj
```

### Building for a package manager

Downstream packagers (MacPorts, and anything else that owns the update path) build the
same sources with one extra compilation condition:

```sh
xcodebuild ... SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) ABENDROT_MACPORTS'
```

`ABENDROT_MACPORTS` compiles an inert `UpdateManager` — no Sparkle, no second update
channel — so the Sparkle SPM dependency can be dropped from `project.yml` for an offline
build. Only that flag changes behaviour; a normal build still ships Sparkle.

Note that macOS 26-only Liquid Glass API (`glassEffect`, `Glass`) sits behind
`#if compiler(>=6.2)` as well as `#available(macOS 26.0, *)`, so the macOS 14 floor still
compiles on Xcode 16, which has no macOS 26 SDK. Keep new Tahoe-only API behind both.

The project is split into:

- **`WarmthKit/`** — the warmth engine as a standalone Swift package. Pure logic (color math, scheduling, per-display state) lives in `WarmthCore` and is fully unit-tested; the system layers (overlay, DDC, gamma, schedule following) sit behind protocols.
- **`App/`** — the SwiftUI + AppKit menu-bar app. It talks to the engine only through the public `WarmthEngine` API.

## Pull requests

- Keep changes focused; one logical change per PR.
- Add or update tests for engine logic (`WarmthCore`) — it's meant to stay headlessly testable.
- Match the surrounding code style. CI runs `swift-format` and the unit tests.
- Be honest in user-facing copy: this is a general-wellness tool, not a medical device. No medical claims.

## Reporting bugs

Open an issue with your macOS version, Mac model, the displays involved (built-in / external, connection type), and what you expected vs. what happened. Display behavior varies a lot across hardware, so those details matter.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
