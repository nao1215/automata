# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- `automata/retry`: `Duration`, `FailureKind` (`Transient` / `Permanent`), `GiveUpReason` (`PolicyDisallowsRetry` / `MaxAttemptsReached` / `PermanentFailureSignaled` / `DelayOverflow`), `RetryError`, `Jitter`, and the duration helpers (`from_milliseconds` / `from_seconds` / `from_minutes` / `duration_milliseconds` / `duration_seconds` / `duration_to_string`) now live directly in `automata/retry` instead of `automata/retry/ast`. The `automata/retry/ast` submodule has been removed; callers that were importing both `automata/retry` and `automata/retry/ast` only need the former now. Migrate with `s/automata\/retry\/ast/automata\/retry/` on imports and references. **Breaking**. (#47)

## [0.8.0] - 2026-05-18

### Fixed

- `automata/rrule`: `rrule.validate` now accepts the three sub-daily RFC 5545 §3.3.10 frequencies (`SECONDLY`, `MINUTELY`, `HOURLY`) which were silently rejected with `InvalidPartValue(FreqPart, ...)` despite the parser accepting them. `rrule.to_string` round-trips them, and `rrule.builder(validator.Secondly | Minutely | Hourly)` now type-checks. `aligned()` in the evaluator gains sub-daily alignment via `calendar.seconds_between`. (#38)
- `automata/cron`: `cron.matches` no longer requires `at.time.second == 0`. UNIX cron is minute-granular per POSIX — the five fields are `minute / hour / day-of-month / month / day-of-week` with no second field, so any instant within a matching minute is a firing. Previously `matches` returned False for inputs with non-zero seconds (e.g. `cron.matches("30 * * * *", at: 12:30:30)` returned False instead of True). The iterator and `next_after` are unchanged because they already produce minute-boundary times by construction. (#41)
- `automata/cron`: `cron.validate` now rejects `*/N` step values that exceed the field's effective range (`max - min`), matching the strictness of Vixie / cronie. Previously `*/60` in the minute field, `*/24` in hour, `*/31` in day-of-month, `*/12` in month, and `*/8` in day-of-week all validated even though they produce at most one firing — an asymmetric behaviour against the existing `*/0` rejection. The boundary at `step == max - min` is still accepted (it produces exactly two firings; `*/59 * * * *` fires at minute 0 and 59). (#39)
- `automata/ical`: `ical.encode` now preserves the trailing `Z` UTC marker on DATE-TIME-valued properties that the RFC requires as UTC (`DTSTAMP`, `CREATED`, `LAST-MODIFIED`, `COMPLETED`) and on `DTSTART` / `DTEND` / `DUE` / `RDATE` / `EXDATE` when no `TZID` parameter is present. Properties tagged with `TZID=...` are still emitted without a `Z` suffix (FORM #3 — local time in a named zone), and `DTSTART` inside `VTIMEZONE` (where the RFC specifies local clock time) also remains unsuffixed. Previously every emitted DATE-TIME value lost its `Z` marker, silently converting RFC 5545 FORM #2 (UTC) inputs to FORM #1 (floating) and shifting receivers by their local UTC offset on import. (#40)

## [0.7.0] - 2026-05-16

### Added

- `automata/cron`: `cron.next_after_string(expr, at)` one-call facade that parses, validates, and evaluates the next firing in a single step, plus a `cron.CronError` sum type wrapping `parser.ParseError` and `validator.ValidationError`. Useful when a caller already holds a cron expression as a string and a `ValidDateTime` — the previous code path required three result/option unwraps and crossed two modules. Power users that evaluate the same expression many times keep using `parse` / `validate` / `normalize` and the `*_plan` family. (#33)
- `automata/retry`: `retry.capped_exponential_ms(initial_ms, multiplier, cap_ms, max_attempts)` direct constructor that accepts raw millisecond integers and skips the explicit `ast.from_milliseconds` calls at the call site. Useful when the initial delay and cap are compile-time literals — the previous code path required two `Result(Duration, _)` unwraps before the policy could be built. Callers that hold runtime-derived `Duration` values (for example, from a config parser) keep using `capped_exponential/4` unchanged. (#34)

## [0.6.0] - 2026-05-12

### Fixed

- `automata/cron`: `cron.next_after` and `cron.iterator_after` no
  longer skip a year when both `month` and `day_of_month` are fixed
  constants and the anchor falls after the cron's day-of-month in
  some later month (e.g. `"0 0 1 1 *"` anchored at `2026-12-15`
  used to yield `2028-01-01` instead of `2027-01-01`). The
  month-roll inside the iterator now resets day-of-month to 1 when
  crossing into the next matching month, so the day-search starts
  from the beginning of that month. The same root cause also
  affected fixed-month + wildcard-day specs that landed past day 1
  on the anchor. (#30)

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
