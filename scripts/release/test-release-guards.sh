#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
DIRTY_MARKER=""
cleanup() {
  [ -z "$DIRTY_MARKER" ] || rm -f "$DIRTY_MARKER"
  rm -rf "$TMP"
}
trap cleanup EXIT

CI_WORKFLOW="$ROOT/.github/workflows/ci.yml"
RELEASE_SCRIPT="$ROOT/scripts/release/release.sh"
NOTARIZE_SCRIPT="$ROOT/scripts/release/notarize.sh"
PRETTY_DMG_SCRIPT="$ROOT/scripts/dmg/pretty-dmg.sh"
APPCAST_VALIDATOR="$ROOT/scripts/release/validate-appcast.py"
SIGN_JOB="$TMP/sign-notarize.yml"

python3 "$ROOT/scripts/release/test-color-contrast.py"

grep -qF 'asc_key.p8.XXXXXX' "$NOTARIZE_SCRIPT"
grep -qF 'notary-submit.txt.XXXXXX' "$NOTARIZE_SCRIPT"
if grep -Eq 'XXXXXX\.(p8|txt)' "$NOTARIZE_SCRIPT"; then
  echo "Notarization temp templates must end in Xs for macOS mktemp." >&2
  exit 1
fi
grep -qF "github.event_name == 'workflow_dispatch'" "$CI_WORKFLOW"
grep -qF "github.ref == 'refs/heads/main'" "$CI_WORKFLOW"
grep -qF "environment: release-signing" "$CI_WORKFLOW"
grep -qF "python3 scripts/release/validate-appcast.py appcast.xml" "$CI_WORKFLOW"
grep -qF '[ "$PUBLISH_APPCAST" = "true" ] && GH_FLAGS+=( --draft )' "$RELEASE_SCRIPT"
grep -qF "Unsigned artifacts cannot be published or uploaded" "$RELEASE_SCRIPT"
if grep -Eq '^  (detect-signing-secrets|detect-secrets):' "$CI_WORKFLOW"; then
  echo "CI must not read release secrets in a separate push/PR-visible job." >&2
  exit 1
fi
if grep -qF "actions/upload-artifact" "$CI_WORKFLOW"; then
  echo "CI must not use the vulnerable unsigned-build artifact action." >&2
  exit 1
fi
if grep -Eq 'brew install (xcodegen|swiftlint)|(^|[[:space:]])swiftlint([[:space:]]|$)' \
  "$CI_WORKFLOW"; then
  echo "CI build tooling must not come from unpinned Homebrew installs." >&2
  exit 1
fi
grep -qF "XCODEGEN_VERSION: 2.46.0" "$CI_WORKFLOW"
grep -qF \
  "XCODEGEN_URL: https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip" \
  "$CI_WORKFLOW"
grep -qF \
  "XCODEGEN_SHA256: 4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806" \
  "$CI_WORKFLOW"
grep -qF 'echo "$XCODEGEN_SHA256  $RUNNER_TEMP/xcodegen.zip" | shasum -a 256 -c -' \
  "$CI_WORKFLOW"
grep -qF '"$RUNNER_TEMP/xcodegen/bin/xcodegen" --version' "$CI_WORKFLOW"
[ "$(grep -cF -- '-onlyUsePackageVersionsFromResolvedFile' "$CI_WORKFLOW")" -eq 2 ]
[ "$(grep -cF -- '--only-use-versions-from-resolved-file' "$RELEASE_SCRIPT")" -eq 2 ]
APP_PACKAGE_LOCK="$ROOT/Abendrot.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
grep -qF '"identity" : "sparkle"' "$APP_PACKAGE_LOCK"
if grep -qF '"identity" : "sparkle"' "$ROOT/WarmthKit/Package.resolved"; then
  echo "WarmthKit must not own the app-only Sparkle dependency." >&2
  exit 1
fi

awk '
  /^  sign-notarize:$/ { in_job = 1 }
  in_job && /^  [[:alnum:]_-]+:$/ && $1 != "sign-notarize:" { exit }
  in_job { print }
' "$CI_WORKFLOW" > "$SIGN_JOB"
grep -qF '${{ secrets.DEVELOPER_ID_APP_CERT_P12_BASE64 }}' "$SIGN_JOB"
secret_refs_total="$(grep -cF '${{ secrets.' "$CI_WORKFLOW")"
secret_refs_sign_job="$(grep -cF '${{ secrets.' "$SIGN_JOB")"
[ "$secret_refs_total" -eq "$secret_refs_sign_job" ] || {
  echo "Release secrets may be referenced only inside sign-notarize." >&2
  exit 1
}
echo "PASS: CI signing secrets are manual-main-only and build tooling is pinned"

DMG_MODE_SELECTOR="$TMP/dmg-mode-selector.sh"
sed -n '/^choose_dmg_mode()/,/^}/p' "$RELEASE_SCRIPT" > "$DMG_MODE_SELECTOR"
grep -qF 'scripts/dmg/pretty-dmg.sh" --check' "$DMG_MODE_SELECTOR"
if grep -Eq 'create-dmg|WindowServer' "$DMG_MODE_SELECTOR"; then
  echo "Auto DMG selection must use headless dmgbuild, not create-dmg or a GUI session." >&2
  exit 1
fi
grep -qF "stable publication requires the branded DMG toolchain" "$RELEASE_SCRIPT"
grep -qF "ABORT — branded DMG creation failed" "$RELEASE_SCRIPT"
echo "PASS: automatic release packaging shares the branded builder's exact readiness probe"

grep -qF 'PDMG_BADGE_ICON="$BADGE_ICON"' "$PRETTY_DMG_SCRIPT"
grep -qF 'badge_icon = os.environ.get("PDMG_BADGE_ICON") or None' "$PRETTY_DMG_SCRIPT"
[ -f "$ROOT/scripts/dmg/assets/volume-badge.png" ] \
  && [ ! -e "$ROOT/scripts/dmg/assets/volume.icns" ] \
  && [ ! -e "$ROOT/scripts/dmg/assets/volume.png" ] \
  && [ ! -e "$ROOT/scripts/dmg/render-volume-icon.py" ] || {
  echo "The mounted DMG must use dmgbuild's native removable-disk badge mode." >&2
  exit 1
}
echo "PASS: mounted DMG uses the native removable-disk icon with Abendrot badge"

