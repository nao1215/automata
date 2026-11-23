import automata as a
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/time/calendar
import gleeunit/should

pub fn weekday_matches_known_dates_test() {
  weekday_from_cron(make_datetime(
    year: 2024,
    month: 2,
    day: 29,
    hour: 0,
    minute: 0,
    second: 0,
  ))
  |> should.equal(calendar.Thursday)

  weekday_from_cron(make_datetime(
    year: 2026,
    month: 1,
    day: 1,
    hour: 0,
    minute: 0,
    second: 0,
  ))
  |> should.equal(calendar.Thursday)

  weekday_from_cron(make_datetime(
    year: 2026,
    month: 5,
    day: 9,
    hour: 0,
    minute: 0,
    second: 0,
  ))
  |> should.equal(calendar.Saturday)

  weekday_from_cron(make_datetime(
    year: 2025,
    month: 2,
    day: 28,
    hour: 0,
    minute: 0,
    second: 0,
  ))
  |> should.equal(calendar.Friday)

  weekday_from_cron(make_datetime(
    year: 2025,
    month: 3,
    day: 1,
    hour: 0,
    minute: 0,
    second: 0,
  ))
  |> should.equal(calendar.Saturday)
}

pub fn add_days_crosses_month_end_test() {
  expect_seconds(
    make_datetime(year: 2026, month: 1, day: 31, hour: 0, minute: 0, second: 0),
    { 1 } * 86_400,
    make_datetime(year: 2026, month: 2, day: 1, hour: 0, minute: 0, second: 0),
  )

  expect_seconds(
    make_datetime(year: 2024, month: 2, day: 28, hour: 0, minute: 0, second: 0),
    { 1 } * 86_400,
    make_datetime(year: 2024, month: 2, day: 29, hour: 0, minute: 0, second: 0),
  )

  expect_seconds(
    make_datetime(year: 2025, month: 2, day: 28, hour: 0, minute: 0, second: 0),
    { 1 } * 86_400,
    make_datetime(year: 2025, month: 3, day: 1, hour: 0, minute: 0, second: 0),
  )

  expect_seconds(
    make_datetime(year: 2026, month: 12, day: 31, hour: 0, minute: 0, second: 0),
    { 1 } * 86_400,
    make_datetime(year: 2027, month: 1, day: 1, hour: 0, minute: 0, second: 0),
  )
}

pub fn add_seconds_rolls_minutes_and_days_test() {
  expect_seconds(
    make_datetime(year: 2026, month: 5, day: 9, hour: 9, minute: 0, second: 59),
    { 1 } * 1,
    make_datetime(year: 2026, month: 5, day: 9, hour: 9, minute: 1, second: 0),
  )

  expect_seconds(
    make_datetime(
      year: 2026,
      month: 5,
      day: 9,
      hour: 23,
      minute: 59,
      second: 59,
    ),
    { 1 } * 1,
    make_datetime(year: 2026, month: 5, day: 10, hour: 0, minute: 0, second: 0),
  )

  expect_seconds(
    make_datetime(year: 2026, month: 5, day: 9, hour: 0, minute: 0, second: 0),
    { -1 } * 1,
    make_datetime(
      year: 2026,
      month: 5,
      day: 8,
      hour: 23,
      minute: 59,
      second: 59,
    ),
  )
}

pub fn add_seconds_zero_is_identity_test() {
  let value =
    make_datetime(
      year: 2026,
      month: 5,
      day: 9,
      hour: 12,
      minute: 30,
      second: 45,
    )
  expect_seconds(value, { 0 } * 1, value)
}

pub fn add_seconds_handles_one_day_jump_test() {
  // 86_400 seconds advances exactly one day, regardless of time-of-day.
  expect_seconds(
    make_datetime(year: 2026, month: 5, day: 9, hour: 9, minute: 30, second: 0),
    { 86_400 } * 1,
    make_datetime(year: 2026, month: 5, day: 10, hour: 9, minute: 30, second: 0),
  )

  expect_seconds(
    make_datetime(
      year: 2026,
      month: 5,
      day: 9,
      hour: 23,
      minute: 59,
      second: 59,
    ),
    { 86_400 } * 1,
    make_datetime(
      year: 2026,
      month: 5,
      day: 10,
      hour: 23,
      minute: 59,
      second: 59,
    ),
  )
}

