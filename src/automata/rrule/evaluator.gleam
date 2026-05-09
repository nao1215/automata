import automata/internal/calendar
import automata/rrule/normalize.{type RRulePlan}
import automata/rrule/validator
import automata/schedule/ast.{
  type Date, type DateTime, type Weekday, Date, DateTime, Friday, Monday,
  Saturday, Sunday, Thursday, Time, Tuesday, Wednesday,
}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}

pub fn matches(plan plan: RRulePlan, at at: DateTime) -> Bool {
  case calendar.less_than(at, plan.anchor) {
    True -> False
    False ->
      case within_until(plan.end_condition, at) {
        False -> False
        True ->
          case base_match(plan, at) {
            False -> False
            True ->
              case plan.end_condition {
                validator.Count(limit) ->
                  occurrence_index(plan, at, 0, plan.anchor) <= limit
                _ -> True
              }
          }
      }
  }
}

pub fn first_time_on_day(plan: RRulePlan, date: Date) -> DateTime {
  DateTime(
    date: date,
    time: Time(
      hour: list_first(plan.by_hour),
      minute: list_first(plan.by_minute),
      second: plan.second,
    ),
  )
}

pub fn next_time_on_day(
  plan: RRulePlan,
  date: Date,
  search: DateTime,
) -> Option(DateTime) {
  find_time(plan.by_hour, plan.by_minute, date, plan.second, search)
}

pub fn day_matches(plan: RRulePlan, date: Date) -> Bool {
  let datetime = DateTime(date:, time: Time(hour: 0, minute: 0, second: 0))
  let month_match = case plan.by_month {
    None -> True
    Some(values) -> list.any(values, fn(item) { item == date.month })
  }
  let month_day_match = month_day_matches(plan.by_month_day, date)
  let weekday_match = weekday_matches(plan, plan.by_day, datetime)

  month_match
  && case plan.by_month_day, plan.by_day {
    Some(_), Some(_) -> month_day_match && weekday_match
    Some(_), None -> month_day_match
    None, Some(_) -> weekday_match
    None, None -> True
  }
}

fn base_match(plan: RRulePlan, at: DateTime) -> Bool {
  aligned(plan, at)
  && day_matches(plan, at.date)
  && list.any(plan.by_hour, fn(hour) { hour == at.time.hour })
  && list.any(plan.by_minute, fn(minute) { minute == at.time.minute })
  && at.time.second == plan.second
}

fn aligned(plan: RRulePlan, at: DateTime) -> Bool {
  case plan.frequency {
    validator.Daily -> modulo(days_between(plan.anchor, at), plan.interval) == 0
    validator.Weekly ->
      modulo(weeks_between(plan.anchor, at), plan.interval) == 0
    validator.Monthly ->
      modulo(months_between(plan.anchor, at), plan.interval) == 0
    validator.Yearly ->
      modulo(at.date.year - plan.anchor.date.year, plan.interval) == 0
  }
}

fn within_until(end_condition: validator.EndCondition, at: DateTime) -> Bool {
  case end_condition {
    validator.Until(until) ->
      case until {
        validator.UntilDate(date) ->
          calendar.less_or_equal(at, date_to_datetime(date))
        validator.UntilDateTime(limit) -> calendar.less_or_equal(at, limit)
      }
    _ -> True
  }
}

fn date_to_datetime(date: Date) -> DateTime {
  DateTime(date:, time: Time(hour: 23, minute: 59, second: 59))
}

fn occurrence_index(
  plan: RRulePlan,
  target: DateTime,
  count: Int,
  search: DateTime,
) -> Int {
  case next_occurrence(plan, search: search, guard: 0) {
    None -> count
    Some(found) ->
      case calendar.compare(found, target) {
        Lt ->
          occurrence_index(
            plan,
            target,
            count + 1,
            calendar.add_seconds(found, 1),
          )
        Eq -> count + 1
        Gt -> count
      }
  }
}

