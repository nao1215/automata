# automata

[![CI](https://github.com/nao1215/automata/actions/workflows/ci.yml/badge.svg)](https://github.com/nao1215/automata/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/automata)](https://hex.pm/packages/automata)
[![Downloads](https://img.shields.io/hexpm/dt/automata)](https://hex.pm/packages/automata)
[![Hex Docs](https://img.shields.io/badge/hexdocs-online-purple)](https://hexdocs.pm/automata)
[![License](https://img.shields.io/hexpm/l/automata)](LICENSE)

Cron, RRULE, retries, filesystem events, and finite automata for
Gleam. Pure data: every module produces the same answers on the
BEAM and on the JavaScript target.

## Features

- `automata` — deterministic finite automaton helper.
- `automata/cron` — UNIX 5-field cron with separate parse, validate, normalise, match, iterate, and next phases.
- `automata/rrule` — RFC 5545 RRULE subset (FREQ, INTERVAL, COUNT, UNTIL, BYDAY, BYMONTH, BYMONTHDAY, BYHOUR, BYMINUTE) anchored on a `ValidDateTime`.
- `automata/ical` — RFC 5545 iCalendar parser and emitter for the `VCALENDAR` envelope around `automata/rrule`, with line folding, parameter quoting, and TEXT escaping.
- `automata/schedule` — one matcher / iterator / next-after API across compiled cron, RRULE, fixed-interval, and one-shot schedules.
- `automata/event` — typed `Event(body)` values with source kinds, correlation / causation / trace metadata, and filter / match combinators.
- `automata/fsevent` — fsnotify-style Create / Write / Remove / Rename / Chmod ops derived from two filesystem snapshots, with file_id-based rename detection.
- `automata/retry` — deterministic retry policies (fixed, exponential, capped exponential) with optional jitter and a step-by-step `Decision` interface.

## Install

```sh
gleam add automata
```

## Automaton

The vanilla `automata` module is a deterministic finite automaton
helper: a current state, a pure transition function, and an
acceptance predicate. Construct one with `automata.new`, advance it
with `step` / `run`, and ask `accepts` whether the input is in the
language.

```gleam
import automata
import gleam/io

pub type Door {
  Closed
  Open
  Locked
}

pub type Action {
  OpenIt
  CloseIt
  LockIt
  UnlockIt
}

fn transition(state: Door, action: Action) -> Door {
  case state, action {
    Closed, OpenIt -> Open
    Open, CloseIt -> Closed
    Closed, LockIt -> Locked
    Locked, UnlockIt -> Closed
    other, _ -> other
  }
}

pub fn main() {
  let dfa =
    automata.new(
      initial_state: Closed,
      transition: transition,
      accepting: fn(state) { state == Open },
    )

  automata.run(dfa, [OpenIt, CloseIt, LockIt]) |> io.debug
  // -> Locked

  automata.accepts(dfa, [OpenIt]) |> io.debug
  // -> True
}
```

`Automaton(state, symbol)` is generic over both the state and symbol
types, so the transition function can pattern-match on whatever your
domain actually looks like (`type Door`, `type LifecycleStage`,
`Int`, `String`, etc.). Unlike `cron.builder` / `rrule.builder`, the
FSM helper has no builder layer — `automata.new` is the single
entry point, and the transition function does the work.

## Cron

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

  cron.next_after(spec, after: after) |> io.debug
}
```

Reuse a normalised plan when you evaluate the same spec many times:

```gleam
let plan = cron.normalize(spec)
cron.matches_plan(plan: plan, at: now)
cron.next_after_plan(plan: plan, after: now)
```

Builder form, without importing the validator submodule:

```gleam
import automata/cron

pub fn business_hours() {
  cron.builder()
  |> cron.with_minute(cron.every(15))
  |> cron.with_hour(cron.between(from: 9, to: 17))
  |> cron.with_day_of_week(cron.one_of([cron.item_range(from: 1, to: 5)]))
  |> cron.build
}
```

## RRULE

```gleam
import automata/rrule
import automata/rrule/validator as rule_validator
import automata/schedule/ast as schedule_ast

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

  rrule.next_after(spec, anchor: anchor, after: anchor)
}
```

Anchor seconds are preserved end-to-end. `BYSECOND`, `BYYEARDAY`,
`BYWEEKNO`, `BYSETPOS`, `WKST`, `DTSTART`, `RDATE`, and `EXDATE` are
not in the supported subset. `rrule.normalize/2` returns an
`RRulePlan` for use with `rrule.matches_plan` / `iterator_after_plan`
/ `next_after_plan` when you reuse the same spec/anchor pair.

## iCalendar

`automata/ical` is an RFC 5545 parser and emitter built on top of
`automata/rrule`. It handles the surrounding `VCALENDAR` envelope
that RRULE almost always ships inside, with line folding,
parameter quoting, and TEXT escaping handled per §3.1, §3.2, and
§3.3.11.

```gleam
import automata/ical
import gleam/io
import gleam/list
import gleam/option

pub fn main() {
  let feed =
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//example//EN\r\n"
    <> "BEGIN:VEVENT\r\nUID:abc@example.com\r\n"
    <> "DTSTAMP:20260511T000000Z\r\nDTSTART:20260511T130000\r\n"
    <> "SUMMARY:Coffee\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

  let assert Ok(cal) = ical.parse(feed)

  ical.events(cal)
  |> list.map(ical.event_summary)
  |> list.map(option.unwrap(_, ""))
  |> io.debug
  // -> ["Coffee"]
}
```

`event_rrule(event)` returns `Option(RawRRule)` straight from
`automata/rrule`, so recurrence rules compose without re-parsing:

```gleam
case ical.event_rrule(event) {
  option.Some(raw) -> rrule.validate(raw: raw)
  option.None -> Error(Nil)
}
```

`ical.parse |> ical.encode |> ical.parse` is stable: parsing an
emitted calendar yields the same property set. Output folds at 75
UTF-8 octets and uses CRLF line terminators per RFC 5545.

## Schedule

```gleam
import automata/cron
import automata/schedule

pub fn shared_api(now, after) {
  let assert Ok(raw) = cron.parse("*/30 9-17 * * 1-5")
  let assert Ok(spec) = cron.validate(raw)
  let assert Ok(compiled) = schedule.from_cron(spec)

  schedule.matches(compiled, at: now)
  schedule.next_after(compiled, after: after)
}
```

`schedule.from_every(interval_seconds:, anchor:)` builds a
fixed-interval schedule; `schedule.from_once(at:)` fires exactly
once. All four constructors return `Result(Schedule, ScheduleError)`
so they share one shape, even though `from_cron` and `from_once`
cannot fail today (`let assert Ok(_) = ...` is the canonical idiom for
those two). Beyond construction, the four schedules share the same
matcher / iterator / next-after API.

## Events

```gleam
import automata/event/builtin/body
import automata/event/builtin/filter as builtin_filter
import automata/event/filter
import automata/fsevent/ast as fs_ast
import automata/schedule/ast as schedule_ast

pub fn cron_event(now) {
  // Smart constructor: in the common case `source_id == plan_id` and
  // `occurred_at == fired_at`, so `scheduled_event` derives both from a
  // single (id, plan_id, at) tuple. Reach for `body.new/4` only when
  // those values genuinely differ.
  body.scheduled_event(
    id: "evt-001",
    plan_id: "daily-report",
    at: now,
    schedule_kind: body.CronSchedule,
  )
}

pub fn watch_logs() {
  filter.all_of([
    builtin_filter.is_file_with_op(op: fs_ast.Write),
    builtin_filter.by_path_prefix(prefix: "/var/log/"),
    filter.negate(builtin_filter.by_path_suffix(suffix: ".tmp")),
  ])
}
```

`body.scheduled_event/4` is a thin wrapper over `body.new/4` for
scheduled events, where `source_id` and `plan_id` are typically the
same string and `occurred_at` and `fired_at` are typically the same
instant. Use `body.new/4` directly for the rare case where the values
genuinely differ (delayed dispatch recorded after the fact, fan-out
under a different `source_id`).

`body.new/4` derives the canonical `SourceKind` from the body, so
`Scheduled` pairs with `ScheduleSource`, `FileSystem(_)` with
`FileSystemSource`, and `Custom("vendor.kind", _)` with
`CustomSource("vendor.kind")`. `Event.occurred_at` is a
`ValidDateTime`, which rejects impossible calendar dates such as
2026-02-30. `event.continue_from/5` chains a child event from a
parent, inheriting `correlation_id`, `trace_id`, and the full
`attributes` dict, and setting `causation_id` to the parent's id.
Use `event.new` plus `event.with_metadata(metadata.empty())` when the
child should start with a fresh attribute set.

`automata/event/metadata` exposes both `with_*` setters
(`with_correlation_id` etc.) and matching getters
(`correlation_id`, `causation_id`, `trace_id`, `attributes`,
`attribute(_, key)`, `has_attribute(_, key)`) so callers can read and
write metadata symmetrically without reaching into the `Metadata`
record's public fields directly.

## Filesystem events

`automata/fsevent` reproduces fsnotify-style operations as a pure
function over two `Snapshot` values. The library does not touch the
filesystem; the caller produces snapshots from a real walk, mocks,
or a log replay.

```gleam
import automata/fsevent
import gleam/option.{Some}

pub fn detect_change() {
  let assert Ok(p) = fsevent.normalize("/tmp/a.log")
  let assert Ok(prev) =
    fsevent.entry_file(
      path: p,
      size: 100,
      mtime: 1_700_000_000,
      mode: 0o644,
      content_hash: Some("abc"),
      file_id: Some("inode-1"),
    )
  let assert Ok(curr) =
    fsevent.entry_file(
      path: p,
      size: 200,
      mtime: 1_700_000_500,
      mode: 0o644,
      content_hash: Some("def"),
      file_id: Some("inode-1"),
    )
  let assert Ok(prev_snap) = fsevent.from_entries([prev])
  let assert Ok(curr_snap) = fsevent.from_entries([curr])

  fsevent.diff(prev: prev_snap, curr: curr_snap, watch: fsevent.watch())
}
```

When both snapshots carry the same `file_id` at different paths, a
move is reported as a single `Rename` event with `renamed_from`
attached. Without `file_id`, the move falls back to `Remove` plus
`Create`. Op masks (`fsevent.with_ops`, `fsevent.unwatch_op`) drop
unwanted ops before they reach the result list.

## Retry

```gleam
import automata/retry
import automata/retry/ast as retry_ast

pub fn http_backoff() {
  let assert Ok(initial) = retry_ast.from_milliseconds(milliseconds: 100)
  let assert Ok(cap) = retry_ast.from_seconds(seconds: 30)
  let assert Ok(base) =
    retry.capped_exponential(
      initial: initial,
      multiplier: 2,
      cap: cap,
      max_attempts: 6,
    )
  retry.with_jitter(policy: base, jitter: retry_ast.FullJitter)
}

pub fn drive(policy) {
  let ctx0 = retry.start(policy: policy, seed: 12_345)

  case retry.decide(ctx: ctx0, failure: retry_ast.Transient) {
    retry.Retry(delay: delay, next: _next) -> delay
    retry.GiveUp(reason: _reason) -> retry_ast.unsafe_milliseconds(value: 0)
  }
}
```

`max_attempts: N` means N total attempts (one initial try plus
`N - 1` retries). The retry module never sleeps; the caller drives
the loop and sums `retry.cumulative_delay/1` to apply a wall-clock
deadline. The bundled PRNG runs in pure Gleam, so the same
`(policy, seed, failure-sequence)` triple produces the same
`Decision` list on the BEAM and the JavaScript target.

`multiplier` must be `>= 2` for `exponential` and `capped_exponential`
(smaller values would not grow). For a constant delay with retries,
reach for `retry.fixed` instead — the policy types are otherwise
interchangeable through `retry.with_jitter` / `retry.start`.

The available jitter strategies live in `automata/retry/ast`:

| Constructor              | Spread                            |
| ------------------------ | --------------------------------- |
| `retry_ast.NoJitter`     | none — use the base delay as-is   |
| `retry_ast.FullJitter`   | uniform on `[0, base]` (AWS "full jitter") |
| `retry_ast.EqualJitter`  | uniform on `[base / 2, base]` (AWS "equal jitter") |

`NoJitter` is the default for every `retry.fixed` / `retry.exponential` /
`retry.capped_exponential` policy; reach for `retry.with_jitter` only
when you want one of the spread strategies.

## Validated date-time

`automata/schedule/ast` exposes `try_datetime/6` and
`try_valid_datetime/6`, which return `Result` when components fall
outside the Gregorian range. The opaque `ValidDateTime` then flows
through cron, RRULE, schedule, and event APIs without further
revalidation.

## Documentation

Full API reference: <https://hexdocs.pm/automata>.

Development setup, code style, and the contribution flow are
documented in [CONTRIBUTING.md](CONTRIBUTING.md). Released changes
are tracked in [CHANGELOG.md](CHANGELOG.md).

## License

MIT
