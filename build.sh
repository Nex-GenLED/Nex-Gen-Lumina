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

  echo "==> Android release build complete."
  echo "    Debug symbols: build/debug-info/android/"
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
