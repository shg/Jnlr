# Journler Modernization Plan

This document is the master plan for modernizing `Jnlr`.

It tracks:

- the current overall strategy
- the major implementation phases
- what is complete, in progress, planned, or deferred
- the current known end state of the project

It does not aim to record every small task or every chat exchange.

## Goal

Rebuild Journler as a current macOS application that can open and save
Journler 2.6 journal data without conversion loss, while restoring the
original Journler 2.6 feature set and look and feel as closely as practical.

## Fixed constraints

- Existing journal data must load without conversion loss.
- Existing journal data must save back to the same on-disk structure.
- Journler 2.6 data compatibility is mandatory.
- Original Journler source remains a reference implementation for now.
- The current app should move toward Swift + AppKit for UI work.
- The compatibility layer should remain isolated and conservative.

## Current architecture

### Compatibility layer

Status: `Completed` for the current minimal milestone

- Implemented as a new lightweight compatibility layer:
  - [compat/probe_model.h](/Users/shg/Dropbox/dev/GitHub/Jnlr/compat/probe_model.h:1)
  - [compat/probe_model.m](/Users/shg/Dropbox/dev/GitHub/Jnlr/compat/probe_model.m:1)
- Uses Journler 2.6 archive class names, archive keys, and file layout.
- Is a new implementation.
- Does not directly link against the original Journler model/runtime code.

### App UI layer

Status: `In Progress`

- Current app bundle:
  - `build/Jnlr.app`
- Current UI implementation:
  - [modern_app/main.swift](/Users/shg/Dropbox/dev/GitHub/Jnlr/modern_app/main.swift:1)
- Build path:
  - [Makefile](/Users/shg/Dropbox/dev/GitHub/Jnlr/Makefile:1)
  - [tools/build_minimal_app.sh](/Users/shg/Dropbox/dev/GitHub/Jnlr/tools/build_minimal_app.sh:1)
- Current direction:
  - Swift + AppKit
  - old Journler nibs and controllers used as reference, not reused directly

### Original Journler code

Status: `Retained as reference`

- The original app source and nibs are not used by the running `Jnlr.app`.
- They remain important as:
  - behavior reference
  - data format reference
  - UI reference for Journler 2.6 parity work

## Verified sample journal

Status: `Completed`

The repository has a real sample journal at `../JnlrData/Journler/`.

Observed shape:

- `Journler.plist`
- `JournlerStore.dict`
- `Journler Entries/Entry <id>/`
- `Collections/*.jcol`
- `Resources/*.jresource`
- `Blogs/*.jblog`
- `Index Entries`
- `Index References`

Observed metadata:

- `Version = 253`
- `PDJournalProperShutDown = 1`
- `JournlerStore.dict` contents:
  - `Entries = 6015`
  - `Collections = 85`
  - `Resources = 4433`
  - `Blogs = 1`
- `Journler Entries/` contains `6036` entry package directories
- `Resources/` contains `4433` `.jresource` files

This journal is the primary compatibility test corpus.

## Current milestone summary

Status: `In Progress`

The project has reached these visible milestones:

- compatibility layer can load the supplied journal on current macOS
- compatibility layer can reconcile store-backed loading with directory loading
- compatibility layer can fall back to directory-only loading when
  `JournlerStore.dict` is absent
- compatibility layer can perform a minimal save round-trip for a single entry
- a working `Jnlr.app` exists and launches
- the current `Jnlr.app` UI has been ported from Objective-C to Swift + AppKit

Current verified behavior of `Jnlr.app`:

- builds on current macOS
- supports `--smoke-test <journal-path>` for headless verification
- loads the supplied journal successfully
- loads `6036` entries from the supplied journal
- displays a 3-pane UI
- shows a hierarchical collection sidebar
- shows a multi-column entry list
- shows and edits entry title and body
- shows entry metadata
- prompts to save, discard, or cancel before losing unsaved changes
- creates backup copies before writing changes
- rewrites `JournlerStore.dict` during minimal entry save
- shows the currently opened journal path in the status area

