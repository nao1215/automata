import automata/cron/evaluator as cron_evaluator
import automata/cron/iterator as cron_iterator
import automata/cron/normalize as cron_normalize
import automata/cron/validator as cron_validator
import automata/internal/calendar
import automata/rrule/evaluator as rule_evaluator
import automata/rrule/iterator as rule_iterator
import automata/rrule/normalize as rule_normalize
import automata/rrule/validator as rule_validator
import automata/schedule/ast.{
  type Boundary, type DateTime, type ValidDateTime, Exclusive, Inclusive,
} as schedule_ast
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/result

/// Errors raised at the `schedule` boundary.
///
/// Carries enough context that LLMs and operators can understand
/// *what* failed and *what value caused it* without parsing strings.
pub type ScheduleError {
  EveryIntervalMustBePositive(actual: Int)
  InvalidRRuleAnchor(at: DateTime)
}

/// A unified schedule.
///
/// `opaque` so the only way to obtain a value is through `from_*`
/// smart constructors; this prevents callers from forging "validated"
/// schedules and lets us add new variants (timezones, solar times,
/// 7-field cron) without breaking existing code.
pub opaque type Schedule {
  CronSchedule(plan: cron_normalize.CronPlan)
  RRuleSchedule(plan: rule_normalize.RRulePlan)
  EverySchedule(plan: EveryPlan)
  OnceSchedule(at: DateTime)
}

type EveryPlan {
  EveryPlan(anchor: DateTime, interval_seconds: Int)
}

/// Iterator over future occurrences of a `Schedule`.
///
/// `opaque` because the cursor (and any per-variant counter such as
/// the RRULE `yielded` count) must stay synchronised with the embedded
/// plan. An externally-constructed iterator could break COUNT
/// enforcement or skip occurrences.
pub opaque type OccurrenceIterator {
  CronOccurrences(cursor: cron_iterator.CronIterator)
  RRuleOccurrences(cursor: rule_iterator.RRuleIterator)
  EveryOccurrences(plan: EveryPlan, cursor: DateTime)
  OnceOccurrences(at: DateTime, eligible: Bool)
}

/// Result of stepping an `OccurrenceIterator`.
///
/// `Yield(at, next)` carries the validated occurrence and the next
/// iterator state. `Done` signals the schedule has been exhausted
/// (RRULE COUNT reached, RRULE UNTIL exceeded, Once consumed, or a
/// pathological cron iteration hit its safety guard).
pub type IterStep {
  Yield(at: ValidDateTime, next: OccurrenceIterator)
  Done
}

/// Build a `Schedule` from a validated cron expression.
///
/// Cron schedules are infinite; iterators never return `Done` on
/// well-formed input. The return type is `Result` so that this
/// constructor shares one shape with `from_rrule`, `from_every`, and
/// `from_once`, letting generic helpers treat the four uniformly. The
/// current implementation cannot fail (a `ValidCron` cannot produce a
/// normalisation error), so callers can `let assert Ok(_) = ...` with
/// confidence.
pub fn from_cron(
  spec spec: cron_validator.ValidCron,
) -> Result(Schedule, ScheduleError) {
  Ok(CronSchedule(cron_normalize.normalize(spec)))
}

/// Build a `Schedule` from a validated RRULE plus an anchor.
///
/// The anchor seeds defaults for unspecified `BYHOUR` / `BYMINUTE` /
/// `BYDAY` / `BYMONTH` / `BYMONTHDAY` and contributes the second
/// component for every yielded occurrence.
pub fn from_rrule(
  spec spec: rule_validator.ValidRRule,
  anchor anchor: ValidDateTime,
) -> Result(Schedule, ScheduleError) {
  case
    rule_normalize.normalize(
      spec,
      anchor: schedule_ast.valid_datetime_value(anchor),
    )
  {
    Ok(plan) -> Ok(RRuleSchedule(plan))
    Error(rule_normalize.InvalidAnchor(at)) -> Error(InvalidRRuleAnchor(at:))
  }
}

/// Build an interval `Schedule` that fires `interval_seconds` apart
/// starting at `anchor` (inclusive).
///
/// Returns `EveryIntervalMustBePositive` when the interval is zero or
/// negative.
pub fn from_every(
  interval_seconds interval_seconds: Int,
  anchor anchor: ValidDateTime,
) -> Result(Schedule, ScheduleError) {
  case interval_seconds <= 0 {
    True -> Error(EveryIntervalMustBePositive(actual: interval_seconds))
    False ->
      Ok(
        EverySchedule(EveryPlan(
          anchor: schedule_ast.valid_datetime_value(anchor),
          interval_seconds: interval_seconds,
        )),
      )
  }
}

/// Build a one-shot `Schedule` that fires exactly once at `at`.
///
/// The return type is `Result` so that this constructor shares one
/// shape with `from_rrule`, `from_every`, and `from_cron`. The current
/// implementation cannot fail (the `at` argument is already a
/// `ValidDateTime`), so callers can `let assert Ok(_) = ...` with
/// confidence.
pub fn from_once(at at: ValidDateTime) -> Result(Schedule, ScheduleError) {
  Ok(OnceSchedule(at: schedule_ast.valid_datetime_value(at)))
}

