//// Differential tests for cron: `next_after` and `iterator_after` walk
//// the normalised plan field by field (skipping whole hours, days and
//// months), while `matches` checks one instant against every field.
//// For random expressions and start times the fast search must agree
//// with a minute-by-minute scan that asks `matches`:
////
//// - the instant `next_after` returns is matched and lies after the
////   start;
//// - no minute between the start and that instant is matched (checked
////   over the first three days, which keeps each case fast);
//// - the first element of `iterator_after(Exclusive(start))` is the same
////   instant.
////
//// The field choices include the day-of-month / day-of-week pairs whose
//// POSIX "either field" rule is the classic source of cron bugs, month
//// ends (29, 30, 31) and leap days.

import automata/cron
import automata/cron/iterator as cron_iterator
import automata/internal/calendar
import automata/internal/gregorian
import automata/schedule/ast as schedule_ast
import gleam/int
import gleam/option.{None, Some}
import gleam/string
import metamon
import metamon/generator.{type Generator}
import metamon/generator/range

const scan_minutes = 4320

fn expression_generator() -> Generator(String) {
  generator.map5(
    generator.element_of(["*", "0", "*/15", "5-10", "0,30", "59", "*/7"]),
    generator.element_of(["*", "0", "9-17", "*/6", "23", "1,13"]),
    generator.element_of(["*", "1", "15", "29", "30", "31", "1-7", "*/10"]),
    generator.element_of(["*", "1", "2", "2,8", "*/3", "12", "4-6"]),
    generator.element_of(["*", "0", "MON-FRI", "6", "1,3", "SUN", "7"]),
    fn(minute, hour, dom, month, dow) {
      string.join([minute, hour, dom, month, dow], " ")
    },
  )
}

fn start_generator() -> Generator(schedule_ast.ValidDateTime) {
  generator.map6(
    generator.int(range.constant(2023, 2028)),
    generator.int(range.constant(1, 12)),
    generator.int(range.constant(1, 31)),
    generator.int(range.constant(0, 23)),
    generator.int(range.constant(0, 59)),
    generator.element_of([0, 0, 30, 59]),
    fn(year, month, day, hour, minute, second) {
      let day = int.min(day, gregorian.days_in_month(year, month))
      let assert Ok(value) =
        schedule_ast.try_valid_datetime(
          year:,
          month:,
          day:,
          hour:,
          minute:,
          second:,
        )
      value
    },
  )
}

fn valid(datetime: schedule_ast.DateTime) -> schedule_ast.ValidDateTime {
  let schedule_ast.DateTime(
    date: schedule_ast.Date(year:, month:, day:),
    time: schedule_ast.Time(hour:, minute:, second:),
  ) = datetime
  let assert Ok(value) =
    schedule_ast.try_valid_datetime(
      year:,
      month:,
      day:,
      hour:,
      minute:,
      second:,
    )
  value
}

/// `validate` rejects expressions that can never fire (`31` in a
/// February-only month field); those are outside the relations.
fn with_valid(raw, check) -> Bool {
  case cron.validate(raw) {
    Ok(spec) -> check(spec)
    Error(_) -> True
  }
}

/// The first whole minute strictly after `start`.
fn first_candidate(start: schedule_ast.ValidDateTime) -> schedule_ast.DateTime {
  let value = schedule_ast.valid_datetime_value(start)
  let floored =
    schedule_ast.DateTime(
      date: value.date,
      time: schedule_ast.Time(..value.time, second: 0),
    )
  calendar.add_minutes(floored, 1)
}

/// The first matching minute within `budget` minutes of `from`.
fn scan(
  spec,
  from: schedule_ast.DateTime,
  budget: Int,
) -> option.Option(schedule_ast.DateTime) {
  case budget <= 0 {
    True -> None
    False ->
      case cron.matches(spec: spec, at: valid(from)) {
        True -> Some(from)
        False -> scan(spec, calendar.add_minutes(from, 1), budget - 1)
      }
  }
}

pub fn next_after_agrees_with_a_minute_by_minute_scan_test() -> Nil {
  metamon.forall(
    generator.tuple2(expression_generator(), start_generator()),
    fn(input) {
      let #(expression, start) = input
      let assert Ok(raw) = cron.parse(expression)
      use spec <- with_valid(raw)
      let scanned = scan(spec, first_candidate(start), scan_minutes)
      case cron.next_after(spec: spec, after: start), scanned {
        // The scan found a firing in the window: it must be the answer.
        Some(next), Some(first) ->
          schedule_ast.valid_datetime_value(next) == first
        // No firing in the window: the answer is matched and later.
        Some(next), None ->
          cron.matches(spec: spec, at: next)
          && calendar.greater_than(
            schedule_ast.valid_datetime_value(next),
            calendar.add_minutes(first_candidate(start), scan_minutes - 1),
          )
        None, _ -> False
      }
    },
  )
}

pub fn iterator_steps_follow_next_after_test() -> Nil {
  metamon.forall(
    generator.tuple2(expression_generator(), start_generator()),
    fn(input) {
      let #(expression, start) = input
      let assert Ok(raw) = cron.parse(expression)
      use spec <- with_valid(raw)
      let iterator =
        cron.iterator_after(spec: spec, boundary: schedule_ast.Exclusive(start))
      case cron_iterator.step(iterator) {
        cron_iterator.Yield(at: first, next: rest) ->
          case cron_iterator.step(rest) {
            cron_iterator.Yield(at: second, next: _) ->
              Some(first) == cron.next_after(spec: spec, after: start)
              && Some(second) == cron.next_after(spec: spec, after: first)
            cron_iterator.Done -> False
          }
        cron_iterator.Done -> False
      }
    },
  )
}

/// An inclusive boundary on a whole minute that matches yields that
/// minute; anything else behaves like the exclusive boundary.
pub fn inclusive_boundary_yields_a_matching_start_test() -> Nil {
  metamon.forall(
    generator.tuple2(expression_generator(), start_generator()),
    fn(input) {
      let #(expression, start) = input
      let assert Ok(raw) = cron.parse(expression)
      use spec <- with_valid(raw)
      let value = schedule_ast.valid_datetime_value(start)
      let expected = case
        value.time.second == 0 && cron.matches(spec: spec, at: start)
      {
        True -> Some(start)
        False -> cron.next_after(spec: spec, after: start)
      }
      let first = case
        cron.iterator_after(spec: spec, boundary: schedule_ast.Inclusive(start))
        |> cron_iterator.step
      {
        cron_iterator.Yield(at: at, next: _) -> Some(at)
        cron_iterator.Done -> None
      }
      first == expected
    },
  )
}
