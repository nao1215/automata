# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.15.0] - 2026-11-23

### Changed

- Breaking: `ical_encode` returns `IcalInvalidParameterValue(property, parameter, value)` for a parameter value containing DQUOTE. RFC 5545 has no way to write such a value, and the output previously failed to parse again.
- Breaking: cron fields, RRULE `INTERVAL`, `COUNT`, `BYMONTH`, `BYHOUR`, `BYMINUTE`, and UNTIL digits accept unsigned decimal digits only, as Vixie cron, croniter, and RFC 5545 do. `+5 * * * *`, `INTERVAL=+2`, and `UNTIL=-0010101` are now errors. `BYMONTHDAY` and `BYDAY` ordinals keep their optional sign.
- Repeated `BYDAY` values are removed like repeated values in the other lists, so `BYDAY=MO,TU,MO` renders as `BYDAY=MO,TU`.

### Fixed

- `FREQ=HOURLY` and `FREQ=MINUTELY` periods are clock hours and minutes counted from the anchor's hour or minute, as in RFC 5545 and python-dateutil. With an anchor of 09:30:17, `FREQ=HOURLY;INTERVAL=2;BYMINUTE=15` now yields 11:15:17 and 13:15:17 instead of 10:15:17 and 12:15:17, and `schedule_matches` agrees.
- Sub-daily rules skip spans that their day, hour, and minute filters exclude, so `FREQ=SECONDLY;BYMONTHDAY=31` or `FREQ=MINUTELY;BYMONTH=12;BYMONTHDAY=31` returns the next occurrence instead of `ScheduleSearchLimitReached`. A rule whose filters can never be reached from the anchor, such as `FREQ=HOURLY;INTERVAL=3;BYHOUR=18` anchored at 16:00, is an empty sequence (`Done`), as in python-dateutil.
- A `COUNT` rule without BY filters counts the occurrences before a query arithmetically. `FREQ=DAILY;COUNT=300000` answers `schedule_matches` and `schedule_iterator` near the end of the sequence instead of reaching the search limit.
- The cron documentation states that only a plain `*` is a wildcard for the day-of-month/day-of-week rule, and that an inclusive boundary with nonzero seconds starts after its minute.

## [0.14.0] - 2026-11-23

### Changed

