#!/bin/sh
set -eu

echo "Pawtrackr Xcode Cloud action completed with CI_XCODEBUILD_EXIT_CODE=${CI_XCODEBUILD_EXIT_CODE:-unknown}"

if [ "${CI_XCODEBUILD_EXIT_CODE:-0}" != "0" ]; then
  echo "xcodebuild reported a failure; Xcode Cloud will keep diagnostics in the build report."
  exit 0
fi

echo "Archive/test action succeeded. TestFlight distribution is handled by the Xcode Cloud workflow post-action."
