import ArgumentParser
import Foundation
import WarmthCore
import AbendrotControl

// MARK: - abendrot
//
// Root command. BetterDisplay-parity control surface for the Abendrot menu-bar app:
//   abendrot status [--json] | get <key> | on | off
//   abendrot set warmth <0..1 | --kelvin K> | mode <…> | max-warmth <K> | reveal-mode <…> | location …
//   abendrot exclude add|remove <bundle-id> | list
//   abendrot reveal [--hold <seconds>]
//
// Every data-emitting command takes `--json`. Settings are persisted to CFPreferences (survive a
// restart) AND posted live to the running app; `status` reads the app's `state.json` snapshot.

struct Abendrot: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "abendrot",
        abstract: "Control the Abendrot screen-warmth app from the terminal or an AI assistant.",
        version: cliVersion,
        subcommands: [
            Status.self, Get.self, On.self, Off.self,
            SetCommand.self, Exclude.self, Reveal.self,
        ]
    )
}

/// The CLI's own semver (independent of the app's MARKETING_VERSION; surfaced in `status --json`).
let cliVersion = "0.1.0"

Abendrot.main()
