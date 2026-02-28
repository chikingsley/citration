#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/commit-swift-checked.sh --message "your commit message" [options]

Options:
  -m, --message <msg>   Commit message (required)
  --remote <name>       Git remote to push to (default: origin)
  --no-push             Commit only; do not push
  --skip-lint           Skip SwiftLint check
  --skip-test           Skip Swift tests
  -h, --help            Show this help

Examples:
  ./scripts/commit-swift-checked.sh -m "feat: polish app shell"
  ./scripts/commit-swift-checked.sh -m "chore: wip" --no-push
USAGE
}

MESSAGE=""
REMOTE="origin"
DO_PUSH=true
RUN_LINT=true
RUN_TEST=true

while [ "$#" -gt 0 ]; do
  case "$1" in
    -m|--message)
      MESSAGE="${2:-}"
      shift 2
      ;;
    --remote)
      REMOTE="${2:-}"
      shift 2
      ;;
    --no-push)
      DO_PUSH=false
      shift
      ;;
    --skip-lint)
      RUN_LINT=false
      shift
      ;;
    --skip-test)
      RUN_TEST=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [ -z "$MESSAGE" ]; then
  echo "Error: --message is required." >&2
  usage
  exit 1
fi

cd "$ROOT_DIR"

if [ "$RUN_LINT" = true ]; then
  echo "→ Running SwiftLint"
  "$ROOT_DIR/scripts/lint-swift.sh"
fi

if [ "$RUN_TEST" = true ]; then
  echo "→ Running Swift package tests"
  "$ROOT_DIR/scripts/test-swift.sh"
fi

echo "→ Staging changes"
git add -A

if git diff --cached --quiet; then
  echo "No staged changes to commit."
  exit 1
fi

echo "→ Committing"
git commit -m "$MESSAGE"

if [ "$DO_PUSH" = true ]; then
  BRANCH="$(git branch --show-current)"
  echo "→ Pushing to ${REMOTE}/${BRANCH}"
  git push "$REMOTE" "$BRANCH"
fi

echo "Done."
