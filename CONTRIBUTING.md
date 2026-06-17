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

The project is split into:

- **`WarmthKit/`** — the warmth engine as a standalone Swift package. Pure logic (color math, scheduling, per-display state) lives in `WarmthCore` and is fully unit-tested; the system layers (overlay, DDC, gamma, schedule following) sit behind protocols.
- **`App/`** — the SwiftUI + AppKit menu-bar app. It talks to the engine only through the public `WarmthEngine` API.

## Pull requests

- Keep changes focused; one logical change per PR.
- Add or update tests for engine logic (`WarmthCore`) — it's meant to stay headlessly testable.
- Match the surrounding code style. CI runs `swift-format` / SwiftLint and the unit tests.
- Be honest in user-facing copy: this is a general-wellness tool, not a medical device. No medical claims.

## Reporting bugs

Open an issue with your macOS version, Mac model, the displays involved (built-in / external, connection type), and what you expected vs. what happened. Display behavior varies a lot across hardware, so those details matter.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
