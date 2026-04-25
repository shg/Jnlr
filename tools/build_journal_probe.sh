#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${ROOT}/build"
OUT_BIN="${OUT_DIR}/journal_probe"

mkdir -p "$OUT_DIR"

cd "$ROOT"

clang \
  -fno-objc-arc \
  -framework Cocoa \
  compat/journal_probe.m \
  compat/probe_model.m \
  -o "$OUT_BIN"

printf 'built %s\n' "$OUT_BIN"
