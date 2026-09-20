#!/usr/bin/env bash
# signing_inputs.sh — the git-ignored Android release build inputs, and where they
# may come from. docs/BUILD_LEDGER.md standing convention 3.
#
#   bash scripts/signing_inputs.sh verify     compare this checkout's copies with the
#                                             main repo's, byte for byte (default)
#   bash scripts/signing_inputs.sh install    copy them FROM THE MAIN REPO into this
#                                             checkout, then verify
#
# The set:   android/key.properties
#            android/app/<storeFile named in key.properties>   (release keystore)
#            android/app/google-services.json
#
# "Main repo" = the main working tree of this git repository: the first entry of
# `git worktree list`. Nothing is hardcoded. A separate clone cannot discover it;
# set LUMINA_SIGNING_CANONICAL_DIR=<path to the main checkout>.
#
# THE ENFORCEMENT IS NOT THIS SCRIPT. android/signing-inputs-guard.gradle runs the
# same comparison before every Android release build, however it is started, and
# has no skip flag. This script is the convenient way to be right the first time:
# `install` is the only sanctioned way to put these files into a build worktree —
# never copy them from another build worktree.
#
# Nothing here prints file contents or hashes (key.properties holds passwords).

set -euo pipefail

cmd="${1:-verify}"

here="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "signing_inputs: not inside a git checkout." >&2; exit 2; }

if [[ -n "${LUMINA_SIGNING_CANONICAL_DIR:-}" ]]; then
  canon="$LUMINA_SIGNING_CANONICAL_DIR"
else
  canon="$(git -C "$here" worktree list --porcelain | sed -n '1s/^worktree //p')"
fi
if [[ -z "$canon" || ! -d "$canon" ]]; then
  echo "signing_inputs: cannot locate the main repo ('$canon')." >&2
  echo "  Set LUMINA_SIGNING_CANONICAL_DIR to the main checkout." >&2
  exit 2
fi

same_dir() { [[ "$(cd "$1" && pwd -P)" == "$(cd "$2" && pwd -P)" ]]; }

# The keystore that is actually used is whatever the MAIN REPO's key.properties names.
store_file=""
if [[ -f "$canon/android/key.properties" ]]; then
  store_file="$(sed -n 's/^storeFile=//p' "$canon/android/key.properties" | tr -d '\r' | head -1)"
fi
inputs=("android/key.properties")
if [[ -z "$store_file" ]]; then
  inputs+=("android/app/<storeFile: not defined in the main repo key.properties>")
elif [[ "$store_file" != /* && ! "$store_file" =~ ^[A-Za-z]:[\\/] ]]; then
  inputs+=("android/app/$store_file")
fi   # an absolute storeFile is the same file for every checkout: nothing to compare
inputs+=("android/app/google-services.json")

verify() {
  local bad=0 is_canon=0
  same_dir "$here" "$canon" && is_canon=1
  echo "  this checkout : $here"
  if (( is_canon )); then
    echo "  main repo     : $canon   (same - inputs here ARE the canonical set)"
  else
    echo "  main repo     : $canon"
  fi
  echo
  local rel
  for rel in "${inputs[@]}"; do
    local verdict
    if [[ ! -f "$canon/$rel" ]]; then
      verdict="MISSING IN THE MAIN REPO"; bad=1
    elif [[ ! -f "$here/$rel" ]]; then
      verdict="MISSING HERE"; bad=1
    elif (( is_canon )); then
      verdict="present ($(wc -c < "$here/$rel" | tr -d ' ') B) - this checkout is the main repo"
    elif cmp -s "$here/$rel" "$canon/$rel"; then
      verdict="IDENTICAL to the main repo ($(wc -c < "$here/$rel" | tr -d ' ') B)"
    else
      verdict="DIFFERS from the main repo (here $(wc -c < "$here/$rel" | tr -d ' ') B, main repo $(wc -c < "$canon/$rel" | tr -d ' ') B)"
      bad=1
    fi
    printf '    %-42s %s\n' "$rel" "$verdict"
  done
  echo
  return $bad
}

case "$cmd" in
  verify)
    echo "SIGNING INPUTS - verify"
    if verify; then
      echo "OK: the release build inputs are the canonical main-repo set."
    else
      {
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "FAILED: the release build inputs in this checkout are NOT the canonical"
        echo "main-repo set. Do not build. Do not copy them from another build worktree."
        echo "Fix:   bash scripts/signing_inputs.sh install"
        echo "Rule:  docs/BUILD_LEDGER.md, standing convention 3."
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
      } >&2
      exit 1
    fi
    ;;
  install)
    echo "SIGNING INPUTS - install from the main repo"
    if same_dir "$here" "$canon"; then
      echo "  This checkout IS the main repo ($here): nothing to install." >&2
      exit 1
    fi
    for rel in "${inputs[@]}"; do
      if [[ ! -f "$canon/$rel" ]]; then
        echo "  MISSING IN THE MAIN REPO: $rel - cannot install." >&2
        exit 1
      fi
      # All three must be git-ignored HERE, or a copy could leak into a commit.
      if ! git -C "$here" check-ignore -q "$rel"; then
        echo "  REFUSING: $rel is not git-ignored in this checkout." >&2
        exit 1
      fi
      mkdir -p "$(dirname "$here/$rel")"
      cp -p "$canon/$rel" "$here/$rel"
      echo "  copied  $rel"
    done
    echo
    verify || { echo "FAILED: copies do not match the main repo after install." >&2; exit 1; }
    echo "OK: installed from the main repo and verified."
    ;;
  *)
    echo "Usage: bash scripts/signing_inputs.sh [verify|install]" >&2
    exit 2
    ;;
esac