grep -qF 'local dmg_sign_id="${BUNDLE_ID}.dmg"' "$RELEASE_SCRIPT"
grep -qF 'codesign --force' "$RELEASE_SCRIPT"
grep -qF -- '--identifier "$dmg_sign_id"' "$RELEASE_SCRIPT"
grep -qF -- '--timestamp' "$RELEASE_SCRIPT"
grep -qF 'codesign --verify --strict --verbose=2 "$dmg"' "$RELEASE_SCRIPT"
grep -qF "DMG container signing authority does not match DEVELOPER_ID_APP" "$RELEASE_SCRIPT"
dmg_sign_call_line="$(grep -nF 'sign_dmg_container "$DMG_OUT"' "$RELEASE_SCRIPT" | cut -d: -f1)"
notarize_call_line="$(grep -nF 'notarize.sh" "$DMG_OUT"' "$RELEASE_SCRIPT" | cut -d: -f1)"
[ -n "$dmg_sign_call_line" ] && [ -n "$notarize_call_line" ] && \
  [ "$dmg_sign_call_line" -lt "$notarize_call_line" ] || {
  echo "Signed release DMGs must be container-signed and verified before notarization." >&2
  exit 1
}
final_dmg_verify_line="$(grep -nF 'verify_dmg_container_signature "$DMG_OUT"' "$RELEASE_SCRIPT" | cut -d: -f1)"
sparkle_sign_line="$(grep -nF 'SIGN_OUT="$("$SIGN_UPDATE" "$DMG_OUT"' "$RELEASE_SCRIPT" | cut -d: -f1)"
[ -n "$final_dmg_verify_line" ] && [ -n "$sparkle_sign_line" ] && \
  [ "$notarize_call_line" -lt "$final_dmg_verify_line" ] && \
  [ "$final_dmg_verify_line" -lt "$sparkle_sign_line" ] || {
  echo "Signed release DMGs must be verified after notarization and before Sparkle signing." >&2
  exit 1
}
sed -n '/^sign_dmg_container()/,/^}/p' "$RELEASE_SCRIPT" \
  | grep -F '[ "$UNSIGNED" != "true" ] || return 0' >/dev/null
echo "PASS: signed release DMGs are container-signed before notarization and verified before Sparkle signing"

# The ticket must be stapled INSIDE the .app before the DMG is built around it,
# so the app still verifies offline once a user drags it to /Applications.
app_notarize_call_line="$(grep -nF 'notarize.sh" "$APP" --app-bundle' "$RELEASE_SCRIPT" | cut -d: -f1)"
dmg_build_line="$(grep -nF 'release: building DMG (mode=$EFFECTIVE_MODE)' "$RELEASE_SCRIPT" | cut -d: -f1)"
[ -n "$app_notarize_call_line" ] && [ -n "$dmg_build_line" ] && \
  [ "$app_notarize_call_line" -lt "$dmg_build_line" ] && \
  [ "$app_notarize_call_line" -lt "$notarize_call_line" ] || {
  echo "The .app must be notarized and stapled before the DMG is built around it." >&2
  exit 1
}
grep -qF "signing is configured but the .app is not notarized+stapled" "$RELEASE_SCRIPT"
sed -n "${app_notarize_call_line},${dmg_build_line}p" "$RELEASE_SCRIPT" \
  | grep -F 'Releases are gated on a stapled ticket inside the shipped app.' >/dev/null
sed -n '/^# --- 2.9 /,/^# --- 3\. /p' "$RELEASE_SCRIPT" \
  | grep -F 'release: --unsigned -> skipping app notarization.' >/dev/null
echo "PASS: the shipped .app is notarized and stapled before DMG packaging"

grep -qF 'DMGBUILD_VERSION="1.6.7"' "$PRETTY_DMG_SCRIPT"
grep -qF -- '--check)' "$PRETTY_DMG_SCRIPT"
grep -qF 'pipx list dmgbuild --short' "$PRETTY_DMG_SCRIPT"
grep -qF 'pipx runpip dmgbuild show pyobjc-framework-Quartz' "$PRETTY_DMG_SCRIPT"
grep -qF 'built image is missing the app or /Applications link' "$PRETTY_DMG_SCRIPT"
grep -qF 'signed app signature was invalidated during DMG creation' "$PRETTY_DMG_SCRIPT"
if grep -qF 'hide_extensions = [app_name]' "$PRETTY_DMG_SCRIPT"; then
  echo "Branded DMG tooling must not attach FinderInfo to the signed app bundle." >&2
  exit 1
fi
grep -qF 'Detach the existing volume before building so Finder records the correct background alias.' \
  "$PRETTY_DMG_SCRIPT"
mounted_volume_guard_line="$(grep -nF 'MOUNT_PATH="/Volumes/$VOLNAME"' "$PRETTY_DMG_SCRIPT" | cut -d: -f1)"
output_delete_line="$(grep -nF 'rm -f "$OUT"' "$PRETTY_DMG_SCRIPT" | cut -d: -f1)"
[ "$mounted_volume_guard_line" -lt "$output_delete_line" ] || {
  echo "Branded DMG mounted-volume guard must run before replacing the output." >&2
  exit 1
}
echo "PASS: branded DMG tooling is version-pinned and verifies its mounted payload"

mkdir -p "$TMP/notary-input.app"
set +e
"$NOTARIZE_SCRIPT" "$TMP/notary-input.app" >"$TMP/notary-app-out" 2>"$TMP/notary-app-err"
notary_app_rc=$?
set -e
[ "$notary_app_rc" -eq 2 ]
grep -qF "only accepts a finished .dmg" "$TMP/notary-app-err"
echo "PASS: notarization rejects raw app bundles before credential handling"

# App-bundle mode is explicit and narrow: it must refuse a DMG and refuse a plain
# file that merely ends in .app, both before any credential handling.
printf 'not a dmg\n' > "$TMP/notary-type.dmg"
set +e
"$NOTARIZE_SCRIPT" "$TMP/notary-type.dmg" --app-bundle \
  >/dev/null 2>"$TMP/notary-appmode-dmg-err"
rc=$?
set -e
[ "$rc" -eq 2 ]
grep -qF -- "--app-bundle requires a .app bundle target" "$TMP/notary-appmode-dmg-err"
printf 'not a bundle\n' > "$TMP/notary-flat.app"
set +e
"$NOTARIZE_SCRIPT" "$TMP/notary-flat.app" --app-bundle \
  >/dev/null 2>"$TMP/notary-appmode-flat-err"
rc=$?
set -e
[ "$rc" -eq 2 ]
grep -qF "is not an app bundle directory" "$TMP/notary-appmode-flat-err"
echo "PASS: app-bundle notarization accepts only a real .app bundle"

APP_MODEL="$ROOT/App/Sources/Abendrot/ViewModel/AppModel.swift"
UPDATE_MANAGER="$ROOT/App/Sources/Abendrot/Services/UpdateManager.swift"
PROJECT_SPEC="$ROOT/project.yml"
INFO_PLIST="$ROOT/App/Resources/Info.plist"
grep -A2 -F -- '- path: App/Sources' "$PROJECT_SPEC" | grep -F -- '- .omc/**' >/dev/null
echo "PASS: ignored agent state is excluded from app resources"
if sed -n '/private static var hasUsableUpdateConfiguration/,/^    }/p' "$UPDATE_MANAGER" \
  | grep -F '#if DEBUG' >/dev/null; then
  echo "Debug builds must use the same validated Sparkle configuration." >&2
  exit 1
fi
grep -qF 'localizedCaseInsensitiveContains("PLACEHOLDER")' "$UPDATE_MANAGER"
grep -qF 'feedURLString == "https://raw.githubusercontent.com/matthewrball/abendrot/main/appcast.xml"' \
  "$UPDATE_MANAGER"
echo "PASS: Debug and release builds use validated Sparkle configuration"

# `glassEffect`/`Glass` exist only in the macOS 26 SDK, so `#available` alone still fails to
# compile on Xcode 16 — which is what packagers use for the macOS 14 floor. Every Tahoe-only
# symbol must sit behind `#if compiler(>=6.2)` with a pre-Tahoe fallback in the `#else`.
GLASS_SURFACE="$ROOT/App/Sources/Abendrot/Theme/GlassSurface.swift"
GLASS_TAHOE="$TMP/glass-tahoe-only.swift"
awk '/#if compiler\(>=6\.2\)/ { in_tahoe = 1; next } /#else|#endif/ { in_tahoe = 0 } in_tahoe' \
  "$GLASS_SURFACE" > "$GLASS_TAHOE"
grep -qF '.glassEffect(glassStyle, in: shape)' "$GLASS_TAHOE"
grep -qF 'private var glassStyle: Glass {' "$GLASS_TAHOE"
grep -qF '@available(macOS 26.0, *)' "$GLASS_TAHOE"
[ "$(grep -cF 'glassEffect(' "$GLASS_SURFACE")" -eq 1 ]
[ "$(grep -cF ': Glass {' "$GLASS_SURFACE")" -eq 1 ]
[ "$(grep -cF '@available(macOS 26.0, *)' "$GLASS_SURFACE")" -eq 1 ]
[ "$(grep -cF '.background(.ultraThinMaterial, in: shape)' "$GLASS_SURFACE")" -eq 2 ]
echo "PASS: macOS 26 Liquid Glass API is compile-guarded so the macOS 14 floor builds on Xcode 16"

grep -qF 'SUEnableAutomaticChecks: true' "$PROJECT_SPEC"
grep -qF 'SUAutomaticallyUpdate: true' "$PROJECT_SPEC"
grep -qF 'SUScheduledCheckInterval: 86400' "$PROJECT_SPEC"
[ "$(/usr/bin/plutil -extract SUEnableAutomaticChecks raw "$INFO_PLIST")" = "true" ]
[ "$(/usr/bin/plutil -extract SUAutomaticallyUpdate raw "$INFO_PLIST")" = "true" ]
[ "$(/usr/bin/plutil -extract SUScheduledCheckInterval raw "$INFO_PLIST")" = "86400" ]
grep -qF 'macOS: "14.0"' "$PROJECT_SPEC"
grep -qF 'MACOSX_DEPLOYMENT_TARGET: "14.0"' "$PROJECT_SPEC"
[ "$(/usr/bin/plutil -extract LSMinimumSystemVersion raw "$INFO_PLIST")" = "14.0" ]
grep -qF '.macOS("14.0")' "$ROOT/WarmthKit/Package.swift"
grep -qF '.macOS("14.0")' "$ROOT/cli/Package.swift"
grep -qF 'Requires macOS 14 "Sonoma" or later.' "$ROOT/README.md"
if [ -f "$ROOT/landing/index.html" ]; then
  grep -qF 'macOS&nbsp;14 Sonoma and later' "$ROOT/landing/index.html"
fi
echo "PASS: app, engine, and CLI share the macOS 14 deployment floor"
sed -n '/private init()/,/^    func checkForUpdates()/p' "$UPDATE_MANAGER" \
  | grep -F 'startingUpdater: true' >/dev/null
sed -n '/func setAutomaticallyDownloadsUpdates/,/^    func refresh()/p' "$UPDATE_MANAGER" \
  | grep -F 'updater.automaticallyChecksForUpdates = enabled' >/dev/null
sed -n '/func setAutomaticallyDownloadsUpdates/,/^    func refresh()/p' "$UPDATE_MANAGER" \
  | grep -F 'updater.automaticallyDownloadsUpdates = enabled' >/dev/null
# Sparkle's 24h scheduler alone never re-checks on relaunch, so the delegate forces
# exactly ONE latched background check per launch and takes over silent
# install-on-quit with a prompt. The latch and the prompt hook must both stay.
grep -qF 'updaterDelegate: updaterDelegate' "$UPDATE_MANAGER"
grep -qF 'guard !didForceLaunchCheck else { return }' "$UPDATE_MANAGER"
if [ "$(grep -cF 'checkForUpdatesInBackground()' "$UPDATE_MANAGER")" -ne 1 ]; then
  echo "Expected exactly one latched launch-time update check in UpdateManager." >&2
  exit 1
fi
grep -qF 'willInstallUpdateOnQuit' "$UPDATE_MANAGER"
grep -qF 'Text("Download updates automatically")' "$UPDATE_MANAGER"
echo "PASS: update checks are latched once per launch and install-on-quit prompts instead of installing silently"

grep -qF 'static let warmedSecondsKey = "stats.warmedSeconds"' "$APP_MODEL"
grep -qF 'static let warmSunsetCountKey = "stats.warmSunsetCount"' "$APP_MODEL"
grep -qF 'static let lastWarmSunsetDayKey = "stats.lastWarmSunsetDay"' "$APP_MODEL"
grep -qF 'static let statsEnabledKey = "stats.enabled"' "$APP_MODEL"
echo "PASS: statistics persistence keys remain upgrade-compatible"

PATCH_APPLY="$TMP/apply-settings-patch.swift"
sed -n \
  '/private func apply(_ patch: SettingsPatch)/,/private func apply(_ action: ControlAction)/p' \
  "$APP_MODEL" > "$PATCH_APPLY"
mode_line="$(grep -nF 'patch.scheduleMode' "$PATCH_APPLY" | head -1 | cut -d: -f1)"
warmth_line="$(grep -nF 'patch.globalWarmthStrength' "$PATCH_APPLY" | head -1 | cut -d: -f1)"
[ -n "$mode_line" ] && [ -n "$warmth_line" ] && [ "$mode_line" -lt "$warmth_line" ] || {
  echo "Control patches must apply schedule mode before mode-specific warmth." >&2
  exit 1
}
echo "PASS: combined control patches select schedule mode before warmth"

APP="$TMP/Abendrot.app"
APPCAST="$TMP/appcast.xml"
CANONICAL_FEED="https://raw.githubusercontent.com/matthewrball/abendrot/main/appcast.xml"
MOCK_DEVELOPER_ID_APP="Developer ID Application: Abendrot Test (ABCDE12345)"

VALID_SIGNATURE="$(head -c 64 /dev/zero | /usr/bin/base64)"
VALID_APPCAST="$TMP/valid-appcast.xml"
cat > "$VALID_APPCAST" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Abendrot</title>
    <link>$CANONICAL_FEED</link>
    <language>en</language>
    <!-- release.sh inserts new <item> elements directly below this line. -->
    <item>
      <sparkle:version>2</sparkle:version>
      <sparkle:shortVersionString>1.1.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0.0</sparkle:minimumSystemVersion>
      <enclosure url="https://github.com/matthewrball/abendrot/releases/download/v1.1.0/Abendrot-1.1.0.dmg"
                 length="222" type="application/octet-stream"
                 sparkle:edSignature="$VALID_SIGNATURE" />
    </item>
    <item>
      <sparkle:version>1</sparkle:version>
      <sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0.0</sparkle:minimumSystemVersion>
      <enclosure url="https://github.com/matthewrball/abendrot/releases/download/v1.0.0/Abendrot-1.0.0.dmg"
                 length="111" type="application/octet-stream"
                 sparkle:edSignature="$VALID_SIGNATURE" />
    </item>
  </channel>
</rss>
XML
python3 "$APPCAST_VALIDATOR" "$VALID_APPCAST" >/dev/null
for field in signature version url length minimum-os; do
  invalid="$TMP/invalid-$field.xml"
  cp "$VALID_APPCAST" "$invalid"
  case "$field" in
    signature) sed -i '' "s/$VALID_SIGNATURE/$VALID_SIGNATURE-invalid/g" "$invalid" ;;
    version) sed -i '' 's#<sparkle:version>2</sparkle:version>#<sparkle:version>1</sparkle:version>#' "$invalid" ;;
    url) sed -i '' 's#https://github.com#http://example.invalid#g' "$invalid" ;;
    length) sed -i '' 's/length="222"/length="0"/' "$invalid" ;;
    minimum-os) sed -i '' 's/>14.0.0</>13.9.0</g' "$invalid" ;;
  esac
  if python3 "$APPCAST_VALIDATOR" "$invalid" >/dev/null 2>&1; then
    echo "Appcast validator accepted invalid $field." >&2
    exit 1
  fi
done
echo "PASS: appcast validation covers every item's signature, version, URL, length, and minimum OS"

mkdir -p "$APP/Contents/MacOS"
cat > "$TMP/app-main.c" <<'C'
int main(void) { return 0; }
C
xcrun clang -arch arm64 -mmacosx-version-min=14.0 "$TMP/app-main.c" -o "$TMP/app-main-arm64"
xcrun clang -arch x86_64 -mmacosx-version-min=14.0 "$TMP/app-main.c" -o "$TMP/app-main-x86_64"
lipo -create "$TMP/app-main-arm64" "$TMP/app-main-x86_64" \
  -output "$APP/Contents/MacOS/Abendrot"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>42</string>
  <key>CFBundleIdentifier</key><string>app.abendrot.Abendrot</string>
  <key>CFBundleExecutable</key><string>Abendrot</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>SUFeedURL</key><string>https://example.invalid/appcast.xml</string>
  <key>SUPublicEDKey</key><string>test-public-key</string>
</dict></plist>
PLIST
printf '<sparkle:version>42</sparkle:version>\n' > "$APPCAST"

EARLY_SIGN_BIN="$TMP/early-sign-bin"
mkdir -p "$EARLY_SIGN_BIN"
cat > "$EARLY_SIGN_BIN/codesign" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *"--verify"*)
    [ "${MOCK_CODESIGN_VERIFY_FAIL:-0}" = "0" ] || exit 1
    ;;
  *"-dv"*|*" -d "*)
    if [ "${MOCK_CODESIGN_NO_AUTHORITY:-0}" = "0" ]; then
      printf 'Authority=%s\n' "${MOCK_CODESIGN_AUTHORITY:?}" >&2
    fi
    if [ "${MOCK_CODESIGN_VERBOSE_TAIL:-0}" = "1" ]; then
      for ((i = 0; i < 4096; i++)); do
        printf 'Detail%04d=verbose codesign output\n' "$i" >&2
      done
    fi
    ;;
esac
exit 0
SH
chmod 755 "$EARLY_SIGN_BIN/codesign"

