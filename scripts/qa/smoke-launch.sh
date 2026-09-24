#!/usr/bin/env bash
set -euo pipefail

APP="${1:-}"
if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  echo "usage: $0 /path/to/Abendrot.app" >&2
  exit 2
fi
APP="$(cd "$APP" && pwd -P)"

INFO="$APP/Contents/Info.plist"
EXECUTABLE_NAME="$(/usr/bin/plutil -extract CFBundleExecutable raw "$INFO")"
EXECUTABLE="$APP/Contents/MacOS/$EXECUTABLE_NAME"
[ -x "$EXECUTABLE" ] || {
  echo "missing executable: $EXECUTABLE" >&2
  exit 1
}

find_pid() {
  # Consume the full ps stream; an early exit can cause SIGPIPE under pipefail.
  /bin/ps -axww -o pid=,command= | /usr/bin/awk -v executable="$EXECUTABLE" '
    { candidate = $1; sub(/^[[:space:]]*[0-9]+[[:space:]]+/, "") }
    $0 == executable && !found { print candidate; found = 1 }
  '
}

# Never mistake a previous instance for the launch under test or terminate it.
if [ -n "$(find_pid)" ]; then
  echo "app is already running; quit this bundle before its launch test: $APP" >&2
  exit 1
fi

TMP="$(mktemp -d -t abendrot-launch.XXXXXX)"
LOG="$TMP/launch.log"
pid=""
is_test_process() {
  [ -n "$pid" ] && [ "$(/bin/ps -ww -p "$pid" -o command= 2>/dev/null)" = "$EXECUTABLE" ]
}
cleanup() {
  if is_test_process; then
    kill -TERM "$pid" 2>/dev/null || true
    for _ in $(seq 1 10); do
      is_test_process || break
      sleep 1
    done
    if is_test_process; then kill -KILL "$pid" 2>/dev/null || true; fi
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT

/usr/bin/open -n --stdout "$LOG" --stderr "$LOG" "$APP"
for _ in $(seq 1 20); do
  pid="$(find_pid)"
  if is_test_process; then
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
  if ! is_test_process; then
    echo "bundle exited during the 20-second LaunchServices smoke test:" >&2
    cat "$LOG" >&2
    exit 1
  fi
  sleep 1
done

# A running AppKit loop alone does not prove the model or engine started (#28).
# Match this bundle's PID so another installed copy or a stale snapshot cannot pass.
STATE="$HOME/Library/Application Support/Abendrot/state.json"
SNAPSHOT_PID="$(/usr/bin/plutil -extract pid raw -o - "$STATE" 2>/dev/null || true)"
if ! is_test_process || [ "$SNAPSHOT_PID" != "$pid" ]; then
  echo "bundle stayed running but did not publish its live state: $STATE" >&2
  cat "$LOG" >&2
  exit 1
fi

echo "PASS: $APP stayed running for 20 seconds and published live state for PID $pid"
