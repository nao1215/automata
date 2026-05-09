import automata/internal/calendar
import automata/schedule/ast as schedule_ast
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