make_fake_release_root() {
  local fake="$1"
  local origin="$fake-origin.git"
  mkdir -p "$fake/scripts/release"
  cp "$ROOT/scripts/release/release.sh" "$fake/scripts/release/release.sh"
  cp "$ROOT/scripts/release/validate-appcast.py" "$fake/scripts/release/validate-appcast.py"
  cat > "$fake/scripts/release/verify-public-snapshot.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "${VERIFY_PUBLIC_SNAPSHOT_LOG:?}"
[ "${VERIFY_PUBLIC_SNAPSHOT_FAIL:-0}" = "0" ]
SH
  chmod 755 "$fake/scripts/release/verify-public-snapshot.sh"
  git init -q -b dev "$fake"
  git -C "$fake" config user.name "Release Guard Test"
  git -C "$fake" config user.email "release-guard@example.invalid"
  git -C "$fake" add scripts/release/release.sh
  git -C "$fake" add scripts/release/validate-appcast.py
  git -C "$fake" add scripts/release/verify-public-snapshot.sh
  git -C "$fake" commit -qm "test: seed release script"
  git init --bare -q "$origin"
  git -C "$fake" remote add origin "$origin"
  git -C "$fake" push -q origin HEAD:refs/heads/dev
}

write_mock_gh() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
target="${GH_TARGET_SHA:?}"
main="${GH_MAIN_SHA:-$target}"
dev="${GH_DEV_SHA:-}"
if [ "${1:-}" = "api" ]; then
  path="${2:-}"
  case "$path" in
    repos/matthewrball/abendrot/commits/*)
      sha="${path##*/}"
      [ "$sha" = "$target" ] || exit 1
      if [ "${4:-}" = ".commit.message" ]; then
        printf '%s\n' "${GH_COMMIT_MESSAGE:-}"
        exit 0
      fi
      printf '%s\n' "$target"
      ;;
    repos/matthewrball/abendrot/git/ref/heads/main)
      printf '%s\n' "$main"
      ;;
    repos/matthewrball/abendrot/git/ref/heads/public-dev)
      [ -n "$dev" ] || exit 1
      printf '%s\n' "$dev"
      ;;
    repos/matthewrball/abendrot/git/ref/tags/v1.0.0)
      if [ "${GH_TAG_EXISTS:-0}" != "1" ]; then
        printf '%s\n' '{"message":"Not Found","status":"404"}'
        exit 1
      fi
      printf '%s\n' "$target"
      ;;
    *)
      echo "unexpected gh api path: $path" >&2
      exit 2
      ;;
  esac
  exit 0
fi
if [ "${1:-}" = "release" ] && [ "${2:-}" = "create" ]; then
  printf '%s\n' "$*" > "${GH_RELEASE_LOG:?}"
  exit 0
fi
echo "unexpected gh invocation: $*" >&2
exit 2
SH
  chmod 755 "$dir/gh"
}

write_canonical_appcast() {
  local path="$1"
  cat > "$path" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Abendrot</title>
    <link>https://raw.githubusercontent.com/matthewrball/abendrot/main/appcast.xml</link>
    <language>en</language>
    <!-- release.sh inserts new <item> elements directly below this line. -->
  </channel>
</rss>
XML
}

FAKE_ROOT="$TMP/fake-release-root"
make_fake_release_root "$FAKE_ROOT"
MOCK_GH="$TMP/mock-gh"
write_mock_gh "$MOCK_GH"
TARGET_MAIN="1111111111111111111111111111111111111111"
TARGET_DEV="2222222222222222222222222222222222222222"
TARGET_OTHER="3333333333333333333333333333333333333333"
FAKE_HEAD="$(git -C "$FAKE_ROOT" rev-parse HEAD)"
export VERIFY_PUBLIC_SNAPSHOT_LOG="$TMP/verify-public-snapshot.log"
/usr/bin/plutil -insert AbendrotSourceCommit -string "$FAKE_HEAD" \
  "$APP/Contents/Info.plist"

set +e
/usr/bin/plutil -replace AbendrotSourceCommit -string "$TARGET_OTHER" \
  "$APP/Contents/Info.plist"
PATH="$EARLY_SIGN_BIN:$MOCK_GH:$PATH" DEVELOPER_ID_APP="$MOCK_DEVELOPER_ID_APP" \
  MOCK_CODESIGN_AUTHORITY="$MOCK_DEVELOPER_ID_APP" \
  RELEASE_PUBLISH=1 RELEASE_TARGET_SHA="$TARGET_MAIN" \
  GH_TARGET_SHA="$TARGET_MAIN" GH_MAIN_SHA="$TARGET_MAIN" \
  "$FAKE_ROOT/scripts/release/release.sh" --app "$APP" \
  >/dev/null 2>"$TMP/stale-app-stderr"
rc=$?
set -e
[ "$rc" -eq 9 ]
grep -qF "exported app was not built from this audited source commit" "$TMP/stale-app-stderr"
echo "PASS: publishing refuses a stale exported app bundle"
/usr/bin/plutil -replace AbendrotSourceCommit -string "$FAKE_HEAD" \
  "$APP/Contents/Info.plist"

set +e
PATH="$EARLY_SIGN_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
  DEVELOPER_ID_APP="$MOCK_DEVELOPER_ID_APP" \
  MOCK_CODESIGN_AUTHORITY="$MOCK_DEVELOPER_ID_APP" \
  RELEASE_PUBLISH=1 RELEASE_TARGET_SHA="$TARGET_MAIN" \
  "$FAKE_ROOT/scripts/release/release.sh" --app "$APP" \
  >/dev/null 2>"$TMP/no-gh-stderr"
rc=$?
set -e
[ "$rc" -eq 9 ]
grep -qF "RELEASE_PUBLISH=1 requires the gh CLI" "$TMP/no-gh-stderr"
echo "PASS: publishing fails closed when gh is unavailable"

set +e
PATH="$EARLY_SIGN_BIN:$MOCK_GH:$PATH" DEVELOPER_ID_APP="$MOCK_DEVELOPER_ID_APP" \
  MOCK_CODESIGN_AUTHORITY="$MOCK_DEVELOPER_ID_APP" \
  RELEASE_PUBLISH=1 \
  "$FAKE_ROOT/scripts/release/release.sh" --app "$APP" \
  >/dev/null 2>"$TMP/no-target-stderr"
rc=$?
set -e
[ "$rc" -eq 9 ]
grep -qF "RELEASE_TARGET_SHA must be the exact 40-char curated public commit SHA" "$TMP/no-target-stderr"
echo "PASS: publishing requires an explicit curated public release target"

set +e
PATH="$EARLY_SIGN_BIN:$MOCK_GH:$PATH" DEVELOPER_ID_APP="$MOCK_DEVELOPER_ID_APP" \
  MOCK_CODESIGN_AUTHORITY="$MOCK_DEVELOPER_ID_APP" \
  RELEASE_PUBLISH=1 RELEASE_TARGET_SHA="$TARGET_OTHER" \
  GH_TARGET_SHA="$TARGET_OTHER" GH_MAIN_SHA="$TARGET_MAIN" GH_DEV_SHA="$TARGET_DEV" \
  "$FAKE_ROOT/scripts/release/release.sh" --app "$APP" \
  >/dev/null 2>"$TMP/bad-target-stderr"
rc=$?
set -e
[ "$rc" -eq 9 ]
grep -qF "stable releases must target the curated public main SHA" "$TMP/bad-target-stderr"
echo "PASS: stable release target must be the curated public main SHA"

set +e
PATH="$EARLY_SIGN_BIN:$MOCK_GH:$PATH" DEVELOPER_ID_APP="$MOCK_DEVELOPER_ID_APP" \
  MOCK_CODESIGN_AUTHORITY="$MOCK_DEVELOPER_ID_APP" \
  RELEASE_PUBLISH=1 RELEASE_TARGET_SHA="$TARGET_MAIN" \
  GH_TARGET_SHA="$TARGET_MAIN" GH_MAIN_SHA="$TARGET_MAIN" GH_TAG_EXISTS=1 \
  GH_COMMIT_MESSAGE=$'sync from build\n\nSource-Build-Commit: '"$FAKE_HEAD" \
  "$FAKE_ROOT/scripts/release/release.sh" --app "$APP" \
  >/dev/null 2>"$TMP/stale-tag-stderr"
rc=$?
set -e
[ "$rc" -eq 9 ]
grep -qF "remote tag v1.0.0 already exists" "$TMP/stale-tag-stderr"
echo "PASS: publishing refuses an existing stale release tag"

set +e
cp "$APPCAST" "$TMP/unsigned-publish-appcast-before.xml"
rm -f "$TMP/unsigned-gh-release.log"
PATH="$EARLY_SIGN_BIN:$MOCK_GH:$PATH" \
  RELEASE_PUBLISH=1 RELEASE_TARGET_SHA="$TARGET_MAIN" \
  GH_TARGET_SHA="$TARGET_MAIN" GH_MAIN_SHA="$TARGET_MAIN" \
  GH_COMMIT_MESSAGE="sync without source trailer" \
  GH_RELEASE_LOG="$TMP/unsigned-gh-release.log" APPCAST_PATH="$APPCAST" \
  "$FAKE_ROOT/scripts/release/release.sh" --app "$APP" --unsigned \
  >/dev/null 2>"$TMP/unsigned-publish-stderr"
rc=$?
set -e
[ "$rc" -eq 9 ]
grep -qF -- "--unsigned is private/local dry-run packaging only" \
  "$TMP/unsigned-publish-stderr"
cmp "$TMP/unsigned-publish-appcast-before.xml" "$APPCAST"
[ ! -e "$TMP/unsigned-gh-release.log" ]
echo "PASS: unsigned publish/upload mode is rejected before gh and leaves appcast unchanged"

set +e
PATH="$EARLY_SIGN_BIN:$MOCK_GH:$PATH" DEVELOPER_ID_APP="$MOCK_DEVELOPER_ID_APP" \
  MOCK_CODESIGN_AUTHORITY="$MOCK_DEVELOPER_ID_APP" \
  RELEASE_PUBLISH=1 RELEASE_TARGET_SHA="$TARGET_MAIN" \
  GH_TARGET_SHA="$TARGET_MAIN" GH_MAIN_SHA="$TARGET_MAIN" \
  GH_COMMIT_MESSAGE="sync without source trailer" \
  "$FAKE_ROOT/scripts/release/release.sh" --app "$APP" \
  >/dev/null 2>"$TMP/missing-trailer-stderr"
rc=$?
set -e
[ "$rc" -eq 9 ]
grep -qF "must contain exactly one Source-Build-Commit" \
  "$TMP/missing-trailer-stderr"
echo "PASS: stable publishing requires a public target source-build trailer"

set +e
PATH="$EARLY_SIGN_BIN:$MOCK_GH:$PATH" DEVELOPER_ID_APP="$MOCK_DEVELOPER_ID_APP" \
  MOCK_CODESIGN_AUTHORITY="$MOCK_DEVELOPER_ID_APP" \
  RELEASE_PUBLISH=1 RELEASE_TARGET_SHA="$TARGET_MAIN" \
  GH_TARGET_SHA="$TARGET_MAIN" GH_MAIN_SHA="$TARGET_MAIN" \
  GH_COMMIT_MESSAGE=$'sync from build\n\nSource-Build-Commit: '"$FAKE_HEAD"$'\nSource-Build-Commit: '"$TARGET_OTHER" \
  "$FAKE_ROOT/scripts/release/release.sh" --app "$APP" \
  >/dev/null 2>"$TMP/duplicate-trailer-stderr"
rc=$?
set -e
[ "$rc" -eq 9 ]
grep -qF "must contain exactly one Source-Build-Commit" "$TMP/duplicate-trailer-stderr"
echo "PASS: stable publishing rejects duplicate source-build trailers"

