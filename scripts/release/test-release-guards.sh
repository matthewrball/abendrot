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
SIGN_JOB="$TMP/sign-notarize.yml"

grep -qF "github.event_name == 'workflow_dispatch'" "$CI_WORKFLOW"
grep -qF "github.ref == 'refs/heads/main'" "$CI_WORKFLOW"
grep -qF "environment: release-signing" "$CI_WORKFLOW"
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

APP_MODEL="$ROOT/App/Sources/Abendrot/ViewModel/AppModel.swift"
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
mkdir -p "$APP/Contents/MacOS"
cat > "$TMP/app-main.c" <<'C'
int main(void) { return 0; }
C
xcrun clang -arch arm64 "$TMP/app-main.c" -o "$TMP/app-main-arm64"
xcrun clang -arch x86_64 "$TMP/app-main.c" -o "$TMP/app-main-x86_64"
lipo -create "$TMP/app-main-arm64" "$TMP/app-main-x86_64" \
  -output "$APP/Contents/MacOS/Abendrot"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>42</string>
  <key>CFBundleExecutable</key><string>Abendrot</string>
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
    printf 'Authority=%s\n' "${MOCK_CODESIGN_AUTHORITY:?}" >&2
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
      [ "${GH_TAG_EXISTS:-0}" = "1" ] || exit 1
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
    <title>Abendrot Updates</title>
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
  "$FAKE_ROOT/scripts/release/release.sh" --app "$APP" --unsigned \
  >/dev/null 2>"$TMP/stale-app-stderr"
rc=$?
set -e
[ "$rc" -eq 9 ]
grep -qF "exported app was not built from this audited source commit" "$TMP/stale-app-stderr"
echo "PASS: publishing refuses a stale exported app bundle"
/usr/bin/plutil -replace AbendrotSourceCommit -string "$FAKE_HEAD" \
  "$APP/Contents/Info.plist"

set +e
PATH="/usr/bin:/bin:/usr/sbin:/sbin" RELEASE_PUBLISH=1 RELEASE_TARGET_SHA="$TARGET_MAIN" \
  "$FAKE_ROOT/scripts/release/release.sh" --app "$APP" --unsigned \
  >/dev/null 2>"$TMP/no-gh-stderr"
rc=$?
set -e
[ "$rc" -eq 9 ]
grep -qF "RELEASE_PUBLISH=1 requires the gh CLI" "$TMP/no-gh-stderr"
echo "PASS: publishing fails closed when gh is unavailable"

set +e
PATH="$MOCK_GH:$PATH" RELEASE_PUBLISH=1 \
  "$FAKE_ROOT/scripts/release/release.sh" --app "$APP" --unsigned \
  >/dev/null 2>"$TMP/no-target-stderr"
rc=$?
set -e
[ "$rc" -eq 9 ]
grep -qF "RELEASE_TARGET_SHA must be the exact 40-char curated public commit SHA" "$TMP/no-target-stderr"
echo "PASS: publishing requires an explicit curated public release target"

set +e
PATH="$MOCK_GH:$PATH" RELEASE_PUBLISH=1 RELEASE_TARGET_SHA="$TARGET_OTHER" \
  GH_TARGET_SHA="$TARGET_OTHER" GH_MAIN_SHA="$TARGET_MAIN" GH_DEV_SHA="$TARGET_DEV" \
  "$FAKE_ROOT/scripts/release/release.sh" --app "$APP" --unsigned \
  >/dev/null 2>"$TMP/bad-target-stderr"
rc=$?
set -e
[ "$rc" -eq 9 ]
grep -qF "RELEASE_TARGET_SHA must be public main or public-dev" "$TMP/bad-target-stderr"
echo "PASS: release target must be on the curated public lineage"

set +e
PATH="$MOCK_GH:$PATH" RELEASE_PUBLISH=1 RELEASE_TARGET_SHA="$TARGET_MAIN" \
  GH_TARGET_SHA="$TARGET_MAIN" GH_MAIN_SHA="$TARGET_MAIN" GH_TAG_EXISTS=1 \
  GH_COMMIT_MESSAGE=$'sync from build\n\nSource-Build-Commit: '"$FAKE_HEAD" \
  "$FAKE_ROOT/scripts/release/release.sh" --app "$APP" --unsigned \
  >/dev/null 2>"$TMP/stale-tag-stderr"
