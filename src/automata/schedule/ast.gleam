import gleam/int

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

/// Boundary semantics used when starting iteration.
pub type Boundary {
  Inclusive(DateTime)
  Exclusive(DateTime)
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
