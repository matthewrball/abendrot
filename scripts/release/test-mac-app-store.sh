#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
STORE_CONFIG="$ROOT/project.yml"
ENTITLEMENTS="$ROOT/App/Resources/AbendrotAppStore.entitlements"
STORE_INFO="$ROOT/App/Resources/Info-AppStore.plist"
PRIVACY_MANIFEST="$ROOT/App/Resources/PrivacyInfo.xcprivacy"
EXPORT_OPTIONS="$ROOT/scripts/release/ExportOptions-AppStore.plist"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

for plist_path in "$ENTITLEMENTS" "$STORE_INFO" "$PRIVACY_MANIFEST" "$EXPORT_OPTIONS"; do
    plutil -lint "$plist_path" >/dev/null || fail "invalid plist: $plist_path"
done
pass "App Store plists are valid"

[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$ENTITLEMENTS")" == "true" ]] \
    || fail "App Sandbox entitlement is missing"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.user-selected.read-only' "$ENTITLEMENTS")" == "true" ]] \
    || fail "read-only Powerbox entitlement is missing"
[[ "$(plutil -extract method raw -o - "$EXPORT_OPTIONS")" == "app-store-connect" ]] \
    || fail "export method is not app-store-connect"
[[ "$(plutil -extract destination raw -o - "$EXPORT_OPTIONS")" == "export" ]] \
    || fail "export options would upload instead of producing a local artifact"
pass "sandbox and local App Store export settings are locked"

STORE_TARGET=$(awk '/^  AbendrotAppStore:/{found=1} found{print}' "$STORE_CONFIG")
[[ -n "$STORE_TARGET" ]] || fail "AbendrotAppStore target is missing"
rg -q 'SWIFT_ACTIVE_COMPILATION_CONDITIONS:.*APP_STORE' <<<"$STORE_TARGET" \
    || fail "App Store compile condition is missing"
rg -q 'CODE_SIGN_ENTITLEMENTS: App/Resources/AbendrotAppStore.entitlements' <<<"$STORE_TARGET" \
    || fail "App Store target does not use its entitlements"
if rg -q 'product: (Sparkle|WarmthKitPrivate)' <<<"$STORE_TARGET"; then
    fail "App Store target links a direct-distribution product"
fi
for sparkle_key in SUFeedURL SUPublicEDKey SUEnableAutomaticChecks SUAutomaticallyUpdate SUScheduledCheckInterval; do
    if plutil -extract "$sparkle_key" raw -o - "$STORE_INFO" >/dev/null 2>&1; then
        fail "App Store Info.plist contains $sparkle_key"
    fi
done
pass "App Store target excludes Sparkle and private engine wiring"

[[ "$(plutil -extract NSPrivacyTracking raw -o - "$PRIVACY_MANIFEST")" == "false" ]] \
    || fail "privacy manifest enables tracking"
for reason in CA92.1 C617.1 35F9.1; do
    rg -q "<string>$reason</string>" "$PRIVACY_MANIFEST" \
        || fail "privacy manifest is missing required-reason code $reason"
done
pass "privacy manifest declares no tracking and the used required-reason APIs"

