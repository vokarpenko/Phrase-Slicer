#!/usr/bin/env bash
set -euo pipefail

APP_PATH="build/macos/Build/Products/Release/Phrase Slicer.app"
ENTITLEMENTS_PATH="macos/Runner/Release.entitlements"
ARTIFACTS_DIR="build/artifacts"
MACOS_ZIP_PATH="$ARTIFACTS_DIR/phrase-slicer-macos.zip"
MACOS_DMG_PATH="$ARTIFACTS_DIR/phrase-slicer-macos.dmg"
LAUNCH_AFTER_BUILD=true
SIGN_ONLY=false
PACKAGE_ONLY=false

usage() {
  cat <<'EOF'
Usage:
  ./tool/build_macos_release.sh [--no-launch]
  ./tool/build_macos_release.sh --sign-only [app-path] [entitlements-path]
  ./tool/build_macos_release.sh --package-only [app-path]

Options:
  --no-launch     Build, sign, and package, but do not open the app. Use this in CI.
  --sign-only     Only ad-hoc sign an already built .app bundle.
  --package-only  Only create zip and dmg artifacts from an already built .app.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-launch)
      LAUNCH_AFTER_BUILD=false
      shift
      ;;
    --sign-only)
      SIGN_ONLY=true
      shift
      if [[ $# -gt 0 && "$1" != --* ]]; then
        APP_PATH="$1"
        shift
      fi
      if [[ $# -gt 0 && "$1" != --* ]]; then
        ENTITLEMENTS_PATH="$1"
        shift
      fi
      ;;
    --package-only)
      PACKAGE_ONLY=true
      shift
      if [[ $# -gt 0 && "$1" != --* ]]; then
        APP_PATH="$1"
        shift
      fi
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

sign_app() {
  if [[ ! -d "$APP_PATH" ]]; then
    echo "App bundle not found: $APP_PATH" >&2
    exit 1
  fi

  # Local release builds can inherit quarantine/provenance metadata from copied
  # frameworks. Clear it before signing so LaunchServices uses the fresh bundle.
  xattr -cr "$APP_PATH" 2>/dev/null || true

  if [[ -f "$ENTITLEMENTS_PATH" ]]; then
    codesign --force --deep --sign - --entitlements "$ENTITLEMENTS_PATH" "$APP_PATH"
  else
    codesign --force --deep --sign - "$APP_PATH"
  fi

  codesign --verify --deep --strict --verbose=2 "$APP_PATH"

  # Some macOS versions attach provenance metadata during local builds. It is not
  # needed for an ad-hoc signed development artifact and can affect double-click
  # launch behavior.
  xattr -cr "$APP_PATH" 2>/dev/null || true
}

package_app() {
  if [[ ! -d "$APP_PATH" ]]; then
    echo "App bundle not found: $APP_PATH" >&2
    exit 1
  fi

  mkdir -p "$ARTIFACTS_DIR"
  rm -f "$MACOS_ZIP_PATH" "$MACOS_DMG_PATH"

  ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$MACOS_ZIP_PATH"
  hdiutil create \
    -volname "Phrase Slicer" \
    -srcfolder "$APP_PATH" \
    -ov \
    -format UDZO \
    "$MACOS_DMG_PATH"

  echo "Created:"
  echo "  $MACOS_ZIP_PATH"
  echo "  $MACOS_DMG_PATH"
}

if [[ "$SIGN_ONLY" == true ]]; then
  sign_app
  exit 0
fi

if [[ "$PACKAGE_ONLY" == true ]]; then
  package_app
  exit 0
fi

pkill -f "Phrase Slicer.app/Contents/MacOS/Phrase Slicer" 2>/dev/null || true
pkill -x "Phrase Slicer" 2>/dev/null || true

flutter clean
rm -rf build/macos

flutter pub get
flutter build macos --release

sign_app
package_app

if [[ "$LAUNCH_AFTER_BUILD" == false ]]; then
  echo "Built, signed, and packaged: $APP_PATH"
  exit 0
fi

open -n "$APP_PATH"
sleep 3

if pgrep -fl "Phrase Slicer.app/Contents/MacOS/Phrase Slicer" >/dev/null; then
  echo "Phrase Slicer is running."
else
  echo "Phrase Slicer closed during launch. Recent logs:" >&2
  log show --style compact --last 2m \
    --predicate 'process == "Phrase Slicer" OR eventMessage CONTAINS[c] "Phrase Slicer" OR eventMessage CONTAINS[c] "phraseslicer"' \
    2>/dev/null | tail -120 >&2 || true
  exit 1
fi
