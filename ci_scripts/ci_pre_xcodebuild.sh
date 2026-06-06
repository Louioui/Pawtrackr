#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

echo "Validating Pawtrackr test and migration gates"

export SWIFT_STRICT_CONCURRENCY=complete

if ! grep -q "PawtrackrMigrationPlan" "$REPO_ROOT/Pawtrackr/Core/Storage/Migrations.swift"; then
  echo "Build failed: migration plan declaration was not found."
  exit 1
fi

if ! grep -q "PawtrackrTests" "$REPO_ROOT/TestPlan.xctestplan"; then
  echo "Build failed: PawtrackrTests is missing from TestPlan.xctestplan."
  exit 1
fi

if ! grep -q "PawtrackrUITests" "$REPO_ROOT/TestPlan.xctestplan"; then
  echo "Build failed: PawtrackrUITests is missing from TestPlan.xctestplan."
  exit 1
fi

if ! find "$REPO_ROOT/QualityControl" -name "*ChaosTests.swift" -type f | grep -q .; then
  echo "Build failed: QualityControl chaos test coverage was not found."
  exit 1
fi

if ! grep -q "QualityControl" "$REPO_ROOT/Pawtrackr.xcodeproj/project.pbxproj"; then
  echo "Build failed: QualityControl is not wired into the Xcode test target."
  exit 1
fi

echo "Pawtrackr test and migration gates passed"
