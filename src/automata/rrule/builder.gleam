import automata/rrule/parser
import automata/rrule/validator
import automata/schedule/ast.{
  type Date, type DateTime, type Weekday, Friday, Monday, Saturday, Sunday,
  Thursday, Tuesday, Wednesday,
}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

/// Mutable-style RRULE builder. `opaque` so the only way to populate
/// fields is the `with_*` API and the only way to extract a validated
/// value is `build/1`.
pub opaque type Builder {
  Builder(
    frequency: validator.Frequency,
    interval: Int,
    end_condition: validator.EndCondition,
    by_day: Option(List(validator.WeekdaySpecifier)),
    by_month: Option(List(Int)),
    by_month_day: Option(List(Int)),
    by_hour: Option(List(Int)),
    by_minute: Option(List(Int)),
  )
}

pub fn builder(frequency frequency: validator.Frequency) -> Builder {
  Builder(
    frequency: frequency,
    interval: 1,
    end_condition: validator.Forever,
    by_day: None,
    by_month: None,
    by_month_day: None,
    by_hour: None,
    by_minute: None,
  )
}

pub fn weekday(day day: Weekday) -> validator.WeekdaySpecifier {
  validator.EveryWeekday(day)
}

pub fn nth_weekday(
  ordinal ordinal: Int,
  day day: Weekday,
) -> validator.WeekdaySpecifier {
  validator.NthWeekday(ordinal, day)
}

pub fn with_interval(builder: Builder, interval: Int) -> Builder {
  Builder(..builder, interval:)
}

pub fn with_count(builder: Builder, count: Int) -> Builder {
  Builder(..builder, end_condition: validator.Count(count))
}

pub fn with_until_date(builder: Builder, until: Date) -> Builder {
  Builder(..builder, end_condition: validator.Until(validator.UntilDate(until)))
}

pub fn with_until_datetime(builder: Builder, until: DateTime) -> Builder {
  Builder(
    ..builder,
    end_condition: validator.Until(validator.UntilDateTime(until)),
  )
}

pub fn without_end_condition(builder: Builder) -> Builder {
  Builder(..builder, end_condition: validator.Forever)
}

pub fn with_by_day(
  builder: Builder,
  values: List(validator.WeekdaySpecifier),
) -> Builder {
  Builder(..builder, by_day: Some(values))
}

pub fn with_by_month(builder: Builder, values: List(Int)) -> Builder {
  Builder(..builder, by_month: Some(values))
}

pub fn with_by_month_day(builder: Builder, values: List(Int)) -> Builder {
  Builder(..builder, by_month_day: Some(values))
}

pub fn with_by_hour(builder: Builder, values: List(Int)) -> Builder {
  Builder(..builder, by_hour: Some(values))
}

pub fn with_by_minute(builder: Builder, values: List(Int)) -> Builder {
  Builder(..builder, by_minute: Some(values))
}

pub fn build(
  builder builder: Builder,
) -> Result(validator.ValidRRule, validator.ValidationError) {
  case validate_inputs(builder) {
    Error(error) -> Error(error)
    Ok(_) -> {
      let rendered = render(builder)

      case parser.parse(input: rendered) {
        Ok(raw) -> validator.validate(raw)
        Error(error) -> Error(translate_parser_error(error))
      }
    }
  }
}

fn validate_inputs(builder: Builder) -> Result(Nil, validator.ValidationError) {
  use _ <- result.try(validate_interval(builder.interval))
  use _ <- result.try(validate_end_condition(builder.end_condition))
  use _ <- result.try(validate_optional_list(
    builder.by_day,
    validator.ByDayPart,
  ))
  use _ <- result.try(validate_weekday_specifiers(builder.by_day))
  use _ <- result.try(validate_optional_list(
    builder.by_month,
    validator.ByMonthPart,
  ))
  use _ <- result.try(validate_optional_list(
    builder.by_month_day,
    validator.ByMonthDayPart,
  ))
  use _ <- result.try(validate_optional_list(
    builder.by_hour,
    validator.ByHourPart,
  ))
  validate_optional_list(builder.by_minute, validator.ByMinutePart)
}

fn validate_interval(interval: Int) -> Result(Nil, validator.ValidationError) {
  case interval > 0 {
    True -> Ok(Nil)
    False ->
      Error(validator.MustBePositive(
        part: validator.IntervalPart,
        actual: interval,
      ))
  }
}

