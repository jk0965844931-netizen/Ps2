#!/usr/bin/env bash
# Build or package an unsigned iOS IPA on a GitHub-hosted macOS runner.
#
# Inputs are read from environment variables so the same script can be used by
# GitHub Actions and locally:
#   APP_PATH          Optional path to an already-built .app bundle.
#   ARCHIVE_PATH      Optional path to an existing .xcarchive.
#   WORKSPACE         Optional .xcworkspace path. Auto-detected when empty.
#   PROJECT           Optional .xcodeproj path. Auto-detected when empty.
#   SCHEME            Optional Xcode scheme. Defaults to iPSX2 when empty.
#   CONFIGURATION     Xcode configuration, defaults to Release.
#   IPA_NAME          Output IPA filename, defaults to iPSX2-unsigned.ipa.
#   SOURCE_REPOSITORY Optional owner/repo or git URL cloned when this checkout
#                     has neither an Xcode project nor cpp/CMakeLists.txt.
#   SOURCE_REF        Optional branch, tag, or commit for SOURCE_REPOSITORY.
#
# If no Xcode project/workspace is checked in but cpp/CMakeLists.txt exists, the
# script generates an iOS Xcode project with CMake before archiving.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_IPA="$SCRIPT_DIR/package_ipa.py"

CONFIGURATION="${CONFIGURATION:-Release}"
IPA_NAME="${IPA_NAME:-iPSX2-unsigned.ipa}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$REPO_ROOT/artifacts}"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build}"
SOURCE_REPOSITORY="${SOURCE_REPOSITORY:-jk0965844931-netizen/iPSX2-src}"
SOURCE_REF="${SOURCE_REF:-}"
SCHEME="${SCHEME:-iPSX2}"

