import automata as a
import gleam/list
import gleam/option.{Some}
import gleeunit/should
import regression_support as support

pub fn typed_minute_ninety_is_rejected_test() {
  a.cron_new(
    a.CronOptions(..a.cron_options(), minute: a.CronValues([a.CronExact(90)])),
  )
  |> should.equal(Error(a.CronOutOfRange(a.CronMinute, 0, 59, 90)))
  let assert Ok(raw) = a.cron_parse_raw(input: "90 * * * *")
  a.cron_validate(raw: raw)
  |> should.equal(Error(a.CronOutOfRange(a.CronMinute, 0, 59, 90)))
}

pub fn typed_empty_month_selector_is_rejected_test() {
  a.cron_new(a.CronOptions(..a.cron_options(), month: a.CronValues([])))
  |> should.equal(Error(a.CronInvalidList(a.CronMonth, "")))
}

pub fn typed_zero_minute_step_is_rejected_test() {
  a.cron_new(
    a.CronOptions(
      ..a.cron_options(),
      minute: a.CronValues([a.CronStep(a.CronStepAny, 0)]),
    ),
  )
  |> should.equal(Error(a.CronInvalidStep(a.CronMinute, "*/0")))
  let assert Ok(raw) = a.cron_parse_raw(input: "*/0 * * * *")
  a.cron_validate(raw: raw)
  |> should.equal(Error(a.CronInvalidStep(a.CronMinute, "*/0")))
}

pub fn cron_next_crosses_negative_year_and_year_zero_test() {
  let spec = support.cron_spec("* * * * *")
  let assert Ok(Some(next)) =
    a.schedule_next(
      a.schedule_from_cron(spec),
      after: support.valid(-1, 12, 31, 23, 59, 59),
    )
  assert_valid_parts(support.parts(next))
  support.parts(next) |> should.equal(#(0, 1, 1, 0, 0, 0))
}

pub fn cron_next_respects_gregorian_century_boundaries_test() {
  let spec = support.cron_spec("0 0 * * *")
  list.each([#(0, 2, 29), #(1900, 3, 1), #(2000, 2, 29)], fn(expected) {
    let assert Ok(Some(next)) =
      a.schedule_next(
        a.schedule_from_cron(spec),
        after: support.valid(expected.0, 2, 28, 0, 0, 0),
      )
    assert_valid_parts(support.parts(next))
    support.parts(next)
    |> should.equal(#(expected.0, expected.1, expected.2, 0, 0, 0))
  })
}

pub fn cron_next_keeps_large_civil_years_test() {
  let spec = support.cron_spec("0 0 * * *")
  let assert Ok(Some(next)) =
    a.schedule_next(
      a.schedule_from_cron(spec),
      after: support.valid(12_000, 12, 31, 23, 59, 59),
    )
  assert_valid_parts(support.parts(next))
  support.parts(next) |> should.equal(#(12_001, 1, 1, 0, 0, 0))
}

pub fn cron_leap_day_skips_nonleap_century_test() {
  let spec = support.cron_spec("0 0 29 2 *")
  let assert Ok(Some(next)) =
    a.schedule_next(
      a.schedule_from_cron(spec),
      after: support.valid(2099, 1, 1, 0, 0, 0),
    )
  assert_valid_parts(support.parts(next))
  support.parts(next) |> should.equal(#(2104, 2, 29, 0, 0, 0))
}

pub fn cron_or_day_matching_never_yields_april_thirty_first_test() {
  let spec = support.cron_spec("0 0 31 4 MON")
  let assert Ok(Some(next)) =
    a.schedule_next(
      a.schedule_from_cron(spec),
      after: support.valid(2026, 4, 1, 0, 0, 0),
    )
  assert_valid_parts(support.parts(next))
  support.parts(next) |> should.equal(#(2026, 4, 6, 0, 0, 0))
}

pub fn cron_matching_keeps_minute_granularity_test() {
  let spec = support.cron_spec("30 9 * * *")
  a.schedule_matches(
    a.schedule_from_cron(spec),
    at: support.valid(2026, 1, 1, 9, 30, 59),
  )
  |> should.equal(Ok(True))
  let assert Ok(Some(next)) =
    a.schedule_next(
      a.schedule_from_cron(spec),
      after: support.valid(2026, 1, 1, 9, 29, 59),
    )
  support.parts(next) |> should.equal(#(2026, 1, 1, 9, 30, 0))
}

fn assert_valid_parts(parts: support.Parts) {
  let #(year, month, day, hour, minute, second) = parts
  let leap = year % 400 == 0 || { year % 4 == 0 && year % 100 != 0 }
  let days = case month {
    2 ->
      case leap {
        True -> 29
        False -> 28
      }
    4 | 6 | 9 | 11 -> 30
    _ -> 31
  }
  should.be_true(month >= 1 && month <= 12 && day >= 1 && day <= days)
  should.be_true(hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59)
  second |> should.equal(0)
}