## Phase status

### Phase 1: Data compatibility core

Status: `Completed`

Target:

- load Journler 2.6 data on current macOS
- preserve file/archive compatibility for the current tested scope

Completed:

- sample journal audited
- keyed archive compatibility implemented
- store-backed loading implemented
- directory fallback implemented
- `6036` entries reached for the supplied journal
- sample entry body loading verified
- minimal single-entry save round-trip verified

### Phase 2: Minimal working app shell

Status: `Completed`

Target:

- have a bootable macOS app around the compatibility layer

Completed:

- app bundle creation outside the legacy Xcode project
- open journal flow
- reload flow
- basic status display
- editable entry detail panel
- unsaved-change prompts
- save integration with compatibility layer

### Phase 3: Swift + AppKit UI migration

Status: `Completed` for the current equivalent UI

Target:

- move the new app UI implementation from Objective-C to Swift + AppKit

Completed:

- Swift entry point added
- Objective-C compatibility layer bridged into Swift
- current 3-pane app shell ported to Swift
- sidebar, table, detail view, save flow, and smoke-test path ported

Notes:

- This phase means parity with the current new app UI, not parity with
  Journler 2.6 yet.

### Phase 4: Journler 2.6 UI and interaction parity

Status: `In Progress`

Target:

- progressively reproduce Journler 2.6 look and feel
- progressively reproduce Journler 2.6 core workflows

Completed:

- 3-pane information architecture established
- hierarchical collection sidebar established
- multi-column entry list established
- basic metadata display established
- date sorting established

Remaining major work:

- toolbar parity
- search and filter UI
- calendar pane
- resource pane
- richer contextual menus and worktool behavior
- inspector/info panels
- multiple window modes
- more exact look-and-feel tuning

### Phase 5: Xcode project and Interface Builder workflow

Status: `Planned`

Target:

- support Xcode-based builds
- enable xib/nib-based editing for the new app UI if needed

Planned work:

- create a new Xcode project for `Jnlr`
- keep the compatibility layer wired into the new project
- decide which views stay code-built and which become xib-based
- use original Journler nibs as reference material, not direct runtime assets

### Phase 6: Broader Journler 2.6 feature restoration

Status: `Planned`

Target:

- restore the major missing Journler 2.6 workflows beyond the current shell

Likely scope:

- richer search behavior
- smart folders
- resource browsing and actions
- more metadata and inspector flows
- additional menu commands and keyboard behavior
- broader save coverage

### Phase 7: Deferred legacy integrations

Status: `Deferred`

These are intentionally not part of the near-term path:

- auto update
- mail sending
- blog publishing
- Address Book integration
- AppleScript parity
- advanced search UI beyond core restoration
- media capture and recording
- legacy WebKit-dependent features

## Current UI strategy

The current UI strategy is:

- do not revive the old Journler UI implementation directly
- do not directly reuse old nibs as runtime UI assets
- use Swift + AppKit for the new UI layer
- use original Journler 2.6 code and nibs as design and behavior reference
- move toward closer Journler 2.6 look and feel over time

Implication:

- the current app is not a direct port of the original UI
- it is a new app that is converging toward Journler 2.6 behavior and appearance

## Current top-level priorities

In order:

1. preserve compatibility safety
2. keep the new Swift + AppKit app stable
3. push the main window toward Journler 2.6 parity
4. move to an Xcode-managed project when the UI structure is ready
5. only then expand into broader legacy feature areas

## Next major steps

The next major steps are:

1. define the first Journler 2.6 parity milestone in concrete UI terms
2. decide when to introduce a new Xcode project
3. decide whether the next UI step is:
   - toolbar and search/filter
   - calendar pane
   - resource pane
4. keep this file updated when strategy or phase status changes

## Out of scope for this document

This file should not become a detailed daily log.

Do not record here:

- every small refactor
- every warning
- every transient experiment
- every command run in chat

Record here only:

- changes in overall direction
- completed major milestones
- phase state changes
- major known remaining gaps
