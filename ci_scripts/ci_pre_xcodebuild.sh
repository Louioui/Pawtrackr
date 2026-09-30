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

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/pawtrackr-ci.XXXXXX")
trap 'rm -rf "$WORK_DIR"' EXIT

SCHEMA_FILE="$REPO_ROOT/Pawtrackr/Core/Storage/Migrations.swift"
MODELS_DIR="$REPO_ROOT/Pawtrackr/Core/Storage/Models"
REQUIRED_TYPES_FILE="$REPO_ROOT/docs/cloudkit/required-record-types.txt"
CLOUDKIT_CONTAINER="iCloud.PartnerShipWithMedia.Pawtrackr"

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

# CloudKit can't enforce uniqueness. A unique constraint on any mirrored model
# makes the CloudKit container fail to load, and the app silently falls back to
# local-only on every device. DeviceStatus.swift already has one, which is fine
# only while DeviceStatus stays out of the schema. The check is per file, so a
# unique constraint anywhere in a file that declares a schema model fails it.
for model in $(cat "$WORK_DIR/schema-models"); do
  model_files=$(grep -rlE "^[[:space:]]*(@[A-Za-z]+[[:space:]]+)*((public|internal|final|open)[[:space:]]+)*class[[:space:]]+${model}([^A-Za-z0-9_]|$)" --include='*.swift' "$MODELS_DIR" || true)
  if [ -z "$model_files" ]; then
    echo "Build failed: $model is in PawtrackrSchema.models but no 'class $model' was found under Pawtrackr/Core/Storage/Models, so its CloudKit constraints can't be checked."
    exit 1
  fi
  for model_file in $model_files; do
    # Joined into one line first, so @Attribute(\n .unique) and
    # @Attribute(.transformable(by: X.self), .unique) are caught too.
    if sed 's://.*$::' "$model_file" | tr '\n' ' ' | grep -qE '@Attribute\([^;{}]*\.unique([^A-Za-z0-9_]|$)|#Unique[[:space:]]*<'; then
      echo "Build failed: ${model_file#"$REPO_ROOT"/} declares a unique constraint, and $model is in the CloudKit-mirrored schema."
      exit 1
    fi
  done
done

# The Production-schema gate below is only as complete as this list.
if [ ! -f "$REQUIRED_TYPES_FILE" ]; then
  echo "Build failed: docs/cloudkit/required-record-types.txt is missing."
  exit 1
fi
: > "$WORK_DIR/required-types"
: > "$WORK_DIR/ignored-fields"
while IFS= read -r line || [ -n "$line" ]; do
  line=$(printf '%s\n' "$line" | sed -e 's/#.*$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  case "$line" in
    "")
      continue ;;
    "ignore CD_"*.CD_*)
      printf '%s\n' "$line" | sed 's/^ignore[[:space:]]*//' >> "$WORK_DIR/ignored-fields"
      continue ;;
    CD_*[!A-Za-z0-9_]*) ;;
    CD_*)
      printf '%s\n' "$line" >> "$WORK_DIR/required-types"
      continue ;;
  esac
  echo "Build failed: docs/cloudkit/required-record-types.txt has a line it doesn't understand: $line"
  exit 1
done < "$REQUIRED_TYPES_FILE"
sort -u -o "$WORK_DIR/required-types" "$WORK_DIR/required-types"
sed 's/^/CD_/' "$WORK_DIR/schema-models" | sort -u > "$WORK_DIR/expected-types"
if ! cmp -s "$WORK_DIR/expected-types" "$WORK_DIR/required-types"; then
  echo "Build failed: docs/cloudkit/required-record-types.txt doesn't match PawtrackrSchema.models."
  comm -23 "$WORK_DIR/expected-types" "$WORK_DIR/required-types" | sed 's/^/  missing from the list: /'
  comm -13 "$WORK_DIR/expected-types" "$WORK_DIR/required-types" | sed 's/^/  not in the schema: /'
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

