# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.5.0] - 2026-05-11

### Added

- `automata/ical` — RFC 5545 iCalendar parser and emitter that
  wraps the existing `automata/rrule`. Parses VCALENDAR /
  VEVENT / VTODO / VJOURNAL / VFREEBUSY / VTIMEZONE / VALARM
  blocks, with §3.1 line folding (CRLF/LF tolerant input,
  CRLF output, 75-octet UTF-8 boundary on emit), §3.2 quoted
  parameter values, §3.3.11 TEXT escaping (`\\`, `\,`, `\;`,
  `\n`/`\N`), and §3.4 content-line layout. RRULE values are
  preserved as `automata/rrule.RawRRule` so callers can pipe
  them through `rrule.validate` for semantic checks —
  `IcalError.InvalidRRule` wraps the syntactic
  `rrule/parser.ParseError`. Opaque `Calendar` / `Event` /
  `Todo` / `Journal` / `FreeBusy` / `Timezone` / `Alarm`
  types are usable as both parse results and builder targets
  (`new_calendar`, `add_event`, `new_event`, `with_summary`,
  `with_dtstart`, `with_rrule`, `with_attendee`, ...). Unknown
  component kinds round-trip through `UnknownComponent`
  rather than being dropped. Pure data, same results on BEAM
  and the JavaScript target. (#27)

## [0.4.0] - 2026-05-09

### Documentation

- README now has an `## Automaton` section with a runnable
  three-state door FSM example (`Closed` / `Open` / `Locked` plus
  `OpenIt` / `CloseIt` / `LockIt` / `UnlockIt`). Every other module
  in the Features list (`cron`, `rrule`, `schedule`, `event`,
  `fsevent`, `retry`) had a code block; the vanilla FSM helper —
  the very first feature listed — was the one module without one.
  The new section also notes that `Automaton(state, symbol)` is
  generic over both type parameters and that, unlike `cron.builder`
  / `rrule.builder`, the FSM helper has no builder layer —
  `automata.new` is the single entry point. (#16)
- `automata/cron.next_after/2` and `automata/cron.next_after_plan/2`
  now document when `None` can actually be returned. UNIX cron is
  non-terminating, so for typical inputs `None` is unreachable —
  the `Option` shape is preserved only for the internal recursion
  guard (~5,000,000 candidate minute steps) and the
  maximum-representable-`ValidDateTime` boundary. The doc-comment
  also calls out the asymmetry with RRULE's `next_after` (whose
  `Option` is real because a `COUNT=N` rule legitimately exhausts).
  `automata/cron/iterator.Step` gains the same note on its `Done`
  variant. (#17)

### Added

- `automata/cron.parse` now accepts the Vixie cron nickname aliases
  `@yearly` / `@annually`, `@monthly`, `@weekly`, `@daily` /
  `@midnight`, and `@hourly`. They are matched case-insensitively
  (matching croniter / robfig/cron / node-cron) and expand to their
  canonical 5-field forms (`0 0 1 1 *`, `0 0 1 * *`, `0 0 * * 0`,
  `0 0 * * *`, `0 * * * *`) before validation, so the rest of the
  pipeline is unchanged. (#18)
- `automata/cron/parser.ParseError` gains a `RebootNotSupported(value:)`
  variant. `@reboot` is recognised but rejected with this dedicated
  error rather than the generic `UnsupportedSyntax` so callers can
  give users a precise message ("startup hook, not a schedule") and
  point them at their host process supervisor instead. (#18)
- Property-based and metamorphic tests using
  [metamon](https://github.com/nao1215/metamon) covering the top-level
  `Automaton` API (parity machine acceptance and the
  "appending two `1`s preserves acceptance" metamorphic relation) and
  the `automata/retry` policy / context surface (round-trip on
  `Duration` milliseconds, `from_seconds` ↔ `duration_milliseconds`
  consistency, `no_retry` always gives up on `Transient`, `Permanent`
  failure short-circuits regardless of policy, fresh `Context` has zero
  attempt count and zero cumulative delay, smart-constructor rejection
  of non-positive `max_attempts` and `multiplier < 2`). Lives in
  `test/automata_metamon_test.gleam`.

## [0.3.0] - 2026-05-09

### Added

- `automata/event/metadata` getter functions
  (`correlation_id/1`, `causation_id/1`, `trace_id/1`, `attributes/1`)
  to mirror the existing `with_*` setters. Callers can now read and
  write metadata through symmetric function APIs without reaching into
  the `Metadata` record's public fields directly. (#13)

### Documentation

- `automata/event.continue_from/5`: docstring and README now state
  explicitly that the child event inherits `correlation_id`, `trace_id`,
  **and the full `attributes` dict** from the parent (previously the
  attribute inheritance was undocumented). Includes a pointer to
  `event.new` + `with_metadata(metadata.empty())` for callers that want
  a fresh attribute set on the child. (#13)

## [0.2.0] - 2026-05-09

### Changed

- **Breaking**: `automata/schedule.from_cron` and `automata/schedule.from_once`
  now return `Result(Schedule, ScheduleError)` instead of `Schedule`, so all
  four constructors (`from_cron`, `from_rrule`, `from_every`, `from_once`)
  share one shape. Generic helpers can compile any spec through the same
  type without per-arm `Ok(_)` wraps. Neither constructor can actually fail
  today (the `let assert Ok(_) = ...` pattern is the canonical idiom for
  both), so the change is mechanical at every call site. (#5)

### Added

- `automata/event/builtin/body.scheduled_event/4` — smart constructor
  for `Scheduled` events that derives `source_id` from `plan_id` and
  reuses a single `at` for both `occurred_at` and `fired_at`. Existing
  `body.new/4` is retained verbatim for the rare case where the two
  values genuinely differ. (#6)

### Documentation

- README's "Retry" section now records the `multiplier >= 2` minimum on
  `exponential` / `capped_exponential` (`retry.fixed` covers the
  multiplier=1 case) and lists every `Jitter` strategy
  (`NoJitter` / `FullJitter` / `EqualJitter`) in a single table, so a
  first-time reader sees both options surfaced together. (#7)

### Fixed

- `automata/cron`: comma-separated UPPERCASE alias lists in the
  day-of-week and month fields (`MON,WED,FRI`, `JAN,JUL`) were rejected
  as `UnsupportedSyntax` because the validator's reserved-Quartz-char
  pre-check matched `L`, `W`, `H` as substrings against the whole field
  before the comma split, even when those characters appeared inside
  legitimate alias tokens (`WED`, `THU`, `JUL`). The check now runs
  per-token after `int.parse` and `parse_alias` have failed, so genuine
  Quartz extensions are still caught (`UnsupportedSyntax(_, "15W")` for
  `15W,20`) while alias lists pass. (#4)

## [0.1.0] - 2026-05-09

Initial public release.

### Added

- Project scaffold with cross-target CI, release workflow, `justfile`,
  `mise` toolchain, contribution guide, and security policy.
- `automata` deterministic finite automaton helper.
- `automata/cron/{ast,parser,validator,normalize,evaluator,iterator,
  next,builder}` UNIX 5-field cron stack with explicit phase
  separation between parsing, validation, normalisation, matching,
  iteration, and next-occurrence calculation. Facade re-exports
  `Item` constructors (`item_exact/1`, `item_range/2`,
  `item_step_any/1`, `item_step_from/2`, `item_step_between/3`) so
  callers do not have to reach into `automata/cron/validator`.
- `automata/rrule/{ast,parser,validator,normalize,evaluator,iterator,
  next,builder}` RFC 5545 RRULE stack covering the supported subset
  (`FREQ`, `INTERVAL`, `COUNT`, `UNTIL`, `BYDAY`, `BYMONTH`,
  `BYMONTHDAY`, `BYHOUR`, `BYMINUTE`) anchored on a `ValidDateTime`.
- `automata/schedule` plus `automata/schedule/{ast,evaluator,iterator,
  next}` as a shared abstraction over compiled cron, RRULE,
  fixed-interval (`from_every`), and one-shot (`from_once`)
  schedules. One `matches` / `iterator_after` / `next_after` API
  serves all four constructors.
- `matches_plan/2`, `iterator_after_plan/2`, and `next_after_plan/2`
  variants on `automata/cron` and `automata/rrule` for callers that
  want to pay the normalisation cost once and reuse a `CronPlan` /
  `RRulePlan`.
- `automata/event` typed `Event(body)` values with source kinds,
  correlation / causation / trace metadata, free-form attributes,
  and filter / match combinators.
- `automata/event/builtin/body.EventBody` closed sum
  (`Scheduled`, `FileSystem(WatchEvent)`, `Manual`, `Custom`) wired
  to canonical `SourceKind` values via `body.new/4`.
- `automata/retry` deterministic retry-policy primitives:
  `no_retry`, `fixed`, `exponential`, `capped_exponential` with
  optional full / equal jitter, an opaque `Context`, and a
  step-by-step `decide` API. Cross-target safe (BEAM and JavaScript
  produce the same `Decision` list for any `(policy, seed,
  failure-sequence)` triple).
- `automata/fsevent` pure-domain port of fsnotify-style ops
  (`Create`, `Write`, `Remove`, `Rename`, `Chmod`) derived from
  comparing two `Snapshot` values, with optional file_id-based
  rename detection. Submodules cover `ast`, `path`, `op`, `entry`,
  `snapshot`, `watch`, `event`, `diff`. Facade re-exports the smart
  constructors and accessors callers actually reach for so a typical
  `diff/3` call no longer requires importing five submodules.
- Cross-OS CI matrix on `ubuntu-latest`, `macos-latest`, and
  `windows-latest` × `erlang` / `javascript` (six combinations).

### Fixed

- `automata/fsevent/path.path_is_absolute/1` returns `True` for
  Windows drive-letter paths (`C:\foo` / `c:/foo`) as documented.
- `automata/internal/calendar.add_seconds/2` advances in one
  arithmetic step instead of looping per second, so daily and weekly
  `schedule.from_every` intervals iterate without per-second
  recursion.
