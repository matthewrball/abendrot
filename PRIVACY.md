# Privacy Policy

_Last updated: July 24, 2026 · Applies to the Abendrot macOS application._

Abendrot is a free, open-source macOS app. It has no account system, analytics
SDK, advertising, or telemetry. Abendrot does not send your settings, display
information, usage statistics, location, or screen contents to its maintainer.

## Data kept on your Mac

Abendrot stores only the local data needed to operate:

- Preferences such as warmth, schedule mode, reveal mode, excluded apps, and
  an optional city coordinate you choose.
- Local statistics such as warmed time and warm-evening count. These statistics
  never leave your Mac and can be disabled or reset in Settings.
- The direct-download edition keeps a small display-recovery file containing
  display identifiers and native color gains, plus a local status file for its
  bundled `abendrot` command-line tool. The Mac App Store edition includes
  neither hardware display control nor the command-line tool.

These files are stored in your user Library and are protected with user-only
file permissions. Abendrot does not read screen contents or collect health,
sleep, or precise GPS data.

## Network access

Core screen warming works without a network connection.

The Mac App Store edition does not make update requests itself; Apple delivers
its updates through the Mac App Store. The direct-download edition uses Sparkle
to check for and download updates from GitHub over HTTPS. You can disable those
automatic checks in Settings. As with any web request, GitHub may receive
standard connection metadata such as an IP address under its own privacy
policy. Abendrot does not add an account, device identifier, analytics payload,
or app settings to those requests.

Links you choose to open from the app, such as the project website, GitHub, or
research references, open in your default browser and are governed by those
sites' privacy policies.

## System permissions

Abendrot does not require Accessibility, Screen Recording, Camera, Microphone,
or Location permission for its core behavior. A manually selected city is
looked up from an offline list and stored locally.

## Removing local data

Uninstalling the app removes the application itself. To also remove its local
settings and recovery files, delete:

- `~/Library/Application Support/Abendrot`
- `~/Library/Preferences/app.abendrot.Abendrot.plist`

The sandboxed Mac App Store edition keeps its files in the macOS container at
`~/Library/Containers/app.abendrot.Abendrot`.

## Changes and contact

Material changes to data collection will be documented here before release.
Questions can be opened as an issue on
[GitHub](https://github.com/matthewrball/abendrot). Sensitive privacy concerns
can use GitHub's private vulnerability reporting under the repository's
Security tab.