pub fn yielded_before(plan plan: RRulePlan, cursor cursor: DateTime) -> Int {
  case calendar.less_than(cursor, plan.anchor) {
    True -> 0
    False ->
      occurrence_index(plan, calendar.add_seconds(cursor, -1), 0, plan.anchor)
  }
}

pub fn next_occurrence(
  plan: RRulePlan,
  search search: DateTime,
  guard guard: Int,
) -> Option(DateTime) {
  case guard > 150_000 {
    True -> None
    False -> {
      let start = case calendar.less_than(search, plan.anchor) {
        True -> plan.anchor
        False -> search
      }

      case within_until(plan.end_condition, start) {
        False -> None
        True ->
          case day_matches(plan, start.date) && aligned(plan, start) {
            True ->
              case next_time_on_day(plan, start.date, start) {
                Some(found) ->
                  case within_until(plan.end_condition, found) {
                    True -> Some(found)
                    False -> None
                  }
                None ->
                  next_occurrence(
                    plan,
                    search: calendar.next_day(start),
                    guard: guard + 1,
                  )
              }
            False ->
              next_occurrence(
                plan,
                search: calendar.next_day(start),
                guard: guard + 1,
              )
          }
      }
    }
  }
}

fn month_day_matches(values: Option(List(Int)), date: Date) -> Bool {
  case values {
    None -> True
    Some(items) -> {
      let maximum = calendar.days_in_month(date.year, date.month)
      list.any(items, fn(item) {
        case item > 0 {
          True -> item == date.day
          False -> maximum + item + 1 == date.day
        }
      })
    }
  }
}

fn weekday_matches(
  plan: RRulePlan,
  values: Option(List(validator.WeekdaySpecifier)),
  at: DateTime,
) -> Bool {
  case values {
    None -> True
    Some(items) -> {
      let actual = calendar.weekday(at)
      list.any(items, fn(item) {
        weekday_specifier_matches(plan, item, actual, at.date)
      })
    }
  }
}

fn weekday_specifier_matches(
  plan: RRulePlan,
  specifier: validator.WeekdaySpecifier,
  actual: Weekday,
  date: Date,
) -> Bool {
  case specifier {
    validator.EveryWeekday(expected) -> expected == actual
    validator.NthWeekday(ordinal, expected) ->
      expected == actual && nth_weekday_matches(plan, ordinal, expected, date)
  }
}

fn nth_weekday_matches(
  plan: RRulePlan,
  ordinal: Int,
  weekday: Weekday,
  date: Date,
) -> Bool {
  let occurrences = case nth_scope(plan) {
    YearScope -> weekday_occurrences_in_year(weekday, date.year)
    MonthScope -> weekday_occurrences_in_month(weekday, date.year, date.month)
  }

  case ordinal > 0 {
    True ->
      case list.drop(occurrences, ordinal - 1) {
        [match, ..] -> match.month == date.month && match.day == date.day
        [] -> False
      }
    False ->
      case list.drop(list.reverse(occurrences), { 0 - ordinal } - 1) {
        [match, ..] -> match.month == date.month && match.day == date.day
        [] -> False
      }
  }
}

type NthScope {
  MonthScope
  YearScope
}

type Occurrence {
  Occurrence(month: Int, day: Int)
}

fn nth_scope(plan: RRulePlan) -> NthScope {
  case plan.frequency, plan.by_month {
    validator.Yearly, None -> YearScope
    _, _ -> MonthScope
  }
}

fn weekday_occurrences_in_month(
  weekday: Weekday,
  year: Int,
  month: Int,
) -> List(Occurrence) {
  weekday_occurrences_in_month_loop(weekday, year, month, 1, [])
}