# Prints one line per record type ("CD_Client") and per non-system field
# ("CD_Client.CD_name") in a cktool .ckdb export.
list_schema_entries() {
  awk '
    /\/\*/ { in_comment = 1 }
    in_comment { if ($0 ~ /\*\//) in_comment = 0; next }
    { sub(/\/\/.*/, ""); sub(/--.*/, "") }
    /^[ \t]*RECORD[ \t]+TYPE[ \t]/ {
      type = $3
      gsub(/["(]/, "", type)
      in_type = 1
      print type
      next
    }
    in_type {
      closes = ($0 ~ /\)[ \t]*;?[ \t]*$/)
      sub(/\)[ \t]*;?[ \t]*$/, "")
      field = $1
      gsub(/[",]/, "", field)
      if (field != "" && field != "GRANT" && substr(field, 1, 1) != "_") print type "." field
      if (closes) in_type = 0
    }
  ' "$1" | sort -u
}

# Uploads of a record type or field that Production lacks are rejected on every
# App Store and TestFlight install, while imports keep working, so nothing looks
# wrong on the device. Development is what the DEBUG CloudKitSchemaInitializer
# fills, so Production must have every field Development has for our types.
if [ "${CI_XCODEBUILD_ACTION:-}" = "archive" ]; then
  CKTOOL_TOKEN="${CKTOOL_MANAGEMENT_TOKEN:-${CLOUDKIT_MANAGEMENT_TOKEN:-}}"
  if [ -z "$CKTOOL_TOKEN" ]; then
    # This used to warn and carry on. A warning in an archive log is easy to
    # miss, and a build whose uploads Production rejects only shows up when a
    # groomer reinstalls or changes device and iCloud has nothing to give back.
    if [ "${PAWTRACKR_SKIP_CLOUDKIT_PRODUCTION_CHECK:-}" != "1" ]; then
      echo "Build failed: CKTOOL_MANAGEMENT_TOKEN isn't set, so this archive can't be"
      echo "checked against the CloudKit Production schema. Add the token as an Xcode"
      echo "Cloud secret (docs/icloud-validation.md#cloudkit-management-token). To archive"
      echo "anyway after checking Production by hand, set PAWTRACKR_SKIP_CLOUDKIT_PRODUCTION_CHECK=1."
      exit 1
    fi
    echo "=================================================================="
    echo "warning: PAWTRACKR_SKIP_CLOUDKIT_PRODUCTION_CHECK=1, so this archive was"
    echo "warning: NOT checked against the CloudKit Production schema."
    echo "warning: Check Production in CloudKit Console before submitting."
    echo "=================================================================="
  else
    # cktool reads the token from the environment, so it never shows up in the
    # process list or the build log.
    CLOUDKIT_MANAGEMENT_TOKEN="$CKTOOL_TOKEN"
    export CLOUDKIT_MANAGEMENT_TOKEN
    CLOUDKIT_TEAM_ID="${CI_TEAM_ID:-6ALS97634D}"

    for environment in production development; do
      if ! xcrun cktool export-schema \
        --team-id "$CLOUDKIT_TEAM_ID" \
        --container-id "$CLOUDKIT_CONTAINER" \
        --environment "$environment" \
        --output-file "$WORK_DIR/$environment.ckdb"; then
        # Carrying on would silently turn the gate off, e.g. when the token expires.
        echo "Build failed: couldn't export the CloudKit $environment schema with cktool. Check that CKTOOL_MANAGEMENT_TOKEN is a current management token for team $CLOUDKIT_TEAM_ID."
        exit 1
      fi
      list_schema_entries "$WORK_DIR/$environment.ckdb" > "$WORK_DIR/$environment.entries"
    done

    : > "$WORK_DIR/schema-gaps"
    development_types_found=0
    for record_type in $(cat "$WORK_DIR/required-types"); do
      if ! grep -qxF "$record_type" "$WORK_DIR/production.entries"; then
        echo "  record type $record_type" >> "$WORK_DIR/schema-gaps"
      fi
      if grep -qxF "$record_type" "$WORK_DIR/development.entries"; then
        development_types_found=$((development_types_found + 1))
      else
        echo "warning: Development has no $record_type, so its fields weren't compared. Run the DEBUG schema initializer (docs/icloud-validation.md)."
      fi
    done
    # Even a reset Development environment holds everything Production has, so
    # finding none of our types means the export or its parsing is broken, and
    # the field comparison would pass without checking anything.
    if [ "$development_types_found" -eq 0 ]; then
      echo "Build failed: couldn't parse any Pawtrackr record types from the CloudKit Development export, so fields can't be compared."
      exit 1
    fi
    # Many-to-many relationships are stored as CDMR records.
    if grep -qxF "CDMR" "$WORK_DIR/development.entries" && ! grep -qxF "CDMR" "$WORK_DIR/production.entries"; then
      echo "  record type CDMR" >> "$WORK_DIR/schema-gaps"
    fi
    grep -F '.' "$WORK_DIR/development.entries" > "$WORK_DIR/development.fields" || true
    while IFS= read -r entry; do
      record_type=${entry%%.*}
      if [ "$record_type" != "CDMR" ] && ! grep -qxF "$record_type" "$WORK_DIR/required-types"; then
        continue
      fi
      if grep -qxF "$entry" "$WORK_DIR/production.entries" || grep -qxF "$entry" "$WORK_DIR/ignored-fields"; then
        continue
      fi
      echo "  field $entry" >> "$WORK_DIR/schema-gaps"
    done < "$WORK_DIR/development.fields"

    if [ -s "$WORK_DIR/schema-gaps" ]; then
      echo "Build failed: the CloudKit Production schema for $CLOUDKIT_CONTAINER is missing:"
      cat "$WORK_DIR/schema-gaps"
      echo "Deploy Schema Changes to Production in CloudKit Console, then archive again (docs/icloud-validation.md)."
      exit 1
    fi
    echo "CloudKit Production schema has every record type and field this build needs."
  fi
fi

echo "Pawtrackr test and migration gates passed"