- Breaking: consolidate the public API into `automata`. Remove the public `automata/cron`, `automata/rrule`, `automata/schedule`, `automata/event`, `automata/fsevent`, `automata/ical`, and `automata/retry` module families, their phase modules, and re-export aliases. Keep finite automata, cron, all seven recurrence frequencies, civil schedules, generic and built-in events, filesystem snapshots/differences, every supported iCalendar component, and retries.
- Breaking: expose `Automaton`, `Event`, `Metadata`, `Source`, `CronOptions`, `RecurrenceOptions`, and `IcalTimezoneRule` as records. Remove `new`, `initial_state`, and `step` from the finite-automaton API; construct the record, read its field, or call its transition callback. Keep `run` and `accepts`.
- Breaking: replace cron and recurrence builders and their `with_*` setters with options records, `cron_new`, and `rrule_new`. Construct `CronSelector`, `CronItem`, `CronStepBase`, `WeekdaySpecifier`, and end-condition variants directly instead of the `any`, `at`, `between`, `every*`, `item_*`, `one_of`, `weekday`, and `nth_weekday` wrappers. `cron_to_options` and `rrule_to_options` replace separate validated-field getters. `cron_parse_raw`/`cron_validate` and `rrule_parse_raw`/`rrule_validate` retain separate syntax and validation errors.
- Breaking: remove `CronError`, `next_after_string`, public `CronPlan`/`RRulePlan`, `IntSet`, normalization helpers, selector expansion, evaluator helpers, and the `*_plan` operations. Schedules keep their compiled lookup data privately. Parse, validation, and search errors can be combined by a caller-owned error type when needed.
- Breaking: use one `Schedule` and `OccurrenceIterator` API for cron, RRULE, fixed intervals, and one-shot occurrences. Replace domain-specific `matches`, `iterator_after`, `next_after`, and `step` variants with `schedule_matches`, `schedule_iterator`, `schedule_next`, and `schedule_step`. These operations return `Result`; an exhausted sequence is distinct from a search-work or numeric-range failure. `schedule_next` is exclusive; iterator boundaries can be inclusive or exclusive.
- Breaking: use gleam_time `Date`, `Month`, `TimeOfDay`, `DayOfWeek`, and `Duration` directly. Remove the local `Date`, `Time`, `Weekday`, retry `Duration`, and `Attempt` aliases/wrappers. Construct a civil `DateTime` and call `datetime_validate`; `datetime_value` reads it and `datetime_to_string` formats a validated value. TimeOfDay uses `hours`, `minutes`, `seconds`, and `nanoseconds`; scheduling requires zero nanoseconds. Remove `unsafe_assume_valid`, the raw `to_string` formatter, and redundant `try_datetime`/`try_valid_datetime` constructors.
- Breaking: replace event filter/matcher DSLs with ordinary predicates, `list.filter`, direct record inspection, and core collection operations. Remove `Filter`, `BuiltinEvent`, `Attributes`, metadata/source/body construction wrappers, and mechanical event/metadata setters. Use `Event(EventBody)` for built-in bodies, `builtin_event` for source derivation, and `event_continue_from` for metadata inheritance. Generic events still accept arbitrary body types.
- Breaking: replace filesystem `Watch` and its wrappers with `Set(Op)`. `diff_snapshots` takes the observed operation set explicitly; `all_ops` selects all five operations. Use `filesystem_event` with a set instead of `created`, `written`, `removed`, `renamed`, `chmoded`, or `multi_op`. Use core set operations and record/value equality instead of set wrappers and `path_equals`. Keep validated paths, entries, snapshots, and events, with their canonical operations in the root module.
- Breaking: prefix iCalendar operations with `ical_` and component types with `Ical`. Keep all component getters and setters that maintain stored values and wire forms. Replace `new_timezone_rule`, `with_timezone_rule_rrule`, and `with_timezone_rule_name` with `IcalTimezoneRule` record construction/updates. Consolidate parse/validation errors into `IcalError`; nested RRULE syntax errors remain typed. Lexer, line-folding, and escaping helpers are private.
- Breaking: `ical_encode` now returns `Result(String, IcalEncodeError)`. Validate typed dates and zero nanoseconds, reject wire years outside -999 through 9999, and reject raw CR/LF in rendered logical lines. Check errors in emission order. Typed TEXT normalizes CRLF and bare CR to LF while encoding; getters preserve the supplied text. Parsed DATE, floating, UTC, TZID, raw-text, and property-parameter forms remain supported.
- Breaking: use `retry_*` operations and the root `RetryPolicy`, `RetryContext`, and `RetryDecision` types. Policies consume core Duration values and reject fractional milliseconds instead of truncating them. Duration errors carry normalized seconds/nanoseconds pairs. Remove `capped_exponential_ms`, local duration conversion/constructor wrappers, `should_retry`, and `next_delay`; construct a core Duration and inspect `RetryDecision`. Preserve seeded jitter, caps, cumulative overflow, permanent-failure priority, and total-attempt limits.
- Accumulate repeated iCalendar values together with their forms, using prepend/reverse so building long lists is linear. Preserve repeated-value order, adjacent form grouping, scalar first-wins behavior, extension-property last-wins behavior, and same-value setter resets.

```gleam
// Before: import automata/cron
let spec = cron.builder()
  |> cron.with_minute(cron.at(15))
  |> cron.build

// After: import automata
let options = automata.cron_options()
let spec = automata.cron_new(automata.CronOptions(
  ..options,
  minute: automata.CronValues([automata.CronExact(15)]),
))
```

### Fixed

