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
[ -x "$EXECUTABLE" ] || {
  echo "missing executable: $EXECUTABLE" >&2
  exit 1
}

TMP="$(mktemp -d -t abendrot-launch.XXXXXX)"
LOG="$TMP/launch.log"
pid=""
cleanup() {
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill -TERM "$pid" 2>/dev/null || true
    for _ in $(seq 1 10); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 1
    done
    kill -KILL "$pid" 2>/dev/null || true
  fi
  [ -z "$pid" ] || wait "$pid" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

/usr/bin/open -n "$APP" >"$LOG" 2>&1
for _ in $(seq 1 20); do
  # Read the full ps stream so pipefail does not treat an early awk exit as a
  # failed launch check (SIGPIPE from ps would otherwise abort this script).
  pid="$(/bin/ps -axo pid=,command= | /usr/bin/awk -v executable="$EXECUTABLE" '$2 == executable && !found { print $1; found = 1 }')"
  if [ -z "$pid" ]; then
    pid="$(/usr/bin/pgrep -x "$EXECUTABLE_NAME" | /usr/bin/head -1 || true)"
  fi
  if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    break
  fi
  sleep 1
done

[ -n "$pid" ] || {
  echo "bundle did not stay running through launch:" >&2
  cat "$LOG" >&2
  exit 1
}

for _ in $(seq 1 20); do
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "bundle exited during the 20-second LaunchServices smoke test:" >&2
    cat "$LOG" >&2
    exit 1
  fi
  sleep 1
done

echo "PASS: $APP stayed running through a 20-second LaunchServices smoke test"
