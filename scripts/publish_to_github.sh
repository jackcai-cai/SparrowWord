#!/usr/bin/env bash

set -euo pipefail

REPO_NAME="${1:-SparrowWord}"
OWNER="${2:-}"
REMOTE_NAME="${REMOTE_NAME:-origin}"
VISIBILITY="${VISIBILITY:-private}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: current directory is not a git repository." >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: GitHub CLI (gh) is not installed." >&2
  exit 1
fi

if ! git config user.name >/dev/null 2>&1; then
  echo "Error: git user.name is not configured." >&2
  echo 'Run: git config --global user.name "Your Name"' >&2
  exit 1
fi

if ! git config user.email >/dev/null 2>&1; then
  echo "Error: git user.email is not configured." >&2
  echo 'Run: git config --global user.email "you@example.com"' >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "Error: GitHub CLI is not logged in." >&2
  echo "Run: gh auth login" >&2
  exit 1
fi

if ! git rev-parse HEAD >/dev/null 2>&1; then
  echo "Error: there is no commit yet." >&2
  echo 'Run: git add . && git commit -m "chore: initial SparrowWord baseline"' >&2
  exit 1
fi

CURRENT_BRANCH="$(git branch --show-current)"
if [[ -z "$CURRENT_BRANCH" ]]; then
  echo "Error: could not determine the current branch." >&2
  exit 1
fi

if git remote get-url "$REMOTE_NAME" >/dev/null 2>&1; then
  echo "Remote '$REMOTE_NAME' already exists. Pushing $CURRENT_BRANCH..."
  git push -u "$REMOTE_NAME" "$CURRENT_BRANCH"
  exit 0
fi

if [[ -n "$OWNER" ]]; then
  REPO_SPEC="$OWNER/$REPO_NAME"
else
  REPO_SPEC="$REPO_NAME"
fi

echo "Creating $VISIBILITY GitHub repository: $REPO_SPEC"
gh repo create "$REPO_SPEC" --"$VISIBILITY" --source=. --remote="$REMOTE_NAME" --push
echo "Done. Remote '$REMOTE_NAME' now points to $REPO_SPEC and $CURRENT_BRANCH has been pushed."
