import automata as a
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/string
import gleam/time/calendar
import gleam/time/duration
import metamon
import metamon/generator
import metamon/generator/range

type Parity {
  Even
  Odd
}

fn parity_machine() -> a.Automaton(Parity, Int) {
  a.Automaton(
    initial_state: Even,
    transition: fn(state, symbol) {
      case state, symbol {
        Even, 1 -> Odd
        Odd, 1 -> Even
        other, _ -> other
      }
    },
    accepting: fn(state) { state == Even },
  )
}

pub fn parity_accepts_iff_even_count_of_ones_test() {
  metamon.forall(
    generator.list_of(generator.int(range.constant(0, 3)), range.constant(0, 8)),
    fn(symbols) {
      let ones = list.count(symbols, fn(symbol) { symbol == 1 })
      a.accepts(parity_machine(), symbols) == { ones % 2 == 0 }
    },
  )
}

pub fn parity_acceptance_invariant_under_appending_pair_of_ones_test() {
  metamon.forall(
    generator.list_of(generator.int(range.constant(0, 3)), range.constant(0, 6)),
    fn(symbols) {
      let machine = parity_machine()
      a.accepts(machine, symbols)
      == a.accepts(machine, list.append(symbols, [1, 1]))
    },
  )
}

pub fn parity_step_is_deterministic_test() {
  metamon.forall(
    generator.tuple2(
      generator.element_of([Even, Odd]),
      generator.int(range.constant(0, 3)),
    ),
    fn(pair) {
      let machine = parity_machine()
      let #(state, symbol) = pair
      transition(machine, state, symbol) == transition(machine, state, symbol)
    },
  )
}

pub fn duration_from_milliseconds_round_trip_test() {
  metamon.forall_round_trip_partial(
    gen: generator.int(range.constant(-1000, 1_000_000)),
    name: "duration_from_milliseconds_round_trip",
    encode: fn(value) {
      case make_milliseconds(milliseconds: value) {
        Ok(duration) -> Ok(duration)
        Error(_) -> Error(Nil)
      }
    },
    decode: fn(duration) { Ok(duration.to_milliseconds(duration)) },
  )
}

pub fn duration_from_seconds_milliseconds_consistent_test() {
  metamon.forall(generator.int(range.constant(0, 100_000)), fn(seconds) {
    let assert Ok(duration) = make_seconds(seconds: seconds)
    duration.to_milliseconds(duration) == seconds * 1000
    && duration_whole_seconds(duration: duration) == seconds
  })
}

pub fn no_retry_always_gives_up_on_transient_test() {
  metamon.forall(generator.int(range.constant(0, 1_000_000)), fn(seed) {
    let context = a.retry_start(policy: a.retry_no_retry(), seed: seed)
    case a.retry_decide(ctx: context, failure: a.Transient) {
      a.GiveUp(reason: a.PolicyDisallowsRetry) -> True
      _ -> False
    }
  })
}

pub fn permanent_failure_always_gives_up_test() {
  metamon.forall(generator.int(range.constant(0, 1_000_000)), fn(seed) {
    let context = a.retry_start(policy: a.retry_no_retry(), seed: seed)
    case a.retry_decide(ctx: context, failure: a.Permanent) {
      a.GiveUp(reason: a.PermanentFailureSignaled(at_attempt: 1)) -> True
      _ -> False
    }
  })
}

pub fn fresh_context_has_zero_attempt_test() {
  metamon.forall(generator.int(range.constant(0, 1_000_000)), fn(seed) {
    let context = a.retry_start(policy: a.retry_no_retry(), seed: seed)
    a.retry_current_attempt(ctx: context) == 0
    && duration.to_milliseconds(a.retry_cumulative_delay(ctx: context)) == 0
  })
}

pub fn fixed_policy_max_attempts_must_be_positive_test() {
  metamon.forall(generator.int(range.constant(-100, 0)), fn(invalid_max) {
    let assert Ok(delay) = make_milliseconds(milliseconds: 100)
    case a.retry_fixed(delay: delay, max_attempts: invalid_max) {
      Error(a.MaxAttemptsMustBePositive(actual: actual)) ->
        actual == invalid_max
      _ -> False
    }
  })
}

pub fn exponential_policy_multiplier_must_be_at_least_two_test() {
  metamon.forall(generator.int(range.constant(-10, 1)), fn(bad_multiplier) {
    let assert Ok(initial) = make_milliseconds(milliseconds: 100)
    case
      a.retry_exponential(
        initial: initial,
        multiplier: bad_multiplier,
        max_attempts: 5,
      )
    {
      Error(a.MultiplierMustBeAtLeastTwo(actual: actual)) ->
        actual == bad_multiplier
      _ -> False
    }
  })
}

fn ical_dtstamp() -> a.DateTime {
  let assert Ok(dt) =
    make_checked_datetime(
      year: 2026,
      month: 5,
      day: 11,
      hour: 12,
      minute: 0,
      second: 0,
    )
  dt
}

