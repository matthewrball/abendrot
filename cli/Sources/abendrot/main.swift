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

// Custom top-level entry (instead of `Abendrot.main()`) so ArgumentParser's parse and validation
// failures honor the documented 0/2/3/4 exit contract. ArgumentParser exits parse/ValidationError
// failures with EX_USAGE=64; we remap ONLY that to exit 2 (bad input) and print the message to
// stderr. Everything else is delegated to ArgumentParser's own `exit(withError:)`, so:
//   • --help / --version / clean success keep exit 0 (and print to stdout),
//   • our own `fail(_, code:)` throws of ExitCode(2/3/4) pass through with their exact codes.
// Note: `set warmth -1` parses as an unknown option (a leading '-' is read as a flag) before any
// value validation, so it lands here as a usage error → exit 2. Use `set warmth -- -1` to pass a
// leading-negative value positionally (it then fails range validation at exit 2 too).
do {
    var command = try Abendrot.parseAsRoot()
    try command.run()
} catch {
    if Abendrot.exitCode(for: error) == .validationFailure {
        // Parse error or ArgumentParser ValidationError (would be EX_USAGE=64): honor the contract.
        printErr(Abendrot.message(for: error))
        exit(CLIExit.badInput)
    }
    // Help/version/clean exits, our own ExitCode(2/3/4), and any other error: let ArgumentParser
    // print and exit with the appropriate code (it routes clean text to stdout, errors to stderr).
    Abendrot.exit(withError: error)
}