pub fn add_seconds_handles_one_week_jump_test() {
  expect_seconds(
    make_datetime(year: 2026, month: 5, day: 1, hour: 0, minute: 0, second: 0),
    { 604_800 } * 1,
    make_datetime(year: 2026, month: 5, day: 8, hour: 0, minute: 0, second: 0),
  )
}

pub fn add_seconds_handles_negative_one_day_jump_test() {
  expect_seconds(
    make_datetime(year: 2026, month: 5, day: 10, hour: 9, minute: 30, second: 0),
    { -86_400 } * 1,
    make_datetime(year: 2026, month: 5, day: 9, hour: 9, minute: 30, second: 0),
  )
}

pub fn add_seconds_handles_arbitrary_offset_test() {
  // 86_400 + 3661 = one day, one hour, one minute, one second.
  expect_seconds(
    make_datetime(year: 2026, month: 5, day: 9, hour: 0, minute: 0, second: 0),
    { 90_061 } * 1,
    make_datetime(year: 2026, month: 5, day: 10, hour: 1, minute: 1, second: 1),
  )
}

pub fn weekday_first_monday_of_january_test() {
  weekday_from_cron(make_datetime(
    year: 2026,
    month: 1,
    day: 5,
    hour: 0,
    minute: 0,
    second: 0,
  ))
  |> should.equal(calendar.Monday)

  weekday_from_cron(make_datetime(
    year: 2027,
    month: 1,
    day: 4,
    hour: 0,
    minute: 0,
    second: 0,
  ))
  |> should.equal(calendar.Monday)

  weekday_from_cron(make_datetime(
    year: 2028,
    month: 1,
    day: 3,
    hour: 0,
    minute: 0,
    second: 0,
  ))
  |> should.equal(calendar.Monday)

  weekday_from_cron(make_datetime(
    year: 2026,
    month: 12,
    day: 27,
    hour: 0,
    minute: 0,
    second: 0,
  ))
  |> should.equal(calendar.Sunday)

  weekday_from_cron(make_datetime(
    year: 2026,
    month: 5,
    day: 27,
    hour: 0,
    minute: 0,
    second: 0,
  ))
  |> should.equal(calendar.Wednesday)
}

pub fn compare_total_orders_full_components_test() {
  let a =
    make_datetime(
      year: 2026,
      month: 5,
      day: 9,
      hour: 12,
      minute: 30,
      second: 45,
    )
  let b =
    make_datetime(
      year: 2026,
      month: 5,
      day: 9,
      hour: 12,
      minute: 30,
      second: 46,
    )
  let c =
    make_datetime(year: 2027, month: 1, day: 1, hour: 0, minute: 0, second: 0)
  let d =
    make_datetime(
      year: 2025,
      month: 12,
      day: 31,
      hour: 23,
      minute: 59,
      second: 59,
    )

  datetime_equal(a, a) |> should.equal(True)
  datetime_before(a, b) |> should.equal(True)
  datetime_after(b, a) |> should.equal(True)
  datetime_before(a, c) |> should.equal(True)
  datetime_after(a, d) |> should.equal(True)
}

pub fn comparison_helpers_match_compare_test() {
  let earlier =
    make_datetime(year: 2026, month: 5, day: 9, hour: 9, minute: 0, second: 0)
  let later =
    make_datetime(year: 2026, month: 5, day: 9, hour: 10, minute: 0, second: 0)
  let same =
    make_datetime(year: 2026, month: 5, day: 9, hour: 9, minute: 0, second: 0)

  datetime_before(earlier, later) |> should.equal(True)
  datetime_before(later, earlier) |> should.equal(False)
  datetime_before(earlier, same) |> should.equal(False)

  datetime_at_or_before(earlier, later) |> should.equal(True)
  datetime_at_or_before(earlier, same) |> should.equal(True)
  datetime_at_or_before(later, earlier) |> should.equal(False)

  datetime_after(later, earlier) |> should.equal(True)
  datetime_after(earlier, later) |> should.equal(False)
  datetime_after(earlier, same) |> should.equal(False)

  datetime_at_or_after(later, earlier) |> should.equal(True)
  datetime_at_or_after(earlier, same) |> should.equal(True)
  datetime_at_or_after(earlier, later) |> should.equal(False)

  datetime_equal(earlier, same) |> should.equal(True)
  datetime_equal(earlier, later) |> should.equal(False)
}