- Return a typed RRULE validation error for out-of-range months in raw UNTIL dates and date-times.
- Keep embedded U+FEFF in iCalendar text, parameters, and unknown components. Only one BOM at the start of the document is removed.
- Search aligned recurrence periods directly, so valid distant occurrences such as an 11,000-year interval are not mistaken for the end of a sequence. Preserve COUNT from the original anchor, including matching and queries starting later in the sequence. Distinguish a proven empty cycle from an exhausted search budget.
- Compute fixed intervals and civil arithmetic using exact calendar-cycle components. Avoid walking one day at a time for large intervals and preserve one-second differences near JavaScript's safe-year boundaries. Erlang continues to support arbitrary-precision civil years.
- Prevent unchecked public cron plans and selector helpers from producing invalid validated dates, hanging on empty selectors, or recursing forever for a zero step. Public typed constructors continue to reject these invalid values.
- Validate every typed date field during iCalendar encoding, preserve the parser's supported signed four-character year forms in a reparseable spelling, and reject physical-newline injection in non-TEXT fields and raw component/property data.

### Documentation

- Rewrite the README and public comments around the root API, civil-time semantics, explicit search failures, retry decisions, and preserved iCalendar forms. Move release verification to CONTRIBUTING.md and distinguish local checks from the CI matrix and historical mutation measurements.

## [0.13.0] - 2026-11-22

### Changed

- Cron steps may be as large as the field's range, so `*/60` for minutes, `*/24` for hours, `*/31`, `*/12` and `*/8` are accepted, as in croniter. Larger steps are still rejected.
- RRULE accepts one `WKST=MO`, the default week start, and drops it from `to_string`. Other values and repeated `WKST` parts are rejected with `UnsupportedPart("WKST")`.
- Retry jitter covers the whole range for delays above 2^32 ms, no longer favours small values for small seeds, and `EqualJitter` can reach the base delay. The same seed gives the same delays on both targets, but they differ from earlier versions.
- `fsevent` reports a move as a `Remove` of the old path and a `Create` of the new one when the watch does not include `Rename`, and reports a rename over an existing file, or two swapped files, as `Rename`. A changed `file_id` at a path reports `Remove` and `Create` unless folded into a `Rename`, including replacement at the destination and recreation of the source; non-empty new files also report `Write`, subject to the watch mask.
- `ical.encode` preserves the forms and parameters of retained properties: floating date-times stay floating, dates stay dates even without `VALUE=DATE`, and each `RDATE`/`EXDATE` value retains its own form. Repeated attendees, categories and free/busy periods keep their parameters, including `PARTSTAT`, `LANGUAGE` and `FBTYPE`, and parameter lists keep their value boundaries. When a single-valued property such as `DTSTART` appears twice, the first one is used; repeated extension properties retain the last value and its parameters.
- iCalendar setters clear the replaced property's parsed parameters, and appended values do not inherit another value's parameters. Added or replaced date-times default to UTC; an event's explicitly set `TZID` still applies, and timezone rules default to local time. Replacing a date-valued `DTSTART`, `DTEND` or VTODO `DUE` also changes its paired date property to DATE-TIME so their value types agree.

### Fixed

- `rrule.next_after` and `rrule.matches` no longer count every occurrence since the start when the rule has no `COUNT`, and stop counting at `COUNT`. A secondly rule a week after its start took 18 seconds.
- Secondly, minutely and hourly rules with a large `INTERVAL` jump to the next step instead of running out of search steps and returning no occurrence. `FREQ=MINUTELY;INTERVAL=4500000` now finds 2034-07-23.
- Weekdays and day counts are correct for years before 1, and `to_string` writes such years as `-0001`.
- The cron and RRULE builders validate typed values directly. The cron builder reports negative values as out of range, for example `OutOfRange(Minute, 0, 59, -1)` for `cron.at(-1)`, instead of interpreting them as malformed ranges.
- iCalendar output no longer escapes parsed `PRODID`, timezone names or extension values a second time, and retains their parameters. Category lists distinguish escaped backslashes from escaped commas, keeping the original value boundaries.
- `ical` adds components in constant time; 20000 events took over 3 seconds on JavaScript.
- The README example that reads an RRULE from an iCalendar event compiles, and the cron `next_after` documentation describes its search limit accurately.

## [0.12.0] - 2026-11-19

### Added

- GitHub Releases now attach the package tarball, `checksums.txt`, its cosign signature (`checksums.txt.sigstore.json`) and build provenance (`.intoto.jsonl`). See "Verifying releases" in the README.

