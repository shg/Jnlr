# Journler Modernization Plan

This repository contains a historical macOS Cocoa application whose data model
must remain compatible with journals created by Journler 2.6.

## Fixed constraints

- Existing journal data must load without conversion loss.
- Existing journal data must save back to the same on-disk structure.
- The first milestone is data compatibility, not full UI parity.

## Verified sample journal

The repository now has a real sample journal at `../JnlrData/Journler/`.

Its observed shape matches the `master` branch loading code:

- `Journler.plist`
- `JournlerStore.dict`
- `Journler Entries/Entry <id>/`
- `Collections/*.jcol`
- `Resources/*.jresource`
- `Blogs/*.jblog`
- `Index Entries`
- `Index References`

Observed metadata from the supplied journal:

- `Version = 253`
- `PDJournalProperShutDown = 1`
- `JournlerStore.dict` contains:
  - `Entries = 6015`
  - `Collections = 85`
  - `Resources = 4433`
  - `Blogs = 1`
- `Journler Entries/` contains `6036` entry package directories
- `Resources/` contains `4433` `.jresource` files

This means the first compatibility target can be Journler 2.5.3/2.6 style
journals. Earlier 1.x and 2.0 upgrade paths can be treated as a later phase.

## Confirmed current milestone

A new non-UI probe now builds on current macOS and can decode the supplied
journal's top-level store directly:

- build script: `tools/build_journal_probe.sh`
- probe sources: `compat/journal_probe.m`, `compat/probe_model.m`

Confirmed on the supplied journal:

- `Journler.plist` loads
- `JournlerStore.dict` loads
- keyed unarchiving succeeds for all store-backed entries
- decoded counts match the store exactly
- first decoded entry returns a valid tag and title
- the first entry body can be loaded from `_Text.jrtfd/Entry.rtfd/TXT.rtf`

An additional minimal AppKit viewer now builds outside the legacy Xcode project:

- app sources: `modern_app/main.m`
- bundle build script: `tools/build_minimal_app.sh`
- output: `build/JournlerMini.app`

Current verified behavior of the minimal viewer:

- builds on current macOS
- supports a `--smoke-test <journal-path>` mode for headless verification
- loads the supplied journal successfully
- shows store-backed entries in read-only mode
- loads entry body text for the first verified sample entry
- can fall back to directory-only loading when `JournlerStore.dict` is absent
- current fallback result on the supplied journal is `6035` entries

Current known gap:

- one entry package (`Entry 4135`) still unarchives to `nil` in the lightweight
  compatibility layer, so the current read-only viewer reaches `6035` package
  entries instead of the raw directory count `6036`

Interpretation:

- Archive compatibility at the `JournlerStore.dict` level is achievable on
  current macOS without reviving the entire legacy app target first.
- The remaining gap is not basic archive readability; it is rebuilding enough
  of the original model/runtime to support full journal behavior and eventual
  save round-tripping.

## What must not be broken

The loader and saver directly depend on keyed archiving contracts and file
layout. These are the core compatibility surfaces:

- `JournlerJournal loadFromPath:`
- `JournlerJournal loadFromStore:`
- `JournlerJournal loadFromDirectoryIgnoringEntryFolders:error:`
- `JournlerJournal save:`
- `JournlerJournal saveEntry:`
- `JournlerEntry initWithCoder:` / `encodeWithCoder:`
- `JournlerCollection initWithCoder:` / `encodeWithCoder:`
- `JournlerResource initWithCoder:` / `encodeWithCoder:`

Implication:

- Keep Objective-C model class names stable.
- Keep keyed archive keys stable.
- Keep package and file naming stable.
- Avoid model rewrites until compatibility tests exist.

## Immediate blockers on current macOS

### Legacy project settings

The Xcode project is pinned to:

- `SDKROOT = macosx10.7`
- `MACOSX_DEPLOYMENT_TARGET = 10.6`
- `ARCHS_STANDARD_32_BIT`

That prevents a direct build on current Xcode.

### Bundled framework binaries are unusable

The checked-in framework binaries are `ppc/i386` only:

- `SproutedUtilities.framework`
- `SproutedInterface.framework`
- `SproutedAVI.framework`
- `Pantomime.framework`
- `Sparkle.framework`

They cannot be linked on current Apple Silicon or modern Intel macOS.

### Deprecated platform APIs

The app still uses APIs that require replacement or isolation:

- `WebView`
- `AddressBook`
- `NSMailDelivery`
- `NSCalendarDate`
- old SearchKit usage
- manual retain/release throughout

## Practical migration strategy

### Phase 1: Build a compatibility core

Goal:

- Load the supplied journal on current macOS.
- Save it back without structural drift.

Approach:

- Create a new minimal target outside the old Xcode project assumptions.
- Start with Objective-C and `-fno-objc-arc`.
- Compile the model layer first:
  - `JournlerObject`
  - `JournlerEntry`
  - `JournlerCollection`
  - `JournlerResource`
  - `JournlerJournal`
- Pull source files from sibling repositories instead of using bundled framework
  binaries:
  - `../SproutedUtilities`
  - `../SproutedInterface`
  - `../SproutedAVI`

Do not start by porting the entire UI.

### Phase 2: Add compatibility tests against the real journal

Need automated checks for:

- `loadFromPath:` succeeds on the supplied journal.
- Entry, collection, resource, and blog counts match expectations.
- A representative set of entries can load their `.jobj` and `Entry.rtfd`.
- Saving does not change required directory/file presence.
- `JournlerStore.dict` is rewritten successfully.
- Deleting search indexes still allows directory-based recovery.

The search indexes are not the source of truth. They can be rebuilt.

### Phase 3: Restore enough app shell to open journals

After the compatibility core works:

- Rebuild app startup around the new target.
- Stub or disable nonessential integrations first.
- Treat these as optional during the first bootable milestone:
  - mail sending
  - blog publishing
  - media capture
  - address book UI

### Phase 4: Replace obsolete integrations

- `WebView` -> `WKWebView` where still required
- `AddressBook` -> `Contacts` / `ContactsUI`
- `NSMailDelivery` -> `NSSharingService` or a custom mail flow
- old Sparkle -> current Sparkle or remove updates temporarily

## Recommended order of work

1. Create a new modern build target for the compatibility core.
2. Vendor only the source files needed from `SproutedUtilities` and related
   sibling repos.
3. Make the supplied journal load in a non-UI executable.
4. Add a minimal read-only app shell around the compatibility core.
5. Add regression checks around counts and sample entries.
6. Implement directory fallback when `JournlerStore.dict` is missing or stale.
7. Make save round-trip succeed.
8. Only then start rebuilding broader application UI.

## Why not start with the UI

Because the project can be made to compile while still silently corrupting old
journal data. The user requirement is the opposite: old data compatibility is
mandatory, while UI parity can be incremental.

## Helper script

Use `tools/audit_journler_data.sh` to verify that a candidate journal directory
still has the expected top-level structure before and after experiments.
