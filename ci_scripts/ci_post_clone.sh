#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

echo "Starting Pawtrackr enterprise build preflight"

export SWIFT_STRICT_CONCURRENCY=complete

TRANSLATION_HITS=$(
  find "$REPO_ROOT/Pawtrackr" \( -name "Localizable.strings" -o -name "*.xcstrings" \) -type f -print0 |
    xargs -0 grep -n "FIXME_TRANSLATION" 2>/dev/null || true
)

if [ -n "$TRANSLATION_HITS" ]; then
  echo "Build failed: incomplete localized strings detected."
  echo "$TRANSLATION_HITS"
  exit 1
fi

/usr/bin/plutil -lint "$REPO_ROOT/Pawtrackr-iOS-Info.plist"

if [ -n "${PAWTRACKR_ENTERPRISE_ENVIRONMENT:-}" ]; then
  /usr/libexec/PlistBuddy \
    -c "Set :EnterpriseEnvironmentName ${PAWTRACKR_ENTERPRISE_ENVIRONMENT}" \
    "$REPO_ROOT/Pawtrackr-iOS-Info.plist" 2>/dev/null ||
  /usr/libexec/PlistBuddy \
    -c "Add :EnterpriseEnvironmentName string ${PAWTRACKR_ENTERPRISE_ENVIRONMENT}" \
    "$REPO_ROOT/Pawtrackr-iOS-Info.plist"
fi

if [ -n "${VAULT_SECRET_TOKEN:-}" ]; then
  echo "VAULT_SECRET_TOKEN is present in Xcode Cloud and intentionally not embedded into Info.plist."
fi

echo "Pawtrackr preflight complete"
