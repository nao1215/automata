import automata/internal/calendar
import automata/schedule/ast as schedule_ast
import gleam/list
import gleeunit/should

pub fn weekday_matches_known_dates_test() {
  calendar.weekday(schedule_ast.datetime(2024, 2, 29, 0, 0, 0))
  |> should.equal(schedule_ast.Thursday)

  calendar.weekday(schedule_ast.datetime(2026, 1, 1, 0, 0, 0))
  |> should.equal(schedule_ast.Thursday)

  calendar.weekday(schedule_ast.datetime(2026, 5, 9, 0, 0, 0))
  |> should.equal(schedule_ast.Saturday)

  calendar.weekday(schedule_ast.datetime(2025, 2, 28, 0, 0, 0))
  |> should.equal(schedule_ast.Friday)

  calendar.weekday(schedule_ast.datetime(2025, 3, 1, 0, 0, 0))
  |> should.equal(schedule_ast.Saturday)
}

pub fn add_days_crosses_month_end_test() {
  calendar.add_days(schedule_ast.datetime(2026, 1, 31, 0, 0, 0), 1)
  |> should.equal(schedule_ast.datetime(2026, 2, 1, 0, 0, 0))

  calendar.add_days(schedule_ast.datetime(2024, 2, 28, 0, 0, 0), 1)
  |> should.equal(schedule_ast.datetime(2024, 2, 29, 0, 0, 0))

  calendar.add_days(schedule_ast.datetime(2025, 2, 28, 0, 0, 0), 1)
  |> should.equal(schedule_ast.datetime(2025, 3, 1, 0, 0, 0))

  calendar.add_days(schedule_ast.datetime(2026, 12, 31, 0, 0, 0), 1)
  |> should.equal(schedule_ast.datetime(2027, 1, 1, 0, 0, 0))
}

pub fn add_seconds_rolls_minutes_and_days_test() {
  calendar.add_seconds(schedule_ast.datetime(2026, 5, 9, 9, 0, 59), 1)
  |> should.equal(schedule_ast.datetime(2026, 5, 9, 9, 1, 0))

  calendar.add_seconds(schedule_ast.datetime(2026, 5, 9, 23, 59, 59), 1)
  |> should.equal(schedule_ast.datetime(2026, 5, 10, 0, 0, 0))

  calendar.add_seconds(schedule_ast.datetime(2026, 5, 9, 0, 0, 0), -1)
  |> should.equal(schedule_ast.datetime(2026, 5, 8, 23, 59, 59))
}

pub fn add_seconds_zero_is_identity_test() {
  let value = schedule_ast.datetime(2026, 5, 9, 12, 30, 45)
  calendar.add_seconds(value, 0) |> should.equal(value)
}

pub fn add_seconds_handles_one_day_jump_test() {
  // 86_400 seconds advances exactly one day, regardless of time-of-day.
  calendar.add_seconds(schedule_ast.datetime(2026, 5, 9, 9, 30, 0), 86_400)
  |> should.equal(schedule_ast.datetime(2026, 5, 10, 9, 30, 0))

  calendar.add_seconds(schedule_ast.datetime(2026, 5, 9, 23, 59, 59), 86_400)
  |> should.equal(schedule_ast.datetime(2026, 5, 10, 23, 59, 59))
}

pub fn add_seconds_handles_one_week_jump_test() {
  calendar.add_seconds(schedule_ast.datetime(2026, 5, 1, 0, 0, 0), 604_800)
  |> should.equal(schedule_ast.datetime(2026, 5, 8, 0, 0, 0))
}

pub fn add_seconds_handles_negative_one_day_jump_test() {
  calendar.add_seconds(schedule_ast.datetime(2026, 5, 10, 9, 30, 0), -86_400)
  |> should.equal(schedule_ast.datetime(2026, 5, 9, 9, 30, 0))
}

pub fn add_seconds_handles_arbitrary_offset_test() {
  // 86_400 + 3661 = one day, one hour, one minute, one second.
  calendar.add_seconds(schedule_ast.datetime(2026, 5, 9, 0, 0, 0), 90_061)
  |> should.equal(schedule_ast.datetime(2026, 5, 10, 1, 1, 1))
}

pub fn weekday_first_monday_of_january_test() {
  calendar.weekday(schedule_ast.datetime(2026, 1, 5, 0, 0, 0))
  |> should.equal(schedule_ast.Monday)

  calendar.weekday(schedule_ast.datetime(2027, 1, 4, 0, 0, 0))
  |> should.equal(schedule_ast.Monday)

  calendar.weekday(schedule_ast.datetime(2028, 1, 3, 0, 0, 0))
  |> should.equal(schedule_ast.Monday)

  calendar.weekday(schedule_ast.datetime(2026, 12, 27, 0, 0, 0))
  |> should.equal(schedule_ast.Sunday)

  calendar.weekday(schedule_ast.datetime(2026, 5, 27, 0, 0, 0))
  |> should.equal(schedule_ast.Wednesday)
}

