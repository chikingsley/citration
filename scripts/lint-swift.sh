#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_PATH="${ROOT_DIR}/.swiftlint.yml"
echo "Running SwiftLint from: ${ROOT_DIR}"

if ! command -v swiftlint >/dev/null 2>&1; then
  cat <<'EOF' >&2
swiftlint is not installed.

Install it with:
- macOS:  brew install swiftlint
- Linux:  curl -L https://raw.githubusercontent.com/realm/SwiftLint/main/install.sh | bash
EOF
  exit 1
fi

if [ "${1:-}" = "--fix" ]; then
  swiftlint lint \
    --config "${CONFIG_PATH}" \
    --strict \
    --quiet \
    --fix \
    --cache-path "${ROOT_DIR}/.swiftlint_cache"
else
  swiftlint lint \
    --config "${CONFIG_PATH}" \
    --strict \
    --quiet \
    --cache-path "${ROOT_DIR}/.swiftlint_cache"
fi