FAKE_ORIGIN="$(git -C "$FAKE_ROOT" remote get-url origin)"
UNRELATED_SOURCE="$TMP/unrelated-source"
git init -q -b dev "$UNRELATED_SOURCE"
git -C "$UNRELATED_SOURCE" config user.name "Release Guard Test"
git -C "$UNRELATED_SOURCE" config user.email "release-guard@example.invalid"
printf 'unrelated\n' > "$UNRELATED_SOURCE/unrelated.txt"
git -C "$UNRELATED_SOURCE" add unrelated.txt
git -C "$UNRELATED_SOURCE" commit -qm "test: unrelated source dev"
git -C "$UNRELATED_SOURCE" remote add origin "$FAKE_ORIGIN"
git -C "$UNRELATED_SOURCE" push -q --force origin HEAD:refs/heads/dev
set +e
PATH="$EARLY_SIGN_BIN:$MOCK_GH:$PATH" DEVELOPER_ID_APP="$MOCK_DEVELOPER_ID_APP" \
  MOCK_CODESIGN_AUTHORITY="$MOCK_DEVELOPER_ID_APP" \
  RELEASE_PUBLISH=1 RELEASE_TARGET_SHA="$TARGET_MAIN" \
  GH_TARGET_SHA="$TARGET_MAIN" GH_MAIN_SHA="$TARGET_MAIN" \
  GH_COMMIT_MESSAGE=$'sync from build\n\nSource-Build-Commit: '"$FAKE_HEAD" \
  "$FAKE_ROOT/scripts/release/release.sh" --app "$APP" \
  >/dev/null 2>"$TMP/unmerged-source-stderr"
rc=$?
set -e
[ "$rc" -eq 9 ]
grep -qF "audited source commit is not an ancestor of source origin/dev" "$TMP/unmerged-source-stderr"
git -C "$FAKE_ROOT" push -q --force origin "$FAKE_HEAD":refs/heads/dev
echo "PASS: stable publishing rejects audited source commits not merged to source origin/dev"

set +e
PATH="$EARLY_SIGN_BIN:$MOCK_GH:$PATH" DEVELOPER_ID_APP="$MOCK_DEVELOPER_ID_APP" \
  MOCK_CODESIGN_AUTHORITY="$MOCK_DEVELOPER_ID_APP" \
  RELEASE_PUBLISH=1 RELEASE_TARGET_SHA="$TARGET_MAIN" \
  GH_TARGET_SHA="$TARGET_MAIN" GH_MAIN_SHA="$TARGET_MAIN" \
  GH_COMMIT_MESSAGE=$'sync from build\n\nSource-Build-Commit: '"$FAKE_HEAD" \
  "$FAKE_ROOT/scripts/release/release.sh" --app "$APP" \
  >"$TMP/good-trailer-out" 2>"$TMP/good-trailer-stderr"
rc=$?
set -e
[ "$rc" -eq 6 ]
grep -qF "verified curated public release target $TARGET_MAIN" "$TMP/good-trailer-out"
grep -qF "SUPublicEDKey must decode to exactly 32 bytes" "$TMP/good-trailer-stderr"
echo "PASS: stable publishing accepts the exact source-build trailer before later gates"

DIRTY_MARKER="$ROOT/.release-guard-dirty.$$"
: > "$DIRTY_MARKER"
set +e
PATH="$EARLY_SIGN_BIN:$PATH" DEVELOPER_ID_APP="$MOCK_DEVELOPER_ID_APP" \
  MOCK_CODESIGN_AUTHORITY="$MOCK_DEVELOPER_ID_APP" \
  RELEASE_PUBLISH=1 APPCAST_PATH="$APPCAST" "$ROOT/scripts/release/release.sh" \
  --app "$APP" >/dev/null 2>"$TMP/dirty-stderr"
rc=$?
set -e
[ "$rc" -eq 9 ]
grep -qF "publishing requires a clean committed source tree" "$TMP/dirty-stderr"
rm -f "$DIRTY_MARKER"
DIRTY_MARKER=""
echo "PASS: publishing rejects an uncommitted source tree"

/usr/bin/plutil -replace CFBundleShortVersionString -string "../../escape" \
  "$APP/Contents/Info.plist"
set +e
APPCAST_PATH="$APPCAST" "$ROOT/scripts/release/release.sh" \
  --app "$APP" --unsigned >/dev/null 2>"$TMP/version-stderr"
rc=$?
set -e
if [ "$rc" -ne 3 ]; then
  cat "$TMP/version-stderr" >&2
  exit 1
fi
grep -qF "unsafe or malformed marketing version" "$TMP/version-stderr"
echo "PASS: release version cannot escape the scratch path or inject appcast XML"
/usr/bin/plutil -replace CFBundleShortVersionString -string $'1.2.3\n../../escape' \
  "$APP/Contents/Info.plist"
set +e
APPCAST_PATH="$APPCAST" "$ROOT/scripts/release/release.sh" \
  --app "$APP" --unsigned >/dev/null 2>"$TMP/multiline-version-stderr"
rc=$?
set -e
[ "$rc" -eq 3 ]
grep -qF "unsafe or malformed marketing version" "$TMP/multiline-version-stderr"
echo "PASS: multiline versions cannot bypass whole-value validation"
/usr/bin/plutil -replace CFBundleShortVersionString -string "1.0.0" \
  "$APP/Contents/Info.plist"

/usr/bin/plutil -replace CFBundleIdentifier -string "example.invalid.Abandrot" \
  "$APP/Contents/Info.plist"
set +e
APPCAST_PATH="$APPCAST" "$ROOT/scripts/release/release.sh" \
  --app "$APP" --unsigned >/dev/null 2>"$TMP/bundle-id-stderr"
rc=$?
set -e
[ "$rc" -eq 3 ]
grep -qF "CFBundleIdentifier must remain app.abendrot.Abendrot" "$TMP/bundle-id-stderr"
echo "PASS: releases preserve the user preferences and statistics domain"
/usr/bin/plutil -replace CFBundleIdentifier -string "app.abendrot.Abendrot" \
  "$APP/Contents/Info.plist"

set +e
APPCAST_PATH="$APPCAST" "$ROOT/scripts/release/release.sh" \
  --app "$APP" >/dev/null 2>"$TMP/key-stderr"
rc=$?
set -e
[ "$rc" -eq 5 ]
grep -qF "signed releases require DEVELOPER_ID_APP" "$TMP/key-stderr"
echo "PASS: signed releases require an explicit Developer ID Application authority"

set +e
PATH="$EARLY_SIGN_BIN:$PATH" DEVELOPER_ID_APP="Developer ID Application" \
  MOCK_CODESIGN_AUTHORITY="$MOCK_DEVELOPER_ID_APP" \
  APPCAST_PATH="$APPCAST" RELEASE_SCRATCH="$TMP/broad-identity-release" \
  "$ROOT/scripts/release/release.sh" \
  --app "$APP" >/dev/null 2>"$TMP/broad-identity-stderr"
rc=$?
set -e
[ "$rc" -eq 5 ]
grep -qF "DEVELOPER_ID_APP must be the exact full leaf authority string" \
  "$TMP/broad-identity-stderr"
[ ! -e "$TMP/broad-identity-release" ]
echo "PASS: signed releases reject a broad Developer ID identity selector"

set +e
PATH="$EARLY_SIGN_BIN:$PATH" DEVELOPER_ID_APP="$MOCK_DEVELOPER_ID_APP" \
  MOCK_CODESIGN_VERIFY_FAIL=1 MOCK_CODESIGN_AUTHORITY="$MOCK_DEVELOPER_ID_APP" \
  APPCAST_PATH="$APPCAST" RELEASE_SCRATCH="$TMP/bad-input-signature-release" \
  "$ROOT/scripts/release/release.sh" \
  --app "$APP" >/dev/null 2>"$TMP/bad-input-signature-stderr"
rc=$?
set -e
[ "$rc" -eq 5 ]
grep -qF "exported app signature is invalid before release packaging" \
  "$TMP/bad-input-signature-stderr"
[ ! -e "$TMP/bad-input-signature-release" ]
echo "PASS: signed releases verify the exported app before packaging"

set +e
PATH="$EARLY_SIGN_BIN:$PATH" DEVELOPER_ID_APP="$MOCK_DEVELOPER_ID_APP" \
  MOCK_CODESIGN_NO_AUTHORITY=1 \
  APPCAST_PATH="$APPCAST" RELEASE_SCRATCH="$TMP/missing-authority-release" \
  "$ROOT/scripts/release/release.sh" \
  --app "$APP" >/dev/null 2>"$TMP/missing-authority-stderr"
rc=$?
set -e
[ "$rc" -eq 5 ]
grep -qF "could not read exported app signing authority" "$TMP/missing-authority-stderr"
[ ! -e "$TMP/missing-authority-release" ]
echo "PASS: signed releases diagnose missing exported-app signing authority"

set +e
PATH="$EARLY_SIGN_BIN:$PATH" DEVELOPER_ID_APP="$MOCK_DEVELOPER_ID_APP" \
  MOCK_CODESIGN_AUTHORITY="Developer ID Application: Other Test (ZZZZZ99999)" \
  APPCAST_PATH="$APPCAST" RELEASE_SCRATCH="$TMP/authority-mismatch-release" \
  "$ROOT/scripts/release/release.sh" \
  --app "$APP" >/dev/null 2>"$TMP/authority-mismatch-stderr"
rc=$?
set -e
[ "$rc" -eq 5 ]
grep -qF "exported app signing authority does not match DEVELOPER_ID_APP" \
  "$TMP/authority-mismatch-stderr"
[ ! -e "$TMP/authority-mismatch-release" ]
echo "PASS: signed releases reject exported apps signed by another authority"

set +e
PATH="$EARLY_SIGN_BIN:$PATH" DEVELOPER_ID_APP="$MOCK_DEVELOPER_ID_APP" \
  MOCK_CODESIGN_AUTHORITY="$MOCK_DEVELOPER_ID_APP" \
  MOCK_CODESIGN_VERBOSE_TAIL=1 \
  APPCAST_PATH="$APPCAST" "$ROOT/scripts/release/release.sh" \
  --app "$APP" >/dev/null 2>"$TMP/key-stderr"
rc=$?
set -e
[ "$rc" -eq 6 ]
grep -qF "SUPublicEDKey must decode to exactly 32 bytes" "$TMP/key-stderr"
echo "PASS: signed releases verify app identity before later Sparkle gates"
echo "PASS: signed releases tolerate verbose codesign authority output under pipefail"
echo "PASS: signed releases reject malformed Sparkle public keys"

TEST_PUBLIC_KEY="$(printf '%032d' 0 | /usr/bin/base64)"
/usr/bin/plutil -replace SUPublicEDKey -string "$TEST_PUBLIC_KEY" \
  "$APP/Contents/Info.plist"
set +e
PATH="$EARLY_SIGN_BIN:$PATH" DEVELOPER_ID_APP="$MOCK_DEVELOPER_ID_APP" \
  MOCK_CODESIGN_AUTHORITY="$MOCK_DEVELOPER_ID_APP" \
  APPCAST_PATH="$APPCAST" "$ROOT/scripts/release/release.sh" \
  --app "$APP" >/dev/null 2>"$TMP/feed-stderr"
rc=$?
set -e
[ "$rc" -eq 6 ]
grep -qF "SUFeedURL must be exactly" "$TMP/feed-stderr"
echo "PASS: signed releases require the canonical Sparkle feed"

/usr/bin/plutil -replace SUFeedURL \
  -string "https://raw.githubusercontent.com/matthewrball/abendrot/main/appcast.xml" \
  "$APP/Contents/Info.plist"
set +e
PATH="$EARLY_SIGN_BIN:$PATH" DEVELOPER_ID_APP="$MOCK_DEVELOPER_ID_APP" \
  MOCK_CODESIGN_AUTHORITY="$MOCK_DEVELOPER_ID_APP" \
  APPCAST_PATH="$APPCAST" "$ROOT/scripts/release/release.sh" \
  --app "$APP" >/dev/null 2>"$TMP/stderr"
rc=$?
set -e

if [ "$rc" -ne 7 ]; then
  cat "$TMP/stderr" >&2
  exit 1
fi
grep -qF "ABORT — build number 42 does not exceed appcast build 42" "$TMP/stderr"
echo "PASS: duplicate Sparkle build is rejected before packaging"

