#!/usr/bin/env bash
# Copyright (c) 2021-2025 community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
#
# Sync with upstream community-scripts/ProxmoxVE repository
# One-way pull from upstream into this fork (no push back to upstream)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM_URL="https://github.com/community-scripts/ProxmoxVE.git"
UPSTREAM_BRANCH="main"

cd "$REPO_ROOT"

echo "=== ProxmoxVE Upstream Sync (Pull Only) ==="
echo ""
echo "Repo root: ${REPO_ROOT}"
echo ""

# Ensure upstream remote exists
if ! git remote | grep -q '^upstream$'; then
  echo "Adding upstream remote..."
  git remote add upstream "$UPSTREAM_URL"
fi

# Fetch upstream
echo "Fetching upstream changes..."
git fetch upstream

# Get current branch
CURRENT_BRANCH=$(git branch --show-current)
echo "Current branch: ${CURRENT_BRANCH}"
echo ""

# Show pending changes
echo "=== Changes from upstream/${UPSTREAM_BRANCH} ==="
COMMITS=$(git log --oneline "HEAD..upstream/${UPSTREAM_BRANCH}" 2>/dev/null | wc -l)

if [[ "$COMMITS" -eq 0 ]]; then
  echo "Already up to date with upstream."
  exit 0
fi

git log --oneline "HEAD..upstream/${UPSTREAM_BRANCH}" | head -20
if [[ "$COMMITS" -gt 20 ]]; then
  echo "... and $((COMMITS - 20)) more commits"
fi

echo ""
echo "Total: ${COMMITS} new commits from upstream"
echo ""

# Auto mode for cron/scripts
if [[ "${1:-}" == "--auto" ]]; then
  echo "Auto mode: attempting merge..."
  if git merge "upstream/${UPSTREAM_BRANCH}" --no-edit; then
    echo ""
    echo "Merge successful."

    # Re-run transformation script to handle new scripts
    if [[ -x "${REPO_ROOT}/tools/localize-scripts.sh" ]]; then
      echo ""
      echo "Re-running script localization..."
      "${REPO_ROOT}/tools/localize-scripts.sh"
    fi

    echo ""
    echo "Sync complete."
  else
    echo ""
    echo "MERGE CONFLICT - manual resolution required"
    echo ""
    echo "To resolve:"
    echo "  cd ${REPO_ROOT}"
    echo "  git status              # See conflicting files"
    echo "  # Edit files to resolve conflicts"
    echo "  git add <files>"
    echo "  git commit"
    echo ""
    git merge --abort 2>/dev/null || true
    exit 1
  fi
  exit 0
fi

# Interactive mode
echo -n "Merge these changes? [y/N] "
read -r response

if [[ "${response,,}" =~ ^y ]]; then
  if git merge "upstream/${UPSTREAM_BRANCH}" --no-edit; then
    echo ""
    echo "Merge successful!"
    echo ""

    # Re-run transformation script
    if [[ -x "${REPO_ROOT}/tools/localize-scripts.sh" ]]; then
      echo -n "Re-run script localization? [Y/n] "
      read -r transform
      if [[ ! "${transform,,}" =~ ^n ]]; then
        "${REPO_ROOT}/tools/localize-scripts.sh"
      fi
    fi

    echo ""
    echo "Sync complete."
  else
    echo ""
    echo "Merge conflicts detected. Please resolve manually:"
    echo ""
    echo "  git status              # See conflicting files"
    echo "  # Edit files to resolve conflicts"
    echo "  git add <files>"
    echo "  git commit"
    echo ""
    exit 1
  fi
else
  echo "Merge cancelled."
fi
