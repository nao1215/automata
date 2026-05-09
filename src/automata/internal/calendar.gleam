import automata/schedule/ast.{
  type Date, type DateTime, type Time, type Weekday, Date, DateTime, Friday,
  Monday, Saturday, Sunday, Thursday, Time, Tuesday, Wednesday,
}
import gleam/int
import gleam/order.{type Order, Eq, Gt, Lt}

pub fn compare(left: DateTime, right: DateTime) -> Order {
  case left.date.year < right.date.year {
    True -> Lt
    False ->
      case left.date.year > right.date.year {
        True -> Gt
        False ->
          case left.date.month < right.date.month {
            True -> Lt
            False ->
              case left.date.month > right.date.month {
                True -> Gt
                False ->
                  case left.date.day < right.date.day {
                    True -> Lt
                    False ->
                      case left.date.day > right.date.day {
                        True -> Gt
                        False ->
                          case left.time.hour < right.time.hour {
                            True -> Lt
                            False ->
                              case left.time.hour > right.time.hour {
                                True -> Gt
                                False ->
                                  case left.time.minute < right.time.minute {
                                    True -> Lt
                                    False ->
                                      case
                                        left.time.minute > right.time.minute
                                      {
                                        True -> Gt
                                        False ->
                                          case
                                            left.time.second < right.time.second
                                          {
                                            True -> Lt
                                            False ->
                                              case
                                                left.time.second
                                                > right.time.second
                                              {
                                                True -> Gt
                                                False -> Eq
                                              }
                                          }
                                      }
                                  }
                              }
                          }
                      }
                  }
              }
          }
      }
  }
}

pub fn less_than(left: DateTime, right: DateTime) -> Bool {
  compare(left, right) == Lt
}

pub fn less_or_equal(left: DateTime, right: DateTime) -> Bool {
  case compare(left, right) {
    Lt -> True
    Eq -> True
    Gt -> False
  }
}

pub fn greater_than(left: DateTime, right: DateTime) -> Bool {
  compare(left, right) == Gt
}

pub fn greater_or_equal(left: DateTime, right: DateTime) -> Bool {
  case compare(left, right) {
    Gt -> True
    Eq -> True
    Lt -> False
  }
}

pub fn equals(left: DateTime, right: DateTime) -> Bool {
  compare(left, right) == Eq
}

pub fn is_valid_date(date: Date) -> Bool {
  date.month >= 1
  && date.month <= 12
  && date.day >= 1
  && date.day <= days_in_month(date.year, date.month)
}

pub fn is_valid_time(time: Time) -> Bool {
  time.hour >= 0
  && time.hour <= 23
  && time.minute >= 0
  && time.minute <= 59
  && time.second >= 0
  && time.second <= 59
}

pub fn is_valid_datetime(datetime: DateTime) -> Bool {
  is_valid_date(datetime.date) && is_valid_time(datetime.time)
}