fn weekday_occurrences_in_month_loop(
  weekday: Weekday,
  year: Int,
  month: Int,
  day: Int,
  acc: List(Occurrence),
) -> List(Occurrence) {
  let maximum = calendar.days_in_month(year, month)

  case day > maximum {
    True -> list.reverse(acc)
    False -> {
      let datetime =
        DateTime(
          date: Date(year:, month:, day: day),
          time: Time(hour: 0, minute: 0, second: 0),
        )
      case calendar.weekday(datetime) == weekday {
        True ->
          weekday_occurrences_in_month_loop(weekday, year, month, day + 1, [
            Occurrence(month:, day:),
            ..acc
          ])
        False ->
          weekday_occurrences_in_month_loop(weekday, year, month, day + 1, acc)
      }
    }
  }
}

fn weekday_occurrences_in_year(weekday: Weekday, year: Int) -> List(Occurrence) {
  weekday_occurrences_in_year_loop(weekday, year, 1, [])
}

fn weekday_occurrences_in_year_loop(
  weekday: Weekday,
  year: Int,
  month: Int,
  acc: List(Occurrence),
) -> List(Occurrence) {
  case month > 12 {
    True -> list.reverse(acc)
    False -> {
      let month_occurrences = weekday_occurrences_in_month(weekday, year, month)
      weekday_occurrences_in_year_loop(
        weekday,
        year,
        month + 1,
        list.fold(month_occurrences, acc, fn(carry, item) { [item, ..carry] }),
      )
    }
  }
}

fn find_time(
  hours: List(Int),
  minutes: List(Int),
  date: Date,
  second: Int,
  search: DateTime,
) -> Option(DateTime) {
  case hours {
    [] -> None
    [hour, ..rest_hours] ->
      case hour < search.time.hour {
        True -> find_time(rest_hours, minutes, date, second, search)
        False ->
          case find_minute(hour, minutes, date, second, search) {
            Some(found) -> Some(found)
            None -> find_time(rest_hours, minutes, date, second, search)
          }
      }
  }
}

fn find_minute(
  hour: Int,
  minutes: List(Int),
  date: Date,
  second: Int,
  search: DateTime,
) -> Option(DateTime) {
  case minutes {
    [] -> None
    [minute, ..rest] -> {
      let candidate =
        DateTime(date:, time: Time(hour:, minute:, second: second))
      case calendar.less_than(candidate, search) {
        True -> find_minute(hour, rest, date, second, search)
        False -> Some(candidate)
      }
    }
  }
}

fn list_first(values: List(Int)) -> Int {
  case values {
    [first, ..] -> first
    [] -> 0
  }
}

fn days_between(from: DateTime, to: DateTime) -> Int {
  days_since_epoch(to.date) - days_since_epoch(from.date)
}

fn weeks_between(from: DateTime, to: DateTime) -> Int {
  quotient(days_between(start_of_week(from), start_of_week(to)), 7)
}

fn months_between(from: DateTime, to: DateTime) -> Int {
  { to.date.year * 12 + to.date.month }
  - { from.date.year * 12 + from.date.month }
}

fn start_of_week(datetime: DateTime) -> DateTime {
  calendar.add_days(
    DateTime(date: datetime.date, time: Time(hour: 0, minute: 0, second: 0)),
    0 - weekday_offset(calendar.weekday(datetime)),
  )
}

fn weekday_offset(day: Weekday) -> Int {
  case day {
    Monday -> 0
    Tuesday -> 1
    Wednesday -> 2
    Thursday -> 3
    Friday -> 4
    Saturday -> 5
    Sunday -> 6
  }
}

fn days_since_epoch(date: Date) -> Int {
  days_before_year(date.year)
  + days_before_month(date.year, date.month)
  + date.day
}

fn days_before_year(year: Int) -> Int {
  let previous = year - 1
  { previous * 365 }
  + quotient(previous, 4)
  - quotient(previous, 100)
  + quotient(previous, 400)
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
        acc + calendar.days_in_month(year, month),
      )
  }
}

fn modulo(dividend: Int, divisor: Int) -> Int {
  case int.modulo(dividend, by: divisor) {
    Ok(result) -> result
    Error(_) -> 0
  }
}

fn quotient(dividend: Int, divisor: Int) -> Int {
  case int.divide(dividend, by: divisor) {
    Ok(result) -> result
    Error(_) -> 0
  }
}
