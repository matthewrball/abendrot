#!/usr/bin/env bash
set -euo pipefail

APP="${1:-}"
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  echo "usage: $0 /path/to/Abendrot.app" >&2
  exit 2
fi

INFO="$APP/Contents/Info.plist"
EXECUTABLE_NAME="$(/usr/bin/plutil -extract CFBundleExecutable raw "$INFO")"
EXECUTABLE="$APP/Contents/MacOS/$EXECUTABLE_NAME"
MINIMUM_OS="$(/usr/bin/plutil -extract LSMinimumSystemVersion raw "$INFO")"
EXPECTED_MINIMUM_SYSTEM_VERSION="12.0"

[ "$MINIMUM_OS" = "$EXPECTED_MINIMUM_SYSTEM_VERSION" ] || {
  echo "expected LSMinimumSystemVersion $EXPECTED_MINIMUM_SYSTEM_VERSION, got $MINIMUM_OS" >&2
  exit 1
}
[ -x "$EXECUTABLE" ] || {
  echo "missing executable: $EXECUTABLE" >&2
  exit 1
}

mach_o_count=0
while IFS= read -r -d '' file; do
  if [[ "$(/usr/bin/file -b "$file")" != Mach-O* ]]; then
    continue
  fi
  mach_o_count=$((mach_o_count + 1))
  /usr/bin/lipo "$file" -verify_arch arm64 x86_64 || {
    echo "not universal (arm64 + x86_64): $file" >&2
    exit 1
  }
  build_info="$(/usr/bin/xcrun vtool -show-build "$file" 2>/dev/null)" || {
    echo "could not inspect deployment floor: $file" >&2
    exit 1
  }
  printf '%s\n' "$build_info" | /usr/bin/awk \
    -v maximum="$EXPECTED_MINIMUM_SYSTEM_VERSION" '
      function encoded(version, parts, count) {
        count = split(version, parts, ".")
        return (parts[1] + 0) * 1000000 + (parts[2] + 0) * 1000 + (parts[3] + 0)
      }
      $1 == "minos" {
        seen = 1
        if (encoded($2) > encoded(maximum)) too_new = 1
      }
      END { if (!seen || too_new) exit 1 }
    ' || {
      echo "$file requires newer than macOS $EXPECTED_MINIMUM_SYSTEM_VERSION" >&2
      exit 1
    }
done < <(find "$APP/Contents" -type f -print0)

[ "$mach_o_count" -gt 0 ] || {
  echo "no Mach-O files found in $APP" >&2
  exit 1
}

echo "PASS: $APP and every nested Mach-O are universal and target macOS $EXPECTED_MINIMUM_SYSTEM_VERSION or earlier"
