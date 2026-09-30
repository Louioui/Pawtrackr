#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

echo "Validating Pawtrackr test and local persistence gates"

export SWIFT_STRICT_CONCURRENCY=complete

# Store upgrades rely on SwiftData's inferred lightweight migration. A staged
# migration plan built from the live model classes is what locked every 1.0.1
# user out of 1.0.2 (NSCocoaErrorDomain 134504). See
# docs/adr/0004-inferred-lightweight-migration.md before reintroducing one.
if grep -rn --include="*.swift" -e "migrationPlan:" -e ": SchemaMigrationPlan" "$REPO_ROOT/Pawtrackr"; then
  echo "Build failed: a SwiftData migration plan is back in the app target (see ADR-0004)."
  exit 1
fi

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/pawtrackr-ci.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT

SCHEMA_FILE="$REPO_ROOT/Pawtrackr/Core/Storage/Migrations.swift"
MODELS_DIR="$REPO_ROOT/Pawtrackr/Core/Storage/Models"

# The type names listed in PawtrackrSchema.models, with comments stripped.
sed -n '/^enum PawtrackrSchema/,/^}/p' "$SCHEMA_FILE" |
  sed 's://.*$::' |
  grep -o '[A-Z][A-Za-z0-9_]*\.self' |
  sed 's/\.self$//' |
  sort -u > "$WORK_DIR/schema-models" || true
if [ ! -s "$WORK_DIR/schema-models" ]; then
  echo "Build failed: couldn't read the model list from PawtrackrSchema.models in Migrations.swift."
  exit 1
fi

# Keep the shipped models available and avoid retrofitting uniqueness onto
# stores that can already contain duplicate legacy records. Model changes
# remain additive under the inferred-migration discipline in ADR-0004.
for model in $(cat "$WORK_DIR/schema-models"); do
  model_files=$(grep -rlE "^[[:space:]]*(@[A-Za-z]+[[:space:]]+)*((public|internal|final|open)[[:space:]]+)*class[[:space:]]+${model}([^A-Za-z0-9_]|$)" --include='*.swift' "$MODELS_DIR" || true)
  if [ -z "$model_files" ]; then
    echo "Build failed: $model is in PawtrackrSchema.models but no 'class $model' was found under Pawtrackr/Core/Storage/Models, so the shipped model list can't be checked."
    exit 1
  fi
  for model_file in $model_files; do
    # Joined into one line first, so @Attribute(\n .unique) and
    # @Attribute(.transformable(by: X.self), .unique) are caught too.
    if sed 's://.*$::' "$model_file" | tr '\n' ' ' | grep -qE '@Attribute\([^;{}]*\.unique([^A-Za-z0-9_]|$)|#Unique[[:space:]]*<'; then
      echo "Build failed: ${model_file#"$REPO_ROOT"/} declares a unique constraint on a shipped store model; keep upgrades additive."
      exit 1
    fi
  done
done

# Applies to every build action, including offline archives; no remote schema
# or management token is needed for the local store.
python3 "$SCRIPT_DIR/validate_local_persistence.py" "$REPO_ROOT"

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

echo "Pawtrackr test and local persistence gates passed"
