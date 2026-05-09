# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- `automata/fsevent/path`: `path_is_absolute/1` now returns `True` for
  Windows drive-letter paths (`C:\foo` / `c:/foo`), matching the
  documented behaviour. Previously only paths starting with `/` were
  treated as absolute.

### Changed

- `automata/cron` facade re-exports `Item` constructors as
  `item_exact/1`, `item_range/2`, `item_step_any/1`, `item_step_from/2`,
  and `item_step_between/3`, so callers no longer need to import
  `automata/cron/validator` to compose `cron.one_of/1` arguments.
- `automata/cron` and `automata/rrule` add `matches_plan/2`,
  `iterator_after_plan/2`, and `next_after_plan/2` (RRULE adds
  `matches_plan/2`, `iterator_after_plan/2`, `next_after_plan/2`)
  variants that accept an already-`normalize`d plan, so callers
  evaluating the same spec many times can pay the normalisation cost
  once.
- `automata/fsevent` facade now re-exports `Entry`, `Snapshot`,
  `Watch`, `WatchEvent`, and `NormalizedPath` types together with the
  smart constructors and accessors most callers reach for, so a
  typical `diff/3` usage no longer requires importing five
  submodules.
- README rewritten to lead with a one-line feature list and runnable
  examples; development setup now lives entirely in
  `CONTRIBUTING.md`.
- Doc comments added to the cron / rrule facades, `event/source`,
  `event/metadata`, and `event/filter` public functions previously
  left undocumented.

### Added

- `automata/cron/{ast,parser,validator,normalize,evaluator,iterator,next,builder}`
  as a composable UNIX 5-field cron stack.
- `automata/rrule/{ast,parser,validator,normalize,evaluator,iterator,next,builder}`
  as a composable RFC 5545 RRULE stack for the initial supported subset.
- `automata/schedule` plus `automata/schedule/{ast,evaluator,iterator,next}`
  as a shared abstraction over compiled cron and RRULE schedules.
- Matching and next-occurrence calculation for both cron and RRULE.
- Iterator-based occurrence generation for both cron and RRULE.
- Anchor-aware RRULE normalization with typed builder APIs.
- `automata/fsevent` module group: a pure-domain port of the Go
  fsnotify semantics with zero I/O. Submodules cover `Op`, `EntryKind`,
  `FseventError` (`ast`); `NormalizedPath` and path canonicalisation
  (`path`); set-based `Op` helpers (`op`); validating `Entry` smart
  constructors (`entry`); `Snapshot` (`snapshot`); a subscription
  `Watch` (`watch`); a `WatchEvent` opaque carrying a path, op set, and
  optional `renamed_from` (`event`); and a snapshot differ that
  reproduces fsnotify's create/write/remove/rename/chmod semantics
  including file_id-based rename detection (`diff`).
- Cross-OS CI matrix expanded to `ubuntu-latest`, `macos-latest`, and
  `windows-latest` × `erlang`/`javascript` (six combinations).

### Changed

- `automata/cron` is now a breaking, UNIX-only API with explicit phase
  separation between parse, validate, normalize, evaluate, iterate, and
  next-occurrence logic.
- `automata/rrule` is now a breaking, subset-focused API with explicit
  parsing, validation, normalization, matching, iteration, and
  next-occurrence boundaries.
- Project metadata and README now describe `automata` as a schedule
  library in addition to the original finite automata helper.
- **BREAKING**: `automata/event/builtin/body.EventBody` replaces the
  four `FileCreated/FileModified/FileDeleted/FileRenamed` variants and
  their per-variant smart constructors with a single
  `FileSystem(automata/fsevent/event.WatchEvent)` variant, accessed
  through `body.file_system(event)`. `body.kind/1` now returns
  `"file_system:<op>"` (e.g. `"file_system:create+write"`,
  `"file_system:rename"`) instead of the four legacy `"file_*"` strings.
- **BREAKING**: `automata/event/builtin/{match,filter}` lose the
  `is_file_created/modified/deleted/renamed` helpers in favour of a
  unified `is_file_with_op(op)` that matches a `FileSystem(_)` body
  against any `fsevent` `Op` value.

### Removed

- AWS/EventBridge cron support from the public `automata/cron` facade.
- Quartz- and Jenkins-style cron syntax from the supported surface.
- Unsupported RRULE parts from the public contract, including
  `BYSECOND`, `BYYEARDAY`, `BYWEEKNO`, `BYSETPOS`, and `WKST`.

## [0.1.0] - 2026-05-08

### Added

- Initial Gleam project scaffold with cross-target CI, release workflow,
  `justfile`, `mise`, contribution guide, and security policy.
