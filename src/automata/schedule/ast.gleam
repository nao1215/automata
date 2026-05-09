import gleam/int
import gleam/result

/// Gregorian weekday names shared by cron and RRULE APIs.
pub type Weekday {
  Monday
  Tuesday
  Wednesday
  Thursday
  Friday
  Saturday
  Sunday
}

/// Calendar date in the proleptic Gregorian calendar.
pub type Date {
  Date(year: Int, month: Int, day: Int)
}

/// Wall-clock time with second precision.
pub type Time {
  Time(hour: Int, minute: Int, second: Int)
}

/// Naive date-time used by schedule matching and iteration.
pub type DateTime {
  DateTime(date: Date, time: Time)
}

/// A `DateTime` proven to fall in the valid Gregorian range.
///
/// Construct via `try_datetime/6`; unwrap with `valid_datetime_value/1`.
pub opaque type ValidDateTime {
  ValidDateTime(value: DateTime)
}

/// Boundary semantics used when starting iteration.
pub type Boundary {
  Inclusive(DateTime)
  Exclusive(DateTime)
}

/// Errors that can occur when smart-constructing `DateTime` values.
pub type DateTimeError {
  InvalidDate(year: Int, month: Int, day: Int)
  InvalidTime(hour: Int, minute: Int, second: Int)
}

pub fn date(year year: Int, month month: Int, day day: Int) -> Date {
  Date(year:, month:, day:)
}

pub fn time(hour hour: Int, minute minute: Int, second second: Int) -> Time {
  Time(hour:, minute:, second:)
}

pub fn datetime(
  year year: Int,
  month month: Int,
  day day: Int,
  hour hour: Int,
  minute minute: Int,
  second second: Int,
) -> DateTime {
  DateTime(date: Date(year:, month:, day:), time: Time(hour:, minute:, second:))
}

/// Build a validated `DateTime` from raw integer components.
///
/// Returns `Error(InvalidDate)` for impossible calendar dates such as
/// February 30, and `Error(InvalidTime)` for clock components outside
/// `00:00:00`-`23:59:59`.
pub fn try_datetime(
  year year: Int,
  month month: Int,
  day day: Int,
  hour hour: Int,
  minute minute: Int,
  second second: Int,
) -> Result(DateTime, DateTimeError) {
  case is_valid_date_components(year, month, day) {
    False -> Error(InvalidDate(year, month, day))
    True ->
      case is_valid_time_components(hour, minute, second) {
        False -> Error(InvalidTime(hour, minute, second))
        True -> Ok(datetime(year:, month:, day:, hour:, minute:, second:))
      }
  }
}

/// Build an opaque `ValidDateTime`, propagating validation errors.
pub fn try_valid_datetime(
  year year: Int,
  month month: Int,
  day day: Int,
  hour hour: Int,
  minute minute: Int,
  second second: Int,
) -> Result(ValidDateTime, DateTimeError) {
  case try_datetime(year:, month:, day:, hour:, minute:, second:) {
    Ok(value) -> Ok(ValidDateTime(value: value))
    Error(error) -> Error(error)
  }
}

/// Recover the raw `DateTime` value from a `ValidDateTime`.
pub fn valid_datetime_value(valid: ValidDateTime) -> DateTime {
  valid.value
}

fn is_valid_date_components(year: Int, month: Int, day: Int) -> Bool {
  month >= 1 && month <= 12 && day >= 1 && day <= days_in_month(year, month)
}

fn is_valid_time_components(hour: Int, minute: Int, second: Int) -> Bool {
  hour >= 0
  && hour <= 23
  && minute >= 0
  && minute <= 59
  && second >= 0
  && second <= 59
}

fn days_in_month(year: Int, month: Int) -> Int {
  case month {
    1 -> 31
    2 ->
      case is_leap_year(year) {
        True -> 29
        False -> 28
      }
    3 -> 31
    4 -> 30
    5 -> 31
    6 -> 30
    7 -> 31
    8 -> 31
    9 -> 30
    10 -> 31
    11 -> 30
    12 -> 31
    _ -> 0
  }
}

fn is_leap_year(year: Int) -> Bool {
  let by_4 = modulo(year, 4)
  let by_100 = modulo(year, 100)
  let by_400 = modulo(year, 400)

  by_400 == 0 || { by_4 == 0 && by_100 != 0 }
}

fn modulo(dividend: Int, divisor: Int) -> Int {
  int.modulo(dividend, by: divisor) |> result.unwrap(0)
}

pub fn to_string(datetime: DateTime) -> String {
  pad4(datetime.date.year)
  <> "-"
  <> pad2(datetime.date.month)
  <> "-"
  <> pad2(datetime.date.day)
  <> "T"
  <> pad2(datetime.time.hour)
  <> ":"
  <> pad2(datetime.time.minute)
  <> ":"
  <> pad2(datetime.time.second)
}

pub fn weekday_to_string(weekday: Weekday) -> String {
  case weekday {
    Monday -> "MO"
    Tuesday -> "TU"
    Wednesday -> "WE"
    Thursday -> "TH"
    Friday -> "FR"
    Saturday -> "SA"
    Sunday -> "SU"
  }
}

fn pad2(value: Int) -> String {
  case value < 10 {
    True -> "0" <> int.to_string(value)
    False -> int.to_string(value)
  }
}

fn pad4(value: Int) -> String {
  case value < 10 {
    True -> "000" <> int.to_string(value)
    False ->
      case value < 100 {
        True -> "00" <> int.to_string(value)
        False ->
          case value < 1000 {
            True -> "0" <> int.to_string(value)
            False -> int.to_string(value)
          }
      }
  }
}