rc=$?
set -e
[ "$rc" -eq 9 ]
grep -qF "remote tag v1.0.0 already exists" "$TMP/stale-tag-stderr"
echo "PASS: publishing refuses an existing stale release tag"

set +e
PATH="$EARLY_SIGN_BIN:$MOCK_GH:$PATH" DEVELOPER_ID_APP="$MOCK_DEVELOPER_ID_APP" \
  MOCK_CODESIGN_AUTHORITY="$MOCK_DEVELOPER_ID_APP" \
  RELEASE_PUBLISH=1 RELEASE_TARGET_SHA="$TARGET_MAIN" \
  GH_TARGET_SHA="$TARGET_MAIN" GH_MAIN_SHA="$TARGET_MAIN" \
  GH_COMMIT_MESSAGE="sync without source trailer" \
  "$FAKE_ROOT/scripts/release/release.sh" --app "$APP" --unsigned \
  >/dev/null 2>"$TMP/unsigned-missing-trailer-stderr"
rc=$?
set -e
[ "$rc" -eq 9 ]
grep -qF "must contain exactly one Source-Build-Commit" \
  "$TMP/unsigned-missing-trailer-stderr"
echo "PASS: unsigned publishing still requires the source-build trailer"

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

set +e
PATH="$MOCK_GH:$PATH" RELEASE_PUBLISH=1 RELEASE_TARGET_SHA="$TARGET_MAIN" \
  GH_TARGET_SHA="$TARGET_MAIN" GH_MAIN_SHA="$TARGET_MAIN" \
  GH_COMMIT_MESSAGE=$'sync from build\n\nSource-Build-Commit: '"$FAKE_HEAD" \
  "$FAKE_ROOT/scripts/release/release.sh" --app "$APP" --unsigned \
  >"$TMP/good-target-out" 2>"$TMP/good-target-stderr"
rc=$?
set -e
[ "$rc" -eq 5 ]
grep -qF "verified curated public release target $TARGET_MAIN" "$TMP/good-target-out"
grep -qF "required cli/ package missing" "$TMP/good-target-stderr"
echo "PASS: explicit release target is verified before publishing work continues"

DIRTY_MARKER="$ROOT/.release-guard-dirty.$$"
: > "$DIRTY_MARKER"
set +e
RELEASE_PUBLISH=1 APPCAST_PATH="$APPCAST" "$ROOT/scripts/release/release.sh" \
  --app "$APP" --unsigned >/dev/null 2>"$TMP/dirty-stderr"
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
  APPCAST_PATH="$APPCAST" "$ROOT/scripts/release/release.sh" \
  --app "$APP" >/dev/null 2>"$TMP/key-stderr"
rc=$?
set -e
[ "$rc" -eq 6 ]
grep -qF "SUPublicEDKey must decode to exactly 32 bytes" "$TMP/key-stderr"
echo "PASS: signed releases verify app identity before later Sparkle gates"
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
  --app "$APP" --unsigned --dmg-mode plain >/dev/null 2>"$TMP/unsigned-stderr"
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
    exit 0
    ;;
  notarytool)
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
[ -n "$triple" ] || triple="arm64-apple-macosx26.0"
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
/usr/bin/xcrun clang -arch "$arch" "$src" -o "$dir/abendrot"
SH
chmod 755 "$MOCK_SIGNED_BIN/"*

cat > "$MOCK_SPARKLE/sign_update" <<'SH'
#!/usr/bin/env bash
printf 'sparkle:edSignature="mock-signature" length="%s"\n' "$(stat -f%z "$1")"
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
echo "PASS: signed dry-runs keep production appcast unchanged and write a verified candidate"

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
  *)
    echo "unexpected gh api path: $path" >&2
    exit 2
    ;;
esac
SH
  chmod 755 "$PROMOTE_GH/gh"

  make_promote_public() {
    local origin="$1" work="$2" build="$3"
    local source_sha
    source_sha="$(git -C "$build" rev-parse HEAD)"
    git init --bare -q "$origin"
    git init -q -b main "$work"
    git -C "$work" config user.name "Release Guard Test"
    git -C "$work" config user.email "release-guard@example.invalid"
    git -C "$work" config gc.auto 0
    printf 'main\n' > "$work/README.md"
    git -C "$work" add README.md
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
