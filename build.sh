#!/usr/bin/env bash
# build.sh — Nex-Gen Lumina release build scripts
# Usage: ./build.sh <target>
#
# Targets:
#   build-android-release   APK + AAB with obfuscation
#   build-ios-release       iOS archive with obfuscation
#   build-all-release       Both platforms
#
# Debug symbols are written to build/debug-info/ and must be retained
# for crash symbolication (never ship or delete these files).

set -euo pipefail

TARGET="${1:-help}"

build_android_release() {
  # Pre-flight: refuse to rebuild the same versionCode that the last
  # completed build used. Play Console rejects duplicate versionCodes,
  # and Android has no auto-bumper (codemagic.yaml's PROJECT_BUILD_NUMBER
  # rewrite only fires for iOS). Tyler hit this twice on 2026-05-18 →
  # 2026-05-19 — the structural fix is to make the script refuse
  # rather than rely on remembering to bump pubspec.
  #
  # Marker lives at repo root (NOT under build/) so it survives
  # `flutter clean`. Gitignored, local-only per checkout.
  local marker=".android-versioncode-state"
  local current
  current=$(grep '^version:' pubspec.yaml | sed -E 's/^version: *[^+]+\+([0-9]+).*/\1/')
  if [[ -z "$current" || ! "$current" =~ ^[0-9]+$ ]]; then
    echo "ERROR: could not parse versionCode from pubspec.yaml 'version:' line." >&2
    exit 1
  fi

  echo "==> Android build at versionCode $current"

  if [[ -f "$marker" ]]; then
    local previous
    previous=$(cat "$marker" 2>/dev/null || echo "")
    if [[ "$current" == "$previous" ]]; then
      echo ""
      echo "  WARNING: versionCode $current was already used by the last"
      echo "  completed Android build on this machine. Play Console will"
      echo "  reject this AAB if versionCode $current is already published."
      echo ""
      echo "  Bump pubspec.yaml from 'version: <name>+$current' to"
      echo "  'version: <name>+$((current+1))' and re-run this script."
      echo ""
      if [[ -t 0 ]]; then
        read -rp "  Override and rebuild anyway? [y/N]: " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
          echo "  Aborting."
          exit 1
        fi
        echo "  Override accepted — proceeding."
      else
        if [[ "${FORCE:-}" != "1" ]]; then
          echo "  Non-interactive shell. Set FORCE=1 to override:"
          echo "    FORCE=1 $0 $TARGET"
          exit 1
        fi
        echo "  FORCE=1 set in non-interactive shell — proceeding."
      fi
      echo ""
    fi
  fi

  echo "==> Building Android APK (obfuscated)..."
  flutter build apk \
    --release \
    --obfuscate \
    --split-debug-info=build/debug-info/android

  echo "==> Building Android App Bundle (obfuscated)..."
  flutter build appbundle \
    --release \
    --obfuscate \
    --split-debug-info=build/debug-info/android

  # Record successful build's versionCode so the next invocation
  # detects a stale-pubspec rebuild attempt.
  echo "$current" > "$marker"

  echo "==> Android release build complete (versionCode $current)."
  echo "    Debug symbols: build/debug-info/android/"
  echo "    Versioncode marker updated: $marker"
}

build_ios_release() {
  echo "==> Building iOS (obfuscated)..."
  flutter build ios \
    --release \
    --obfuscate \
    --split-debug-info=build/debug-info/ios

  echo "==> iOS release build complete."
  echo "    Debug symbols: build/debug-info/ios/"
}

case "$TARGET" in
  build-android-release)
    build_android_release
    ;;
  build-ios-release)
    build_ios_release
    ;;
  build-all-release)
    build_android_release
    build_ios_release
    ;;
  help|*)
    echo "Usage: ./build.sh <target>"
    echo ""
    echo "Targets:"
    echo "  build-android-release   APK + AAB with obfuscation"
    echo "  build-ios-release       iOS archive with obfuscation"
    echo "  build-all-release       Both platforms"
    echo ""
    echo "Debug symbols are written to build/debug-info/ — keep these"
    echo "for crash symbolication. Do not commit them to source control."
    ;;
esac
