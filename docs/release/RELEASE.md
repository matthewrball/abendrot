# Abendrot — Release Engineering Runbook (Lane E)

Authoritative runbook for building, signing, notarizing, packaging, and shipping
Abendrot. Grounded in plan §9, §21.2, §7 (M0/M5), and the Wave-1 founder
decisions. Where §21 refines earlier prose, **§21 wins**.

> **Two modes, one pipeline.** Everything here runs in **Mode B (today, no Apple
> account)** or **Mode A (after the $99 Apple Developer Program)**. Mode B is the
> current default. Mode A activates only when credentials are present.

---

## 0. TL;DR

| | **Mode B — TODAY (default)** | **Mode A — after $99 account** |
|---|---|---|
| Signing | unsigned / ad-hoc local build | Developer ID Application + Hardened Runtime |
| Notarization | skipped (clean no-op) | `notarytool submit --wait` + `stapler staple` |
| DMG | `plain-dmg.sh` (scripted `hdiutil`, headless) | `pretty-dmg.sh` (branded) or `plain-dmg.sh` |
| Gatekeeper on other Macs | right-click → Open / `xattr -dr` | passes silently |
| Release gate | UNSIGNED pre-release allowed | **≥1 notarized + stapled DMG required (§21.2)** |
| Sparkle appcast | `--unsigned`: item written, **edSignature attribute omitted** | item written + EdDSA-signed (missing signature or placeholder public key = hard fail) |

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
`swift-format --lint` + `SwiftLint` → `swift test --filter WarmthCoreTests` on the
pure headless **WarmthCore** target (no displays). This is the **single real
hosted test gate** (`test-warmthcore`): it runs on every push/PR including forks
and **fails hard** if `WarmthKit/Package.swift` or the WarmthCore tests are
missing/failing — it does not skip-pass. No secrets.

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
  --timestamp"`, then `-exportArchive` with
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
`SUPublicEDKey` is still the placeholder, warns on duplicate build numbers,
builds the DMG, notarizes (Mode A), **Sparkle `sign_update`** (EdDSA), **updates
`appcast.xml` preserving existing items**, then `gh release create` (guarded by
`RELEASE_PUBLISH=1`). Commit the updated `appcast.xml` so the raw GitHub URL
Sparkle reads reflects the new item.

**Signed vs unsigned (integrity gate):** by default `release.sh` treats the build
as **signed** and **hard-fails (exit 5, no appcast write)** if `sign_update`
produces no EdDSA signature — it never emits an item with `edSignature=""` that
falsely claims to be signed. For dev/dogfood builds pass **`--unsigned`**: the
appcast item then **omits the `sparkle:edSignature` attribute entirely** (not an
empty string), the title is tagged `(UNSIGNED dev build)`, and the GitHub release
is forced to pre-release. Such an item must not feed a real auto-update channel.

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

- **Hosted (always, no secrets, fork-safe):** detect-secrets → lint →
  **WarmthCore headless tests (the real required gate, fails hard)** → unsigned
  app build (XcodeGen-generated project, `xcodebuild` — fails on generate/build
  error) + plain DMG artifact.
- **Hosted Mode-A job (`sign-notarize`):** runs **only** when signing secrets are
  present **and** the trigger is not a `pull_request`. Imports the cert into a
  **temp keychain**, archives/exports Developer ID, notarizes, staples, uploads.
  Tears the keychain down on exit. Uses a GitHub **`environment`**
  (`release-signing`) so optional required reviewers can gate it.
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
| **Signing identity string** | `Developer ID Application: Name (TEAMID)` | CI secret `DEVELOPER_ID_APP_IDENTITY` |
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
4. Run `release.sh --app <exported app>` locally to produce the first
   notarized+stapled, Sparkle-signed `0.1`.

> **Never commit** `.p12`, `.p8`, `.cer`, or any private key. `.gitignore`
> already excludes them, plus `*.dmg`, `*.zip`, and `secrets/`.

---

## 9. Open dependencies on other lanes

- **Lane A (engine):** finalize `Package.swift` + `Abendrot.xcodeproj` scheme /
  target / bundle-id names. CI references them as placeholders
  (`ABENDROT_APP_SCHEME=Abendrot`, `WARMTHKIT_TEST_TARGET=WarmthCoreTests`,
  bundle id `app.abendrot.Abendrot`). Keep `ENABLE_HARDENED_RUNTIME`, no sandbox,
  and replace the placeholder `SUPublicEDKey` before the first signed release.
- **Lane C (brand):** deliver the split-screen cold→warm DMG background
  (`scripts/dmg/assets/`) per the geometry in `pretty-dmg.sh`; volume `.icns`
  optional.
- **Founder:** buy the $99 account before the first **public** `0.1`; generate +
  back up the Sparkle EdDSA key; populate the six CI secrets.