if [[ $# -eq 0 ]]; then
    exit 0
fi

DISTRIBUTION=false
if [[ "${1:-}" == "--distribution" ]]; then
    DISTRIBUTION=true
    shift
fi
[[ $# -eq 1 ]] || fail "usage: $0 [--distribution] [path/to/Abendrot.app]"

APP=$1
[[ -d "$APP/Contents" ]] || fail "not an app bundle: $APP"
APP_INFO="$APP/Contents/Info.plist"
EXECUTABLE="$APP/Contents/MacOS/Abendrot"
[[ -f "$APP_INFO" && -x "$EXECUTABLE" ]] || fail "incomplete Abendrot app bundle"

codesign --verify --deep --strict "$APP" || fail "bundle signature verification failed"
ENTITLEMENTS_ACTUAL=$(mktemp)
trap 'rm -f "$ENTITLEMENTS_ACTUAL"' EXIT
codesign -d --entitlements :- "$APP" >"$ENTITLEMENTS_ACTUAL" 2>/dev/null \
    || fail "unable to read signed entitlements"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$ENTITLEMENTS_ACTUAL")" == "true" ]] \
    || fail "built app is not sandboxed"

[[ "$(plutil -extract CFBundleIdentifier raw -o - "$APP_INFO")" == "app.abendrot.Abendrot" ]] \
    || fail "built app has the wrong bundle identifier"
[[ "$(plutil -extract ITSAppUsesNonExemptEncryption raw -o - "$APP_INFO")" == "false" ]] \
    || fail "built app does not declare its export-compliance status"
[[ "$(plutil -extract CFBundleShortVersionString raw -o - "$APP_INFO")" == "1.1.1" ]] \
    || fail "built app has the wrong marketing version"
[[ "$(plutil -extract CFBundleVersion raw -o - "$APP_INFO")" == "14" ]] \
    || fail "built app has the wrong build number"
[[ "$(plutil -extract LSMinimumSystemVersion raw -o - "$APP_INFO")" == "12.0" ]] \
    || fail "built app has the wrong minimum macOS version"
[[ "$(plutil -extract LSApplicationCategoryType raw -o - "$APP_INFO")" == "public.app-category.utilities" ]] \
    || fail "built app has the wrong App Store category"
[[ "$(plutil -extract AbendrotSourceCommit raw -o - "$APP_INFO")" == "$(git -C "$ROOT" rev-parse HEAD)" ]] \
    || fail "built app is not bound to the checked-out source commit"
for sparkle_key in SUFeedURL SUPublicEDKey SUEnableAutomaticChecks SUAutomaticallyUpdate SUScheduledCheckInterval; do
    if plutil -extract "$sparkle_key" raw -o - "$APP_INFO" >/dev/null 2>&1; then
        fail "built app Info.plist contains $sparkle_key"
    fi
done
[[ ! -e "$APP/Contents/Frameworks/Sparkle.framework" ]] || fail "built app embeds Sparkle"
[[ ! -e "$APP/Contents/Helpers/abendrot" ]] || fail "built app embeds the command-line helper"
[[ -f "$APP/Contents/Resources/PrivacyInfo.xcprivacy" ]] || fail "built app omits PrivacyInfo.xcprivacy"
[[ -f "$APP/Contents/Resources/AppIcon.icns" ]] || fail "built app omits the Mac app icon"

ARCHS=$(lipo -archs "$EXECUTABLE")
[[ " $ARCHS " == *" arm64 "* && " $ARCHS " == *" x86_64 "* ]] \
    || fail "built app is not universal (arm64 + x86_64)"

if otool -L "$EXECUTABLE" | rg -q 'Sparkle|CoreBrightness|CoreDisplay'; then
    fail "built executable links a forbidden framework"
fi
if rg -a -q 'IOAVService|CoreDisplay_DisplayCreateInfoDictionary|CBBlueLightClient|SUPublicEDKey|SUFeedURL' "$APP"; then
    fail "built app contains private API or Sparkle strings"
fi
if xattr -lr "$APP" 2>/dev/null | rg -q 'com\.apple\.quarantine'; then
    fail "built app contains a quarantine attribute"
fi

if [[ "$DISTRIBUTION" == true ]]; then
    SIGNATURE=$(codesign -dvv "$APP" 2>&1)
    rg -q '^TeamIdentifier=XGFJEZS3MA$' <<<"$SIGNATURE" \
        || fail "distribution archive is not signed by team XGFJEZS3MA"
    if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$ENTITLEMENTS_ACTUAL" 2>/dev/null \
        | rg -q '^true$'; then
        fail "distribution archive enables get-task-allow"
    fi
fi

pass "built app is sandboxed, universal, helper-free, Sparkle-free, and private-symbol-free"
