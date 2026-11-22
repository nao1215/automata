# automata

[![CI](https://github.com/nao1215/automata/actions/workflows/ci.yml/badge.svg)](https://github.com/nao1215/automata/actions/workflows/ci.yml)
[![Gitleaks](https://github.com/nao1215/automata/actions/workflows/gitleaks.yml/badge.svg)](https://github.com/nao1215/automata/actions/workflows/gitleaks.yml)
[![Trivy](https://github.com/nao1215/automata/actions/workflows/trivy.yml/badge.svg)](https://github.com/nao1215/automata/actions/workflows/trivy.yml)
[![OSV-Scanner](https://github.com/nao1215/automata/actions/workflows/osv-scan.yml/badge.svg)](https://github.com/nao1215/automata/actions/workflows/osv-scan.yml)
[![Hex](https://img.shields.io/hexpm/v/automata)](https://hex.pm/packages/automata)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/automata/)
[![Hex Downloads](https://img.shields.io/hexpm/dt/automata)](https://hex.pm/packages/automata)
[![License](https://img.shields.io/github/license/nao1215/automata)](./LICENSE)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/nao1215/automata/badge)](https://scorecard.dev/viewer/?uri=github.com/nao1215/automata)

Cron, RRULE, retries, filesystem events, and finite automata for
Gleam. Everything is pure, so each module gives the same answers on the
BEAM and on the JavaScript target.

## Modules

- `automata`: deterministic finite automaton.
- `automata/cron`: UNIX 5-field cron, with parse, validate, normalise, match, iterate, and next as separate steps.
- `automata/rrule`: RFC 5545 RRULE subset (FREQ, INTERVAL, COUNT, UNTIL, BYDAY, BYMONTH, BYMONTHDAY, BYHOUR, BYMINUTE) anchored on a `ValidDateTime`.
- `automata/ical`: RFC 5545 iCalendar parser and emitter for the `VCALENDAR` envelope, with line folding, parameter quoting, and TEXT escaping.
- `automata/schedule`: one matcher, iterator, and next-after API for cron, RRULE, fixed-interval, and one-shot schedules.
- `automata/event`: typed `Event(body)` values with source kinds, correlation, causation, and trace metadata, plus filters.
- `automata/fsevent`: fsnotify-style Create, Write, Remove, Rename, and Chmod ops from two filesystem snapshots, with rename detection by file_id.
- `automata/retry`: deterministic retry policies (fixed, exponential, capped exponential) with optional jitter, decided one step at a time.

## Install

```sh
gleam add automata
```

## Automaton

An automaton is a current state, a transition function, and an
accepting predicate. Build one with `automata.new`, advance it with
`step` or `run`, and check input with `accepts`.

```gleam
import automata

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

  automata.run(dfa, [OpenIt, CloseIt, LockIt]) |> echo
  // -> Locked

  automata.accepts(dfa, [OpenIt]) |> echo
  // -> True
}
```

`Automaton(state, symbol)` is generic over both types, so states and
symbols can be your own types, `Int`, or `String`.

## Cron

```gleam
import automata/cron
import automata/schedule/ast as schedule_ast

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

  cron.next_after(spec, after: after) |> echo
}
```

Output:

```text
Some(ValidDateTime(DateTime(Date(2026, 5, 11), Time(9, 15, 0))))
```

To evaluate the same spec many times, normalise it once:

```gleam
let plan = cron.normalize(spec)
cron.matches_plan(plan: plan, at: now)
cron.next_after_plan(plan: plan, after: now)
```

The builder form needs no validator import:

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

Anchor seconds are kept. `BYSECOND`, `BYYEARDAY`, `BYWEEKNO`,
`BYSETPOS`, `WKST` other than `MO`, `DTSTART`, `RDATE`, and `EXDATE` are not supported.
For a spec and anchor you reuse, `rrule.normalize/2` returns an
`RRulePlan` for `rrule.matches_plan`, `iterator_after_plan`, and
`next_after_plan`.

## iCalendar

`automata/ical` parses and emits the `VCALENDAR` envelope that RRULEs
usually come in, with line folding, parameter quoting, and TEXT escaping
per RFC 5545 §3.1, §3.2, and §3.3.11.

```gleam
import automata/ical
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
  |> echo
  // -> ["Coffee"]
}
```

`event_rrule(event)` returns an `automata/rrule` `Option(RawRRule)`, so
there is no second parse:

```gleam
case ical.event_rrule(event) {
  option.Some(raw) -> rrule.validate(raw: raw)
  option.None -> Error(Nil)
}
```

Parsing the output of `ical.encode` gives back the same properties.
Output folds at 75 UTF-8 octets and uses CRLF line endings.

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
fixed-interval schedule and `schedule.from_once(at:)` fires once. All
four constructors return `Result(Schedule, ScheduleError)`; `from_cron`
and `from_once` cannot fail today, so `let assert Ok(_) = ...` is fine
for them.

## Events

```gleam
import automata/event/builtin/body
import automata/event/builtin/filter as builtin_filter
import automata/event/filter
import automata/fsevent/ast as fs_ast

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

`body.new/4` derives the `SourceKind` from the body: `Scheduled` gets
`ScheduleSource`, `FileSystem(_)` gets `FileSystemSource`, and
`Custom("vendor.kind", _)` gets `CustomSource("vendor.kind")`.
`Event.occurred_at` is a `ValidDateTime`, so dates such as 2026-02-30 are
rejected. `event.continue_from/5` creates a child event that inherits
`correlation_id`, `trace_id`, and all `attributes`, with `causation_id`
set to the parent's id. For a child with no attributes, use `event.new`
with `event.with_metadata(metadata.empty())`.

`automata/event/metadata` has `with_*` setters and matching getters
(`correlation_id`, `causation_id`, `trace_id`, `attributes`,
`attribute(_, key)`, `has_attribute(_, key)`).

## Filesystem events

`automata/fsevent` computes fsnotify-style operations from two
`Snapshot` values. It never touches the filesystem; you build the
snapshots from a directory walk, a mock, or a log replay.

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

The same `file_id` at a new path is reported as one `Rename` with
`renamed_from`. Without `file_id`, a move is a `Remove` and a `Create` (plus `Write` if the file is non-empty).
`fsevent.with_ops` and `fsevent.unwatch_op` filter which ops are
reported.

## Retry

```gleam
import automata/retry

pub fn http_backoff() {
  let assert Ok(initial) = retry.from_milliseconds(milliseconds: 100)
  let assert Ok(cap) = retry.from_seconds(seconds: 30)
  let assert Ok(base) =
    retry.capped_exponential(
      initial: initial,
      multiplier: 2,
      cap: cap,
      max_attempts: 6,
    )
  retry.with_jitter(policy: base, jitter: retry.FullJitter)
}

pub fn drive(policy) {
  let assert Ok(zero) = retry.from_milliseconds(milliseconds: 0)
  let ctx0 = retry.start(policy: policy, seed: 12_345)

  case retry.decide(ctx: ctx0, failure: retry.Transient) {
    retry.Retry(delay: delay, next: _next) -> delay
    retry.GiveUp(reason: _reason) -> zero
  }
}
```

`max_attempts: N` means N attempts in total, so `N - 1` retries. The
module never sleeps: you run the loop and can check
`retry.cumulative_delay/1` against a deadline. The PRNG is pure Gleam, so
the same policy, seed, and failures give the same decisions on BEAM and
JavaScript.

`exponential` and `capped_exponential` need `multiplier >= 2`. For a
constant delay, use `retry.fixed`.

Jitter strategies:

| Constructor          | Spread                                             |
| -------------------- | -------------------------------------------------- |
| `retry.NoJitter`     | none, the base delay as is                         |
| `retry.FullJitter`   | uniform on `[0, base]` (AWS "full jitter")         |
| `retry.EqualJitter`  | uniform on `[base / 2, base]` (AWS "equal jitter") |

`NoJitter` is the default; `retry.with_jitter` sets another.

## Validated date-time

`automata/schedule/ast.try_datetime/6` and `try_valid_datetime/6`
return an error for components outside the Gregorian range. The
resulting `ValidDateTime` is accepted by the cron, RRULE, schedule, and
event APIs without another check.

## Documentation

Full API reference: <https://hexdocs.pm/automata>.

Development setup and the contribution flow: [CONTRIBUTING.md](CONTRIBUTING.md).
Release notes: [CHANGELOG.md](CHANGELOG.md).

## Testing

| Technique | Bug class caught here |
|---|---|
| Examples and unit tests | [Wrong parses, occurrences, diffs and retry decisions](doc/testing.md#examples-and-unit-tests) |
| Generated properties | [Automata, durations and iCalendar text that do not round-trip](doc/testing.md#generated-properties) |
| Differential testing | [Cron searches that skip or invent a firing](doc/testing.md#differential-testing) |
| Mutation testing | [Assertions that miss a changed operator or branch](doc/testing.md#mutation-testing) |

## Verifying releases

Each GitHub Release attaches the Hex package tarball (`automata-<version>.tar`),
`checksums.txt`, a cosign signature bundle (`checksums.txt.sigstore.json`) and
build provenance (`automata-<version>.intoto.jsonl`). Download the assets, then:

```sh
gh attestation verify automata-<version>.tar --repo nao1215/automata

cosign verify-blob \
  --bundle checksums.txt.sigstore.json \
  --certificate-identity-regexp '^https://github\.com/nao1215/automata/\.github/workflows/release\.yml@refs/tags/v' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  checksums.txt
sha256sum --check checksums.txt
```

## License

MIT
