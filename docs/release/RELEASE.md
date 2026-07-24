# Abendrot — Release Engineering Runbook (Lane E)

Authoritative runbook for building, signing, notarizing, packaging, and shipping
Abendrot. Grounded in plan §9, §21.2, §7 (M0/M5), and the Wave-1 founder
decisions. Where §21 refines earlier prose, **§21 wins**.

> **Two modes, one pipeline.** CI and local smoke builds can run in **Mode B
> (today, no Apple account)** without credentials. `release.sh` does not silently
> downgrade to Mode B: pass `--unsigned` explicitly for that local-test path.
> Mode A activates only for signed releases.

---

## 0. TL;DR

| | **Mode B — TODAY (default)** | **Mode A — after $99 account** |
|---|---|---|
| Signing | unsigned / ad-hoc local build | Developer ID Application + Hardened Runtime |
| Notarization | skipped (clean no-op) | `notarytool submit --wait` + `stapler staple` |
| DMG | `plain-dmg.sh` (scripted `hdiutil`, headless) | `pretty-dmg.sh` (branded) or `plain-dmg.sh` |
| Gatekeeper on other Macs | right-click → Open / `xattr -dr` | passes silently |
| Release gate | UNSIGNED pre-release allowed | **≥1 notarized + stapled DMG required (§21.2)** |
| Sparkle appcast | `--unsigned`: production appcast unchanged | stable signed release only: item written + EdDSA-signed; `--prerelease` leaves the stable feed unchanged |

```
# Mode B smoke (works right now, no account):
xcodebuild ... CODE_SIGNING_ALLOWED=NO build         # unsigned Abendrot.app
scripts/dmg/plain-dmg.sh --app <Abendrot.app> --out Abendrot.dmg --volname Abendrot
scripts/release/notarize.sh Abendrot.dmg             # prints "SKIPPED (Mode B)", exits 0
```

---

## 1. M0 smoke build (plan §7 M0, §21.2)

The M0 milestone requires a **smoke build that proves the packaging path end to
end.** Two stages:

- **Now (Mode B):** local **unsigned** build → `plain-dmg.sh` → mount → drag to
  `/Applications` → launch (right-click → Open past Gatekeeper). This validates
  bundle layout, the DMG, and first-launch on the founder's own Mac.
- **Later (Mode A):** the same app **signed + Hardened-Runtime + notarized +
  stapled**, verified with `spctl -a -vvv` and a fresh-Mac Gatekeeper first
  launch. `notarize.sh` parses the `notarytool log` and staples.

The M0 smoke build is intentionally minimal — it exists to de-risk release
plumbing before the engine is complete.

---

## 2. Staged-beta release sequence (plan §21.6, CONFIRMED)

Releases ship as **signed public betas** before the branded 1.0:

| Tag | Contents | Signing reality |
|---|---|---|
| `0.1` | overlay + hotkey + schedule + DMG + notarization | Mode A *expected* by here (buy the account before 0.1 public) |
| `0.2` | DDC opt-in + Restore Displays tooling | Mode A |
| `0.3` | Sparkle auto-update dogfood + release polish | Mode A (EdDSA signing mandatory) |
| `1.0` | branded launch, after the hardware matrix passes | Mode A |

Internal/local dogfood builds before `0.1` may be **Mode B / unsigned**. Any
**public** beta should be notarized (Mode A) so testers don't fight Gatekeeper.
This is the practical trigger to buy the $99 account: **before the first public
`0.1`.**

---

## 3. The pipeline, step by step

### 3.1 Lint + test (hosted CI, always — `.github/workflows/ci.yml`)
`swift-format --lint` + `SwiftLint` → the complete headless WarmthKit suite
(engine, fake-backed DDC recovery, and control validation) → the CLI suite.
The `test-warmthcore` check runs on every push/PR including forks and fails hard
if either package or any test is missing/failing. `shell-release-guards` checks
every shipped shell script and exercises the release failure gates. Neither job
uses secrets or physical displays. On `public-dev`, the single
`public-dev/release-gate` context succeeds only after the real test, build, shell,
and curated-tree checks succeed on that exact public commit.