if [[ "$ARTIFACTS_DIR" != /* ]]; then
  ARTIFACTS_DIR="$REPO_ROOT/$ARTIFACTS_DIR"
fi
if [[ "$BUILD_DIR" != /* ]]; then
  BUILD_DIR="$REPO_ROOT/$BUILD_DIR"
fi

mkdir -p "$ARTIFACTS_DIR" "$BUILD_DIR"

log() {
  printf '==> %s\n' "$*"
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 2
}

source_clone_url() {
  local repository="$1"
  if [[ "$repository" == https://* || "$repository" == git@* || "$repository" == ssh://* ]]; then
    printf '%s\n' "$repository"
  else
    printf 'https://github.com/%s.git\n' "$repository"
  fi
}

first_match() {
  local pattern="$1"
  find . \
    -path './.git' -prune -o \
    -path './build' -prune -o \
    -path './artifacts' -prune -o \
    -path './ipa-staging' -prune -o \
    -path './cpp/3rdparty' -prune -o \
    -path './3rdparty' -prune -o \
    -path './Pods' -prune -o \
    -name "$pattern" -print | sort | head -n 1
}

has_explicit_xcode_container() {
  [[ -n "${WORKSPACE:-}" || -n "${PROJECT:-}" ]]
}

has_xcode_container() {
  has_explicit_xcode_container && return 0
  [[ -n "$(first_match '*.xcworkspace')" || -n "$(first_match '*.xcodeproj')" ]]
}

package_existing_app_or_archive() {
  if [[ -n "${APP_PATH:-}" ]]; then
    log "Packaging existing app: $APP_PATH"
    python3 "$PACKAGE_IPA" --app "$APP_PATH" --output "$ARTIFACTS_DIR/$IPA_NAME"
    return 0
  fi

  if [[ -n "${ARCHIVE_PATH:-}" ]]; then
    log "Packaging existing archive: $ARCHIVE_PATH"
    python3 "$PACKAGE_IPA" --archive "$ARCHIVE_PATH" --output "$ARTIFACTS_DIR/$IPA_NAME"
    return 0
  fi

  return 1
}

prepare_source_tree() {
  cd "$REPO_ROOT"

  if has_xcode_container || [[ -f cpp/CMakeLists.txt ]]; then
    log "Using checked-out source tree: $PWD"
    return
  fi

  [[ -n "$SOURCE_REPOSITORY" ]] || fail "no Xcode project or cpp/CMakeLists.txt found; set SOURCE_REPOSITORY, WORKSPACE, PROJECT, APP_PATH, or ARCHIVE_PATH"

  local source_dir="$BUILD_DIR/source"
  local clone_url
  clone_url="$(source_clone_url "$SOURCE_REPOSITORY")"

  log "No source project found in this checkout; cloning $SOURCE_REPOSITORY"
  rm -rf "$source_dir"
  if [[ -n "$SOURCE_REF" ]]; then
    git clone --depth 1 --recursive --branch "$SOURCE_REF" "$clone_url" "$source_dir"
  else
    git clone --depth 1 --recursive "$clone_url" "$source_dir"
  fi

  cd "$source_dir"
  log "Using cloned source tree: $PWD"
}

generate_xcode_project_if_needed() {
  if has_explicit_xcode_container; then
    log "Using explicit Xcode container; skipping CMake generation"
    return
  fi

  if [[ ! -f cpp/CMakeLists.txt ]]; then
    has_xcode_container && return
    fail "missing cpp/CMakeLists.txt after source preparation"
  fi

  # iPSX2-src contains vendor Xcode projects under cpp/3rdparty (for example
  # SDL). Those projects do not contain the iPSX2 scheme, so always generate the
  # top-level iOS project from cpp/CMakeLists.txt unless the user explicitly set
  # WORKSPACE or PROJECT.
  log "Generating top-level iPSX2 Xcode project with CMake from cpp/"
  set -o pipefail
  cmake -S "$PWD/cpp" -B "$BUILD_DIR" \
    -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=18.0 \
    -DiPSX2_REAL_DEVICE=ON \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache \
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
    -DUSE_DISCORD_SDK=OFF \
    -DUSE_VULKAN=OFF \
    -DSDL_VULKAN=OFF \
    -DSDL_RENDER_VULKAN=OFF \
    -DENABLE_TESTS=OFF \
    -DENABLE_GSRUNNER=OFF \
    -DWEBP_BUILD_ANIM_UTILS=OFF \
    -DWEBP_BUILD_CWEBP=OFF \
    -DWEBP_BUILD_DWEBP=OFF \
    -DWEBP_BUILD_GIF2WEBP=OFF \
    -DWEBP_BUILD_IMG2WEBP=OFF \
    -DWEBP_BUILD_VWEBP=OFF \
    -DWEBP_BUILD_WEBPINFO=OFF \
    -DWEBP_BUILD_WEBPMUX=OFF \
    -DWEBP_BUILD_EXTRAS=OFF \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
    "-DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY=" \
    --fresh 2>&1 | tee /tmp/cmake_configure.log

  if grep -q '^CMake Error' /tmp/cmake_configure.log; then
    fail "CMake configure reported errors"
  fi

  PROJECT="$(find "$BUILD_DIR" -maxdepth 1 -name '*.xcodeproj' -type d | head -n 1 || true)"
  [[ -n "$PROJECT" ]] || fail "CMake completed but no .xcodeproj was generated in $BUILD_DIR"
  log "Generated project: $PROJECT"
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
    fail "no .xcworkspace or .xcodeproj found after source preparation"
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
)" || fail "could not auto-detect an Xcode scheme; set SCHEME"

  log "Auto-detected scheme: $SCHEME"
}

if package_existing_app_or_archive; then
  log "Unsigned IPA is ready: $ARTIFACTS_DIR/$IPA_NAME"
  exit 0
fi

prepare_source_tree
generate_xcode_project_if_needed
detect_project_or_workspace
detect_scheme

ARCHIVE_OUTPUT="$BUILD_DIR/iPSX2.xcarchive"
log "Archiving unsigned iOS build to: $ARCHIVE_OUTPUT"
xcodebuild archive \
  "${BUILD_CONTAINER_FLAG[@]}" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_OUTPUT" \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  SKIP_INSTALL=NO

log "Packaging unsigned IPA"
python3 "$PACKAGE_IPA" --archive "$ARCHIVE_OUTPUT" --output "$ARTIFACTS_DIR/$IPA_NAME"
log "Unsigned IPA is ready: $ARTIFACTS_DIR/$IPA_NAME"