pub fn days_since_epoch_increments_by_one_per_day_test() {
  expect_seconds(
    make_datetime(year: 2026, month: 5, day: 9, hour: 0, minute: 0, second: 0),
    86_400,
    make_datetime(year: 2026, month: 5, day: 10, hour: 0, minute: 0, second: 0),
  )
}

pub fn days_since_epoch_handles_leap_year_boundary_test() {
  expect_seconds(
    make_datetime(year: 2024, month: 2, day: 28, hour: 0, minute: 0, second: 0),
    86_400,
    make_datetime(year: 2024, month: 2, day: 29, hour: 0, minute: 0, second: 0),
  )
  expect_seconds(
    make_datetime(year: 2024, month: 2, day: 29, hour: 0, minute: 0, second: 0),
    86_400,
    make_datetime(year: 2024, month: 3, day: 1, hour: 0, minute: 0, second: 0),
  )
  expect_seconds(
    make_datetime(year: 2025, month: 2, day: 28, hour: 0, minute: 0, second: 0),
    86_400,
    make_datetime(year: 2025, month: 3, day: 1, hour: 0, minute: 0, second: 0),
  )
}

pub fn seconds_between_is_signed_difference_test() {
  let a =
    make_datetime(year: 2026, month: 5, day: 9, hour: 12, minute: 0, second: 0)
  let b =
    make_datetime(year: 2026, month: 5, day: 9, hour: 12, minute: 0, second: 30)
  let c =
    make_datetime(year: 2026, month: 5, day: 10, hour: 12, minute: 0, second: 0)
  expect_seconds(a, 30, b)
  expect_seconds(b, -30, a)
  expect_seconds(a, 86_400, c)
}

pub fn add_minutes_handles_hour_and_day_rollover_test() {
  expect_seconds(
    make_datetime(year: 2026, month: 5, day: 9, hour: 9, minute: 59, second: 0),
    { 1 } * 60,
    make_datetime(year: 2026, month: 5, day: 9, hour: 10, minute: 0, second: 0),
  )

  expect_seconds(
    make_datetime(year: 2026, month: 5, day: 9, hour: 23, minute: 59, second: 0),
    { 1 } * 60,
    make_datetime(year: 2026, month: 5, day: 10, hour: 0, minute: 0, second: 0),
  )

  expect_seconds(
    make_datetime(year: 2026, month: 5, day: 10, hour: 0, minute: 0, second: 0),
    { -1 } * 60,
    make_datetime(year: 2026, month: 5, day: 9, hour: 23, minute: 59, second: 0),
  )
}

pub fn next_month_advances_month_clamping_day_test() {
  // `next_month` advances the month by one and clamps day-of-month to
  // the new month's max (so 2026-01-31 → 2026-02-28). Time is reset to
  // 00:00:00.
  next_monthly_date(make_datetime(
    year: 2026,
    month: 1,
    day: 31,
    hour: 9,
    minute: 30,
    second: 45,
  ))
  |> should.equal(make_datetime(
    year: 2026,
    month: 2,
    day: 28,
    hour: 0,
    minute: 0,
    second: 0,
  ))

  next_monthly_date(make_datetime(
    year: 2026,
    month: 12,
    day: 15,
    hour: 12,
    minute: 0,
    second: 0,
  ))
  |> should.equal(make_datetime(
    year: 2027,
    month: 1,
    day: 15,
    hour: 0,
    minute: 0,
    second: 0,
  ))
}

pub fn ceil_to_next_minute_is_identity_when_already_aligned_test() {
  let aligned =
    make_datetime(year: 2026, month: 5, day: 9, hour: 12, minute: 30, second: 0)
  next_cron_minute(aligned) |> should.equal(aligned)
}

