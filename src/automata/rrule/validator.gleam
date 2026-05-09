import automata/internal/calendar
import automata/rrule/ast as rule_ast
import automata/schedule/ast as schedule_ast
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type Frequency {
  Daily
  Weekly
  Monthly
  Yearly
}

pub type WeekdaySpecifier {
  EveryWeekday(schedule_ast.Weekday)
  NthWeekday(Int, schedule_ast.Weekday)
}

pub type Until {
  UntilDate(schedule_ast.Date)
  UntilDateTime(schedule_ast.DateTime)
}

pub type EndCondition {
  Forever
  Count(Int)
  Until(Until)
}

pub type RulePart {
  FreqPart
  IntervalPart
  CountPart
  UntilPart
  ByDayPart
  ByMonthPart
  ByMonthDayPart
  ByHourPart
  ByMinutePart
}

/// An RRULE that has passed `validate/1`. `opaque` so the only way
/// to obtain a value is through validation, preventing callers from
/// forging "validated" inputs.
pub opaque type ValidRRule {
  ValidRRule(
    frequency: Frequency,
    interval: Int,
    end_condition: EndCondition,
    by_day: Option(List(WeekdaySpecifier)),
    by_month: Option(List(Int)),
    by_month_day: Option(List(Int)),
    by_hour: Option(List(Int)),
    by_minute: Option(List(Int)),
  )
}

pub fn frequency(spec: ValidRRule) -> Frequency {
  spec.frequency
}

pub fn interval(spec: ValidRRule) -> Int {
  spec.interval
}

pub fn end_condition(spec: ValidRRule) -> EndCondition {
  spec.end_condition
}

pub fn by_day(spec: ValidRRule) -> Option(List(WeekdaySpecifier)) {
  spec.by_day
}

pub fn by_month(spec: ValidRRule) -> Option(List(Int)) {
  spec.by_month
}

pub fn by_month_day(spec: ValidRRule) -> Option(List(Int)) {
  spec.by_month_day
}

pub fn by_hour(spec: ValidRRule) -> Option(List(Int)) {
  spec.by_hour
}

pub fn by_minute(spec: ValidRRule) -> Option(List(Int)) {
  spec.by_minute
}

pub type ValidationError {
  MissingPart(part: RulePart)
  DuplicatePart(part: RulePart)
  UnknownPart(name: String)
  UnsupportedPart(name: String)
  InvalidNumber(part: RulePart, value: String)
  InvalidPartValue(part: RulePart, value: String)
  InvalidList(part: RulePart, value: String)
  OutOfRange(part: RulePart, min: Int, max: Int, actual: Int)
  MustBePositive(part: RulePart, actual: Int)
  MutuallyExclusiveParts(left: RulePart, right: RulePart)
  NumericWeekdayRequiresMonthlyOrYearly(frequency: Frequency)
  ImpossibleDate(by_month: String, by_month_day: String)
  IncompatibleFrequencyAndPart(frequency: Frequency, part: RulePart)
}

type PartialRule {
  PartialRule(
    frequency: Option(Frequency),
    interval: Option(Int),
    end_condition: EndCondition,
    by_day: Option(List(WeekdaySpecifier)),
    by_month: Option(List(Int)),
    by_month_day: Option(List(Int)),
    by_hour: Option(List(Int)),
    by_minute: Option(List(Int)),
  )
}

pub fn validate(
  raw raw: rule_ast.RawRRule,
) -> Result(ValidRRule, ValidationError) {
  collect(raw.parts, empty_partial_rule())
}

pub fn to_string(spec: ValidRRule) -> String {
  let parts = ["FREQ=" <> frequency_to_string(spec.frequency)]

  let parts = case spec.end_condition {
    Forever -> parts
    Count(count) -> list.append(parts, ["COUNT=" <> int.to_string(count)])
    Until(until) -> list.append(parts, ["UNTIL=" <> until_to_string(until)])
  }

  let parts = case spec.interval == 1 {
    True -> parts
    False -> list.append(parts, ["INTERVAL=" <> int.to_string(spec.interval)])
  }

  let parts = append_weekday_part(parts, spec.by_day)
  let parts = append_int_part(parts, "BYMONTH", spec.by_month)
  let parts = append_int_part(parts, "BYMONTHDAY", spec.by_month_day)
  let parts = append_int_part(parts, "BYHOUR", spec.by_hour)
  let parts = append_int_part(parts, "BYMINUTE", spec.by_minute)

  string.join(parts, with: ";")
}

