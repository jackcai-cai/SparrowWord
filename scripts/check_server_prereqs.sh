#!/usr/bin/env bash

set -euo pipefail

echo "SparrowWord server prerequisite check"
echo

check_bin() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then
    printf "OK    %-10s %s\n" "$name" "$("$name" --version 2>/dev/null | head -n 1 || echo installed)"
  else
    printf "MISS  %-10s not installed\n" "$name"
  fi
}

check_alt() {
  local label="$1"
  shift
  for candidate in "$@"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      printf "OK    %-10s %s\n" "$label" "$("$candidate" --version 2>/dev/null | head -n 1 || echo installed)"
      return
    fi
  done

  printf "MISS  %-10s not installed\n" "$label"
}

check_bin git
check_alt node node nodejs
check_alt npm npm
check_alt sqlite sqlite3
check_alt python python3 python

echo
echo "Recommended for the future web dictionary API:"
echo "- git"
echo "- node + npm"
echo "- sqlite3"
echo "- python3 (optional helper tooling)"
