import automata as a
import gleam/time/calendar
import gleeunit/should

pub type Parts =
  #(Int, Int, Int, Int, Int, Int)

pub fn valid(year, month, day, hour, minute, second) -> a.ValidDateTime {
  let assert Ok(month) = calendar.month_from_int(month)
  let assert Ok(value) =
    a.datetime_validate(a.DateTime(
      calendar.Date(year, month, day),
      calendar.TimeOfDay(hour, minute, second, 0),
    ))
  value
}

pub fn parts(value: a.ValidDateTime) -> Parts {
  let value = a.datetime_value(value)
  #(
    value.date.year,
    calendar.month_to_int(value.date.month),
    value.date.day,
    value.time.hours,
    value.time.minutes,
    value.time.seconds,
  )
}

pub fn rule(input: String) -> a.RecurrenceRule {
  let assert Ok(raw) = a.rrule_parse_raw(input: input)
  let assert Ok(value) = a.rrule_validate(raw: raw)
  value
}

pub fn cron_spec(input: String) -> a.Cron {
  let assert Ok(raw) = a.cron_parse_raw(input: input)
  let assert Ok(value) = a.cron_validate(raw: raw)
  value
}

pub fn expect_rule(
  rule: a.RecurrenceRule,
  anchor: a.ValidDateTime,
  boundary: a.Boundary,
  expected: List(Parts),
  exhausted: Bool,
) {
  expect_schedule(
    a.schedule_from_rrule(rule, anchor:),
    boundary,
    expected,
    exhausted,
  )
}

pub fn expect_schedule(
  value: a.Schedule,
  boundary: a.Boundary,
  expected: List(Parts),
  exhausted: Bool,
) {
  let assert Ok(iterator) = a.schedule_iterator(value, boundary:)
  schedule_steps(iterator, expected, exhausted)
}

fn schedule_steps(
  iterator: a.OccurrenceIterator,
  expected: List(Parts),
  exhausted: Bool,
) {
  case expected {
    [] ->
      case exhausted {
        True -> a.schedule_step(iterator) |> should.equal(Ok(a.Done))
        False -> Nil
      }
    [first, ..rest] -> {
      let assert Ok(a.Yield(value, next)) = a.schedule_step(iterator)
      parts(value) |> should.equal(first)
      schedule_steps(next, rest, exhausted)
    }
  }
}