### 3.2 Build the app
- The `Abendrot.xcodeproj` is a **git-ignored build artifact**; `project.yml` is
  the source of truth. CI (and you, locally) **generate it with XcodeGen first**:
  `brew install xcodegen && xcodegen generate --spec project.yml`. CI's
  `build-app-unsigned` job does exactly this and **fails the job if generate or
  build fails** — "no project file" can no longer silently pass.
- **Mode B:** `xcodebuild -project Abendrot.xcodeproj -scheme Abendrot …
  CODE_SIGNING_ALLOWED=NO build`. If the engine cannot link headlessly with the
  full toolchain, that surfaces as a CI build failure (by design).
- **Mode A:** `xcodebuild … archive` with `CODE_SIGN_IDENTITY="Developer ID
  Application: … (TEAMID)"`, `OTHER_CODE_SIGN_FLAGS="--options runtime
  --timestamp"`, and `ABENDROT_SOURCE_COMMIT="$(git rev-parse HEAD)"`, then
  `-exportArchive` with
  `scripts/release/ExportOptions-DeveloperID.plist`.
- **Hardened Runtime YES, App Sandbox NO** (§9 — sandbox blocks private-framework
  `dlopen` + IOAVService). The app uses Sparkle 2 via SPM and the standard
  updater controller. Do **not** enable Sparkle's sandbox-only XPC service plist
  keys unless the app is ever sandboxed.

### 3.3 Package the DMG
- **`scripts/dmg/plain-dmg.sh`** — scripted `hdiutil`, headless-safe, the
  **Mode-B default** and the CI baseline. Always works. (Not byte-reproducible —
  UDZO embeds timestamps; we lean on code-signing + Sparkle EdDSA for integrity.)
- **`scripts/dmg/pretty-dmg.sh`** — branded create-dmg window with the
  split-screen **cold→warm** background (Lane C art, §21.4). **UI runner /
  local only** — create-dmg's AppleScript hangs headless (issue #154). Falls
  back to plain if art or GUI is missing.
- Prefer **pretty** for public releases; **plain** is the guaranteed fallback so
  releases never block (§9).

### 3.4 Notarize + staple (`scripts/release/notarize.sh`)
`notarytool submit --wait` → parse status from the plist → fetch + print
`notarytool log` → `stapler staple` + `validate` → `spctl -a -vvv`. **No-ops with
a clear message and exits 0 when no Apple credentials are configured** (Mode B).

### 3.5 Sparkle-sign + appcast + publish (`scripts/release/release.sh`)
Reads version/build from the exported app, rejects signed releases whose
`SUPublicEDKey` is not a 32-byte Ed25519 key or does not match the private key
reported by Sparkle's `generate_keys -p`, and requires `SUFeedURL` to equal the
canonical HTTPS appcast URL exactly. For signed releases, `DEVELOPER_ID_APP`
must be the exact leaf authority string (`Developer ID Application: Name
(TEAMID)`), and the input exported app must pass `codesign --verify --deep
--strict` with that exact first `Authority=` before the script trusts its
source marker or mutates the bundle. It rejects non-increasing build numbers,
embeds and signs the CLI helper, re-signs and verifies the containing app, and
verifies that the helper covers every architecture in the app executable. It
then builds the DMG, requires successful notarization, runs Sparkle
**`sign_update`** (EdDSA), and **updates `appcast.xml` preserving existing
items**. Actual GitHub publication is guarded by `RELEASE_PUBLISH=1` and an
explicit `RELEASE_TARGET_SHA`; a stable release must target the current curated
public `main` commit. Missing `gh`, a stale tag, or a different target fails
closed. It also re-runs the audited source commit's own `scripts/sync-public.sh`
against the exact public target commit and requires a clean result, so the public
snapshot is content-equal to the source export while preserving public-only
files. The exported app must also carry an `AbendrotSourceCommit` value equal to
the clean build checkout's full `HEAD`, binding the binary, public source
snapshot, and release tag to the same source revision.

