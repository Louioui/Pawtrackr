#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

echo "Validating Pawtrackr test and migration gates"

export SWIFT_STRICT_CONCURRENCY=complete

# Store upgrades rely on SwiftData's inferred lightweight migration. A staged
# migration plan built from the live model classes is what locked every 1.0.1
# user out of 1.0.2 (NSCocoaErrorDomain 134504). See
# docs/adr/0004-inferred-lightweight-migration.md before reintroducing one.
if grep -rn --include="*.swift" -e "migrationPlan:" -e ": SchemaMigrationPlan" "$REPO_ROOT/Pawtrackr"; then
  echo "Build failed: a SwiftData migration plan is back in the app target (see ADR-0004)."
  exit 1
fi

FIXTURES_DIR="$REPO_ROOT/PawtrackrTests/Fixtures"
if [ ! -f "$REPO_ROOT/PawtrackrTests/StoreUpgradeRegressionTests.swift" ] || [ ! -f "$FIXTURES_DIR/StoreFixtures.md" ]; then
  echo "Build failed: the store upgrade regression test or PawtrackrTests/Fixtures/StoreFixtures.md is missing."
  exit 1
fi
# Every shipped-store fixture listed in StoreFixtures.md must be checked in.
for fixture in $(grep -o 'Pawtrackr-[0-9][0-9.]*-build[0-9]*\.sqlite' "$FIXTURES_DIR/StoreFixtures.md" | sort -u); do
  if [ ! -f "$FIXTURES_DIR/$fixture" ]; then
    echo "Build failed: StoreFixtures.md lists $fixture, but it isn't in PawtrackrTests/Fixtures."
    exit 1
  fi
done

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