## [0.11.0] - 2026-09-10

### Changed

- The minimum Gleam version is now 1.14.0 (was 1.15.0). 1.14.0 builds and tests the package unchanged on both targets, and `gleam_stdlib` 1.0 already requires it. CI tests that floor alongside the latest Gleam 1.x.

## [0.10.0] - 2026-05-23

### Fixed

- `automata/rrule`: `FREQ=HOURLY`, `FREQ=MINUTELY`, and `FREQ=SECONDLY` now expand correctly when no `BYHOUR` / `BYMINUTE` / (implicit) `BYSECOND` part is specified — previously the iterator collapsed sub-daily frequencies to one occurrence per day at the anchor's single hour/minute/second instead of walking the full 0..23 / 0..59 / 0..59 range per RFC 5545 §3.3.10. `FREQ=HOURLY;INTERVAL=2` and `FREQ=MINUTELY;INTERVAL=15` style rules now also yield the correct interval-stepped occurrences. Daily-and-coarser frequencies are unchanged. Follow-up to #38. (#55)

### Documentation

- Added module-header docstrings to all five `*/ast.gleam` modules (`automata/cron/ast`, `automata/rrule/ast`, `automata/ical/ast`, `automata/fsevent/ast`, `automata/schedule/ast`) clarifying that they hold the public runtime domain types every caller needs (e.g. `ValidDateTime`, `Weekday`, `Op`), not parser internals. Each docstring links back to the corresponding feature module where the parse / validate / iterate entry points live. (#54)

## [0.9.0] - 2026-05-20

### Changed

- `automata/retry`: `Duration`, `FailureKind` (`Transient` / `Permanent`), `GiveUpReason` (`PolicyDisallowsRetry` / `MaxAttemptsReached` / `PermanentFailureSignaled` / `DelayOverflow`), `RetryError`, `Jitter`, and the duration helpers (`from_milliseconds` / `from_seconds` / `from_minutes` / `duration_milliseconds` / `duration_seconds` / `duration_to_string`) now live directly in `automata/retry` instead of `automata/retry/ast`. The `automata/retry/ast` submodule has been removed; callers that were importing both `automata/retry` and `automata/retry/ast` only need the former now. Migrate with `s/automata\/retry\/ast/automata\/retry/` on imports and references. **Breaking**. (#47)

### Fixed

- `automata/rrule`: `rrule.validate` no longer hides the specific reason an UNTIL value was rejected behind the generic `InvalidPartValue(UntilPart, _)`. Three new `ValidationError` variants name the actual cause: `UntilMissingZ(value: String)` when the caller wrote a DATE-TIME shape (`YYYYMMDDTHHMMSS` of length 15, or length 16 with `T` at position 8 but no trailing `Z`) and almost certainly meant UTC; `UntilMalformedDateTime(value: String)` for wrong-length, non-digit, or otherwise unparseable input; and `UntilLocalFormUnsupported(value: String, reason: String)` reserved for future explicit FORM #3 handling. The `InvalidPartValue` catch-all is retained for backward-compatible matching elsewhere. **Breaking** for code that pattern-matched specifically on `InvalidPartValue(UntilPart, _)` to detect UNTIL errors — switch to matching `UntilMissingZ` / `UntilMalformedDateTime`. (#49)
- `automata/fsevent`: `fsevent.normalize` no longer silently collapses Windows UNC-style paths (`//server/share` or `\\server\share`) to `/server/share`. Inputs with exactly two leading slashes after backslash unification are now rejected with a dedicated `UncPathNotSupported(path: String)` error; `fsevent` is POSIX-only and cross-platform callers should now see an explicit failure instead of a path whose UNC prefix has silently disappeared. Three or more leading slashes are still treated as a single leading slash per POSIX `IEEE Std 1003.1-2017 §4.13` (`///a/b` → `/a/b`). **Breaking** for callers that relied on the silent collapse — they will now see `Error(UncPathNotSupported(...))` and must filter or convert UNC inputs themselves. (#48)

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
