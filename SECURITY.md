# Security Policy

## Reporting a vulnerability

Please report security issues **privately** rather than opening a public issue.

Use GitHub's private vulnerability reporting on this repository: go to the **Security** tab → **Report a vulnerability**. That opens a private advisory visible only to the maintainers.

Please include enough detail to reproduce (macOS version, Mac model, displays involved, and steps). We'll acknowledge your report and keep you updated on a fix.

## Scope

Abendrot is a local, menu-bar app. It has no backend and collects no data by default. Areas of particular interest:

- The display/warmth engine and its use of system display APIs.
- The auto-update path (see below).
- Any path that could leave a display in an altered state.

## Software updates

Releases are distributed as signed, notarized builds, and in-app updates are verified with an **EdDSA** signature before they are applied (the public key ships inside the app; the private signing key is never committed to this repository). A failure to verify a signature aborts the update.

## Supported versions

Abendrot is pre-release. Until a `1.0` release, only the latest source on the default branch is supported for security fixes.
