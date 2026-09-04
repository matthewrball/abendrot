#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ARCHIVE_PATH="$ROOT/build/AppStore/Abendrot.xcarchive"
EXPORT_PATH="$ROOT/build/AppStore/export"
APP="$ARCHIVE_PATH/Products/Applications/Abendrot.app"

cd "$ROOT"
[[ -z "$(git status --porcelain)" ]] || {
    echo "Refusing to archive a dirty source tree." >&2
    exit 1
}
command -v xcodegen >/dev/null || {
    echo "xcodegen is required (brew install xcodegen)." >&2
    exit 1
}

./scripts/release/test-mac-app-store.sh
xcodegen generate

[[ ! -e "$ARCHIVE_PATH" && ! -e "$EXPORT_PATH" ]] || {
    echo "App Store output already exists under $ROOT/build/AppStore; move it aside before archiving." >&2
    exit 1
}

xcodebuild \
    -project Abendrot.xcodeproj \
    -scheme AbendrotAppStore \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    ABENDROT_SOURCE_COMMIT="$(git rev-parse HEAD)" \
    clean archive

./scripts/release/test-mac-app-store.sh --distribution "$APP"

xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist scripts/release/ExportOptions-AppStore.plist \
    -allowProvisioningUpdates

echo "App Store archive: $ARCHIVE_PATH"
echo "Local export: $EXPORT_PATH"