pub fn days_in_month(year: Int, month: Int) -> Int {
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

pub fn is_leap_year(year: Int) -> Bool {
  let by_4 = modulo(year, 4)
  let by_100 = modulo(year, 100)
  let by_400 = modulo(year, 400)

  by_400 == 0 || { by_4 == 0 && by_100 != 0 }
}

pub fn weekday(datetime: DateTime) -> Weekday {
  case
    weekday_number(datetime.date.year, datetime.date.month, datetime.date.day)
  {
    0 -> Sunday
    1 -> Monday
    2 -> Tuesday
    3 -> Wednesday
    4 -> Thursday
    5 -> Friday
    _ -> Saturday
  }
}

pub fn day_of_week_number(datetime: DateTime) -> Int {
  case weekday(datetime) {
    Sunday -> 0
    Monday -> 1
    Tuesday -> 2
    Wednesday -> 3
    Thursday -> 4
    Friday -> 5
    Saturday -> 6
  }
}

pub fn days_since_epoch(date: Date) -> Int {
  let previous = date.year - 1
  let leap_days =
    quotient(previous, 4) - quotient(previous, 100) + quotient(previous, 400)
  let days_before_year = previous * 365 + leap_days
  days_before_year + days_before_month(date.year, date.month) + date.day
}

pub fn datetime_to_seconds(datetime: DateTime) -> Int {
  days_since_epoch(datetime.date)
  * 86_400
  + datetime.time.hour
  * 3600
  + datetime.time.minute
  * 60
  + datetime.time.second
}

pub fn seconds_between(from: DateTime, to: DateTime) -> Int {
  datetime_to_seconds(to) - datetime_to_seconds(from)
}

fn days_before_month(year: Int, month: Int) -> Int {
  days_before_month_loop(year, month, 1, 0)
}

fn days_before_month_loop(year: Int, target: Int, month: Int, acc: Int) -> Int {
  case month >= target {
    True -> acc
    False ->
      days_before_month_loop(
        year,
        target,
        month + 1,
        acc + days_in_month(year, month),
      )
  }
}

pub fn add_minutes(datetime: DateTime, minutes: Int) -> DateTime {
  case minutes == 0 {
    True -> datetime
    False ->
      case minutes > 0 {
        True -> add_positive_minutes(datetime, minutes)
        False -> add_negative_minutes(datetime, 0 - minutes)
      }
  }
}

pub fn add_seconds(datetime: DateTime, seconds: Int) -> DateTime {
  case seconds {
    0 -> datetime
    _ -> {
      let seconds_in_day = 86_400
      let current_in_day =
        datetime.time.hour
        * 3600
        + datetime.time.minute
        * 60
        + datetime.time.second
      let total = current_in_day + seconds
      let in_day = modulo(total, seconds_in_day)
      let day_offset = quotient(total - in_day, seconds_in_day)
      let hour = quotient(in_day, 3600)
      let after_hour = in_day - hour * 3600
      let minute = quotient(after_hour, 60)
      let second = after_hour - minute * 60
      add_days(
        DateTime(date: datetime.date, time: Time(hour:, minute:, second:)),
        day_offset,
      )
    }
  }
}

pub fn add_days(datetime: DateTime, days: Int) -> DateTime {
  case days == 0 {
    True -> datetime
    False ->
      case days > 0 {
        True -> add_positive_days(datetime, days)
        False -> add_negative_days(datetime, 0 - days)
      }
  }
}

pub fn add_months(datetime: DateTime, months: Int) -> DateTime {
  case months == 0 {
    True -> datetime
    False -> {
      let total = { datetime.date.year * 12 + datetime.date.month - 1 } + months
      let year = quotient(total, 12)
      let month = modulo(total, 12) + 1
      let max_day = days_in_month(year, month)
      let day = case datetime.date.day > max_day {
        True -> max_day
        False -> datetime.date.day
      }

      DateTime(date: Date(year:, month:, day: day), time: datetime.time)
    }
  }
}

pub fn start_of_day(datetime: DateTime) -> DateTime {
  DateTime(date: datetime.date, time: Time(hour: 0, minute: 0, second: 0))
}

pub fn at_time(
  datetime: DateTime,
  hour: Int,
  minute: Int,
  second: Int,
) -> DateTime {
  DateTime(date: datetime.date, time: Time(hour:, minute:, second:))
}

pub fn at_date(datetime: DateTime, date: Date) -> DateTime {
  DateTime(date:, time: datetime.time)
}

pub fn next_day(datetime: DateTime) -> DateTime {
  add_days(start_of_day(datetime), 1)
}

pub fn next_month(datetime: DateTime) -> DateTime {
  DateTime(
    date: add_months(start_of_day(datetime), 1).date,
    time: Time(hour: 0, minute: 0, second: 0),
  )
}

pub fn next_year(datetime: DateTime) -> DateTime {
  add_months(
    DateTime(date: datetime.date, time: Time(hour: 0, minute: 0, second: 0)),
    12,
  )
}

pub fn ceil_to_next_minute(datetime: DateTime) -> DateTime {
  case datetime.time.second == 0 {
    True -> datetime
    False ->
      add_minutes(
        DateTime(
          date: datetime.date,
          time: Time(
            hour: datetime.time.hour,
            minute: datetime.time.minute,
            second: 0,
          ),
        ),
        1,
      )
  }
}

pub fn set_minute(datetime: DateTime, minute: Int) -> DateTime {
  DateTime(
    date: datetime.date,
    time: Time(
      hour: datetime.time.hour,
      minute: minute,
      second: datetime.time.second,
    ),
  )
}

pub fn set_hour(datetime: DateTime, hour: Int) -> DateTime {
  DateTime(
    date: datetime.date,
    time: Time(
      hour: hour,
      minute: datetime.time.minute,
      second: datetime.time.second,
    ),
  )
}

pub fn set_day(datetime: DateTime, day: Int) -> DateTime {
  DateTime(
    date: Date(year: datetime.date.year, month: datetime.date.month, day: day),
    time: datetime.time,
  )
}

pub fn set_month(datetime: DateTime, month: Int) -> DateTime {
  let max_day = days_in_month(datetime.date.year, month)
  let day = case datetime.date.day > max_day {
    True -> max_day
    False -> datetime.date.day
  }

  DateTime(
    date: Date(year: datetime.date.year, month:, day: day),
    time: datetime.time,
  )
}

pub fn set_year(datetime: DateTime, year: Int) -> DateTime {
  let max_day = days_in_month(year, datetime.date.month)
  let day = case datetime.date.day > max_day {
    True -> max_day
    False -> datetime.date.day
  }

  DateTime(
    date: Date(year:, month: datetime.date.month, day: day),
    time: datetime.time,
  )
}

fn add_positive_minutes(datetime: DateTime, minutes: Int) -> DateTime {
  case minutes {
    0 -> datetime
    _ -> add_positive_minutes(add_one_minute(datetime), minutes - 1)
  }
}

fn add_negative_minutes(datetime: DateTime, minutes: Int) -> DateTime {
  case minutes {
    0 -> datetime
    _ -> add_negative_minutes(subtract_one_minute(datetime), minutes - 1)
  }
}

fn add_positive_days(datetime: DateTime, days: Int) -> DateTime {
  case days {
    0 -> datetime
    _ -> add_positive_days(add_one_day(datetime), days - 1)
  }
}

fn add_negative_days(datetime: DateTime, days: Int) -> DateTime {
  case days {
    0 -> datetime
    _ -> add_negative_days(subtract_one_day(datetime), days - 1)
  }
}

fn add_one_minute(datetime: DateTime) -> DateTime {
  case datetime.time.minute < 59 {
    True ->
      DateTime(
        date: datetime.date,
        time: Time(
          hour: datetime.time.hour,
          minute: datetime.time.minute + 1,
          second: datetime.time.second,
        ),
      )
    False ->
      case datetime.time.hour < 23 {
        True ->
          DateTime(
            date: datetime.date,
            time: Time(
              hour: datetime.time.hour + 1,
              minute: 0,
              second: datetime.time.second,
            ),
          )
        False ->
          DateTime(
            date: add_one_day(datetime).date,
            time: Time(hour: 0, minute: 0, second: datetime.time.second),
          )
      }
  }
}

fn subtract_one_minute(datetime: DateTime) -> DateTime {
  case datetime.time.minute > 0 {
    True ->
      DateTime(
        date: datetime.date,
        time: Time(
          hour: datetime.time.hour,
          minute: datetime.time.minute - 1,
          second: datetime.time.second,
        ),
      )
    False ->
      case datetime.time.hour > 0 {
        True ->
          DateTime(
            date: datetime.date,
            time: Time(
              hour: datetime.time.hour - 1,
              minute: 59,
              second: datetime.time.second,
            ),
          )
        False ->
          DateTime(
            date: subtract_one_day(datetime).date,
            time: Time(hour: 23, minute: 59, second: datetime.time.second),
          )
      }
  }
}

fn add_one_day(datetime: DateTime) -> DateTime {
  let max_day = days_in_month(datetime.date.year, datetime.date.month)

  case datetime.date.day < max_day {
    True ->
      DateTime(
        date: Date(
          year: datetime.date.year,
          month: datetime.date.month,
          day: datetime.date.day + 1,
        ),
        time: datetime.time,
      )
    False ->
      case datetime.date.month < 12 {
        True ->
          DateTime(
            date: Date(
              year: datetime.date.year,
              month: datetime.date.month + 1,
              day: 1,
            ),
            time: datetime.time,
          )
        False ->
          DateTime(
            date: Date(year: datetime.date.year + 1, month: 1, day: 1),
            time: datetime.time,
          )
      }
  }
}

fn subtract_one_day(datetime: DateTime) -> DateTime {
  case datetime.date.day > 1 {
    True ->
      DateTime(
        date: Date(
          year: datetime.date.year,
          month: datetime.date.month,
          day: datetime.date.day - 1,
        ),
        time: datetime.time,
      )
    False ->
      case datetime.date.month > 1 {
        True -> {
          let previous_month = datetime.date.month - 1
          DateTime(
            date: Date(
              year: datetime.date.year,
              month: previous_month,
              day: days_in_month(datetime.date.year, previous_month),
            ),
            time: datetime.time,
          )
        }
        False ->
          DateTime(
            date: Date(
              year: datetime.date.year - 1,
              month: 12,
              day: days_in_month(datetime.date.year - 1, 12),
            ),
            time: datetime.time,
          )
      }
  }
}

fn weekday_number(year: Int, month: Int, day: Int) -> Int {
  let adjusted_year = case month < 3 {
    True -> year - 1
    False -> year
  }

  modulo(
    adjusted_year
      + quotient(adjusted_year, 4)
      - quotient(adjusted_year, 100)
      + quotient(adjusted_year, 400)
      + month_offset(month)
      + day,
    7,
  )
}

fn month_offset(month: Int) -> Int {
  case month {
    1 -> 0
    2 -> 3
    3 -> 2
    4 -> 5
    5 -> 0
    6 -> 3
    7 -> 5
    8 -> 1
    9 -> 4
    10 -> 6
    11 -> 2
    12 -> 4
    _ -> 0
  }
}

fn quotient(dividend: Int, divisor: Int) -> Int {
  case int.divide(dividend, by: divisor) {
    Ok(result) -> result
    Error(_) -> 0
  }
}

fn modulo(dividend: Int, divisor: Int) -> Int {
  case int.modulo(dividend, by: divisor) {
    Ok(result) -> result
    Error(_) -> 0
  }
}