fn empty_partial_rule() -> PartialRule {
  PartialRule(
    frequency: None,
    interval: None,
    end_condition: Forever,
    by_day: None,
    by_month: None,
    by_month_day: None,
    by_hour: None,
    by_minute: None,
  )
}

fn collect(
  parts: List(rule_ast.RawRulePart),
  partial: PartialRule,
) -> Result(ValidRRule, ValidationError) {
  case parts {
    [] -> finalize(partial)
    [rule_ast.RawRulePart(name:, value:), ..rest] ->
      case apply_part(name, value, partial) {
        Ok(next) -> collect(rest, next)
        Error(error) -> Error(error)
      }
  }
}

fn apply_part(
  name: String,
  value: String,
  partial: PartialRule,
) -> Result(PartialRule, ValidationError) {
  case name {
    "FREQ" ->
      set_optional(
        partial.frequency,
        parse_frequency(value),
        FreqPart,
        fn(updated) { PartialRule(..partial, frequency: updated) },
      )
    "INTERVAL" ->
      set_optional(
        partial.interval,
        parse_positive_int(IntervalPart, value),
        IntervalPart,
        fn(updated) { PartialRule(..partial, interval: updated) },
      )
    "COUNT" ->
      case parse_positive_int(CountPart, value) {
        Error(error) -> Error(error)
        Ok(count) ->
          case partial.end_condition {
            Forever -> Ok(PartialRule(..partial, end_condition: Count(count)))
            Count(_) -> Error(DuplicatePart(part: CountPart))
            Until(_) ->
              Error(MutuallyExclusiveParts(left: CountPart, right: UntilPart))
          }
      }
    "UNTIL" ->
      case parse_until(value) {
        Error(error) -> Error(error)
        Ok(until) ->
          case partial.end_condition {
            Forever -> Ok(PartialRule(..partial, end_condition: Until(until)))
            Count(_) ->
              Error(MutuallyExclusiveParts(left: CountPart, right: UntilPart))
            Until(_) -> Error(DuplicatePart(part: UntilPart))
          }
      }
    "BYDAY" ->
      set_optional(
        partial.by_day,
        parse_weekday_specifiers(value),
        ByDayPart,
        fn(updated) { PartialRule(..partial, by_day: updated) },
      )
    "BYMONTH" ->
      set_optional(
        partial.by_month,
        parse_int_list(ByMonthPart, value, 1, 12, False),
        ByMonthPart,
        fn(updated) { PartialRule(..partial, by_month: updated) },
      )
    "BYMONTHDAY" ->
      set_optional(
        partial.by_month_day,
        parse_int_list(ByMonthDayPart, value, -31, 31, True),
        ByMonthDayPart,
        fn(updated) { PartialRule(..partial, by_month_day: updated) },
      )
    "BYHOUR" ->
      set_optional(
        partial.by_hour,
        parse_int_list(ByHourPart, value, 0, 23, False),
        ByHourPart,
        fn(updated) { PartialRule(..partial, by_hour: updated) },
      )
    "BYMINUTE" ->
      set_optional(
        partial.by_minute,
        parse_int_list(ByMinutePart, value, 0, 59, False),
        ByMinutePart,
        fn(updated) { PartialRule(..partial, by_minute: updated) },
      )
    "BYSECOND" -> Error(UnsupportedPart(name: "BYSECOND"))
    "BYYEARDAY" -> Error(UnsupportedPart(name: "BYYEARDAY"))
    "BYWEEKNO" -> Error(UnsupportedPart(name: "BYWEEKNO"))
    "BYSETPOS" -> Error(UnsupportedPart(name: "BYSETPOS"))
    "WKST" -> Error(UnsupportedPart(name: "WKST"))
    "BYEASTER" -> Error(UnsupportedPart(name: "BYEASTER"))
    _ -> Error(UnknownPart(name: name))
  }
}

fn set_optional(
  current: Option(a),
  parsed: Result(a, ValidationError),
  part: RulePart,
  setter: fn(Option(a)) -> PartialRule,
) -> Result(PartialRule, ValidationError) {
  case parsed {
    Error(error) -> Error(error)
    Ok(value) ->
      case current {
        None -> Ok(setter(Some(value)))
        Some(_) -> Error(DuplicatePart(part: part))
      }
  }
}

fn finalize(partial: PartialRule) -> Result(ValidRRule, ValidationError) {
  case partial.frequency {
    None -> Error(MissingPart(part: FreqPart))
    Some(frequency) -> {
      let spec =
        ValidRRule(
          frequency: frequency,
          interval: case partial.interval {
            None -> 1
            Some(interval) -> interval
          },
          end_condition: partial.end_condition,
          by_day: partial.by_day,
          by_month: partial.by_month,
          by_month_day: partial.by_month_day,
          by_hour: partial.by_hour,
          by_minute: partial.by_minute,
        )

      case validate_semantics(spec) {
        Ok(_) -> Ok(spec)
        Error(error) -> Error(error)
      }
    }
  }
}