/usr/bin/plutil -replace CFBundleVersion -string "41" "$APP/Contents/Info.plist"
set +e
PATH="$EARLY_SIGN_BIN:$PATH" DEVELOPER_ID_APP="$MOCK_DEVELOPER_ID_APP" \
  MOCK_CODESIGN_AUTHORITY="$MOCK_DEVELOPER_ID_APP" \
  APPCAST_PATH="$APPCAST" "$ROOT/scripts/release/release.sh" \
  --app "$APP" >/dev/null 2>"$TMP/lower-stderr"
rc=$?
set -e
if [ "$rc" -ne 7 ]; then
  cat "$TMP/lower-stderr" >&2
  exit 1
fi
grep -qF "ABORT — build number 41 does not exceed appcast build 42" "$TMP/lower-stderr"
echo "PASS: decreasing Sparkle build is rejected before packaging"

/usr/bin/plutil -replace CFBundleVersion -string "43" "$APP/Contents/Info.plist"
/usr/bin/plutil -replace SUFeedURL -string "http://example.invalid/appcast.xml" \
  "$APP/Contents/Info.plist"
printf '<rss><channel><language>en</language></channel></rss>\n' > "$APPCAST"
set +e
PATH="$EARLY_SIGN_BIN:$PATH" DEVELOPER_ID_APP="$MOCK_DEVELOPER_ID_APP" \
  MOCK_CODESIGN_AUTHORITY="$MOCK_DEVELOPER_ID_APP" \
  APPCAST_PATH="$APPCAST" "$ROOT/scripts/release/release.sh" \
  --app "$APP" >/dev/null 2>"$TMP/http-stderr"
rc=$?
set -e
if [ "$rc" -ne 6 ]; then
  cat "$TMP/http-stderr" >&2
  exit 1
fi
grep -qF "SUFeedURL must be exactly" "$TMP/http-stderr"
echo "PASS: signed releases reject a noncanonical update feed"

/usr/bin/plutil -replace SUFeedURL \
  -string "https://raw.githubusercontent.com/matthewrball/abendrot/main/appcast.xml" \
  "$APP/Contents/Info.plist"
cp "$APPCAST" "$TMP/appcast-before.xml"
set +e
ASC_API_KEY_P8= ASC_API_KEY_ID= ASC_API_ISSUER_ID= \
APPCAST_PATH="$APPCAST" RELEASE_SCRATCH="$TMP/release" \
  "$ROOT/scripts/release/release.sh" \
  --app "$APP" --unsigned --dmg-mode plain >"$TMP/unsigned-out" 2>"$TMP/unsigned-stderr"
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  cat "$TMP/unsigned-stderr" >&2
  exit "$rc"
fi
cmp "$TMP/appcast-before.xml" "$APPCAST"
lipo "$APP/Contents/Helpers/abendrot" \
  -verify_arch $(lipo -archs "$APP/Contents/MacOS/Abendrot")
echo "PASS: unsigned builds cannot modify the production appcast"
echo "PASS: embedded CLI covers every app architecture"
grep -qF "verified every shipped Mach-O slice targets macOS 14.0 or earlier" \
  "$TMP/unsigned-out"

/usr/bin/plutil -replace LSMinimumSystemVersion -string "15.0" "$APP/Contents/Info.plist"
set +e
APPCAST_PATH="$APPCAST" RELEASE_SCRATCH="$TMP/wrong-plist-floor" \
  "$ROOT/scripts/release/release.sh" \
  --app "$APP" --unsigned --dmg-mode plain >/dev/null 2>"$TMP/wrong-plist-floor-stderr"
rc=$?
set -e
[ "$rc" -eq 3 ]
grep -qF "LSMinimumSystemVersion must be 14.0" "$TMP/wrong-plist-floor-stderr"
/usr/bin/plutil -replace LSMinimumSystemVersion -string "14.0" "$APP/Contents/Info.plist"
echo "PASS: release packaging rejects an app that overstates its supported OS floor"

mkdir -p "$APP/Contents/Frameworks"
xcrun clang -arch arm64 -mmacosx-version-min=15.0 "$TMP/app-main.c" \
  -o "$APP/Contents/Frameworks/TooNew"
set +e
APPCAST_PATH="$APPCAST" RELEASE_SCRATCH="$TMP/too-new-nested-code" \
  "$ROOT/scripts/release/release.sh" \
  --app "$APP" --unsigned --dmg-mode plain >/dev/null 2>"$TMP/too-new-nested-stderr"
rc=$?
set -e
[ "$rc" -eq 5 ]
grep -qF "contains a slice requiring newer than macOS 14.0" \
  "$TMP/too-new-nested-stderr"
rm -f "$APP/Contents/Frameworks/TooNew"
echo "PASS: release packaging rejects too-new nested Mach-O slices"

MOCK_SIGNED_BIN="$TMP/mock-signed-bin"
MOCK_SPARKLE="$TMP/mock-sparkle-tools"
MOCK_SWIFT_BUILD="$TMP/mock-swift-build"
mkdir -p "$MOCK_SIGNED_BIN" "$MOCK_SPARKLE" "$MOCK_SWIFT_BUILD"
cat > "$MOCK_SIGNED_BIN/codesign" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *"--verify"*)
    [ "${MOCK_CODESIGN_VERIFY_FAIL:-0}" = "0" ] || exit 1
    ;;
  *"-dv"*|*" -d "*)
    printf 'Authority=%s\n' "${MOCK_CODESIGN_AUTHORITY:?}" >&2
    ;;
esac
exit 0
SH
cat > "$MOCK_SIGNED_BIN/spctl" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "$MOCK_SIGNED_BIN/hdiutil" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  create)
    out="${@: -1}"
    printf 'mock dmg\n' > "$out"
    ;;
  attach)
    mount=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -mountpoint) mount="${2:-}"; shift 2 ;;
        *) shift;;
      esac
    done
    mkdir -p "$mount/Abendrot.app"
    ;;
  detach)
    ;;
  *)
    echo "unexpected hdiutil invocation: $*" >&2
    exit 2
    ;;
esac
SH
cat > "$MOCK_SIGNED_BIN/xcrun" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  stapler)
    if [ -n "${MOCK_STAPLER_ARG_LOG:-}" ]; then
      printf '%s\n' "$*" >> "$MOCK_STAPLER_ARG_LOG"
    fi
    # Simulate an app bundle that cannot carry a ticket, without disturbing the
    # DMG's own staple/validate behavior.
    case "${@: -1}" in
      *.app) [ "${MOCK_STAPLER_APP_FAIL:-0}" = "0" ] || exit 1;;
    esac
    exit 0
    ;;
  notarytool)
    if [ -n "${MOCK_NOTARYTOOL_ARG_LOG:-}" ]; then
      printf '%s\n' "$*" >> "$MOCK_NOTARYTOOL_ARG_LOG"
    fi
    case "${2:-}" in
      submit)
        cat <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>status</key><string>Accepted</string>
  <key>id</key><string>MOCK-NOTARY-ID</string>
</dict></plist>
PLIST
        ;;
      log)
        echo "mock notary log"
        ;;
      *)
        echo "unexpected notarytool invocation: $*" >&2
        exit 2
        ;;
    esac
    ;;
  *)
    echo "unexpected xcrun invocation: $*" >&2
    exit 2
    ;;
esac
SH
cat > "$MOCK_SIGNED_BIN/swift" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
show=""
triple=""
while [ $# -gt 0 ]; do
  case "$1" in
    --show-bin-path) show=1; shift ;;
    --triple) triple="${2:-}"; shift 2 ;;
    *) shift;;
  esac
done
[ -n "$triple" ] || triple="arm64-apple-macosx14.0"
arch="${triple%%-*}"
dir="${MOCK_SWIFT_BUILD_ROOT:?}/$triple"
if [ -n "$show" ]; then
  mkdir -p "$dir"
  printf '%s\n' "$dir"
  exit 0
fi
mkdir -p "$dir"
src="$dir/main.c"
printf 'int main(void) { return 0; }\n' > "$src"
/usr/bin/xcrun clang -arch "$arch" -mmacosx-version-min=14.0 "$src" -o "$dir/abendrot"
SH
chmod 755 "$MOCK_SIGNED_BIN/"*

MOCK_NOTARY_DMG="$TMP/mock-notary.dmg"
printf 'mock dmg\n' > "$MOCK_NOTARY_DMG"
set +e
PATH="$MOCK_SIGNED_BIN:$PATH" \
  NOTARY_KEYCHAIN_PROFILE=abendrot-notary ASC_API_KEY_ID=MOCKKEY \
  "$NOTARIZE_SCRIPT" "$MOCK_NOTARY_DMG" \
  >/dev/null 2>"$TMP/notary-mixed-profile-stderr"
rc=$?
set -e
[ "$rc" -eq 2 ]
grep -qF "NOTARY_KEYCHAIN_PROFILE cannot be combined with ASC API-key credentials" \
  "$TMP/notary-mixed-profile-stderr"
echo "PASS: notarization profile mode rejects mixed ASC API-key credentials"

MOCK_NOTARY_ARGS="$TMP/notarytool-profile-args.log"
set +e
PATH="$MOCK_SIGNED_BIN:$PATH" MOCK_NOTARYTOOL_ARG_LOG="$MOCK_NOTARY_ARGS" \
  NOTARY_KEYCHAIN_PROFILE=abendrot-notary \
  NOTARY_KEYCHAIN="$TMP/mock-notary.keychain-db" \
  "$NOTARIZE_SCRIPT" "$MOCK_NOTARY_DMG" \
  >"$TMP/notary-profile-out" 2>"$TMP/notary-profile-stderr"
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  cat "$TMP/notary-profile-stderr" >&2
  exit "$rc"
fi
grep -qF "notarytool submit $MOCK_NOTARY_DMG --keychain-profile abendrot-notary --keychain $TMP/mock-notary.keychain-db --wait --output-format plist" \
  "$MOCK_NOTARY_ARGS"
grep -qF "notarytool log MOCK-NOTARY-ID --keychain-profile abendrot-notary --keychain $TMP/mock-notary.keychain-db" \
  "$MOCK_NOTARY_ARGS"
echo "PASS: notarization profile mode uses identical notarytool submit/log auth args"

MOCK_APP_NOTARY_ARGS="$TMP/notarytool-app-args.log"
MOCK_APP_STAPLER_ARGS="$TMP/stapler-app-args.log"
MOCK_NOTARY_APP="$TMP/mock-notary-Abendrot.app"
mkdir -p "$MOCK_NOTARY_APP/Contents/MacOS"
printf 'mock binary\n' > "$MOCK_NOTARY_APP/Contents/MacOS/Abendrot"
set +e
PATH="$MOCK_SIGNED_BIN:$PATH" MOCK_NOTARYTOOL_ARG_LOG="$MOCK_APP_NOTARY_ARGS" \
  MOCK_STAPLER_ARG_LOG="$MOCK_APP_STAPLER_ARGS" \
  NOTARY_KEYCHAIN_PROFILE=abendrot-notary \
  "$NOTARIZE_SCRIPT" "$MOCK_NOTARY_APP" --app-bundle \
  >"$TMP/notary-app-mode-out" 2>"$TMP/notary-app-mode-stderr"
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  cat "$TMP/notary-app-mode-stderr" >&2
  exit "$rc"
fi
grep -qE \
  'notarytool submit .*/mock-notary-Abendrot\.app\.zip --keychain-profile abendrot-notary --wait --output-format plist' \
  "$MOCK_APP_NOTARY_ARGS"
grep -qF "staple $MOCK_NOTARY_APP" "$MOCK_APP_STAPLER_ARGS"
grep -qF "validate $MOCK_NOTARY_APP" "$MOCK_APP_STAPLER_ARGS"
grep -qF "notarized, stapled, and Gatekeeper-accepted" "$TMP/notary-app-mode-out"
echo "PASS: app-bundle notarization submits a ditto zip and staples the .app itself"

cat > "$MOCK_SPARKLE/sign_update" <<'SH'
#!/usr/bin/env bash
signature="$(head -c 64 /dev/zero | /usr/bin/base64)"
printf 'sparkle:edSignature="%s" length="%s"\n' "$signature" "$(stat -f%z "$1")"
SH
cat > "$MOCK_SPARKLE/generate_keys" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = "-p" ] || exit 2
printf '%s\n' "${MOCK_SPARKLE_PUBLIC_KEY:?}"
SH
chmod 755 "$MOCK_SPARKLE/"*

