import automata as a
import gleam/time/calendar
import gleeunit/should

pub type Parts =
  #(Int, Int, Int, Int, Int, Int)

pub fn raw(year, month, day, hour, minute, second, nanos) -> a.DateTime {
  let assert Ok(month) = calendar.month_from_int(month)
  a.DateTime(
    calendar.Date(year, month, day),
    calendar.TimeOfDay(hour, minute, second, nanos),
  )
}

pub fn valid(year, month, day, hour, minute, second) -> a.ValidDateTime {
  let assert Ok(value) =
    raw(year, month, day, hour, minute, second, 0) |> a.datetime_validate
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

pub fn schedule(rule: String, anchor: a.ValidDateTime) -> a.Schedule {
  let assert Ok(raw) = a.rrule_parse_raw(input: rule)
  let assert Ok(rule) = a.rrule_validate(raw: raw)
  a.schedule_from_rrule(rule, anchor: anchor)
}

pub fn expect(
  schedule,
  boundary,
  expected: List(Parts),
  exhausted: Bool,
) -> Nil {
  let assert Ok(iterator) = a.schedule_iterator(schedule, boundary: boundary)
  expect_steps(iterator, expected, exhausted)
}

fn expect_steps(iterator, expected, exhausted) -> Nil {
  case expected {
    [] -> {
      case exhausted {
        True -> a.schedule_step(iterator) |> should.equal(Ok(a.Done))
        False -> Nil
      }
    }
    [first, ..rest] -> {
      let assert Ok(a.Yield(at, next)) = a.schedule_step(iterator)
      parts(at) |> should.equal(first)
      expect_steps(next, rest, exhausted)
    }
  }
}
