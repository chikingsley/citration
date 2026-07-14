#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
prefix="services/zotero-selfhost"
remote="${ZOTERO_SELFHOST_REMOTE:-https://github.com/chikingsley/zotero-selfhost.git}"
action="${1:-status}"

cd "$repo_root"

require_clean() {
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "The Citration worktree must be clean before subtree synchronization." >&2
    exit 1
  fi
}

case "$action" in
  status)
    standalone_head="$(git ls-remote "$remote" refs/heads/main | awk '{print $1}')"
    subtree_head="$(git subtree split --prefix="$prefix" HEAD)"
    printf 'standalone main: %s\n' "$standalone_head"
    printf 'monorepo split:  %s\n' "$subtree_head"
    if [[ "$standalone_head" == "$subtree_head" ]]; then
      echo "Zotero Self-Host subtree is synchronized."
    else
      echo "Zotero Self-Host subtree differs; pull or push after reviewing both histories."
      exit 1
    fi
    ;;
  pull)
    require_clean
    git subtree pull --prefix="$prefix" "$remote" main -m "Sync Zotero Self-Host from standalone repository"
    ;;
  push)
    require_clean
    git subtree push --prefix="$prefix" "$remote" main
    ;;
  *)
    echo "Usage: $0 [status|pull|push]" >&2
    exit 2
    ;;
esac