fn validate_end_condition(
  end_condition: validator.EndCondition,
) -> Result(Nil, validator.ValidationError) {
  case end_condition {
    validator.Count(count) ->
      case count > 0 {
        True -> Ok(Nil)
        False ->
          Error(validator.MustBePositive(
            part: validator.CountPart,
            actual: count,
          ))
      }
    _ -> Ok(Nil)
  }
}

fn validate_optional_list(
  values: Option(List(a)),
  part: validator.RulePart,
) -> Result(Nil, validator.ValidationError) {
  case values {
    None -> Ok(Nil)
    Some([]) -> Error(validator.InvalidList(part: part, value: ""))
    Some(_) -> Ok(Nil)
  }
}

fn validate_weekday_specifiers(
  values: Option(List(validator.WeekdaySpecifier)),
) -> Result(Nil, validator.ValidationError) {
  case values {
    None -> Ok(Nil)
    Some(items) -> check_weekday_items(items)
  }
}

fn check_weekday_items(
  items: List(validator.WeekdaySpecifier),
) -> Result(Nil, validator.ValidationError) {
  case items {
    [] -> Ok(Nil)
    [item, ..rest] ->
      case item {
        validator.NthWeekday(0, day) ->
          Error(validator.InvalidPartValue(
            part: validator.ByDayPart,
            value: "0" <> weekday_to_string(day),
          ))
        _ -> check_weekday_items(rest)
      }
  }
}

fn translate_parser_error(error: parser.ParseError) -> validator.ValidationError {
  case error {
    parser.InvalidRule(value:) ->
      validator.InvalidPartValue(part: validator.FreqPart, value: value)
    parser.InvalidPartSyntax(value:) ->
      validator.InvalidPartValue(part: validator.FreqPart, value: value)
    parser.EmptyPart(value:) ->
      validator.InvalidPartValue(part: validator.FreqPart, value: value)
  }
}

fn render(builder: Builder) -> String {
  let parts = ["FREQ=" <> frequency_to_string(builder.frequency)]
  let parts = case builder.end_condition {
    validator.Forever -> parts
    validator.Count(count) ->
      list.append(parts, ["COUNT=" <> int.to_string(count)])
    validator.Until(until) ->
      list.append(parts, ["UNTIL=" <> until_to_string(until)])
  }
  let parts = case builder.interval == 1 {
    True -> parts
    False ->
      list.append(parts, ["INTERVAL=" <> int.to_string(builder.interval)])
  }
  let parts = append_weekday_part(parts, builder.by_day)
  let parts = append_int_part(parts, "BYMONTH", builder.by_month)
  let parts = append_int_part(parts, "BYMONTHDAY", builder.by_month_day)
  let parts = append_int_part(parts, "BYHOUR", builder.by_hour)
  let parts = append_int_part(parts, "BYMINUTE", builder.by_minute)

  string.join(parts, with: ";")
}

fn append_int_part(
  parts: List(String),
  name: String,
  values: Option(List(Int)),
) -> List(String) {
  case values {
    None -> parts
    Some(items) ->
      list.append(parts, [
        name <> "=" <> string.join(list.map(items, int.to_string), with: ","),
      ])
  }
}

fn append_weekday_part(
  parts: List(String),
  values: Option(List(validator.WeekdaySpecifier)),
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

fn weekday_specifier_to_string(specifier: validator.WeekdaySpecifier) -> String {
  case specifier {
    validator.EveryWeekday(day) -> weekday_to_string(day)
    validator.NthWeekday(ordinal, day) ->
      int.to_string(ordinal) <> weekday_to_string(day)
  }
}

fn weekday_to_string(day: Weekday) -> String {
  case day {
    Monday -> "MO"
    Tuesday -> "TU"
    Wednesday -> "WE"
    Thursday -> "TH"
    Friday -> "FR"
    Saturday -> "SA"
    Sunday -> "SU"
  }
}

fn frequency_to_string(frequency: validator.Frequency) -> String {
  case frequency {
    validator.Daily -> "DAILY"
    validator.Weekly -> "WEEKLY"
    validator.Monthly -> "MONTHLY"
    validator.Yearly -> "YEARLY"
  }
}

fn until_to_string(until: validator.Until) -> String {
  case until {
    validator.UntilDate(date) -> date_to_string(date)
    validator.UntilDateTime(datetime) -> datetime_to_string(datetime)
  }
}

fn date_to_string(date: Date) -> String {
  pad4(date.year) <> pad2(date.month) <> pad2(date.day)
}

fn datetime_to_string(datetime: DateTime) -> String {
  date_to_string(datetime.date)
  <> "T"
  <> pad2(datetime.time.hour)
  <> pad2(datetime.time.minute)
  <> pad2(datetime.time.second)
  <> "Z"
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