pub fn ceil_to_next_minute_rounds_up_partial_seconds_test() {
  next_cron_minute(make_datetime(
    year: 2026,
    month: 5,
    day: 9,
    hour: 12,
    minute: 30,
    second: 1,
  ))
  |> should.equal(make_datetime(
    year: 2026,
    month: 5,
    day: 9,
    hour: 12,
    minute: 31,
    second: 0,
  ))

  next_cron_minute(make_datetime(
    year: 2026,
    month: 5,
    day: 9,
    hour: 23,
    minute: 59,
    second: 30,
  ))
  |> should.equal(make_datetime(
    year: 2026,
    month: 5,
    day: 10,
    hour: 0,
    minute: 0,
    second: 0,
  ))
}

pub fn set_day_replaces_day_only_test() {
  with_day(
    make_datetime(year: 2026, month: 5, day: 9, hour: 9, minute: 30, second: 0),
    25,
  )
  |> should.equal(make_datetime(
    year: 2026,
    month: 5,
    day: 25,
    hour: 9,
    minute: 30,
    second: 0,
  ))
}

// --- boundaries found by mutation testing ----------------------------------

fn dt(y: Int, mo: Int, d: Int, h: Int, mi: Int, s: Int) -> a.DateTime {
  a.DateTime(
    date: make_date(year: y, month: mo, day: d),
    time: make_time(hour: h, minute: mi, second: s),
  )
}

pub fn is_valid_date_accepts_the_last_day_of_each_month_test() {
  date_is_valid(make_date(year: 2024, month: 12, day: 31)) |> should.equal(True)
  date_is_valid(make_date(year: 2024, month: 2, day: 29)) |> should.equal(True)
  date_is_valid(make_date(year: 2025, month: 2, day: 29)) |> should.equal(False)
  calendar.month_from_int(13) |> should.equal(Error(Nil))
  calendar.month_from_int(0) |> should.equal(Error(Nil))
  date_is_valid(make_date(year: 2024, month: 4, day: 0)) |> should.equal(False)
  datetime_is_valid(dt(2024, 2, 29, 23, 59, 59))
  |> should.equal(True)
  datetime_is_valid(dt(2024, 2, 29, 24, 0, 0))
  |> should.equal(False)
  datetime_is_valid(dt(2024, 2, 30, 0, 0, 0))
  |> should.equal(False)
}

pub fn days_since_epoch_matches_python_toordinal_test() {
  // Expected values from Python's datetime.date(y, m, d).toordinal(),
  // an independent proleptic Gregorian day count with 0001-01-01 = 1.
  [
    #(make_date(year: 1, month: 1, day: 1), 1),
    #(make_date(year: 1970, month: 1, day: 1), 719_163),
    #(make_date(year: 2000, month: 2, day: 29), 730_179),
    #(make_date(year: 2000, month: 3, day: 1), 730_180),
    #(make_date(year: 1900, month: 3, day: 1), 693_655),
    #(make_date(year: 2024, month: 12, day: 31), 739_251),
    #(make_date(year: 2100, month: 3, day: 1), 766_704),
  ]
  |> list.each(fn(case_) {
    let #(date, ordinal) = case_
    expect_seconds(
      make_datetime(year: 1, month: 1, day: 1, hour: 0, minute: 0, second: 0),
      { ordinal - 1 } * 86_400,
      a.DateTime(date, make_time(hour: 0, minute: 0, second: 0)),
    )
  })
}

pub fn stepping_backwards_crosses_minute_hour_day_month_and_year_test() {
  expect_seconds(
    dt(2024, 3, 1, 10, 1, 30),
    { -1 } * 60,
    dt(2024, 3, 1, 10, 0, 30),
  )
  expect_seconds(
    dt(2024, 3, 1, 10, 0, 30),
    { -1 } * 60,
    dt(2024, 3, 1, 9, 59, 30),
  )
  expect_seconds(
    dt(2024, 3, 1, 0, 0, 30),
    { -1 } * 60,
    dt(2024, 2, 29, 23, 59, 30),
  )
  expect_seconds(
    dt(2024, 3, 2, 8, 0, 0),
    { -1 } * 86_400,
    dt(2024, 3, 1, 8, 0, 0),
  )
  expect_seconds(
    dt(2025, 1, 1, 8, 0, 0),
    { -1 } * 86_400,
    dt(2024, 12, 31, 8, 0, 0),
  )
}

fn validated(value: a.DateTime) -> a.ValidDateTime {
  let assert Ok(value) = a.datetime_validate(value)
  value
}