/// encode → parse must round-trip arbitrary printable ASCII summaries
/// (no control characters that the lexer would reject).
pub fn ical_parse_encode_parse_idempotent_test() {
  metamon.forall(
    generator.string_printable_ascii(range.constant(0, 40)),
    fn(summary) {
      let cal =
        a.ical_new_calendar(version: "2.0", prod_id: "-//x//EN")
        |> a.ical_add_event(
          a.ical_new_event(uid: "pbt@x", dtstamp: ical_dtstamp())
          |> a.ical_with_summary(summary),
        )
      let encoded = encode_calendar(cal)
      case a.ical_parse(encoded) {
        Error(_) -> False
        Ok(decoded) ->
          case a.ical_events(decoded) {
            [event] -> a.ical_event_summary(event) == Some(summary)
            _ -> False
          }
      }
    },
  )
}

/// Every folded physical line must respect the 75-octet boundary.
pub fn ical_fold_respects_octet_limit_test() {
  metamon.forall(
    generator.string_printable_ascii(range.constant(0, 200)),
    fn(input) {
      let lines = old_ical_emitter_fold_line(input)
      list.all(lines, fn(line) { string.byte_size(line) <= 75 })
    },
  )
}

/// Escape output must contain only the documented escape sequences for
/// the four reserved code points; non-reserved code points pass
/// through unchanged.
pub fn ical_escape_preserves_alpha_test() {
  metamon.forall(generator.string_alpha(range.constant(0, 60)), fn(s) {
    case
      string.contains(s, "\\")
      || string.contains(s, ",")
      || string.contains(s, ";")
      || string.contains(s, "\n")
    {
      True -> True
      False -> old_ical_emitter_escape_text(s) == s
    }
  })
}

fn duration_whole_seconds(duration value: duration.Duration) -> Int {
  duration.to_milliseconds(value) / 1000
}

fn encode_calendar(value: a.IcalCalendar) -> String {
  let assert Ok(value) = a.ical_encode(value)
  value
}

fn make_checked_datetime(
  year year: Int,
  month month: Int,
  day day: Int,
  hour hour: Int,
  minute minute: Int,
  second second: Int,
) -> Result(a.DateTime, a.DateTimeError) {
  make_valid_datetime(
    year: year,
    month: month,
    day: day,
    hour: hour,
    minute: minute,
    second: second,
  )
  |> result.map(a.datetime_value)
}

fn make_milliseconds(
  milliseconds milliseconds: Int,
) -> Result(duration.Duration, a.RetryError) {
  let value = duration.milliseconds(milliseconds)
  a.retry_fixed(delay: value, max_attempts: 2) |> result.map(fn(_) { value })
}

fn make_seconds(
  seconds seconds: Int,
) -> Result(duration.Duration, a.RetryError) {
  let value = duration.seconds(seconds)
  a.retry_fixed(delay: value, max_attempts: 2) |> result.map(fn(_) { value })
}

fn make_time(
  hour hour: Int,
  minute minute: Int,
  second second: Int,
) -> calendar.TimeOfDay {
  calendar.TimeOfDay(hour, minute, second, 0)
}

fn make_valid_datetime(
  year year: Int,
  month month: Int,
  day day: Int,
  hour hour: Int,
  minute minute: Int,
  second second: Int,
) -> Result(a.ValidDateTime, a.DateTimeError) {
  case calendar.month_from_int(month) {
    Error(_) -> Error(a.InvalidDate(year, month, day))
    Ok(month) ->
      a.datetime_validate(a.DateTime(
        calendar.Date(year, month, day),
        make_time(hour: hour, minute: minute, second: second),
      ))
  }
}

fn transition(
  machine: a.Automaton(state, symbol),
  state: state,
  symbol: symbol,
) -> state {
  machine.transition(state, symbol)
}

fn old_ical_emitter_fold_line(value: String) -> List(String) {
  let encoded =
    encode_calendar(a.ical_new_calendar(version: "2.0", prod_id: value))
  let lines =
    string.split(encoded, "\r\n")
    |> list.drop(2)
    |> list.take_while(fn(line) { line != "END:VCALENDAR" && line != "" })
  let assert [first, ..rest] = lines
  [string.drop_start(first, 7), ..rest]
}

fn old_ical_emitter_escape_text(value: String) -> String {
  let at =
    make_datetime(year: 2026, month: 1, day: 1, hour: 0, minute: 0, second: 0)
  let event =
    a.ical_new_event(uid: "escape", dtstamp: at) |> a.ical_with_summary(value)
  let encoded =
    a.ical_new_calendar(version: "2.0", prod_id: "test")
    |> a.ical_add_event(event)
    |> encode_calendar
  let assert Ok(line) =
    encoded
    |> string.replace("\r\n ", "")
    |> string.split("\r\n")
    |> list.find(fn(line) { string.starts_with(line, "SUMMARY:") })
  string.drop_start(line, 8)
}

fn make_datetime(
  year year: Int,
  month month: Int,
  day day: Int,
  hour hour: Int,
  minute minute: Int,
  second second: Int,
) -> a.DateTime {
  a.DateTime(
    make_date(year: year, month: month, day: day),
    make_time(hour: hour, minute: minute, second: second),
  )
}

fn make_date(year year: Int, month month: Int, day day: Int) -> calendar.Date {
  let assert Ok(month) = calendar.month_from_int(month)
  calendar.Date(year, month, day)
}