fn validate_semantics(spec: ValidRRule) -> Result(Nil, ValidationError) {
  case validate_frequency_compatibility(spec) {
    Error(error) -> Error(error)
    Ok(_) ->
      case validate_weekday_ordinals(spec.frequency, spec.by_day) {
        Error(error) -> Error(error)
        Ok(_) ->
          case impossible_month_day(spec.by_month, spec.by_month_day) {
            True ->
              Error(
                ImpossibleDate(
                  by_month: case spec.by_month {
                    Some(values) -> int_list_to_string(values)
                    None -> "*"
                  },
                  by_month_day: case spec.by_month_day {
                    Some(values) -> int_list_to_string(values)
                    None -> "*"
                  },
                ),
              )
            False -> Ok(Nil)
          }
      }
  }
}

fn validate_frequency_compatibility(
  spec: ValidRRule,
) -> Result(Nil, ValidationError) {
  case spec.frequency, spec.by_month_day {
    Weekly, Some(_) ->
      Error(IncompatibleFrequencyAndPart(
        frequency: Weekly,
        part: ByMonthDayPart,
      ))
    _, _ -> Ok(Nil)
  }
}

fn validate_weekday_ordinals(
  frequency: Frequency,
  by_day: Option(List(WeekdaySpecifier)),
) -> Result(Nil, ValidationError) {
  case by_day {
    None -> Ok(Nil)
    Some(values) ->
      case
        list.any(values, fn(item) {
          case item {
            EveryWeekday(_) -> False
            NthWeekday(_, _) -> True
          }
        })
      {
        False -> Ok(Nil)
        True ->
          case frequency {
            Monthly -> validate_ordinal_range(values, 5)
            Yearly -> validate_ordinal_range(values, 53)
            _ ->
              Error(NumericWeekdayRequiresMonthlyOrYearly(frequency: frequency))
          }
      }
  }
}

fn validate_ordinal_range(
  values: List(WeekdaySpecifier),
  bound: Int,
) -> Result(Nil, ValidationError) {
  case values {
    [] -> Ok(Nil)
    [item, ..rest] ->
      case item {
        NthWeekday(ordinal, day) ->
          case ordinal_within_bound(ordinal, bound) {
            True -> validate_ordinal_range(rest, bound)
            False ->
              Error(InvalidPartValue(
                part: ByDayPart,
                value: int.to_string(ordinal) <> weekday_to_string(day),
              ))
          }
        EveryWeekday(_) -> validate_ordinal_range(rest, bound)
      }
  }
}

fn ordinal_within_bound(ordinal: Int, bound: Int) -> Bool {
  ordinal != 0 && ordinal >= 0 - bound && ordinal <= bound
}

fn impossible_month_day(
  by_month: Option(List(Int)),
  by_month_day: Option(List(Int)),
) -> Bool {
  case by_month, by_month_day {
    Some(months), Some(days) ->
      !list.any(months, fn(month) {
        let maximum = calendar.days_in_month(2024, month)
        list.any(days, fn(day) { day_matches_month_day(day, maximum) })
        || list.any(days, fn(day) {
          day_matches_month_day(day, calendar.days_in_month(2025, month))
        })
      })
    _, _ -> False
  }
}

fn day_matches_month_day(day: Int, maximum: Int) -> Bool {
  case day > 0 {
    True -> day <= maximum
    False -> 0 - day <= maximum
  }
}

fn parse_frequency(value: String) -> Result(Frequency, ValidationError) {
  case string.uppercase(value) {
    "DAILY" -> Ok(Daily)
    "WEEKLY" -> Ok(Weekly)
    "MONTHLY" -> Ok(Monthly)
    "YEARLY" -> Ok(Yearly)
    _ -> Error(InvalidPartValue(part: FreqPart, value: value))
  }
}

fn parse_positive_int(
  part: RulePart,
  value: String,
) -> Result(Int, ValidationError) {
  case int.parse(value) {
    Error(_) -> Error(InvalidNumber(part: part, value: value))
    Ok(number) ->
      case number > 0 {
        True -> Ok(number)
        False -> Error(MustBePositive(part: part, actual: number))
      }
  }
}

