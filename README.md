# automata

[![CI](https://github.com/nao1215/automata/actions/workflows/ci.yml/badge.svg)](https://github.com/nao1215/automata/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/automata)](https://hex.pm/packages/automata)

Finite automata and schedule helpers for Gleam.

This repository is scaffolded as a cross-target Gleam library with:

- `just` tasks for day-to-day development
- `mise` toolchain management
- GitHub Actions for CI and release
- starter `CONTRIBUTING.md`, `SECURITY.md`, and `CHANGELOG.md`

Current modules:

- `automata` - small deterministic automaton helpers
- `automata/cron` - UNIX cron facade over parser, validator,
  normalizer, evaluator, iterator, next, and builder modules
- `automata/rrule` - RFC 5545 RRULE facade over parser, validator,
  normalizer, evaluator, iterator, next, and builder modules
- `automata/schedule` - shared abstraction over compiled cron and
  RRULE schedules
- `automata/event` - common event abstraction shared across the
  ecosystem (cron/rrule firings, file-system notifications, manual
  triggers, future webhooks/queues/signals)

## Requirements

- Gleam 1.15 or later
- Erlang/OTP 28 or later
- Node.js 22 or later (for JavaScript-target checks)
- [just](https://just.systems/) (recommended)
- [mise](https://mise.jdx.dev/) (recommended)

## Install

```sh
gleam add automata
```

## Development setup

```sh
git clone https://github.com/nao1215/automata.git
cd automata
mise install
just deps
```

`just` recipes source `scripts/lib/mise_bootstrap.sh`, so `mise activate`
is not required in the current shell.

## Quick start

```gleam
import automata
import gleam/io

pub type State {
  Even
  Odd
}

pub fn parity_machine() {
  automata.new(
    initial_state: Even,
    transition: fn(state, symbol) {
      case state, symbol {
        Even, 1 -> Odd
        Odd, 1 -> Even
        _, _ -> state
      }
    },
    accepting: fn(state) { state == Even },
  )
}

pub fn main() {
  let machine = parity_machine()

  automata.accepts(machine, [1, 0, 1, 1])
  |> io.debug
  // False
}
```

## Cron

Initial cron support is intentionally narrow:

- UNIX 5-field only: `minute hour day_of_month month day_of_week`
- no seconds field
- no Quartz syntax
- no Jenkins syntax
- no embedded timezone syntax

Parsing, validation, normalization, matching, iteration, and
next-occurrence calculation are separate phases.

```gleam
import automata/cron
import automata/schedule/ast as schedule_ast
import gleam/io

pub fn main() {
  let assert Ok(raw) = cron.parse("*/15 9-17 * * MON-FRI")
  let assert Ok(spec) = cron.validate(raw)
  let assert Ok(after) =
    schedule_ast.try_valid_datetime(
      year: 2026,
      month: 5,
      day: 11,
      hour: 9,
      minute: 7,
      second: 0,
    )

  cron.to_string(spec)
  |> io.debug

  cron.next_after(spec, after: after)
  |> io.debug
}
```

Builder usage:

```gleam
import automata/cron
import automata/cron/validator as cron_validator

pub fn business_hours() {
  cron.builder()
  |> cron.with_minute(cron.every(15))
  |> cron.with_hour(cron.between(from: 9, to: 17))
  |> cron.with_day_of_week(cron.one_of([cron_validator.Range(1, 5)]))
  |> cron.build
}
```

## RRULE

`automata/rrule` supports RFC 5545 recurrence rule values with an
explicitly limited initial feature set.

Supported parts:

- `FREQ`
- `INTERVAL`
- `COUNT`
- `UNTIL`
- `BYMINUTE`
- `BYHOUR`
- `BYDAY`
- `BYMONTHDAY`
- `BYMONTH`

Supported input forms:

- raw value: `FREQ=WEEKLY;BYDAY=MO,WE`
- property line: `RRULE:FREQ=WEEKLY;BYDAY=MO,WE`

Evaluation is anchor-dependent, so normalization and execution-facing
APIs require a `ValidDateTime` anchor similar to `DTSTART`.
`ValidDateTime` is constructed via `schedule_ast.try_valid_datetime/6`
and prevents impossible calendar dates such as 2026-02-30 from
flowing into match / next_after / iterator entry points.

```gleam
import automata/rrule
import automata/rrule/validator as rule_validator
import automata/schedule/ast as schedule_ast
import gleam/io

pub fn every_other_week() {
  let assert Ok(anchor) =
    schedule_ast.try_valid_datetime(
      year: 2026,
      month: 1,
      day: 5,
      hour: 9,
      minute: 30,
      second: 0,
    )
  let assert Ok(after) =
    schedule_ast.try_valid_datetime(
      year: 2026,
      month: 1,
      day: 5,
      hour: 9,
      minute: 31,
      second: 0,
    )

  let assert Ok(spec) =
    rrule.builder(rule_validator.Weekly)
    |> rrule.with_interval(2)
    |> rrule.with_by_day([
      rrule.weekday(day: schedule_ast.Monday),
      rrule.weekday(day: schedule_ast.Wednesday),
    ])
    |> rrule.with_by_hour([9])
    |> rrule.with_by_minute([30])
    |> rrule.build

  rrule.next_after(spec, anchor: anchor, after: after)
  |> io.debug
}
```

Anchor seconds are preserved end-to-end. An anchor of
`2026-05-01T09:00:30` produces occurrences at `:30` and the
exclusive `next_after` / iterator boundary advances by one second
rather than one minute, so `next_after(after: 09:00:00)` returns
`09:00:30` of the same day.

Frequency-specific validation follows RFC 5545 §3.3.10:

- `FREQ=WEEKLY;BYMONTHDAY=...` is rejected (returns
  `IncompatibleFrequencyAndPart(Weekly, ByMonthDayPart)`).
- `FREQ=YEARLY;BYDAY=<n>XX` without `BYMONTH` evaluates the
  numeric ordinal as an offset within the year. With `BYMONTH`
  present, the offset is within that month.

Builder construction validates inputs eagerly:

- `with_by_*([])` returns `InvalidList(<part>, "")`.
- `nth_weekday(ordinal: 0, ...)` returns
  `InvalidPartValue(ByDayPart, "0XX")`.
- BYDAY ordinals are bounded per RFC 5545: monthly accepts
  `[-5, -1] ∪ [1, 5]` and yearly accepts `[-53, -1] ∪ [1, 53]`.
  Out-of-range values such as `99MO` or `-6MO` are rejected with
  `InvalidPartValue(ByDayPart, ...)`.

Sparse rules are supported. For example
`FREQ=YEARLY;INTERVAL=500` produces occurrences ~182,500 days apart
and the iterator scans up to ~10,950 years before giving up.

Not supported in the current version:

- `BYSECOND`
- `BYYEARDAY`
- `BYWEEKNO`
- `BYSETPOS`
- `WKST`
- `DTSTART`, `TZID`, `RDATE`, `EXDATE`, `EXRULE`
- recurrence set algebra

## Validated date-time construction

`automata/schedule/ast` exposes `try_datetime/6` and
`try_valid_datetime/6` smart constructors that return `Result`
when month/day/time components fall outside the Gregorian range.
The opaque `ValidDateTime` wrapper communicates "already
validated" at the type level and unwraps with
`valid_datetime_value/1`.

```gleam
import automata/schedule/ast as schedule_ast

pub fn safe_anchor() {
  schedule_ast.try_datetime(
    year: 2024,
    month: 2,
    day: 29,
    hour: 9,
    minute: 0,
    second: 0,
  )
}
```

## Shared schedule API

Cron and RRULE stay separate at the syntax layer, but share one
compiled abstraction.

```gleam
import automata/cron
import automata/schedule
import automata/schedule/ast as schedule_ast
import gleam/io

pub fn shared_api() {
  let assert Ok(raw) = cron.parse("*/30 9-17 * * 1-5")
  let assert Ok(spec) = cron.validate(raw)
  let compiled = schedule.from_cron(spec)

  let assert Ok(at) =
    schedule_ast.try_valid_datetime(
      year: 2026,
      month: 5,
      day: 11,
      hour: 10,
      minute: 0,
      second: 0,
    )
  let assert Ok(after) =
    schedule_ast.try_valid_datetime(
      year: 2026,
      month: 5,
      day: 11,
      hour: 10,
      minute: 7,
      second: 0,
    )

  schedule.matches(compiled, at: at)
  |> io.debug

  schedule.next_after(compiled, after: after)
  |> io.debug
}
```

`schedule` also offers two more constructors that share the same
matching/iterator/next-after API:

- `schedule.from_every(interval_seconds:, anchor:)` for fixed-interval
  schedules (returns `Error(EveryIntervalMustBePositive(...))` when the
  interval is non-positive).
- `schedule.from_once(at:)` for a one-shot schedule that fires exactly
  once at `at`.

## Events

`automata/event` is the common event abstraction shared across the
automata ecosystem. It defines value-only types for "something
happened" — schedulers, file watchers, manual triggers, and future
webhook/queue/signal integrations all produce the same `Event` shape
so that workers and runtimes can route them with one vocabulary.

The library does not own a runtime. It does not run event loops, send
network messages, or implement queues. It only defines types,
metadata, classification, filtering, and matching primitives.

```gleam
import automata/event/builtin/body
import automata/event/builtin/filter as builtin_filter
import automata/event/filter
import automata/schedule/ast as schedule_ast

pub fn cron_event() {
  let assert Ok(now) =
    schedule_ast.try_valid_datetime(
      year: 2026,
      month: 5,
      day: 9,
      hour: 9,
      minute: 0,
      second: 0,
    )

  body.new(
    id: "evt-001",
    occurred_at: now,
    source_id: "daily-report",
    body: body.scheduled(
      plan_id: "daily-report",
      fired_at: now,
      schedule_kind: body.CronSchedule,
    ),
  )
}

pub fn watch_logs() {
  filter.all_of([
    builtin_filter.is_file_event(),
    builtin_filter.by_path_prefix(prefix: "/var/log/"),
    filter.negate(builtin_filter.by_path_suffix(suffix: ".tmp")),
  ])
}
```

`Event(body)` is parameterised so callers can pipeline typed events
inside their own code, while ecosystem-wide layers use the
`BuiltinEvent` alias backed by the closed `EventBody` sum
(`Scheduled`, `FileCreated`, `FileModified`, `FileDeleted`,
`FileRenamed`, `Manual`, `Custom`).

`body.new/4` is the canonical constructor for `BuiltinEvent`: it
takes a `source_id` and derives the `SourceKind` from `body`, so
`Scheduled` always pairs with `ScheduleSource`, `FileModified` with
`FileSystemSource`, and `Custom("vendor.kind", _)` with
`CustomSource("vendor.kind")`. Source/body misclassification cannot
arise via this path.

`Custom(kind, attributes)` is the escape hatch for events that do not
yet have a typed variant; recommended naming is `"<vendor>.<event>"`
(for example `"slack.message_posted"`).

`event.continue_from/5` derives a child event whose metadata chains
from a parent: it copies `correlation_id` and `trace_id` and sets
`causation_id` to `parent.id`, so chains of custody are preserved
without manual bookkeeping.

`Event.occurred_at` and `Scheduled.fired_at` are typed as
`ValidDateTime`, so impossible dates such as 2026-02-30 cannot enter
the event stream. Filter helpers `filter.occurred_between/2`,
`filter.occurred_after/1`, and `filter.occurred_before/1` likewise
accept `ValidDateTime`.

## Module layout

- `automata/cron/ast`, `parser`, `validator`, `normalize`, `evaluator`,
  `iterator`, `next`, `builder`
- `automata/rrule/ast`, `parser`, `validator`, `normalize`,
  `evaluator`, `iterator`, `next`, `builder`
- `automata/schedule`, `automata/schedule/ast`
- `automata/event`, `automata/event/source`,
  `automata/event/metadata`, `automata/event/filter`,
  `automata/event/match`, `automata/event/builtin/body`,
  `automata/event/builtin/filter`, `automata/event/builtin/match`

Breaking changes are acceptable in this repository and the current
schedule APIs prefer correctness and explicit phase separation over
backward compatibility.

## Commands

```sh
just ci
```

Runs format check, lint, type check, Erlang/JavaScript builds, and
Erlang/JavaScript tests.

## License

MIT
