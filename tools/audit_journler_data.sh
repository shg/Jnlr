#!/usr/bin/env bash

set -euo pipefail

ROOT="${1:-../JnlrData/Journler}"

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

require_path() {
  local path="$1"
  [[ -e "$path" ]] || fail "missing expected path: $path"
}

[[ -d "$ROOT" ]] || fail "journal directory not found: $ROOT"

PROPERTIES="$ROOT/Journler.plist"
STORE="$ROOT/JournlerStore.dict"
ENTRIES_DIR="$ROOT/Journler Entries"
COLLECTIONS_DIR="$ROOT/Collections"
RESOURCES_DIR="$ROOT/Resources"
BLOGS_DIR="$ROOT/Blogs"
DROPBOX_DIR="$ROOT/Journler Drop Box"
ENTRY_INDEX="$ROOT/Index Entries"
REFERENCE_INDEX="$ROOT/Index References"

require_path "$PROPERTIES"
require_path "$STORE"
require_path "$ENTRIES_DIR"
require_path "$COLLECTIONS_DIR"
require_path "$RESOURCES_DIR"
require_path "$BLOGS_DIR"
require_path "$DROPBOX_DIR"

version="$(/usr/bin/plutil -extract Version raw -o - "$PROPERTIES" 2>/dev/null || true)"
journal_id="$(/usr/bin/plutil -extract JournalID raw -o - "$PROPERTIES" 2>/dev/null || true)"
shutdown_clean="$(/usr/bin/plutil -extract PDJournalProperShutDown raw -o - "$PROPERTIES" 2>/dev/null || true)"
title="$(/usr/bin/plutil -extract Title raw -o - "$PROPERTIES" 2>/dev/null || true)"

entry_count="$(find "$ENTRIES_DIR" -maxdepth 1 -type d -name 'Entry *' | wc -l | tr -d ' ')"
collection_count="$(find "$COLLECTIONS_DIR" -maxdepth 1 -type f -name '*.jcol' | wc -l | tr -d ' ')"
resource_count="$(find "$RESOURCES_DIR" -maxdepth 1 -type f -name '*.jresource' | wc -l | tr -d ' ')"
blog_count="$(find "$BLOGS_DIR" -maxdepth 1 -type f -name '*.jblog' | wc -l | tr -d ' ')"

store_size="$(du -sh "$STORE" | awk '{print $1}')"
entry_index_size="$(if [[ -e "$ENTRY_INDEX" ]]; then du -sh "$ENTRY_INDEX" | awk '{print $1}'; else echo 'missing'; fi)"
reference_index_size="$(if [[ -e "$REFERENCE_INDEX" ]]; then du -sh "$REFERENCE_INDEX" | awk '{print $1}'; else echo 'missing'; fi)"

sample_entry="$(find "$ENTRIES_DIR" -maxdepth 1 -type d -name 'Entry *' | sort | sed -n '1p')"

printf 'Journal root: %s\n' "$ROOT"
printf 'Title: %s\n' "${title:-<missing>}"
printf 'Version: %s\n' "${version:-<missing>}"
printf 'JournalID: %s\n' "${journal_id:-<missing>}"
printf 'Proper shutdown: %s\n' "${shutdown_clean:-<missing>}"
printf '\n'
printf 'Store: %s (%s)\n' "$STORE" "$store_size"
printf 'Entry index: %s\n' "$entry_index_size"
printf 'Reference index: %s\n' "$reference_index_size"
printf '\n'
printf 'Entries: %s\n' "$entry_count"
printf 'Collections: %s\n' "$collection_count"
printf 'Resources: %s\n' "$resource_count"
printf 'Blogs: %s\n' "$blog_count"
printf '\n'

if [[ -n "$sample_entry" ]]; then
  printf 'Sample entry package: %s\n' "$sample_entry"
  find "$sample_entry" -maxdepth 2 -print | sort
fi
