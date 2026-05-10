#!/usr/bin/env bash
# Build or package an unsigned iOS IPA on a GitHub-hosted macOS runner.
#
# Inputs are read from environment variables so the same script can be used by
# GitHub Actions and locally:
#   APP_PATH       Optional path to an already-built .app bundle.
#   ARCHIVE_PATH   Optional path to an existing .xcarchive.
#   WORKSPACE      Optional .xcworkspace path. Auto-detected when empty.
#   PROJECT        Optional .xcodeproj path. Auto-detected when empty.
#   SCHEME         Optional Xcode scheme. Auto-detected when empty.
#   CONFIGURATION  Xcode configuration, defaults to Release.
#   IPA_NAME       Output IPA filename, defaults to iPSX2-unsigned.ipa.

set -euo pipefail

CONFIGURATION="${CONFIGURATION:-Release}"
IPA_NAME="${IPA_NAME:-iPSX2-unsigned.ipa}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-artifacts}"
BUILD_DIR="${BUILD_DIR:-build}"

mkdir -p "$ARTIFACTS_DIR" "$BUILD_DIR"

log() {
  printf '==> %s\n' "$*"
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 2
}

first_match() {
  local pattern="$1"
  find . \
    -path './.git' -prune -o \
    -path './build' -prune -o \
    -path './artifacts' -prune -o \
    -name "$pattern" -print | sort | head -n 1
}

detect_project_or_workspace() {
  if [[ -z "${WORKSPACE:-}" && -z "${PROJECT:-}" ]]; then
    WORKSPACE="$(first_match '*.xcworkspace')"
    if [[ -z "$WORKSPACE" ]]; then
      PROJECT="$(first_match '*.xcodeproj')"
    fi
  fi

  if [[ -n "${WORKSPACE:-}" ]]; then
    BUILD_CONTAINER_FLAG=(-workspace "$WORKSPACE")
    LIST_CONTAINER_FLAG=(-workspace "$WORKSPACE")
    log "Using workspace: $WORKSPACE"
  elif [[ -n "${PROJECT:-}" ]]; then
    BUILD_CONTAINER_FLAG=(-project "$PROJECT")
    LIST_CONTAINER_FLAG=(-project "$PROJECT")
    log "Using project: $PROJECT"
  else
    fail "no .xcworkspace or .xcodeproj found; set WORKSPACE or PROJECT, or provide APP_PATH/ARCHIVE_PATH"
  fi
}

detect_scheme() {
  if [[ -n "${SCHEME:-}" ]]; then
    log "Using scheme: $SCHEME"
    return
  fi

  local schemes_json="$BUILD_DIR/xcodebuild-list.json"
  xcodebuild -list -json "${LIST_CONTAINER_FLAG[@]}" > "$schemes_json"
  SCHEME="$(python3 - "$schemes_json" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
for key in ('workspace', 'project'):
    schemes = data.get(key, {}).get('schemes') or []
    if schemes:
        print(schemes[0])
        raise SystemExit(0)
raise SystemExit(1)
PY
)" || fail "could not auto-detect an Xcode scheme; set SCHEME in the workflow inputs"

  log "Auto-detected scheme: $SCHEME"
}

package_existing_app_or_archive() {
  if [[ -n "${APP_PATH:-}" ]]; then
    log "Packaging existing app: $APP_PATH"
    python3 scripts/package_ipa.py --app "$APP_PATH" --output "$ARTIFACTS_DIR/$IPA_NAME"
    return 0
  fi

  if [[ -n "${ARCHIVE_PATH:-}" ]]; then
    log "Packaging existing archive: $ARCHIVE_PATH"
    python3 scripts/package_ipa.py --archive "$ARCHIVE_PATH" --output "$ARTIFACTS_DIR/$IPA_NAME"
    return 0
  fi

  return 1
}

if package_existing_app_or_archive; then
  log "Unsigned IPA is ready: $ARTIFACTS_DIR/$IPA_NAME"
  exit 0
fi

detect_project_or_workspace
detect_scheme

ARCHIVE_OUTPUT="$PWD/$BUILD_DIR/iPSX2.xcarchive"
log "Archiving unsigned iOS build to: $ARCHIVE_OUTPUT"
xcodebuild archive \
  "${BUILD_CONTAINER_FLAG[@]}" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_OUTPUT" \
  -derivedDataPath "$PWD/$BUILD_DIR/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM=""

log "Packaging unsigned IPA"
python3 scripts/package_ipa.py --archive "$ARCHIVE_OUTPUT" --output "$ARTIFACTS_DIR/$IPA_NAME"
log "Unsigned IPA is ready: $ARTIFACTS_DIR/$IPA_NAME"
