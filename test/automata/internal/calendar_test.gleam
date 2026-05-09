import automata/internal/calendar
import automata/schedule/ast as schedule_ast
import gleam/order
import gleeunit/should

pub fn is_leap_year_handles_century_rules_test() {
  calendar.is_leap_year(2000) |> should.equal(True)
  calendar.is_leap_year(2024) |> should.equal(True)
  calendar.is_leap_year(1900) |> should.equal(False)
  calendar.is_leap_year(2100) |> should.equal(False)
  calendar.is_leap_year(2025) |> should.equal(False)
}

pub fn days_in_month_handles_february_test() {
  calendar.days_in_month(2024, 2) |> should.equal(29)
  calendar.days_in_month(2025, 2) |> should.equal(28)
  calendar.days_in_month(2000, 2) |> should.equal(29)
  calendar.days_in_month(1900, 2) |> should.equal(28)
}

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

pub fn add_months_clamps_to_month_end_test() {
  calendar.add_months(schedule_ast.datetime(2026, 1, 31, 9, 0, 0), 1)
  |> should.equal(schedule_ast.datetime(2026, 2, 28, 9, 0, 0))

  calendar.add_months(schedule_ast.datetime(2024, 1, 31, 9, 0, 0), 1)
  |> should.equal(schedule_ast.datetime(2024, 2, 29, 9, 0, 0))

  calendar.add_months(schedule_ast.datetime(2026, 5, 31, 9, 0, 0), 1)
  |> should.equal(schedule_ast.datetime(2026, 6, 30, 9, 0, 0))
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

  calendar.compare(a, a) |> should.equal(order.Eq)
  calendar.compare(a, b) |> should.equal(order.Lt)
  calendar.compare(b, a) |> should.equal(order.Gt)
  calendar.compare(a, c) |> should.equal(order.Lt)
  calendar.compare(a, d) |> should.equal(order.Gt)
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

pub fn datetime_to_seconds_combines_date_and_time_test() {
  let base = schedule_ast.datetime(2026, 1, 1, 0, 0, 0)
  let later = schedule_ast.datetime(2026, 1, 1, 1, 2, 3)

  calendar.datetime_to_seconds(later) - calendar.datetime_to_seconds(base)
  |> should.equal(3723)
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

pub fn next_year_advances_year_and_zeroes_time_test() {
  calendar.next_year(schedule_ast.datetime(2026, 5, 9, 12, 0, 0))
  |> should.equal(schedule_ast.datetime(2027, 5, 9, 0, 0, 0))

  calendar.next_year(schedule_ast.datetime(2024, 2, 29, 9, 0, 0))
  |> should.equal(schedule_ast.datetime(2025, 2, 28, 0, 0, 0))
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

pub fn set_minute_replaces_minute_only_test() {
  calendar.set_minute(schedule_ast.datetime(2026, 5, 9, 9, 0, 30), 45)
  |> should.equal(schedule_ast.datetime(2026, 5, 9, 9, 45, 30))
}

pub fn set_hour_replaces_hour_only_test() {
  calendar.set_hour(schedule_ast.datetime(2026, 5, 9, 9, 30, 0), 17)
  |> should.equal(schedule_ast.datetime(2026, 5, 9, 17, 30, 0))
}

pub fn set_day_replaces_day_only_test() {
  calendar.set_day(schedule_ast.datetime(2026, 5, 9, 9, 30, 0), 25)
  |> should.equal(schedule_ast.datetime(2026, 5, 25, 9, 30, 0))
}

pub fn set_month_clamps_day_to_max_test() {
  // 2026-01-31 → set_month 2 → must clamp day to Feb 28 (non-leap).
  calendar.set_month(schedule_ast.datetime(2026, 1, 31, 9, 0, 0), 2)
  |> should.equal(schedule_ast.datetime(2026, 2, 28, 9, 0, 0))

  // 2024-01-31 → set_month 2 → leap year → Feb 29.
  calendar.set_month(schedule_ast.datetime(2024, 1, 31, 9, 0, 0), 2)
  |> should.equal(schedule_ast.datetime(2024, 2, 29, 9, 0, 0))
}

pub fn set_year_clamps_day_for_non_leap_year_test() {
  calendar.set_year(schedule_ast.datetime(2024, 2, 29, 9, 0, 0), 2025)
  |> should.equal(schedule_ast.datetime(2025, 2, 28, 9, 0, 0))

  calendar.set_year(schedule_ast.datetime(2024, 2, 29, 9, 0, 0), 2028)
  |> should.equal(schedule_ast.datetime(2028, 2, 29, 9, 0, 0))
}

pub fn add_months_negative_walks_backwards_test() {
  calendar.add_months(schedule_ast.datetime(2026, 3, 31, 9, 0, 0), -1)
  |> should.equal(schedule_ast.datetime(2026, 2, 28, 9, 0, 0))

  calendar.add_months(schedule_ast.datetime(2026, 1, 15, 9, 0, 0), -2)
  |> should.equal(schedule_ast.datetime(2025, 11, 15, 9, 0, 0))
}
