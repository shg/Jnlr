#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${ROOT}/build/JournlerMini.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
EXECUTABLE="${MACOS_DIR}/JournlerMini"

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cd "${ROOT}"

clang \
  -fno-objc-arc \
  -framework Cocoa \
  compat/probe_model.m \
  modern_app/main.m \
  -o "${EXECUTABLE}"

cp modern_app/Info.plist "${CONTENTS_DIR}/Info.plist"

printf 'built %s\n' "${APP_DIR}"