fn parse_int_list(
  part: RulePart,
  value: String,
  min: Int,
  max: Int,
  reject_zero: Bool,
) -> Result(List(Int), ValidationError) {
  case list.any(string.split(value, on: ","), string.is_empty) {
    True -> Error(InvalidList(part: part, value: value))
    False ->
      parse_int_items(
        string.split(value, on: ","),
        part,
        min,
        max,
        reject_zero,
        [],
      )
  }
}

fn parse_int_items(
  values: List(String),
  part: RulePart,
  min: Int,
  max: Int,
  reject_zero: Bool,
  acc: List(Int),
) -> Result(List(Int), ValidationError) {
  case values {
    [] -> Ok(dedup_sort(list.reverse(acc), []))
    [value, ..rest] ->
      case int.parse(value) {
        Error(_) -> Error(InvalidNumber(part: part, value: value))
        Ok(number) ->
          case reject_zero && number == 0 {
            True -> Error(InvalidPartValue(part: part, value: value))
            False ->
              case number < min || number > max {
                True ->
                  Error(OutOfRange(
                    part: part,
                    min: min,
                    max: max,
                    actual: number,
                  ))
                False ->
                  parse_int_items(rest, part, min, max, reject_zero, [
                    number,
                    ..acc
                  ])
              }
          }
      }
  }
}

fn parse_weekday_specifiers(
  value: String,
) -> Result(List(WeekdaySpecifier), ValidationError) {
  case list.any(string.split(value, on: ","), string.is_empty) {
    True -> Error(InvalidList(part: ByDayPart, value: value))
    False -> collect_weekdays(string.split(value, on: ","), [], value)
  }
}

fn collect_weekdays(
  values: List(String),
  acc: List(WeekdaySpecifier),
  original: String,
) -> Result(List(WeekdaySpecifier), ValidationError) {
  case values {
    [] -> Ok(list.reverse(acc))
    [value, ..rest] ->
      case parse_weekday_specifier(value) {
        Ok(item) -> collect_weekdays(rest, [item, ..acc], original)
        Error(Nil) -> Error(InvalidPartValue(part: ByDayPart, value: original))
      }
  }
}

fn parse_weekday_specifier(value: String) -> Result(WeekdaySpecifier, Nil) {
  let upper = string.uppercase(value)
  let length = string.length(upper)

  case length < 2 {
    True -> Error(Nil)
    False -> {
      let prefix_length = length - 2
      let prefix = string.slice(from: upper, at_index: 0, length: prefix_length)
      let suffix = string.slice(from: upper, at_index: prefix_length, length: 2)

      case parse_weekday(suffix) {
        Error(Nil) -> Error(Nil)
        Ok(weekday) ->
          case prefix {
            "" -> Ok(EveryWeekday(weekday))
            _ ->
              case int.parse(prefix) {
                Ok(ordinal) ->
                  case ordinal == 0 {
                    True -> Error(Nil)
                    False -> Ok(NthWeekday(ordinal, weekday))
                  }
                Error(_) -> Error(Nil)
              }
          }
      }
    }
  }
}

fn parse_weekday(value: String) -> Result(schedule_ast.Weekday, Nil) {
  case value {
    "MO" -> Ok(schedule_ast.Monday)
    "TU" -> Ok(schedule_ast.Tuesday)
    "WE" -> Ok(schedule_ast.Wednesday)
    "TH" -> Ok(schedule_ast.Thursday)
    "FR" -> Ok(schedule_ast.Friday)
    "SA" -> Ok(schedule_ast.Saturday)
    "SU" -> Ok(schedule_ast.Sunday)
    _ -> Error(Nil)
  }
}

fn parse_until(value: String) -> Result(Until, ValidationError) {
  case string.length(value) {
    8 ->
      case parse_date(value) {
        Ok(date) -> Ok(UntilDate(date))
        Error(error) -> Error(error)
      }
    16 ->
      case
        string.slice(from: value, at_index: 8, length: 1) == "T"
        && string.slice(from: value, at_index: 15, length: 1) == "Z"
      {
        False -> Error(InvalidPartValue(part: UntilPart, value: value))
        True ->
          case parse_datetime(value) {
            Ok(datetime) -> Ok(UntilDateTime(datetime))
            Error(error) -> Error(error)
          }
      }
    _ -> Error(InvalidPartValue(part: UntilPart, value: value))
  }
}

fn parse_date(value: String) -> Result(schedule_ast.Date, ValidationError) {
  case parse_fixed_int(value, 0, 4) {
    Error(_) -> Error(InvalidPartValue(part: UntilPart, value: value))
    Ok(year) ->
      case parse_fixed_int(value, 4, 2) {
        Error(_) -> Error(InvalidPartValue(part: UntilPart, value: value))
        Ok(month) ->
          case parse_fixed_int(value, 6, 2) {
            Error(_) -> Error(InvalidPartValue(part: UntilPart, value: value))
            Ok(day) -> {
              let date = schedule_ast.Date(year:, month:, day:)
              case calendar.is_valid_date(date) {
                True -> Ok(date)
                False -> Error(InvalidPartValue(part: UntilPart, value: value))
              }
            }
          }
      }
  }
}