printf 'mock asc key\n' > "$TMP/mock-asc.p8"
/usr/bin/plutil -replace CFBundleVersion -string "44" "$APP/Contents/Info.plist"
/usr/bin/plutil -replace SUFeedURL -string "$CANONICAL_FEED" "$APP/Contents/Info.plist"
write_canonical_appcast "$APPCAST"

MISMATCH_PUBLIC_KEY="$(printf '%032d' 1 | /usr/bin/base64)"
set +e
PATH="$MOCK_SIGNED_BIN:$PATH" DEVELOPER_ID_APP="$MOCK_DEVELOPER_ID_APP" \
  MOCK_CODESIGN_AUTHORITY="$MOCK_DEVELOPER_ID_APP" \
  MOCK_SWIFT_BUILD_ROOT="$MOCK_SWIFT_BUILD/mismatch" \
  MOCK_SPARKLE_PUBLIC_KEY="$MISMATCH_PUBLIC_KEY" \
  ASC_API_KEY_P8="$TMP/mock-asc.p8" ASC_API_KEY_ID=MOCKKEY ASC_API_ISSUER_ID=MOCKISSUER \
  APPCAST_PATH="$APPCAST" RELEASE_SCRATCH="$TMP/signed-mismatch" \
  SPARKLE_SIGN_UPDATE="$MOCK_SPARKLE/sign_update" \
  "$ROOT/scripts/release/release.sh" --app "$APP" --dmg-mode plain \
  >/dev/null 2>"$TMP/key-mismatch-stderr"
rc=$?
set -e
[ "$rc" -eq 5 ]
grep -qF "Sparkle keychain public key does not match embedded SUPublicEDKey" \
  "$TMP/key-mismatch-stderr"
echo "PASS: signed releases prove the keychain Sparkle key matches SUPublicEDKey"

cp "$APPCAST" "$TMP/signed-appcast-before.xml"
set +e
PATH="$MOCK_SIGNED_BIN:$PATH" DEVELOPER_ID_APP="$MOCK_DEVELOPER_ID_APP" \
  MOCK_CODESIGN_AUTHORITY="$MOCK_DEVELOPER_ID_APP" \
  MOCK_SWIFT_BUILD_ROOT="$MOCK_SWIFT_BUILD/pass" \
  MOCK_SPARKLE_PUBLIC_KEY="$TEST_PUBLIC_KEY" \
  ASC_API_KEY_P8="$TMP/mock-asc.p8" ASC_API_KEY_ID=MOCKKEY ASC_API_ISSUER_ID=MOCKISSUER \
  APPCAST_PATH="$APPCAST" RELEASE_SCRATCH="$TMP/signed-pass" \
  SPARKLE_SIGN_UPDATE="$MOCK_SPARKLE/sign_update" \
  "$ROOT/scripts/release/release.sh" --app "$APP" --dmg-mode plain \
  >"$TMP/key-pass-out" 2>"$TMP/key-pass-stderr"
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  cat "$TMP/key-pass-stderr" >&2
  exit "$rc"
fi
grep -qF "Sparkle keychain public key matches embedded SUPublicEDKey" "$TMP/key-pass-out"
cmp "$TMP/signed-appcast-before.xml" "$APPCAST"
grep -qF '<sparkle:version>44</sparkle:version>' "$TMP/signed-pass/appcast-1.0.0-44.xml"
grep -qF -- '--draft' "$TMP/key-pass-out"
echo "PASS: signed dry-runs keep production appcast unchanged and write a verified candidate"
echo "PASS: stable signed releases are uploaded as drafts before appcast staging"

# A signed release whose .app cannot carry a ticket must abort BEFORE the DMG is
# built, so no artifact is ever produced around an unstapled app.
set +e
PATH="$MOCK_SIGNED_BIN:$PATH" DEVELOPER_ID_APP="$MOCK_DEVELOPER_ID_APP" \
  MOCK_CODESIGN_AUTHORITY="$MOCK_DEVELOPER_ID_APP" \
  MOCK_SWIFT_BUILD_ROOT="$MOCK_SWIFT_BUILD/app-staple-fail" \
  MOCK_SPARKLE_PUBLIC_KEY="$TEST_PUBLIC_KEY" \
  MOCK_STAPLER_APP_FAIL=1 \
  ASC_API_KEY_P8="$TMP/mock-asc.p8" ASC_API_KEY_ID=MOCKKEY ASC_API_ISSUER_ID=MOCKISSUER \
  APPCAST_PATH="$APPCAST" RELEASE_SCRATCH="$TMP/app-staple-fail" \
  SPARKLE_SIGN_UPDATE="$MOCK_SPARKLE/sign_update" \
  "$ROOT/scripts/release/release.sh" --app "$APP" --dmg-mode plain \
  >/dev/null 2>"$TMP/app-staple-fail-stderr"
rc=$?
set -e
[ "$rc" -eq 4 ]
grep -qF "the .app is not notarized+stapled" "$TMP/app-staple-fail-stderr"
[ ! -e "$TMP/app-staple-fail" ]
echo "PASS: signed releases abort before packaging when the .app cannot be stapled"

/usr/bin/plutil -replace CFBundleVersion -string "45" "$APP/Contents/Info.plist"
write_canonical_appcast "$APPCAST"
cp "$APPCAST" "$TMP/prerelease-appcast-before.xml"
set +e
PATH="$MOCK_SIGNED_BIN:$PATH" DEVELOPER_ID_APP="$MOCK_DEVELOPER_ID_APP" \
  MOCK_CODESIGN_AUTHORITY="$MOCK_DEVELOPER_ID_APP" \
  MOCK_SWIFT_BUILD_ROOT="$MOCK_SWIFT_BUILD/prerelease" \
  MOCK_SPARKLE_PUBLIC_KEY="$TEST_PUBLIC_KEY" \
  ASC_API_KEY_P8="$TMP/mock-asc.p8" ASC_API_KEY_ID=MOCKKEY ASC_API_ISSUER_ID=MOCKISSUER \
  APPCAST_PATH="$APPCAST" RELEASE_SCRATCH="$TMP/signed-prerelease" \
  SPARKLE_SIGN_UPDATE="$MOCK_SPARKLE/sign_update" \
  "$ROOT/scripts/release/release.sh" --app "$APP" --dmg-mode plain --prerelease \
  >"$TMP/prerelease-out" 2>"$TMP/prerelease-stderr"
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  cat "$TMP/prerelease-stderr" >&2
  exit "$rc"
fi
cmp "$TMP/prerelease-appcast-before.xml" "$APPCAST"
[ -z "$(find "$TMP/signed-prerelease" -name 'appcast-*.xml' -print 2>/dev/null)" ]
grep -qF "signed pre-release — production appcast left unchanged" "$TMP/prerelease-out"
echo "PASS: signed pre-releases stay outside the stable appcast"

PUBLISH_ROOT="$TMP/publish-release-root"
make_fake_release_root "$PUBLISH_ROOT"
mkdir -p "$PUBLISH_ROOT/cli" "$PUBLISH_ROOT/scripts/dmg"
printf '// mock package\n' > "$PUBLISH_ROOT/cli/Package.swift"
cp "$ROOT/scripts/dmg/plain-dmg.sh" "$PUBLISH_ROOT/scripts/dmg/plain-dmg.sh"
cat > "$PUBLISH_ROOT/scripts/dmg/pretty-dmg.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "${1:-}" != "--check" ] || exit 0
out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) out="${2:-}"; shift 2 ;;
    *) shift;;
  esac
done
[ -n "$out" ]
printf 'mock branded dmg\n' > "$out"
SH
chmod 755 "$PUBLISH_ROOT/scripts/dmg/pretty-dmg.sh"
cp "$ROOT/scripts/release/notarize.sh" "$PUBLISH_ROOT/scripts/release/notarize.sh"
write_canonical_appcast "$PUBLISH_ROOT/appcast.xml"
git -C "$PUBLISH_ROOT" add cli/Package.swift scripts/dmg/plain-dmg.sh \
  scripts/dmg/pretty-dmg.sh \
  scripts/release/notarize.sh appcast.xml
git -C "$PUBLISH_ROOT" commit -qm "test: complete mocked release root"
PUBLISH_HEAD="$(git -C "$PUBLISH_ROOT" rev-parse HEAD)"
git -C "$PUBLISH_ROOT" push -q origin HEAD:refs/heads/dev

PUBLISH_APP="$TMP/publish-Abendrot.app"
cp -R "$APP" "$PUBLISH_APP"
/usr/bin/plutil -replace CFBundleVersion -string "46" "$PUBLISH_APP/Contents/Info.plist"
/usr/bin/plutil -replace AbendrotSourceCommit -string "$PUBLISH_HEAD" \
  "$PUBLISH_APP/Contents/Info.plist"
GH_RELEASE_LOG="$TMP/gh-release-create.log"
set +e
PATH="$MOCK_SIGNED_BIN:$MOCK_GH:$PATH" DEVELOPER_ID_APP="$MOCK_DEVELOPER_ID_APP" \
  MOCK_CODESIGN_AUTHORITY="$MOCK_DEVELOPER_ID_APP" \
  MOCK_SWIFT_BUILD_ROOT="$MOCK_SWIFT_BUILD/publish" \
  MOCK_SPARKLE_PUBLIC_KEY="$TEST_PUBLIC_KEY" \
  ASC_API_KEY_P8="$TMP/mock-asc.p8" ASC_API_KEY_ID=MOCKKEY ASC_API_ISSUER_ID=MOCKISSUER \
  RELEASE_PUBLISH=1 RELEASE_TARGET_SHA="$TARGET_MAIN" \
  GH_TARGET_SHA="$TARGET_MAIN" GH_MAIN_SHA="$TARGET_MAIN" \
  GH_COMMIT_MESSAGE=$'sync from build\n\nSource-Build-Commit: '"$PUBLISH_HEAD" \
  GH_RELEASE_LOG="$GH_RELEASE_LOG" VERIFY_PUBLIC_SNAPSHOT_LOG="$VERIFY_PUBLIC_SNAPSHOT_LOG" \
  RELEASE_SCRATCH="$TMP/signed-publish" \
  SPARKLE_SIGN_UPDATE="$MOCK_SPARKLE/sign_update" \
  "$PUBLISH_ROOT/scripts/release/release.sh" --app "$PUBLISH_APP" --dmg-mode pretty \
  >"$TMP/signed-publish-out" 2>"$TMP/signed-publish-stderr"
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  cat "$TMP/signed-publish-stderr" >&2
  exit "$rc"
fi
grep -qF -- '--draft' "$GH_RELEASE_LOG"
grep -qF "created draft v1.0.0" "$TMP/signed-publish-out"
grep -qF "Do NOT promote the appcast while the release asset is still private" \
  "$TMP/signed-publish-out"
grep -qF "Only then run scripts/publish.sh promote" "$TMP/signed-publish-out"
grep -qF '<sparkle:version>46</sparkle:version>' "$PUBLISH_ROOT/appcast.xml"
echo "PASS: stable publish stages appcast CI before release publication and feed promotion"

if [ -x "$ROOT/scripts/sync-public.sh" ]; then
  set +e
  "$ROOT/scripts/sync-public.sh" --dryrun >/dev/null 2>"$TMP/sync-stderr"
  rc=$?
  set -e
  [ "$rc" -eq 2 ]
  grep -qF "usage: sync-public.sh [--dry-run]" "$TMP/sync-stderr"
  echo "PASS: mistyped sync option cannot trigger a destructive real run"
else
  echo "SKIP: build-only sync-public.sh guard (not present in curated public source)"
fi

if [ -x "$ROOT/scripts/release/verify-public-snapshot.sh" ]; then
  SNAP_SRC="$TMP/snapshot-source"
  SNAP_PUBLIC="$TMP/snapshot-public"
  git init -q -b dev "$SNAP_SRC"
  git -C "$SNAP_SRC" config user.name "Release Guard Test"
  git -C "$SNAP_SRC" config user.email "release-guard@example.invalid"
  mkdir -p "$SNAP_SRC/scripts"
  cat > "$SNAP_SRC/scripts/sync-public.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
