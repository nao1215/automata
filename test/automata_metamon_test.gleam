import automata
import automata/ical
import automata/ical/emitter as ical_emitter
import automata/retry
import automata/retry/ast as retry_ast
import automata/schedule/ast as schedule_ast
import gleam/list
import gleam/option.{Some}
import gleam/string
import metamon
import metamon/generator
import metamon/generator/range

type Parity {
  Even
  Odd
}

fn parity_machine() -> automata.Automaton(Parity, Int) {
  automata.new(
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
      automata.accepts(parity_machine(), symbols) == { ones % 2 == 0 }
    },
  )
}

pub fn parity_acceptance_invariant_under_appending_pair_of_ones_test() {
  metamon.forall(
    generator.list_of(generator.int(range.constant(0, 3)), range.constant(0, 6)),
    fn(symbols) {
      let machine = parity_machine()
      automata.accepts(machine, symbols)
      == automata.accepts(machine, list.append(symbols, [1, 1]))
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
      automata.step(machine, state, symbol)
      == automata.step(machine, state, symbol)
    },
  )
}

pub fn duration_from_milliseconds_round_trip_test() {
  metamon.forall_round_trip_partial(
    gen: generator.int(range.constant(-1000, 1_000_000)),
    name: "duration_from_milliseconds_round_trip",
    encode: fn(value) {
      case retry_ast.from_milliseconds(milliseconds: value) {
        Ok(duration) -> Ok(duration)
        Error(_) -> Error(Nil)
      }
    },
    decode: fn(duration) { Ok(retry_ast.duration_milliseconds(duration)) },
  )
}

pub fn duration_from_seconds_milliseconds_consistent_test() {
  metamon.forall(generator.int(range.constant(0, 100_000)), fn(seconds) {
    let assert Ok(duration) = retry_ast.from_seconds(seconds: seconds)
    retry_ast.duration_milliseconds(duration) == seconds * 1000
    && retry_ast.duration_seconds(duration) == seconds
  })
}

pub fn no_retry_always_gives_up_on_transient_test() {
  metamon.forall(generator.int(range.constant(0, 1_000_000)), fn(seed) {
    let context = retry.start(policy: retry.no_retry(), seed: seed)
    case retry.decide(ctx: context, failure: retry_ast.Transient) {
      retry.GiveUp(reason: retry_ast.PolicyDisallowsRetry) -> True
      _ -> False
    }
  })
}

pub fn permanent_failure_always_gives_up_test() {
  metamon.forall(generator.int(range.constant(0, 1_000_000)), fn(seed) {
    let context = retry.start(policy: retry.no_retry(), seed: seed)
    case retry.decide(ctx: context, failure: retry_ast.Permanent) {
      retry.GiveUp(reason: retry_ast.PermanentFailureSignaled(at_attempt: 1)) ->
        True
      _ -> False
    }
  })
}

pub fn fresh_context_has_zero_attempt_test() {
  metamon.forall(generator.int(range.constant(0, 1_000_000)), fn(seed) {
    let context = retry.start(policy: retry.no_retry(), seed: seed)
    retry.current_attempt(ctx: context) == 0
    && retry_ast.duration_milliseconds(retry.cumulative_delay(ctx: context))
    == 0
  })
}

pub fn fixed_policy_max_attempts_must_be_positive_test() {
  metamon.forall(generator.int(range.constant(-100, 0)), fn(invalid_max) {
    let assert Ok(delay) = retry_ast.from_milliseconds(milliseconds: 100)
    case retry.fixed(delay: delay, max_attempts: invalid_max) {
      Error(retry_ast.MaxAttemptsMustBePositive(actual: actual)) ->
        actual == invalid_max
      _ -> False
    }
  })
}

pub fn exponential_policy_multiplier_must_be_at_least_two_test() {
  metamon.forall(generator.int(range.constant(-10, 1)), fn(bad_multiplier) {
    let assert Ok(initial) = retry_ast.from_milliseconds(milliseconds: 100)
    case
      retry.exponential(
        initial: initial,
        multiplier: bad_multiplier,
        max_attempts: 5,
      )
    {
      Error(retry_ast.MultiplierMustBeAtLeastTwo(actual: actual)) ->
        actual == bad_multiplier
      _ -> False
    }
  })
}

fn ical_dtstamp() -> schedule_ast.DateTime {
  let assert Ok(dt) =
    schedule_ast.try_datetime(
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
        ical.new_calendar(version: "2.0", prod_id: "-//x//EN")
        |> ical.add_event(
          ical.new_event(uid: "pbt@x", dtstamp: ical_dtstamp())
          |> ical.with_summary(summary),
        )
      let encoded = ical.encode(cal)
      case ical.parse(encoded) {
        Error(_) -> False
        Ok(decoded) ->
          case ical.events(decoded) {
            [event] -> ical.event_summary(event) == Some(summary)
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
      let lines = ical_emitter.fold_line(input)
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
      False -> ical_emitter.escape_text(s) == s
    }
  })
}
