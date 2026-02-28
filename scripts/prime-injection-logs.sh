#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WORKSPACE="${1:-BetterCite.xcworkspace}"
SCHEME="${2:-BetterCiteApp}"
CONFIGURATION="${3:-Debug}"

INJECTION_TMP_DIR="$HOME/Library/Containers/com.johnholdsworth.InjectionIII/Data/tmp"
COMMAND_SH="$INJECTION_TMP_DIR/command.sh"

if [[ ! -f "$COMMAND_SH" ]]; then
  echo "error: InjectionIII command script not found at $COMMAND_SH" >&2
  echo "Open InjectionIII and connect it to the workspace first, then retry." >&2
  exit 1
fi

if ! command -v rg >/dev/null 2>&1; then
  echo "error: rg (ripgrep) is required for this script." >&2
  exit 1
fi

BUILD_LOG="$(mktemp -t bettercite-injection-build.XXXXXX.log)"
trap 'rm -f "$BUILD_LOG"' EXIT

echo "Building $SCHEME with EMIT_FRONTEND_COMMAND_LINES=YES ..."
(
  cd "$ROOT_DIR"
  xcodebuild \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'platform=macOS' \
    EMIT_FRONTEND_COMMAND_LINES=YES \
    clean build >"$BUILD_LOG" 2>&1
)

LOG_DIR="$(perl -ne 'if (/cd "([^"]+\/Logs\/Build)"/) { print "$1\n"; exit }' "$COMMAND_SH")"
if [[ -z "${LOG_DIR:-}" || ! -d "$LOG_DIR" ]]; then
  echo "error: Could not resolve InjectionIII build log directory from $COMMAND_SH" >&2
  exit 1
fi

FRONTEND_PATTERN='^/Applications/.*/swift-frontend -frontend -c .* -primary-file '
COMMAND_COUNT="$(rg "$FRONTEND_PATTERN" -N "$BUILD_LOG" | wc -l | tr -d ' ')"
if [[ "$COMMAND_COUNT" == "0" ]]; then
  echo "error: No swift-frontend compile lines were captured." >&2
  echo "See $BUILD_LOG for xcodebuild output." >&2
  exit 1
fi

FAKE_LOG="$LOG_DIR/FFFF0000-0000-0000-0000-FAKEINJECTALL.xcactivitylog"
{
  printf 'cd %s\r' "$ROOT_DIR"
  rg "$FRONTEND_PATTERN" -N "$BUILD_LOG" | while IFS= read -r line; do
    printf '%s\r' "$line"
  done
} | gzip -c >"$FAKE_LOG"
touch "$FAKE_LOG"

echo "Wrote $FAKE_LOG with $COMMAND_COUNT compile commands."

if bash "$COMMAND_SH" >/dev/null 2>&1 && [[ -s "$INJECTION_TMP_DIR/eval101.sh" ]]; then
  echo "InjectionIII parser check passed."
else
  echo "warning: InjectionIII parser check did not pass. Try saving a Swift file and rerun this script." >&2
fi