: "${BUILD:?}"
: "${PUBLIC:?}"
cp "$BUILD/app.txt" "$PUBLIC/app.txt"
SH
  chmod 755 "$SNAP_SRC/scripts/sync-public.sh"
  printf 'source\n' > "$SNAP_SRC/app.txt"
  git -C "$SNAP_SRC" add scripts/sync-public.sh app.txt
  git -C "$SNAP_SRC" commit -qm "test: source snapshot"
  SNAP_SRC_SHA="$(git -C "$SNAP_SRC" rev-parse HEAD)"

  git init -q -b main "$SNAP_PUBLIC"
  git -C "$SNAP_PUBLIC" config user.name "Release Guard Test"
  git -C "$SNAP_PUBLIC" config user.email "release-guard@example.invalid"
  printf 'source\n' > "$SNAP_PUBLIC/app.txt"
  printf 'public only\n' > "$SNAP_PUBLIC/LICENSE"
  git -C "$SNAP_PUBLIC" add app.txt LICENSE
  git -C "$SNAP_PUBLIC" commit -qm "test: matching public snapshot"
  SNAP_PUBLIC_SHA="$(git -C "$SNAP_PUBLIC" rev-parse HEAD)"
  "$ROOT/scripts/release/verify-public-snapshot.sh" \
    "$SNAP_SRC" "$SNAP_SRC_SHA" "$SNAP_PUBLIC" "$SNAP_PUBLIC_SHA" \
    >"$TMP/snapshot-ok-out"
  grep -qF "snapshot: public $SNAP_PUBLIC_SHA matches source $SNAP_SRC_SHA" "$TMP/snapshot-ok-out"
  echo "PASS: snapshot verifier accepts exact source/public content and preserves public-only files"

  git -C "$SNAP_PUBLIC" rm -q app.txt
  printf 'app.txt\n' > "$SNAP_PUBLIC/.gitignore"
  git -C "$SNAP_PUBLIC" add .gitignore
  git -C "$SNAP_PUBLIC" commit -qm "test: ignored missing synced file"
  SNAP_IGNORED_SHA="$(git -C "$SNAP_PUBLIC" rev-parse HEAD)"
  set +e
  "$ROOT/scripts/release/verify-public-snapshot.sh" \
    "$SNAP_SRC" "$SNAP_SRC_SHA" "$SNAP_PUBLIC" "$SNAP_IGNORED_SHA" \
    >/dev/null 2>"$TMP/snapshot-ignored-stderr"
  rc=$?
  set -e
  [ "$rc" -eq 1 ]
  grep -qF "public target does not match source sync output" "$TMP/snapshot-ignored-stderr"
  echo "PASS: snapshot verifier rejects ignored missing synced files"

  printf 'tampered\n' > "$SNAP_PUBLIC/app.txt"
  git -C "$SNAP_PUBLIC" add -f app.txt
  git -C "$SNAP_PUBLIC" commit -qm "test: tampered public snapshot"
  SNAP_TAMPER_SHA="$(git -C "$SNAP_PUBLIC" rev-parse HEAD)"
  set +e
  "$ROOT/scripts/release/verify-public-snapshot.sh" \
    "$SNAP_SRC" "$SNAP_SRC_SHA" "$SNAP_PUBLIC" "$SNAP_TAMPER_SHA" \
    >/dev/null 2>"$TMP/snapshot-tamper-stderr"
  rc=$?
  set -e
  [ "$rc" -eq 1 ]
  grep -qF "public target does not match source sync output" "$TMP/snapshot-tamper-stderr"
  echo "PASS: snapshot verifier rejects tampered synced content"

  ln -s app.txt "$SNAP_SRC/source-link"
  git -C "$SNAP_SRC" add source-link
  git -C "$SNAP_SRC" commit -qm "test: source symlink"
  SNAP_SRC_SYMLINK_SHA="$(git -C "$SNAP_SRC" rev-parse HEAD)"
  set +e
  "$ROOT/scripts/release/verify-public-snapshot.sh" \
    "$SNAP_SRC" "$SNAP_SRC_SYMLINK_SHA" "$SNAP_PUBLIC" "$SNAP_PUBLIC_SHA" \
    >/dev/null 2>"$TMP/snapshot-source-symlink-stderr"
  rc=$?
  set -e
  [ "$rc" -eq 1 ]
  grep -qF "refusing source commit with tracked symlink" "$TMP/snapshot-source-symlink-stderr"
  echo "PASS: snapshot verifier rejects tracked source symlinks"

  git -C "$SNAP_PUBLIC" checkout -q --detach "$SNAP_PUBLIC_SHA"
  git -C "$SNAP_PUBLIC" switch -q -c symlink-public
  rm "$SNAP_PUBLIC/app.txt"
  ln -s /tmp/abendrot-outside "$SNAP_PUBLIC/app.txt"
  git -C "$SNAP_PUBLIC" add -f app.txt
  git -C "$SNAP_PUBLIC" commit -qm "test: public symlink"
  SNAP_PUBLIC_SYMLINK_SHA="$(git -C "$SNAP_PUBLIC" rev-parse HEAD)"
  set +e
  "$ROOT/scripts/release/verify-public-snapshot.sh" \
    "$SNAP_SRC" "$SNAP_SRC_SHA" "$SNAP_PUBLIC" "$SNAP_PUBLIC_SYMLINK_SHA" \
    >/dev/null 2>"$TMP/snapshot-public-symlink-stderr"
  rc=$?
  set -e
  [ "$rc" -eq 1 ]
  grep -qF "refusing public commit with tracked symlink" "$TMP/snapshot-public-symlink-stderr"
  echo "PASS: snapshot verifier rejects tracked public symlinks"
else
  echo "SKIP: snapshot verifier guard (helper not present)"
fi

if [ -x "$ROOT/scripts/publish.sh" ]; then
  PROMOTE_GH="$TMP/promote-gh"
  mkdir -p "$PROMOTE_GH"
  cat > "$PROMOTE_GH/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "${1:-}" = "api" ] || { echo "unexpected gh invocation: $*" >&2; exit 2; }