/// Return `True` when `at` is an occurrence of `schedule`.
///
/// Pure: same inputs always produce the same output.
pub fn matches(schedule schedule: Schedule, at at: ValidDateTime) -> Bool {
  let raw = schedule_ast.valid_datetime_value(at)
  case schedule {
    CronSchedule(plan) -> cron_evaluator.matches(plan, at: raw)
    RRuleSchedule(plan) -> rule_evaluator.matches(plan, at: raw)
    EverySchedule(plan) -> every_matches(plan, raw)
    OnceSchedule(at: when) -> calendar.equals(when, raw)
  }
}

/// Build an iterator over occurrences strictly satisfying `boundary`.
pub fn iterator_after(
  schedule schedule: Schedule,
  boundary boundary: Boundary,
) -> OccurrenceIterator {
  case schedule {
    CronSchedule(plan) ->
      CronOccurrences(cron_iterator.after(plan, boundary: boundary))
    RRuleSchedule(plan) ->
      RRuleOccurrences(rule_iterator.after(plan, boundary: boundary))
    EverySchedule(plan) ->
      EveryOccurrences(plan: plan, cursor: every_start_cursor(plan, boundary))
    OnceSchedule(at: when) ->
      OnceOccurrences(at: when, eligible: once_eligible(when, boundary))
  }
}

/// Advance an iterator by one occurrence.
pub fn step(iterator iterator: OccurrenceIterator) -> IterStep {
  case iterator {
    CronOccurrences(cursor) ->
      case cron_iterator.step(cursor) {
        cron_iterator.Yield(at:, next:) ->
          Yield(at:, next: CronOccurrences(next))
        cron_iterator.Done -> Done
      }
    RRuleOccurrences(cursor) ->
      case rule_iterator.step(cursor) {
        rule_iterator.Yield(at:, next:) ->
          Yield(at:, next: RRuleOccurrences(next))
        rule_iterator.Done -> Done
      }
    EveryOccurrences(plan:, cursor:) ->
      Yield(
        at: schedule_ast.unsafe_assume_valid(cursor),
        next: EveryOccurrences(
          plan:,
          cursor: calendar.add_seconds(cursor, plan.interval_seconds),
        ),
      )
    OnceOccurrences(at:, eligible: True) ->
      Yield(
        at: schedule_ast.unsafe_assume_valid(at),
        next: OnceOccurrences(at:, eligible: False),
      )
    OnceOccurrences(at: _, eligible: False) -> Done
  }
}

/// Return the next occurrence strictly after `after`, if any.
///
/// Equivalent to stepping `iterator_after(schedule, Exclusive(after))`
/// once.
pub fn next_after(
  schedule schedule: Schedule,
  after after: ValidDateTime,
) -> Option(ValidDateTime) {
  case
    step(iterator: iterator_after(
      schedule: schedule,
      boundary: Exclusive(after),
    ))
  {
    Yield(at:, next: _) -> Some(at)
    Done -> None
  }
}

fn every_matches(plan: EveryPlan, at: DateTime) -> Bool {
  case calendar.less_than(at, plan.anchor) {
    True -> False
    False -> {
      let delta = calendar.seconds_between(plan.anchor, at)
      modulo(delta, plan.interval_seconds) == 0
    }
  }
}

fn every_start_cursor(plan: EveryPlan, boundary: Boundary) -> DateTime {
  case boundary {
    Inclusive(valid) -> {
      let target = schedule_ast.valid_datetime_value(valid)
      case calendar.less_or_equal(target, plan.anchor) {
        True -> plan.anchor
        False -> every_align_cursor(plan, target, False)
      }
    }
    Exclusive(valid) -> {
      let target = schedule_ast.valid_datetime_value(valid)
      case calendar.less_than(target, plan.anchor) {
        True -> plan.anchor
        False -> every_align_cursor(plan, target, True)
      }
    }
  }
}

fn every_align_cursor(
  plan: EveryPlan,
  target: DateTime,
  exclusive: Bool,
) -> DateTime {
  let delta = calendar.seconds_between(plan.anchor, target)
  let interval = plan.interval_seconds
  let remainder = modulo(delta, interval)
  let advance = case exclusive, remainder {
    True, _ -> delta - remainder + interval
    False, 0 -> delta
    False, _ -> delta - remainder + interval
  }
  calendar.add_seconds(plan.anchor, advance)
}

fn once_eligible(at: DateTime, boundary: Boundary) -> Bool {
  case boundary {
    Inclusive(valid) ->
      calendar.less_or_equal(schedule_ast.valid_datetime_value(valid), at)
    Exclusive(valid) ->
      calendar.less_than(schedule_ast.valid_datetime_value(valid), at)
  }
}

fn modulo(dividend: Int, divisor: Int) -> Int {
  int.modulo(dividend, by: divisor) |> result.unwrap(0)
}
