#!/usr/bin/env bash
# Run the same lint checks that .github/workflows/ci.yml runs, locally.
#
# Usage:
#   scripts/lint.sh            # check only
#   scripts/lint.sh --fix      # auto-format (gdformat + cargo fmt), then lint
set -uo pipefail

cd "$(dirname "$0")/.."

FIX=0
[[ "${1:-}" == "--fix" ]] && FIX=1

fail=0
step() {
  local name="$1"
  shift
  echo "== $name =="
  if "$@"; then
    echo "-- $name: ok"
  else
    echo "!! $name: FAILED"
    fail=1
  fi
  echo
}

if [[ $FIX -eq 1 ]]; then
  step "gdformat (write)" gdformat --line-length 100 godot/
  step "cargo fmt (write)" bash -c 'cd rust && cargo fmt --all'
fi

step "gdformat --check" gdformat --check --line-length 100 godot/
step "gdlint" gdlint godot/
step "cargo fmt --check" bash -c 'cd rust && cargo fmt --all --check'
step "cargo clippy" bash -c 'cd rust && cargo clippy --workspace --all-targets -- -D warnings'

if [[ $fail -eq 0 ]]; then
  echo "All lint checks passed."
else
  echo "Lint checks FAILED. Run 'scripts/lint.sh --fix' to auto-format, then fix remaining gdlint/clippy issues."
fi
exit $fail
