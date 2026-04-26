#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${ROOT}/build/Jnlr.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
EXECUTABLE="${MACOS_DIR}/Jnlr"
OBJ_DIR="${ROOT}/build/obj"
OBJC_OBJECT="${OBJ_DIR}/probe_model.o"
MODULE_CACHE_DIR="${ROOT}/build/module-cache"

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${OBJ_DIR}" "${MODULE_CACHE_DIR}"

cd "${ROOT}"

clang \
  -fno-objc-arc \
  -c \
  -framework Cocoa \
  compat/probe_model.m \
  -o "${OBJC_OBJECT}"

swiftc \
  -module-cache-path "${MODULE_CACHE_DIR}" \
  -import-objc-header modern_app/Jnlr-Bridging-Header.h \
  -framework Cocoa \
  modern_app/main.swift \
  "${OBJC_OBJECT}" \
  -o "${EXECUTABLE}"

cp modern_app/Info.plist "${CONTENTS_DIR}/Info.plist"

printf 'built %s\n' "${APP_DIR}"