**Signed vs unsigned (integrity gate):** by default `release.sh` treats the build
as **signed** and hard-fails before publishing unless the app is configured for
the real HTTPS feed, the bundle is signed after helper embedding, the DMG is
notarized and stapled, and `sign_update` produces a non-empty EdDSA signature.
For local testing pass **`--unsigned`**: the GitHub release is forced to
pre-release and the production appcast is left byte-for-byte unchanged.

Publishing is deliberately two-phase so the release tag's source archive matches
the code that produced the binary:

1. Commit the clean source tree. Run `scripts/publish.sh stage`, review the
   curated public diff, and use the printed commit command so the public commit
   records exactly one full `Source-Build-Commit` trailer. Push `public-dev`.
   `scripts/publish.sh promote` verifies that trailer, proves the exact public
   commit is content-equal to the source export, then accepts only a successful
   `.github/workflows/ci.yml` push run on `public-dev` with a successful
   `public-dev/release-gate` job for the same SHA. Record the resulting
   40-character public `main` SHA.
2. Build/export the release app from that same source commit and publish with
   `RELEASE_PUBLISH=1 RELEASE_TARGET_SHA=<public-main-sha>
   scripts/release/release.sh --app <Abendrot.app> ...`. The tag and GitHub source
   archive are now bound to the already-published curated source snapshot.
3. Review and commit the updated `appcast.xml` in the build repository. Run the
   same stage → `public-dev` CI → promote flow a second time to publish the feed
   entry.

The public `dev` branch remains the source-history lane; `public-dev` is the
curated promotion lane. `release.sh` never commits or pushes either repository.

A dry run prepares an appcast candidate under `release-scratch` but never
changes the production `appcast.xml`. The production feed is replaced locally
only after `gh release create` succeeds, so a failed or skipped publish cannot
leave a feed entry pointing at a nonexistent release.

> `ditto -c -k --keepParent` is the correct ZIP path **if** a ZIP channel is
> added later (preserves signature/xattrs; never `zip`). Current default ships
> the DMG; staple the `.app` before any offline-first-launch ZIP.

---

## 4. The single Sparkle release authority (resolves §9 ↔ §21.2)

**Decision (recommended, adopt this): the LOCAL release machine is the single
Sparkle signing authority. The EdDSA private key lives ONLY in the founder's
login keychain — never in the repo, never in CI secrets.**

- **Why local, not CI:** §9 says "private key in login keychain only"; a CI
  secret would be a second copy and a second authority. §21.2 demands exactly
  one. Local keychain keeps the key off GitHub's servers entirely — the
  strongest story for a trust-first OSS app.
