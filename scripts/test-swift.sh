#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PACKAGE_DIRS=()
while IFS= read -r package_dir; do
  PACKAGE_DIRS+=("${package_dir}")
done < <(find "${ROOT_DIR}/Apps" "${ROOT_DIR}/Packages" -mindepth 1 -maxdepth 2 -type f -name Package.swift -exec dirname {} \; | sort)

if [ "${#PACKAGE_DIRS[@]}" -eq 0 ]; then
  echo "No Swift packages found under Apps/ or Packages/" >&2
  exit 1
fi

for package_dir in "${PACKAGE_DIRS[@]}"; do
  echo "→ swift test (${package_dir#${ROOT_DIR}/})"
  (
    cd "${package_dir}"
    swift test --parallel
  )
done