pub fn compare_total_orders_full_components_test() {
  let a = schedule_ast.datetime(2026, 5, 9, 12, 30, 45)
  let b = schedule_ast.datetime(2026, 5, 9, 12, 30, 46)
  let c = schedule_ast.datetime(2027, 1, 1, 0, 0, 0)
  let d = schedule_ast.datetime(2025, 12, 31, 23, 59, 59)

  calendar.equals(a, a) |> should.equal(True)
  calendar.less_than(a, b) |> should.equal(True)
  calendar.greater_than(b, a) |> should.equal(True)
  calendar.less_than(a, c) |> should.equal(True)
  calendar.greater_than(a, d) |> should.equal(True)
}

pub fn comparison_helpers_match_compare_test() {
  let earlier = schedule_ast.datetime(2026, 5, 9, 9, 0, 0)
  let later = schedule_ast.datetime(2026, 5, 9, 10, 0, 0)
  let same = schedule_ast.datetime(2026, 5, 9, 9, 0, 0)

  calendar.less_than(earlier, later) |> should.equal(True)
  calendar.less_than(later, earlier) |> should.equal(False)
  calendar.less_than(earlier, same) |> should.equal(False)

  calendar.less_or_equal(earlier, later) |> should.equal(True)
  calendar.less_or_equal(earlier, same) |> should.equal(True)
  calendar.less_or_equal(later, earlier) |> should.equal(False)

  calendar.greater_than(later, earlier) |> should.equal(True)
  calendar.greater_than(earlier, later) |> should.equal(False)
  calendar.greater_than(earlier, same) |> should.equal(False)

  calendar.greater_or_equal(later, earlier) |> should.equal(True)
  calendar.greater_or_equal(earlier, same) |> should.equal(True)
  calendar.greater_or_equal(earlier, later) |> should.equal(False)

  calendar.equals(earlier, same) |> should.equal(True)
  calendar.equals(earlier, later) |> should.equal(False)
}

pub fn days_since_epoch_increments_by_one_per_day_test() {
  let a = calendar.days_since_epoch(schedule_ast.Date(2026, 5, 9))
  let b = calendar.days_since_epoch(schedule_ast.Date(2026, 5, 10))

  b - a |> should.equal(1)
}

pub fn days_since_epoch_handles_leap_year_boundary_test() {
  let feb_28 = calendar.days_since_epoch(schedule_ast.Date(2024, 2, 28))
  let feb_29 = calendar.days_since_epoch(schedule_ast.Date(2024, 2, 29))
  let mar_01 = calendar.days_since_epoch(schedule_ast.Date(2024, 3, 1))

  feb_29 - feb_28 |> should.equal(1)
  mar_01 - feb_29 |> should.equal(1)

  // In a non-leap year: Feb 28 → Mar 1 is exactly 1 day apart.
  let feb_28_2025 = calendar.days_since_epoch(schedule_ast.Date(2025, 2, 28))
  let mar_01_2025 = calendar.days_since_epoch(schedule_ast.Date(2025, 3, 1))
  mar_01_2025 - feb_28_2025 |> should.equal(1)
}

pub fn seconds_between_is_signed_difference_test() {
  let a = schedule_ast.datetime(2026, 5, 9, 12, 0, 0)
  let b = schedule_ast.datetime(2026, 5, 9, 12, 0, 30)
  let c = schedule_ast.datetime(2026, 5, 10, 12, 0, 0)

  calendar.seconds_between(a, b) |> should.equal(30)
  calendar.seconds_between(b, a) |> should.equal(-30)
  calendar.seconds_between(a, c) |> should.equal(86_400)
}

pub fn add_minutes_handles_hour_and_day_rollover_test() {
  calendar.add_minutes(schedule_ast.datetime(2026, 5, 9, 9, 59, 0), 1)
  |> should.equal(schedule_ast.datetime(2026, 5, 9, 10, 0, 0))

  calendar.add_minutes(schedule_ast.datetime(2026, 5, 9, 23, 59, 0), 1)
  |> should.equal(schedule_ast.datetime(2026, 5, 10, 0, 0, 0))

  calendar.add_minutes(schedule_ast.datetime(2026, 5, 10, 0, 0, 0), -1)
  |> should.equal(schedule_ast.datetime(2026, 5, 9, 23, 59, 0))
}

