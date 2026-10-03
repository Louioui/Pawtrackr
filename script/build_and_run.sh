#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
case "$MODE" in
  run|--debug|--logs|--telemetry|--verify) ;;
  *) echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Pawtrackr"
DERIVED_DIR="$ROOT_DIR/DerivedData/LocalRun"
APP_BUNDLE="$DERIVED_DIR/Build/Products/Debug/$APP_NAME.app"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
xcodebuild -project "$ROOT_DIR/Pawtrackr.xcodeproj" -scheme "$APP_NAME" \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DIR" CODE_SIGNING_ALLOWED=NO build

# Desktop/File Provider can attach Finder metadata to generated bundles.
# Remove it from this build artifact before signing.
xattr -cr "$APP_BUNDLE"

# Ad-hoc signing supports local development without a provisioning profile.
codesign --force --sign - --entitlements "$ROOT_DIR/Pawtrackr/Pawtrackr-Debug.entitlements" "$APP_BUNDLE"
case "$MODE" in
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  --logs)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'process == "Pawtrackr"'
    ;;
  --telemetry)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "PartnerShipWithMedia.Pawtrackr"'
    ;;
  --verify)
    /usr/bin/open -n "$APP_BUNDLE"
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
esac