- **Setup (once, when starting Sparkle / `0.3`):**
  1. `generate_keys` (Sparkle tool) → creates the EdDSA keypair; the **private
     key is stored in the login keychain**, the **public key** is printed.
  2. Put the public key in the app's `Info.plist` as `SUPublicEDKey` before the
     first signed release; `release.sh` aborts while the placeholder remains.
  3. Set `SUFeedURL` to the raw appcast URL
     `https://raw.githubusercontent.com/matthewrball/abendrot/main/appcast.xml`.
  4. Back up the private key **once** to an offline password manager / encrypted
     vault (losing it means users can't auto-update to anything you sign next).
- **Signing happens only on that machine:** `release.sh` calls `sign_update`,
  which reads the key from the keychain automatically. CI never signs the
  appcast.
- **Rotation / revocation:**
  - **Rotation (planned):** generate a new keypair, ship an app update **signed
    with the OLD key** whose new `Info.plist` carries the NEW `SUPublicEDKey`.
    Once that update is broadly adopted, sign subsequent appcasts with the new
    key. Sparkle supports listing the new key while the installed base still
    trusts the old one during the transition.
  - **Revocation (key compromised):** treat as a security incident — generate a
    new key, publish a normally-distributed (DMG download) update carrying the
    new public key, and consider the appcast channel untrusted until users are on
    a build with the new `SUPublicEDKey`. Document in `SECURITY.md`.
  - Never delete the old key until telemetry/heuristics say the old-key install
    base is negligible.

> Alternative (NOT chosen): a GitHub Actions *environment-protected* secret with
> manual approval. Rejected to keep a single authority and the key off GitHub.
> If ever adopted, it must **replace** local signing, not coexist (§21.2).

---

## 5. Homebrew cask contract (§21.2)

Template: `scripts/release/abendrot.rb.template`. **Publish only after the
appcast + DMG are coherent and ≥1 release is notarized+stapled.**

Required stanzas (all present in the template):
- **versioned GitHub-release URL** — `…/releases/download/v#{version}/Abendrot-#{version}.dmg`.
- **`sha256`** — real DMG hash at publish time (`plain-/pretty-dmg.sh` print it).
- **`auto_updates true`** — Sparkle self-updates; brew defers.
- **`livecheck` with `strategy :sparkle`** — reads the appcast as source of truth.
- **`zap trash:`** — removes app support/caches/prefs/saved-state on `--zap`.

Path: **own tap first** (`matthewrball/homebrew-abendrot`) → submit to
`homebrew-cask` central later. Confirm the real **bundle id** with Lane A and
replace the `app.abendrot.Abendrot` placeholders.

---

## 6. CI overview (`.github/workflows/ci.yml`)

- **Hosted (always, no signing secrets, fork-safe):** detect-signing-secrets → lint →
  **complete WarmthKit + CLI headless tests (the real required gate)** → unsigned
  app build (XcodeGen-generated project, `xcodebuild` — fails on generate/build
  error) + plain DMG artifact. `shell-release-guards` also runs shell syntax and
  adversarial release guard tests.
- **Curated publication gate:** a push to `public-dev` receives the unique
  `public-dev/release-gate` context only after the headless tests, unsigned app
  build, release guards, and tracked-tree leak/allowlist verification succeed on
  that exact commit. Public `main` protection should require this context; source
  `dev` checks cannot satisfy it.
- **Hosted Mode-A job (`sign-notarize`):** runs **only** when signing secrets are
  present **and** the trigger is not a `pull_request`. Imports the cert into a
  **temp keychain**, archives/exports Developer ID, and validates notarization
  plus stapling. It is a validation job, not a distributable-release upload;
  publication stays on the single local release machine. The job tears the
  keychain down on exit and uses a GitHub **`environment`** (`release-signing`)
  so optional required reviewers can gate it.
- **Self-hosted display matrix (`display-matrix-planned-not-a-gate`, PLANNED /
  UNIMPLEMENTED):** manual `workflow_dispatch` with `run_display_matrix=true`
  only, on a runner labeled `self-hosted, macOS, abendrot-display-matrix`. Never
  on push/PR → never sees fork secrets and **never a passing check**. It documents
  the physical matrix (M5 Tahoe gamma-broken, M3/M4, Apple display, generic DDC
  monitor, HDMI/dock) and **intentionally exits 1** so a green CI can never imply
  hardware validation that did not happen. Replace the failing stub with real
  integration (which then decides pass/fail) once hardware is registered.

**Fork-PR safety:** GitHub does not expose repo secrets to forked-PR runs; we add
defense-in-depth by (a) gating Mode-A steps on a detected-secrets output and
(b) refusing the signing job on any `pull_request`. Never echo secret values.

---

## 7. Release gates (must all pass for a SIGNED release — §8, §21.2)

1. `codesign --verify --deep --strict` on the `.app`.
   `Authority=` must equal the exact `DEVELOPER_ID_APP` value; broad
   selectors such as `Developer ID Application` are rejected.
2. `spctl -a -vvv` (Gatekeeper) accepts the app.
3. **Notarization stapled** (`stapler validate` ok) — **≥1 notarized+stapled DMG
   is the hard release gate.**
4. Sparkle update dry-run from `vN-1 → vN` succeeds.
5. Fresh-Mac Gatekeeper first launch (manual, self-hosted / real machine).
6. Mount the final DMG; verify layout, `/Applications` drag-install, and
   quarantine first-launch (§21.2).

In **Mode B** gates 1–3 are not applicable; the build ships as an **UNSIGNED
pre-release** with the documented `xattr -dr com.apple.quarantine` / right-click
→ Open workaround, and `release.sh` forces `--prerelease`.

---

## 8. "$99 account → what to supply" checklist (Mode A activation)

When the founder enrolls in the Apple Developer Program, provide these. Store CI
copies as **GitHub Actions secrets** (Settings → Secrets and variables →
Actions); keep the Sparkle key **out of CI** (§4).

| Item | What it is | Where it goes |
|---|---|---|
| **Developer ID Application certificate** | `.p12` export (cert + private key) from Keychain/Xcode | CI secret `DEVELOPER_ID_APP_CERT_P12_BASE64` (base64 of the `.p12`) + `DEVELOPER_ID_APP_CERT_PASSWORD`; locally, the login keychain |
| **Signing identity string** | Exact leaf authority, `Developer ID Application: Name (TEAMID)` | CI secret `DEVELOPER_ID_APP_IDENTITY`; local env `DEVELOPER_ID_APP` for `release.sh` |
| **Team ID** | 10-char Apple Team ID | replace `TEAMID_PLACEHOLDER` in `ExportOptions-DeveloperID.plist` |
| **App Store Connect API key** | `.p8` key file for `notarytool` | CI secret `ASC_API_KEY_P8_BASE64` (base64 of the `.p8`) |
| **ASC API Key ID** | the key's ID | CI secret `ASC_API_KEY_ID` |
| **ASC API Issuer ID** | issuer UUID | CI secret `ASC_API_ISSUER_ID` |
| **Sparkle EdDSA key** | generated via `generate_keys` | **login keychain ONLY** (never CI/repo); public key → `Info.plist SUPublicEDKey` (Lane A) |

Then:
1. Set the six CI secrets above → the `sign-notarize` job activates automatically.
2. Replace `TEAMID_PLACEHOLDER` in the ExportOptions plist.
3. Confirm `ENABLE_HARDENED_RUNTIME=YES`, no App Sandbox, and that Xcode
   archive/export embeds and signs Sparkle.
4. Run `DEVELOPER_ID_APP="Developer ID Application: Name (TEAMID)"
   release.sh --app <exported app>` locally to produce the first
   notarized+stapled, Sparkle-signed `0.1`.

> **Never commit** `.p12`, `.p8`, `.cer`, or any private key. `.gitignore`
> already excludes them, plus `*.dmg`, `*.zip`, and `secrets/`.

---

## 9. Open dependencies on other lanes

- **Lane A (engine):** finalize `Package.swift` + `Abendrot.xcodeproj` scheme /
  target / bundle-id names. CI references them as placeholders
  (`ABENDROT_APP_SCHEME=Abendrot`, bundle id `app.abendrot.Abendrot`). Keep
  `ENABLE_HARDENED_RUNTIME`, no sandbox,
  and replace the placeholder `SUPublicEDKey` before the first signed release.
- **Lane C (brand):** deliver the split-screen cold→warm DMG background
  (`scripts/dmg/assets/`) per the geometry in `pretty-dmg.sh`; volume `.icns`
  optional.
- **Founder:** buy the $99 account before the first **public** `0.1`; generate +
  back up the Sparkle EdDSA key; populate the six CI secrets.