pub fn next_month_advances_month_clamping_day_test() {
  // `next_month` advances the month by one and clamps day-of-month to
  // the new month's max (so 2026-01-31 → 2026-02-28). Time is reset to
  // 00:00:00.
  calendar.next_month(schedule_ast.datetime(2026, 1, 31, 9, 30, 45))
  |> should.equal(schedule_ast.datetime(2026, 2, 28, 0, 0, 0))

  calendar.next_month(schedule_ast.datetime(2026, 12, 15, 12, 0, 0))
  |> should.equal(schedule_ast.datetime(2027, 1, 15, 0, 0, 0))
}

pub fn ceil_to_next_minute_is_identity_when_already_aligned_test() {
  let aligned = schedule_ast.datetime(2026, 5, 9, 12, 30, 0)
  calendar.ceil_to_next_minute(aligned) |> should.equal(aligned)
}

pub fn ceil_to_next_minute_rounds_up_partial_seconds_test() {
  calendar.ceil_to_next_minute(schedule_ast.datetime(2026, 5, 9, 12, 30, 1))
  |> should.equal(schedule_ast.datetime(2026, 5, 9, 12, 31, 0))

  calendar.ceil_to_next_minute(schedule_ast.datetime(2026, 5, 9, 23, 59, 30))
  |> should.equal(schedule_ast.datetime(2026, 5, 10, 0, 0, 0))
}

pub fn set_day_replaces_day_only_test() {
  calendar.set_day(schedule_ast.datetime(2026, 5, 9, 9, 30, 0), 25)
  |> should.equal(schedule_ast.datetime(2026, 5, 25, 9, 30, 0))
}

// --- boundaries found by mutation testing ----------------------------------

fn dt(
  y: Int,
  mo: Int,
  d: Int,
  h: Int,
  mi: Int,
  s: Int,
) -> schedule_ast.DateTime {
  schedule_ast.DateTime(
    date: schedule_ast.Date(year: y, month: mo, day: d),
    time: schedule_ast.Time(hour: h, minute: mi, second: s),
  )
}

pub fn is_valid_date_accepts_the_last_day_of_each_month_test() {
  calendar.is_valid_date(schedule_ast.Date(2024, 12, 31)) |> should.equal(True)
  calendar.is_valid_date(schedule_ast.Date(2024, 2, 29)) |> should.equal(True)
  calendar.is_valid_date(schedule_ast.Date(2025, 2, 29)) |> should.equal(False)
  calendar.is_valid_date(schedule_ast.Date(2024, 13, 1)) |> should.equal(False)
  calendar.is_valid_date(schedule_ast.Date(2024, 0, 1)) |> should.equal(False)
  calendar.is_valid_date(schedule_ast.Date(2024, 4, 0)) |> should.equal(False)
  calendar.is_valid_datetime(dt(2024, 2, 29, 23, 59, 59))
  |> should.equal(True)
  calendar.is_valid_datetime(dt(2024, 2, 29, 24, 0, 0))
  |> should.equal(False)
  calendar.is_valid_datetime(dt(2024, 2, 30, 0, 0, 0))
  |> should.equal(False)
}

pub fn days_since_epoch_matches_python_toordinal_test() {
  // Expected values from Python's datetime.date(y, m, d).toordinal(),
  // an independent proleptic Gregorian day count with 0001-01-01 = 1.
  [
    #(schedule_ast.Date(1, 1, 1), 1),
    #(schedule_ast.Date(1970, 1, 1), 719_163),
    #(schedule_ast.Date(2000, 2, 29), 730_179),
    #(schedule_ast.Date(2000, 3, 1), 730_180),
    #(schedule_ast.Date(1900, 3, 1), 693_655),
    #(schedule_ast.Date(2024, 12, 31), 739_251),
    #(schedule_ast.Date(2100, 3, 1), 766_704),
  ]
  |> list.each(fn(case_) {
    let #(date, ordinal) = case_
    calendar.days_since_epoch(date) |> should.equal(ordinal)
  })
}

pub fn stepping_backwards_crosses_minute_hour_day_month_and_year_test() {
  calendar.add_minutes(dt(2024, 3, 1, 10, 1, 30), -1)
  |> should.equal(dt(2024, 3, 1, 10, 0, 30))
  calendar.add_minutes(dt(2024, 3, 1, 10, 0, 30), -1)
  |> should.equal(dt(2024, 3, 1, 9, 59, 30))
  calendar.add_minutes(dt(2024, 3, 1, 0, 0, 30), -1)
  |> should.equal(dt(2024, 2, 29, 23, 59, 30))
  calendar.add_days(dt(2024, 3, 2, 8, 0, 0), -1)
  |> should.equal(dt(2024, 3, 1, 8, 0, 0))
  calendar.add_days(dt(2025, 1, 1, 8, 0, 0), -1)
  |> should.equal(dt(2024, 12, 31, 8, 0, 0))
}
