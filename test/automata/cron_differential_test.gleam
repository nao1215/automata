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

import automata as a
import gleam/list
import gleam/order
import gleam/result
import gleam/time/calendar
import gleam/time/duration
import gleam/time/timestamp

import gleam/int
import gleam/option.{None, Some}
import gleam/string
import metamon
import metamon/generator.{type Generator}

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

fn start_generator() -> Generator(a.ValidDateTime) {
  generator.map6(
    generator.int(generator.range(from: 2023, to: 2028)),
    generator.int(generator.range(from: 1, to: 12)),
    generator.int(generator.range(from: 1, to: 31)),
    generator.int(generator.range(from: 0, to: 23)),
    generator.int(generator.range(from: 0, to: 59)),
    generator.element_of([0, 0, 30, 59]),
    fn(year, month, day, hour, minute, second) {
      let day = int.min(day, old_internal_gregorian_days_in_month(year, month))
      let assert Ok(value) =
        make_valid_datetime(year:, month:, day:, hour:, minute:, second:)
      value
    },
  )
}

fn valid(datetime: a.DateTime) -> a.ValidDateTime {
  let assert Ok(value) = a.datetime_validate(datetime)
  value
}

/// `validate` rejects expressions that can never fire (`31` in a
/// February-only month field); those are outside the relations.
fn with_valid(raw, check) -> Nil {
  case a.cron_validate(raw: raw) {
    Ok(spec) -> check(spec)
    Error(_) -> Nil
  }
}

/// The first whole minute strictly after `start`.
fn first_candidate(start: a.ValidDateTime) -> a.DateTime {
  let value = a.datetime_value(start)
  let floored =
    a.DateTime(
      date: value.date,
      time: calendar.TimeOfDay(..value.time, seconds: 0),
    )
  old_internal_calendar_add_minutes(floored, 1)
}

/// The first matching minute within `budget` minutes of `from`.
fn scan(spec, from: a.DateTime, budget: Int) -> option.Option(a.DateTime) {
  case budget <= 0 {
    True -> None
    False ->
      case matches_cron(spec: spec, at: valid(from)) {
        True -> Some(from)
        False ->
          scan(spec, old_internal_calendar_add_minutes(from, 1), budget - 1)
      }
  }
}

pub fn next_after_agrees_with_a_minute_by_minute_scan_test() -> Nil {
  metamon.forall(
    generator.tuple2(expression_generator(), start_generator()),
    fn(input) {
      let #(expression, start) = input
      let assert Ok(raw) = a.cron_parse_raw(input: expression)
      use spec <- with_valid(raw)
      let scanned = scan(spec, first_candidate(start), scan_minutes)
      let next = next_cron(spec: spec, after: start)
      case scanned {
        // The scan found a firing in the window: it must be the answer.
        Some(first) -> {
          assert option.map(next, a.datetime_value) == Some(first)
        }
        // No firing in the window: the answer is matched and later.
        None -> {
          let assert Some(next) = next
          assert matches_cron(spec: spec, at: next)
          assert old_internal_calendar_greater_than(
            a.datetime_value(next),
            old_internal_calendar_add_minutes(
              first_candidate(start),
              scan_minutes - 1,
            ),
          )
        }
      }
    },
  )
}

pub fn iterator_steps_follow_next_after_test() -> Nil {
  metamon.forall(
    generator.tuple2(expression_generator(), start_generator()),
    fn(input) {
      let #(expression, start) = input
      let assert Ok(raw) = a.cron_parse_raw(input: expression)
      use spec <- with_valid(raw)
      let iterator = iterate_cron(spec: spec, boundary: a.Exclusive(start))
      let assert a.Yield(at: first, next: rest) =
        step_schedule(iterator: iterator)
      let assert a.Yield(at: second, next: _) = step_schedule(iterator: rest)
      assert Some(first) == next_cron(spec: spec, after: start)
      assert Some(second) == next_cron(spec: spec, after: first)
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
      let assert Ok(raw) = a.cron_parse_raw(input: expression)
      use spec <- with_valid(raw)
      let value = a.datetime_value(start)
      let expected = case
        value.time.seconds == 0 && matches_cron(spec: spec, at: start)
      {
        True -> Some(start)
        False -> next_cron(spec: spec, after: start)
      }
      let first = case
        iterate_cron(spec: spec, boundary: a.Inclusive(start))
        |> step_schedule
      {
        a.Yield(at: at, next: _) -> Some(at)
        a.Done -> None
      }
      assert first == expected
    },
  )
}

fn iterate_cron(
  spec spec: a.Cron,
  boundary boundary: a.Boundary,
) -> a.OccurrenceIterator {
  iterate_schedule(schedule: a.schedule_from_cron(spec), boundary: boundary)
}

fn iterate_schedule(
  schedule schedule: a.Schedule,
  boundary boundary: a.Boundary,
) -> a.OccurrenceIterator {
  let assert Ok(value) = a.schedule_iterator(schedule, boundary: boundary)
  value
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

fn matches_cron(spec spec: a.Cron, at at: a.ValidDateTime) -> Bool {
  matches_schedule(schedule: a.schedule_from_cron(spec), at: at)
}

fn matches_schedule(
  schedule schedule: a.Schedule,
  at at: a.ValidDateTime,
) -> Bool {
  let assert Ok(value) = a.schedule_matches(schedule, at: at)
  value
}

fn next_cron(
  spec spec: a.Cron,
  after after: a.ValidDateTime,
) -> option.Option(a.ValidDateTime) {
  next_schedule(schedule: a.schedule_from_cron(spec), after: after)
}

fn next_schedule(
  schedule schedule: a.Schedule,
  after after: a.ValidDateTime,
) -> option.Option(a.ValidDateTime) {
  let assert Ok(value) = a.schedule_next(schedule, after: after)
  value
}

fn step_schedule(iterator iterator: a.OccurrenceIterator) -> a.IterStep {
  let assert Ok(value) = a.schedule_step(iterator)
  value
}

fn old_internal_gregorian_days_in_month(year: Int, month: Int) -> Int {
  let assert Ok(month) = calendar.month_from_int(month)
  [31, 30, 29, 28]
  |> list.find(fn(day) {
    calendar.is_valid_date(calendar.Date(year, month, day))
  })
  |> result.unwrap(28)
}

fn old_internal_calendar_greater_than(
  left: a.DateTime,
  right: a.DateTime,
) -> Bool {
  // Oracle uses the core library for the ordinary years sampled here.
  case calendar.naive_date_compare(left.date, right.date) {
    order.Gt -> True
    order.Lt -> False
    order.Eq ->
      { left.time.hours * 3600 + left.time.minutes * 60 + left.time.seconds }
      > {
        right.time.hours * 3600 + right.time.minutes * 60 + right.time.seconds
      }
  }
}

fn old_internal_calendar_add_minutes(
  value: a.DateTime,
  minutes: Int,
) -> a.DateTime {
  // Independent small-range reference uses core calendar timestamps.
  let stamp =
    timestamp.from_calendar(value.date, value.time, duration.seconds(0))
  let moved = timestamp.add(stamp, duration.minutes(minutes))
  let #(date, time) = timestamp.to_calendar(moved, duration.seconds(0))
  a.DateTime(date, time)
}