shift
[ "${1:-}" = "--paginate" ] && shift
path="${1:-}"
case "$path" in
  repos/*/actions/runs/*/jobs*)
    case "${GH_WORKFLOW_CASE:-missing}" in
      success)
        printf 'public-dev/release-gate\t%s\t%s\tcompleted\tsuccess\n' "${GH_RUN_ID:?}" "${GH_PROMOTE_SHA:?}"
        ;;
      job-failure)
        printf 'public-dev/release-gate\t%s\t%s\tcompleted\tfailure\n' "${GH_RUN_ID:?}" "${GH_PROMOTE_SHA:?}"
        ;;
      *)
        printf 'public-dev/release-gate\t%s\t%s\tcompleted\tsuccess\n' "${GH_RUN_ID:-1001}" "${GH_PROMOTE_SHA:-0000000000000000000000000000000000000000}"
        ;;
    esac
    ;;
  repos/*/actions/runs*)
    case "${GH_WORKFLOW_CASE:-missing}" in
      missing)
        ;;
      spoof-path)
        printf '%s\t.github/workflows/not-ci.yml\tpublic-dev\tpush\tcompleted\tsuccess\t%s\t%s\t%s\n' \
          "${GH_RUN_ID:?}" "${GH_PROMOTE_SHA:?}" "${GH_REPO:?}" "${GH_REPO:?}"
        ;;
      wrong-repo)
        printf '%s\t.github/workflows/ci.yml\tpublic-dev\tpush\tcompleted\tsuccess\t%s\tevil/abendrot\t%s\n' \
          "${GH_RUN_ID:?}" "${GH_PROMOTE_SHA:?}" "${GH_REPO:?}"
        ;;
      run-failure)
        printf '%s\t.github/workflows/ci.yml\tpublic-dev\tpush\tcompleted\tfailure\t%s\t%s\t%s\n' \
          "${GH_RUN_ID:?}" "${GH_PROMOTE_SHA:?}" "${GH_REPO:?}" "${GH_REPO:?}"
        ;;
      job-failure|success)
        printf '%s\t.github/workflows/ci.yml\tpublic-dev\tpush\tcompleted\tsuccess\t%s\t%s\t%s\n' \
          "${GH_RUN_ID:?}" "${GH_PROMOTE_SHA:?}" "${GH_REPO:?}" "${GH_REPO:?}"
        ;;
      *)
        echo "unknown GH_WORKFLOW_CASE=$GH_WORKFLOW_CASE" >&2
        exit 2
        ;;
    esac
    ;;
  repos/*/releases/tags/*)
    case "${GH_RELEASE_CASE:-public-good}" in
      public-good)
        cat <<'JSON'
{"draft":false,"body":"SHA-256: fe31565c05c990c33899f12a49f2f429141694a931ef081f77c4c6a8abcf1bb6","assets":[{"name":"Abendrot-1.0.0.dmg","state":"uploaded","size":10800533,"digest":"sha256:fe31565c05c990c33899f12a49f2f429141694a931ef081f77c4c6a8abcf1bb6"}]}
JSON
        ;;
      draft)
        cat <<'JSON'
{"draft":true,"body":"SHA-256: fe31565c05c990c33899f12a49f2f429141694a931ef081f77c4c6a8abcf1bb6","assets":[{"name":"Abendrot-1.0.0.dmg","state":"uploaded","size":10800533,"digest":"sha256:fe31565c05c990c33899f12a49f2f429141694a931ef081f77c4c6a8abcf1bb6"}]}
JSON
        ;;
      missing-digest)
        cat <<'JSON'
{"draft":false,"body":"SHA-256: fe31565c05c990c33899f12a49f2f429141694a931ef081f77c4c6a8abcf1bb6","assets":[{"name":"Abendrot-1.0.0.dmg","state":"uploaded","size":10800533}]}
JSON
        ;;
      digest-not-in-notes)
        cat <<'JSON'
{"draft":false,"body":"SHA-256: 0000000000000000000000000000000000000000000000000000000000000000","assets":[{"name":"Abendrot-1.0.0.dmg","state":"uploaded","size":10800533,"digest":"sha256:fe31565c05c990c33899f12a49f2f429141694a931ef081f77c4c6a8abcf1bb6"}]}
JSON
        ;;
      *)
        echo "unknown GH_RELEASE_CASE=$GH_RELEASE_CASE" >&2
        exit 2
        ;;
    esac
    ;;
  *)
    echo "unexpected gh api path: $path" >&2
    exit 2
    ;;
esac
SH
  chmod 755 "$PROMOTE_GH/gh"

  make_promote_public() {
    local origin="$1" work="$2" build="$3" seed_appcast="${4:-true}"
    local source_sha
    source_sha="$(git -C "$build" rev-parse HEAD)"
    git init --bare -q "$origin"
    git init -q -b main "$work"
    git -C "$work" config user.name "Release Guard Test"
    git -C "$work" config user.email "release-guard@example.invalid"
    git -C "$work" config gc.auto 0
    printf 'main\n' > "$work/README.md"
    if [ "$seed_appcast" = "true" ]; then
      cp "$build/appcast.xml" "$work/appcast.xml"
    fi
    git -C "$work" add -A
    git -C "$work" commit -qm "test: seed public main"
    git -C "$work" remote add origin "$origin"
    git -C "$work" push -qu origin main
    git -C "$work" checkout -qb public-dev
    BUILD="$build" PUBLIC="$work" bash "$build/scripts/sync-public.sh" >/dev/null
    git -C "$work" add -A
    git -C "$work" commit -qm "test: seed public dev" -m "Source-Build-Commit: $source_sha"
    git -C "$work" push -qu -u origin public-dev
  }

  make_promote_build() {
    local build="$1" origin="$2"
    git clone --quiet "$ROOT" "$build"
    git init --bare -q "$origin"
    # GitHub Actions checks out pull-request merge commits with fetch-depth=1.
    # A local clone of that checkout is shallow too, so its disposable bare
    # remote must explicitly accept the shallow boundary for this test fixture.
    # This changes only the temporary test remote; production remotes remain
    # governed by their normal receive policy.
    git -C "$origin" config receive.shallowUpdate true
    git -C "$build" remote remove origin || true
    git -C "$build" remote add origin "$origin"
    git -C "$build" push -q origin HEAD:refs/heads/dev
  }

  assert_promote_case() {
    local name="$1" workflow_case="$2" expected_rc="$3" expected_text="$4"
    local origin="$TMP/promote-$name-origin.git" work="$TMP/promote-$name-work"
    local build="$TMP/promote-$name-build" build_origin="$TMP/promote-$name-build-origin.git"
    make_promote_build "$build" "$build_origin"
    make_promote_public "$origin" "$work" "$build"
    local publish_sha repo
    publish_sha="$(git -C "$work" rev-parse origin/public-dev)"
    repo="$(git -C "$work" config --get remote.origin.url | sed -E 's#.*[:/]([^/]+/[^/]+)$#\1#; s#\.git$##')"
    set +e
    printf 'n\n' | PATH="$PROMOTE_GH:$PATH" BUILD="$build" PUBLIC="$work" \
      GH_WORKFLOW_CASE="$workflow_case" GH_PROMOTE_SHA="$publish_sha" GH_RUN_ID="1001" GH_REPO="$repo" \
      "$ROOT/scripts/publish.sh" promote \
      >"$TMP/promote-$name-out" 2>"$TMP/promote-$name-stderr"
    rc=$?
    set -e
    if [ "$rc" -ne "$expected_rc" ]; then
      cat "$TMP/promote-$name-out" >&2
      cat "$TMP/promote-$name-stderr" >&2
      exit 1
    fi
    grep -qF "$expected_text" "$TMP/promote-$name-out" "$TMP/promote-$name-stderr"
  }

  write_public_appcast_item() {
    local appcast="$1"
    cat > "$appcast" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Abendrot</title>
    <item>
      <title>Version 1.0.0</title>
      <sparkle:version>2</sparkle:version>
      <sparkle:shortVersionString>1.0.0</sparkle:shortVersionString>
      <enclosure url="https://github.com/matthewrball/abendrot/releases/download/v1.0.0/Abendrot-1.0.0.dmg"
                 sparkle:edSignature="ZmFrZQ=="
                 sparkle:minimumSystemVersion="14.0"
                 length="10800533"
                 type="application/octet-stream" />
    </item>
  </channel>
</rss>
XML
  }

  assert_promote_appcast_case() {
    local name="$1" release_case="$2" expected_rc="$3" expected_text="$4"
    local origin="$TMP/promote-appcast-$name-origin.git" work="$TMP/promote-appcast-$name-work"
    local build="$TMP/promote-appcast-$name-build" build_origin="$TMP/promote-appcast-$name-build-origin.git"
    make_promote_build "$build" "$build_origin"
    write_public_appcast_item "$build/appcast.xml"
    git -C "$build" add appcast.xml
    git -C "$build" commit -qm "test: add appcast item"
    git -C "$build" push -q origin HEAD:refs/heads/dev
    make_promote_public "$origin" "$work" "$build" false
    local publish_sha repo
    publish_sha="$(git -C "$work" rev-parse origin/public-dev)"
    repo="$(git -C "$work" config --get remote.origin.url | sed -E 's#.*[:/]([^/]+/[^/]+)$#\1#; s#\.git$##')"
    set +e
    printf 'n\n' | PATH="$PROMOTE_GH:$PATH" BUILD="$build" PUBLIC="$work" \
      GH_WORKFLOW_CASE="success" GH_RELEASE_CASE="$release_case" GH_PROMOTE_SHA="$publish_sha" GH_RUN_ID="1001" GH_REPO="$repo" \
      "$ROOT/scripts/publish.sh" promote \
      >"$TMP/promote-appcast-$name-out" 2>"$TMP/promote-appcast-$name-stderr"
    rc=$?
    set -e
    if [ "$rc" -ne "$expected_rc" ]; then
      cat "$TMP/promote-appcast-$name-out" >&2
      cat "$TMP/promote-appcast-$name-stderr" >&2
      exit 1
    fi
    grep -qF "$expected_text" "$TMP/promote-appcast-$name-out" "$TMP/promote-appcast-$name-stderr"
  }

  assert_promote_same_url_metadata_rejected() {
    local origin="$TMP/promote-appcast-same-url-origin.git" work="$TMP/promote-appcast-same-url-work"
    local build="$TMP/promote-appcast-same-url-build" build_origin="$TMP/promote-appcast-same-url-build-origin.git"
    make_promote_build "$build" "$build_origin"
    write_public_appcast_item "$build/appcast.xml"
    git -C "$build" add appcast.xml
    git -C "$build" commit -qm "test: update appcast item metadata"
    git -C "$build" push -q origin HEAD:refs/heads/dev

    git init --bare -q "$origin"
    git init -q -b main "$work"
    git -C "$work" config user.name "Release Guard Test"
    git -C "$work" config user.email "release-guard@example.invalid"
    git -C "$work" config gc.auto 0
    write_public_appcast_item "$work/appcast.xml"
    perl -0pi -e 's/length="10800533"/length="1"/' "$work/appcast.xml"
    git -C "$work" add appcast.xml
    git -C "$work" commit -qm "test: seed old public appcast"
    git -C "$work" remote add origin "$origin"
    git -C "$work" push -qu origin main
    git -C "$work" checkout -qb public-dev
    BUILD="$build" PUBLIC="$work" bash "$build/scripts/sync-public.sh" >/dev/null
    git -C "$work" add -A
    git -C "$work" commit -qm "test: changed appcast metadata" -m "Source-Build-Commit: $(git -C "$build" rev-parse HEAD)"
    git -C "$work" push -qu -u origin public-dev

    local publish_sha repo
    publish_sha="$(git -C "$work" rev-parse origin/public-dev)"
    repo="$(git -C "$work" config --get remote.origin.url | sed -E 's#.*[:/]([^/]+/[^/]+)$#\1#; s#\.git$##')"
    set +e
    printf 'n\n' | PATH="$PROMOTE_GH:$PATH" BUILD="$build" PUBLIC="$work" \
      GH_WORKFLOW_CASE="success" GH_RELEASE_CASE="public-good" GH_PROMOTE_SHA="$publish_sha" GH_RUN_ID="1001" GH_REPO="$repo" \
      "$ROOT/scripts/publish.sh" promote \
      >"$TMP/promote-appcast-same-url-out" 2>"$TMP/promote-appcast-same-url-stderr"
    rc=$?
    set -e
    [ "$rc" -eq 1 ]
    grep -qF "appcast enclosure metadata changed for existing URL" \
      "$TMP/promote-appcast-same-url-stderr"
  }

  assert_promote_case missing missing 1 "no successful completed push run"
  echo "PASS: promote rejects missing public-dev workflow run"
  assert_promote_case spoof-path spoof-path 1 "path=.github/workflows/not-ci.yml"
  echo "PASS: promote rejects workflow identity spoofing"
  assert_promote_case wrong-repo wrong-repo 1 "head_repo=evil/abendrot"
  echo "PASS: promote rejects workflow runs from another repository"
  assert_promote_case run-failure run-failure 1 "conclusion=failure"
  echo "PASS: promote rejects non-success workflow run conclusions"
  assert_promote_case job-failure job-failure 1 "conclusion=failure"
  grep -qF "observed: name=public-dev/release-gate" "$TMP/promote-job-failure-stderr"
  echo "PASS: promote rejects non-success release-gate jobs"

  lineage_origin="$TMP/promote-lineage-origin.git"
  lineage_work="$TMP/promote-lineage-work"
  lineage_build="$TMP/promote-lineage-build"
  lineage_build_origin="$TMP/promote-lineage-build-origin.git"
  make_promote_build "$lineage_build" "$lineage_build_origin"
  make_promote_public "$lineage_origin" "$lineage_work" "$lineage_build"
  git -C "$lineage_build" switch -q --orphan unrelated-dev
  git -C "$lineage_build" rm -qr . >/dev/null 2>&1 || true
  printf 'unrelated\n' > "$lineage_build/unrelated.txt"
  git -C "$lineage_build" add unrelated.txt
  git -C "$lineage_build" commit -qm "test: unrelated dev"
  git -C "$lineage_build" push -q --force origin HEAD:refs/heads/dev
  lineage_sha="$(git -C "$lineage_work" rev-parse origin/public-dev)"
  lineage_repo="$(git -C "$lineage_work" config --get remote.origin.url | sed -E 's#.*[:/]([^/]+/[^/]+)$#\1#; s#\.git$##')"
  set +e
  printf 'n\n' | PATH="$PROMOTE_GH:$PATH" BUILD="$lineage_build" PUBLIC="$lineage_work" \
    GH_WORKFLOW_CASE="success" GH_PROMOTE_SHA="$lineage_sha" GH_RUN_ID="1001" GH_REPO="$lineage_repo" \
    "$ROOT/scripts/publish.sh" promote \
    >"$TMP/promote-lineage-out" 2>"$TMP/promote-lineage-stderr"
  rc=$?
  set -e
  [ "$rc" -eq 1 ]
  grep -qF "Source-Build-Commit is not an ancestor of BUILD origin/dev" "$TMP/promote-lineage-stderr"
  echo "PASS: promote rejects source commits not merged to BUILD origin/dev"

  assert_promote_case success success 0 "Aborted (no push)."
  grep -qF "public-dev/release-gate green" "$TMP/promote-success-out"
  grep -qF "snapshot: public" "$TMP/promote-success-out"
  echo "PASS: promote accepts exact workflow run, job, SHA, repo, and source snapshot"

  assert_promote_appcast_case appcast-draft draft 1 "appcast asset is not public yet"
  echo "PASS: promote rejects appcast assets still on draft releases"
  assert_promote_appcast_case appcast-missing-digest missing-digest 1 "digest is missing or invalid"
  echo "PASS: promote rejects appcast assets without verifiable GitHub digests"
  assert_promote_appcast_case appcast-digest-not-in-notes digest-not-in-notes 1 "digest is not recorded in release notes"
  echo "PASS: promote rejects appcast assets whose API digest is not frozen in release notes"
  assert_promote_same_url_metadata_rejected
  echo "PASS: promote rejects same-URL appcast enclosure metadata changes"
  assert_promote_appcast_case appcast-public public-good 0 "Aborted (no push)."
  grep -qF "Abendrot-1.0.0.dmg public, uploaded, size/digest match release notes" \
    "$TMP/promote-appcast-appcast-public-out"
  echo "PASS: promote accepts new appcast assets only after public exact-asset verification"

  PUBLIC_ORIGIN="$TMP/public-origin.git"
  PUBLIC_WORK="$TMP/public-work"
  git init --bare -q "$PUBLIC_ORIGIN"
  git init -q -b main "$PUBLIC_WORK"
  git -C "$PUBLIC_WORK" config user.name "Release Guard Test"
  git -C "$PUBLIC_WORK" config user.email "release-guard@example.invalid"
  printf 'main\n' > "$PUBLIC_WORK/README.md"
  git -C "$PUBLIC_WORK" add README.md
  git -C "$PUBLIC_WORK" commit -qm "test: seed public main"
  git -C "$PUBLIC_WORK" remote add origin "$PUBLIC_ORIGIN"
  git -C "$PUBLIC_WORK" push -qu origin main
  git -C "$PUBLIC_WORK" checkout -qb public-dev
  printf 'remote public dev\n' > "$PUBLIC_WORK/public-dev.txt"
  git -C "$PUBLIC_WORK" add public-dev.txt
  git -C "$PUBLIC_WORK" commit -qm "test: seed public dev"
  git -C "$PUBLIC_WORK" push -qu -u origin public-dev
  printf 'local only\n' > "$PUBLIC_WORK/local-only.txt"
  git -C "$PUBLIC_WORK" add local-only.txt
  git -C "$PUBLIC_WORK" commit -qm "test: diverge local dev"
  set +e
  BUILD="$ROOT" PUBLIC="$PUBLIC_WORK" "$ROOT/scripts/publish.sh" stage \
    >/dev/null 2>"$TMP/publish-stderr"
  rc=$?
  set -e
  [ "$rc" -eq 1 ]
  grep -qF "PUBLIC public-dev does not exactly match origin/public-dev" "$TMP/publish-stderr"
  echo "PASS: publish staging rejects divergent public-dev history"
else
  echo "SKIP: build-only publish.sh guard (not present in curated public source)"
fi