fn expect_seconds(start: a.DateTime, seconds: Int, expected: a.DateTime) {
  case seconds {
    0 -> start |> should.equal(expected)
    _ -> {
      let #(anchor, after, delta) = case seconds < 0 {
        True -> #(validated(expected), validated(start), 0 - seconds)
        False -> #(validated(start), validated(expected), seconds)
      }
      let assert Ok(schedule) =
        a.schedule_every(interval_seconds: delta, anchor: anchor)
      a.schedule_next(schedule, after: anchor) |> should.equal(Ok(Some(after)))
    }
  }
}

fn event_at(value: a.DateTime) -> a.Event(Nil) {
  a.Event(
    "time",
    validated(value),
    a.Source(a.ManualSource, "test", None),
    Nil,
    a.Metadata(None, None, None, dict.new()),
  )
}

fn datetime_equal(left: a.DateTime, right: a.DateTime) -> Bool {
  a.datetime_value(validated(left)) == a.datetime_value(validated(right))
}

fn datetime_before(left: a.DateTime, right: a.DateTime) -> Bool {
  a.event_occurred_before(event_at(left), before: validated(right))
}

fn datetime_after(left: a.DateTime, right: a.DateTime) -> Bool {
  a.event_occurred_after(event_at(left), after: validated(right))
}

fn datetime_at_or_before(left: a.DateTime, right: a.DateTime) -> Bool {
  !datetime_after(left, right)
}

fn datetime_at_or_after(left: a.DateTime, right: a.DateTime) -> Bool {
  !datetime_before(left, right)
}

fn weekday_from_cron(value: a.DateTime) -> calendar.DayOfWeek {
  let options = a.cron_options()
  let assert Ok(#(_, day)) =
    [
      #(0, calendar.Sunday),
      #(1, calendar.Monday),
      #(2, calendar.Tuesday),
      #(3, calendar.Wednesday),
      #(4, calendar.Thursday),
      #(5, calendar.Friday),
      #(6, calendar.Saturday),
    ]
    |> list.find(fn(row) {
      let assert Ok(cron) =
        a.cron_new(
          a.CronOptions(
            ..options,
            day_of_week: a.CronValues([a.CronExact(row.0)]),
          ),
        )
      a.schedule_matches(a.schedule_from_cron(cron), at: validated(value))
      == Ok(True)
    })
  day
}

fn date_is_valid(value: calendar.Date) -> Bool {
  datetime_is_valid(a.DateTime(value, make_time(hour: 0, minute: 0, second: 0)))
}

fn datetime_is_valid(value: a.DateTime) -> Bool {
  result.is_ok(a.datetime_validate(value))
}

fn with_day(value: a.DateTime, day: Int) -> a.DateTime {
  let date = calendar.Date(..value.date, day: day)
  let result = a.DateTime(..value, date: date)
  a.datetime_value(validated(result))
}

fn next_cron_minute(value: a.DateTime) -> a.DateTime {
  let assert Ok(cron) = a.cron_new(a.cron_options())
  let assert Ok(it) =
    a.schedule_iterator(
      a.schedule_from_cron(cron),
      boundary: a.Inclusive(validated(value)),
    )
  let assert Ok(a.Yield(at, _)) = a.schedule_step(it)
  a.datetime_value(at)
}

fn next_monthly_date(value: a.DateTime) -> a.DateTime {
  // These existing fixtures cover a last-day recurrence and a fixed-day recurrence.
  let options = a.rrule_options(a.Monthly)
  let options = case value.date.day == 31 {
    True -> a.RecurrenceOptions(..options, by_month_day: Some([-1]))
    False -> options
  }
  let anchor =
    validated(a.DateTime(value.date, make_time(hour: 0, minute: 0, second: 0)))
  let assert Ok(rule) = a.rrule_new(options)
  let assert Ok(Some(at)) =
    a.schedule_next(a.schedule_from_rrule(rule, anchor: anchor), after: anchor)
  a.datetime_value(at)
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

fn make_time(
  hour hour: Int,
  minute minute: Int,
  second second: Int,
) -> calendar.TimeOfDay {
  calendar.TimeOfDay(hour, minute, second, 0)
}