fn parse_datetime(
  value: String,
) -> Result(schedule_ast.DateTime, ValidationError) {
  case parse_date(string.slice(from: value, at_index: 0, length: 8)) {
    Error(error) -> Error(error)
    Ok(date) ->
      case parse_fixed_int(value, 9, 2) {
        Error(_) -> Error(InvalidPartValue(part: UntilPart, value: value))
        Ok(hour) ->
          case parse_fixed_int(value, 11, 2) {
            Error(_) -> Error(InvalidPartValue(part: UntilPart, value: value))
            Ok(minute) ->
              case parse_fixed_int(value, 13, 2) {
                Error(_) ->
                  Error(InvalidPartValue(part: UntilPart, value: value))
                Ok(second) -> {
                  let datetime =
                    schedule_ast.DateTime(
                      date: date,
                      time: schedule_ast.Time(
                        hour: hour,
                        minute: minute,
                        second: second,
                      ),
                    )
                  case calendar.is_valid_datetime(datetime) {
                    True -> Ok(datetime)
                    False ->
                      Error(InvalidPartValue(part: UntilPart, value: value))
                  }
                }
              }
          }
      }
  }
}

fn parse_fixed_int(value: String, start: Int, length: Int) -> Result(Int, Nil) {
  int.parse(string.slice(from: value, at_index: start, length: length))
}

fn append_int_part(
  parts: List(String),
  name: String,
  values: Option(List(Int)),
) -> List(String) {
  case values {
    None -> parts
    Some(items) ->
      list.append(parts, [name <> "=" <> int_list_to_string(items)])
  }
}

fn append_weekday_part(
  parts: List(String),
  values: Option(List(WeekdaySpecifier)),
) -> List(String) {
  case values {
    None -> parts
    Some(items) ->
      list.append(parts, [
        "BYDAY="
        <> string.join(list.map(items, weekday_specifier_to_string), with: ","),
      ])
  }
}

fn weekday_specifier_to_string(specifier: WeekdaySpecifier) -> String {
  case specifier {
    EveryWeekday(day) -> weekday_to_string(day)
    NthWeekday(ordinal, day) -> int.to_string(ordinal) <> weekday_to_string(day)
  }
}

fn weekday_to_string(day: schedule_ast.Weekday) -> String {
  case day {
    schedule_ast.Monday -> "MO"
    schedule_ast.Tuesday -> "TU"
    schedule_ast.Wednesday -> "WE"
    schedule_ast.Thursday -> "TH"
    schedule_ast.Friday -> "FR"
    schedule_ast.Saturday -> "SA"
    schedule_ast.Sunday -> "SU"
  }
}

fn frequency_to_string(frequency: Frequency) -> String {
  case frequency {
    Daily -> "DAILY"
    Weekly -> "WEEKLY"
    Monthly -> "MONTHLY"
    Yearly -> "YEARLY"
  }
}

fn until_to_string(until: Until) -> String {
  case until {
    UntilDate(date) -> date_to_string(date)
    UntilDateTime(datetime) -> datetime_to_string(datetime)
  }
}

fn date_to_string(date: schedule_ast.Date) -> String {
  pad4(date.year) <> pad2(date.month) <> pad2(date.day)
}

fn datetime_to_string(datetime: schedule_ast.DateTime) -> String {
  date_to_string(datetime.date)
  <> "T"
  <> pad2(datetime.time.hour)
  <> pad2(datetime.time.minute)
  <> pad2(datetime.time.second)
  <> "Z"
}

fn int_list_to_string(items: List(Int)) -> String {
  string.join(list.map(items, int.to_string), with: ",")
}

fn dedup_sort(values: List(Int), acc: List(Int)) -> List(Int) {
  case list.sort(values, by: int.compare) {
    [] -> list.reverse(acc)
    [first, ..rest] -> dedup_sorted(rest, first, [first, ..acc])
  }
}

fn dedup_sorted(rest: List(Int), previous: Int, acc: List(Int)) -> List(Int) {
  case rest {
    [] -> list.reverse(acc)
    [value, ..tail] ->
      case value == previous {
        True -> dedup_sorted(tail, previous, acc)
        False -> dedup_sorted(tail, value, [value, ..acc])
      }
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
