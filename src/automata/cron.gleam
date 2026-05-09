import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// Supported cron dialects.
pub type Dialect {
  Unix
  AwsEventBridge
}

/// Parse strategy used to choose how an input string is interpreted.
pub type ParseStyle {
  Auto
  UnixStyle
  AwsEventBridgeStyle
}

/// Field identifiers used in parse errors.
pub type Field {
  Minute
  Hour
  DayOfMonth
  Month
  DayOfWeek
  Year
}

/// Parse and validation errors for cron expressions.
pub type ParseError {
  InvalidExpression(value: String)
  InvalidFieldCount(min_expected: Int, max_expected: Int, actual: Int)
  EmptyField(field: Field)
  InvalidNumber(field: Field, value: String)
  InvalidAlias(field: Field, value: String)
  OutOfRange(field: Field, min: Int, max: Int, actual: Int)
  InvalidStep(field: Field, value: String)
  InvalidRange(field: Field, value: String)
  InvalidList(field: Field, value: String)
  UnsupportedSyntax(field: Field, value: String)
  InvalidDayFieldCombination(day_of_month: String, day_of_week: String)
  ImpossibleDate(day_of_month: String, month: String, year: Option(String))
  ImpossibleWeekdayOccurrence(
    day_of_week: String,
    month: String,
    year: Option(String),
  )
}

/// Generic cron field used by minute, hour, month, and year.
pub type BasicField {
  All
  Values(List(BasicItem))
}

/// One selectable item within a generic cron field.
pub type BasicItem {
  Exact(Int)
  Range(Int, Int)
  Step(StepBase, Int)
}

/// Base expression used by a stepped cron item.
pub type StepBase {
  StepAll
  StepExact(Int)
  StepRange(Int, Int)
}

/// Day-of-month cron field.
pub type DayOfMonthField {
  AnyDayOfMonth
  NoSpecificDayOfMonth
  LastDayOfMonth
  NearestWeekday(Int)
  DayOfMonthValues(List(BasicItem))
}

/// Day-of-week cron field.
pub type DayOfWeekField {
  AnyDayOfWeek
  NoSpecificDayOfWeek
  LastWeekdayOfMonth(Int)
  NthWeekdayOfMonth(Int, Int)
  DayOfWeekValues(List(BasicItem))
}

/// Parsed cron expression.
pub type CronExpression {
  CronExpression(
    dialect: Dialect,
    minute: BasicField,
    hour: BasicField,
    day_of_month: DayOfMonthField,
    month: BasicField,
    day_of_week: DayOfWeekField,
    year: Option(BasicField),
  )
}

/// Immutable builder for constructing cron expressions without
/// parsing a string.
pub opaque type Builder {
  Builder(
    dialect: Dialect,
    minute: BasicField,
    hour: BasicField,
    day_of_month: DayOfMonthField,
    month: BasicField,
    day_of_week: DayOfWeekField,
    year: Option(BasicField),
  )
}

type AliasMode {
  NoAliases
  MonthAliases
  UnixDayAliases
  AwsDayAliases
}

/// Create a builder with the default field values for the selected
/// dialect.
pub fn builder(dialect dialect: Dialect) -> Builder {
  case dialect {
    Unix ->
      Builder(
        dialect: Unix,
        minute: All,
        hour: All,
        day_of_month: AnyDayOfMonth,
        month: All,
        day_of_week: AnyDayOfWeek,
        year: None,
      )
    AwsEventBridge ->
      Builder(
        dialect: AwsEventBridge,
        minute: All,
        hour: All,
        day_of_month: AnyDayOfMonth,
        month: All,
        day_of_week: NoSpecificDayOfWeek,
        year: Some(All),
      )
  }
}

/// Match every value in a basic cron field.
pub fn any() -> BasicField {
  All
}

/// Match exactly one value in a basic cron field.
pub fn at(value value: Int) -> BasicField {
  Values([Exact(value)])
}

/// Match a range in a basic cron field.
pub fn between(from start: Int, to end: Int) -> BasicField {
  Values([Range(start, end)])
}

/// Match every `step` values in a basic cron field.
pub fn every(step step: Int) -> BasicField {
  Values([Step(StepAll, step)])
}

/// Match every `step` values starting from one value.
pub fn every_from(start start: Int, step step: Int) -> BasicField {
  Values([Step(StepExact(start), step)])
}

/// Match every `step` values within a range.
pub fn every_between(from start: Int, to end: Int, step step: Int) -> BasicField {
  Values([Step(StepRange(start, end), step)])
}

/// Wrap multiple basic items into one cron field.
pub fn one_of(items items: List(BasicItem)) -> BasicField {
  Values(items)
}

/// Replace the minute field in a builder.
pub fn with_minute(builder: Builder, minute: BasicField) -> Builder {
  Builder(..builder, minute:)
}

/// Replace the hour field in a builder.
pub fn with_hour(builder: Builder, hour: BasicField) -> Builder {
  Builder(..builder, hour:)
}

/// Replace the day-of-month field in a builder.
pub fn with_day_of_month(
  builder: Builder,
  day_of_month: DayOfMonthField,
) -> Builder {
  Builder(..builder, day_of_month:)
}

/// Replace the month field in a builder.
pub fn with_month(builder: Builder, month: BasicField) -> Builder {
  Builder(..builder, month:)
}

/// Replace the day-of-week field in a builder.
pub fn with_day_of_week(
  builder: Builder,
  day_of_week: DayOfWeekField,
) -> Builder {
  Builder(..builder, day_of_week:)
}

/// Set the optional year field in a builder.
pub fn with_year(builder: Builder, year: BasicField) -> Builder {
  Builder(..builder, year: Some(year))
}

/// Remove the optional year field from a builder.
pub fn without_year(builder: Builder) -> Builder {
  Builder(..builder, year: None)
}

/// Parse a cron expression using the requested style.
///
/// `Auto` detects either a UNIX 5-field expression or an
/// AWS/EventBridge-style expression. `UnixStyle` and
/// `AwsEventBridgeStyle` require the caller to choose explicitly.
pub fn parse(
  input input: String,
  style style: ParseStyle,
) -> Result(CronExpression, ParseError) {
  let trimmed = string.trim(input)

  case trimmed {
    "" -> Error(InvalidExpression(value: input))
    _ ->
      case style {
        Auto ->
          case string.starts_with(trimmed, "cron(") {
            True -> parse_aws_expression(trimmed)
            False -> auto_detect(trimmed)
          }
        UnixStyle -> parse_unix_expression(trimmed)
        AwsEventBridgeStyle -> parse_aws_expression(trimmed)
      }
  }
}

fn parse_unix_expression(input: String) -> Result(CronExpression, ParseError) {
  let fields = split_whitespace(string.trim(input))

  case fields {
    [minute, hour, day_of_month, month, day_of_week] ->
      parse_unix_fields(
        minute: minute,
        hour: hour,
        day_of_month: day_of_month,
        month: month,
        day_of_week: day_of_week,
      )
    _ ->
      Error(InvalidFieldCount(
        min_expected: 5,
        max_expected: 5,
        actual: list.length(fields),
      ))
  }
}

fn parse_aws_expression(input: String) -> Result(CronExpression, ParseError) {
  let trimmed = string.trim(input)

  case trimmed {
    "" -> Error(InvalidExpression(value: input))
    _ ->
      case string.starts_with(trimmed, "cron(") {
        True ->
          case string.ends_with(trimmed, ")") {
            True ->
              trimmed
              |> string.drop_start(up_to: 5)
              |> string.drop_end(up_to: 1)
              |> parse_aws_body
            False -> Error(InvalidExpression(value: trimmed))
          }
        False -> parse_aws_body(trimmed)
      }
  }
}

/// Validate a cron expression and discard the parsed value.
pub fn validate(
  input input: String,
  style style: ParseStyle,
) -> Result(Nil, ParseError) {
  case parse(input: input, style: style) {
    Ok(_) -> Ok(Nil)
    Error(error) -> Error(error)
  }
}

/// Validate and produce a cron expression from a builder.
pub fn build(builder builder: Builder) -> Result(CronExpression, ParseError) {
  case validate_builder(builder) {
    Error(error) -> Error(error)
    Ok(_) -> {
      let expression = builder_to_expression(builder)
      parse(
        input: render_builder(builder),
        style: style_for_dialect(expression.dialect),
      )
    }
  }
}

/// Render a parsed cron expression to a canonical string.
pub fn to_string(expression: CronExpression) -> String {
  let fields = [
    basic_field_to_string(expression.minute),
    basic_field_to_string(expression.hour),
    day_of_month_to_string(expression.day_of_month),
    basic_field_to_string(expression.month),
    day_of_week_to_string(expression.day_of_week),
  ]

  case expression.dialect {
    Unix -> string.join(fields, with: " ")
    AwsEventBridge ->
      case expression.year {
        Some(year) ->
          "cron("
          <> string.join(
            list.append(fields, [basic_field_to_string(year)]),
            with: " ",
          )
          <> ")"
        None -> "cron(" <> string.join(fields, with: " ") <> ")"
      }
  }
}

fn validate_builder(builder: Builder) -> Result(Nil, ParseError) {
  case validate_non_empty_basic_field(Minute, builder.minute) {
    Error(error) -> Error(error)
    Ok(_) ->
      case validate_non_empty_basic_field(Hour, builder.hour) {
        Error(error) -> Error(error)
        Ok(_) ->
          case validate_non_empty_day_of_month(builder.day_of_month) {
            Error(error) -> Error(error)
            Ok(_) ->
              case validate_non_empty_basic_field(Month, builder.month) {
                Error(error) -> Error(error)
                Ok(_) ->
                  case validate_non_empty_day_of_week(builder.day_of_week) {
                    Error(error) -> Error(error)
                    Ok(_) ->
                      case builder.dialect, builder.year {
                        Unix, Some(year) ->
                          Error(UnsupportedSyntax(
                            field: Year,
                            value: basic_field_to_string(year),
                          ))
                        _, Some(year) ->
                          validate_non_empty_basic_field(Year, year)
                        _, None -> Ok(Nil)
                      }
                  }
              }
          }
      }
  }
}

fn validate_non_empty_basic_field(
  field: Field,
  basic_field: BasicField,
) -> Result(Nil, ParseError) {
  case basic_field {
    All -> Ok(Nil)
    Values([]) -> Error(EmptyField(field: field))
    Values(_) -> Ok(Nil)
  }
}

fn validate_non_empty_day_of_month(
  field: DayOfMonthField,
) -> Result(Nil, ParseError) {
  case field {
    DayOfMonthValues([]) -> Error(EmptyField(field: DayOfMonth))
    _ -> Ok(Nil)
  }
}

fn validate_non_empty_day_of_week(
  field: DayOfWeekField,
) -> Result(Nil, ParseError) {
  case field {
    DayOfWeekValues([]) -> Error(EmptyField(field: DayOfWeek))
    _ -> Ok(Nil)
  }
}

fn builder_to_expression(builder: Builder) -> CronExpression {
  CronExpression(
    dialect: builder.dialect,
    minute: builder.minute,
    hour: builder.hour,
    day_of_month: builder.day_of_month,
    month: builder.month,
    day_of_week: builder.day_of_week,
    year: builder.year,
  )
}

fn render_builder(builder: Builder) -> String {
  builder
  |> builder_to_expression
  |> to_string
}

fn style_for_dialect(dialect: Dialect) -> ParseStyle {
  case dialect {
    Unix -> UnixStyle
    AwsEventBridge -> AwsEventBridgeStyle
  }
}

fn auto_detect(input: String) -> Result(CronExpression, ParseError) {
  let fields = split_whitespace(input)

  case fields {
    [_, _, day_of_month, _, day_of_week] ->
      case has_aws_only_syntax(day_of_month, day_of_week) {
        True -> parse_aws_fields(fields)
        False -> parse_unix_expression(input)
      }
    [_, _, day_of_month, _, day_of_week, _] ->
      case has_aws_only_syntax(day_of_month, day_of_week) {
        True -> parse_aws_fields(fields)
        False -> parse_aws_fields(fields)
      }
    _ ->
      Error(InvalidFieldCount(
        min_expected: 5,
        max_expected: 6,
        actual: list.length(fields),
      ))
  }
}

fn parse_aws_body(body: String) -> Result(CronExpression, ParseError) {
  parse_aws_fields(split_whitespace(string.trim(body)))
}

fn parse_aws_fields(fields: List(String)) -> Result(CronExpression, ParseError) {
  case fields {
    [minute, hour, day_of_month, month, day_of_week] ->
      parse_aws_parts(minute, hour, day_of_month, month, day_of_week, None)
    [minute, hour, day_of_month, month, day_of_week, year] ->
      parse_aws_parts(
        minute,
        hour,
        day_of_month,
        month,
        day_of_week,
        Some(year),
      )
    _ ->
      Error(InvalidFieldCount(
        min_expected: 5,
        max_expected: 6,
        actual: list.length(fields),
      ))
  }
}

fn parse_aws_parts(
  minute minute: String,
  hour hour: String,
  day_of_month day_of_month: String,
  month month: String,
  day_of_week day_of_week: String,
  year year: Option(String),
) -> Result(CronExpression, ParseError) {
  case parse_basic_field(Minute, minute, 0, 59, NoAliases) {
    Error(error) -> Error(error)
    Ok(minute_field) ->
      case parse_basic_field(Hour, hour, 0, 23, NoAliases) {
        Error(error) -> Error(error)
        Ok(hour_field) ->
          case parse_day_of_month_aws(day_of_month) {
            Error(error) -> Error(error)
            Ok(day_of_month_field) ->
              case parse_basic_field(Month, month, 1, 12, MonthAliases) {
                Error(error) -> Error(error)
                Ok(month_field) ->
                  case parse_day_of_week_aws(day_of_week) {
                    Error(error) -> Error(error)
                    Ok(day_of_week_field) ->
                      case parse_optional_year(year) {
                        Error(error) -> Error(error)
                        Ok(year_field) ->
                          case
                            validate_aws_day_fields(
                              day_of_month,
                              day_of_week,
                              day_of_month_field,
                              day_of_week_field,
                            )
                          {
                            Error(error) -> Error(error)
                            Ok(_) -> {
                              let expression =
                                CronExpression(
                                  dialect: AwsEventBridge,
                                  minute: minute_field,
                                  hour: hour_field,
                                  day_of_month: day_of_month_field,
                                  month: month_field,
                                  day_of_week: day_of_week_field,
                                  year: year_field,
                                )

                              case validate_expression_semantics(expression) {
                                Ok(_) -> Ok(expression)
                                Error(error) -> Error(error)
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

fn parse_optional_year(
  year: Option(String),
) -> Result(Option(BasicField), ParseError) {
  case year {
    None -> Ok(None)
    Some(value) ->
      case parse_basic_field(Year, value, 1970, 2199, NoAliases) {
        Ok(field) -> Ok(Some(field))
        Error(error) -> Error(error)
      }
  }
}

fn parse_unix_fields(
  minute minute: String,
  hour hour: String,
  day_of_month day_of_month: String,
  month month: String,
  day_of_week day_of_week: String,
) -> Result(CronExpression, ParseError) {
  case parse_basic_field(Minute, minute, 0, 59, NoAliases) {
    Error(error) -> Error(error)
    Ok(minute_field) ->
      case parse_basic_field(Hour, hour, 0, 23, NoAliases) {
        Error(error) -> Error(error)
        Ok(hour_field) ->
          case parse_day_of_month_unix(day_of_month) {
            Error(error) -> Error(error)
            Ok(day_of_month_field) ->
              case parse_basic_field(Month, month, 1, 12, MonthAliases) {
                Error(error) -> Error(error)
                Ok(month_field) ->
                  case parse_day_of_week_unix(day_of_week) {
                    Error(error) -> Error(error)
                    Ok(day_of_week_field) -> {
                      let expression =
                        CronExpression(
                          dialect: Unix,
                          minute: minute_field,
                          hour: hour_field,
                          day_of_month: day_of_month_field,
                          month: month_field,
                          day_of_week: day_of_week_field,
                          year: None,
                        )

                      case validate_expression_semantics(expression) {
                        Ok(_) -> Ok(expression)
                        Error(error) -> Error(error)
                      }
                    }
                  }
              }
          }
      }
  }
}

fn validate_expression_semantics(
  expression expression: CronExpression,
) -> Result(Nil, ParseError) {
  case expression.dialect {
    Unix -> validate_unix_semantics(expression)
    AwsEventBridge -> validate_aws_semantics(expression)
  }
}

fn validate_unix_semantics(
  expression expression: CronExpression,
) -> Result(Nil, ParseError) {
  case expression.day_of_week {
    AnyDayOfWeek ->
      validate_day_of_month_schedule(
        day_of_month: expression.day_of_month,
        month: expression.month,
        year: None,
      )
    _ -> Ok(Nil)
  }
}

fn validate_aws_semantics(
  expression expression: CronExpression,
) -> Result(Nil, ParseError) {
  case expression.day_of_month, expression.day_of_week {
    NoSpecificDayOfMonth, NthWeekdayOfMonth(day, occurrence) ->
      validate_nth_weekday_schedule(
        day: day,
        occurrence: occurrence,
        month: expression.month,
        year: expression.year,
      )
    NoSpecificDayOfMonth, _ -> Ok(Nil)
    _, NoSpecificDayOfWeek ->
      validate_day_of_month_schedule(
        day_of_month: expression.day_of_month,
        month: expression.month,
        year: expression.year,
      )
    _, _ -> Ok(Nil)
  }
}

fn validate_day_of_month_schedule(
  day_of_month day_of_month: DayOfMonthField,
  month month: BasicField,
  year year: Option(BasicField),
) -> Result(Nil, ParseError) {
  case day_of_month_schedule_possible(day_of_month, month, year) {
    True -> Ok(Nil)
    False ->
      Error(ImpossibleDate(
        day_of_month: day_of_month_to_string(day_of_month),
        month: basic_field_to_string(month),
        year: year_to_error_value(year),
      ))
  }
}

fn day_of_month_schedule_possible(
  day_of_month day_of_month: DayOfMonthField,
  month month: BasicField,
  year year: Option(BasicField),
) -> Bool {
  let months = basic_field_values(month, 1, 12)
  let years = year_values(year)

  case day_of_month {
    AnyDayOfMonth -> True
    NoSpecificDayOfMonth -> True
    LastDayOfMonth -> True
    NearestWeekday(day) ->
      list.any(years, fn(year) {
        list.any(months, fn(month) { day <= days_in_month(year, month) })
      })
    DayOfMonthValues(items) -> {
      let days =
        list.flat_map(items, fn(item) { basic_item_values(item, 1, 31) })

      list.any(years, fn(year) {
        list.any(months, fn(month) {
          let maximum = days_in_month(year, month)
          list.any(days, fn(day) { day <= maximum })
        })
      })
    }
  }
}

fn validate_nth_weekday_schedule(
  day day: Int,
  occurrence occurrence: Int,
  month month: BasicField,
  year year: Option(BasicField),
) -> Result(Nil, ParseError) {
  case nth_weekday_schedule_possible(day, occurrence, month, year) {
    True -> Ok(Nil)
    False ->
      Error(ImpossibleWeekdayOccurrence(
        day_of_week: int.to_string(day) <> "#" <> int.to_string(occurrence),
        month: basic_field_to_string(month),
        year: year_to_error_value(year),
      ))
  }
}

fn nth_weekday_schedule_possible(
  day day: Int,
  occurrence occurrence: Int,
  month month: BasicField,
  year year: Option(BasicField),
) -> Bool {
  let months = basic_field_values(month, 1, 12)
  let years = year_values(year)

  list.any(years, fn(year) {
    list.any(months, fn(month) {
      nth_weekday_exists(
        day: day,
        occurrence: occurrence,
        year: year,
        month: month,
      )
    })
  })
}

fn year_to_error_value(year: Option(BasicField)) -> Option(String) {
  case year {
    None -> None
    Some(field) -> Some(basic_field_to_string(field))
  }
}

fn year_values(year: Option(BasicField)) -> List(Int) {
  case year {
    None -> inclusive_range(1970, 2199)
    Some(field) -> basic_field_values(field, 1970, 2199)
  }
}

fn basic_field_values(field: BasicField, min: Int, max: Int) -> List(Int) {
  case field {
    All -> inclusive_range(min, max)
    Values(items) ->
      list.flat_map(items, fn(item) { basic_item_values(item, min, max) })
  }
}

fn basic_item_values(item: BasicItem, min: Int, max: Int) -> List(Int) {
  case item {
    Exact(value) -> [value]
    Range(start, end) -> inclusive_range(start, end)
    Step(base, step) -> step_values(base, step, min, max)
  }
}

fn step_values(base: StepBase, step: Int, min: Int, max: Int) -> List(Int) {
  case base {
    StepAll -> stepped_range_values(min, max, step)
    StepExact(start) -> stepped_range_values(start, max, step)
    StepRange(start, end) -> stepped_range_values(start, end, step)
  }
}

fn stepped_range_values(start: Int, stop: Int, step: Int) -> List(Int) {
  case start > stop {
    True -> []
    False -> [start, ..stepped_range_values(start + step, stop, step)]
  }
}

fn inclusive_range(start: Int, stop: Int) -> List(Int) {
  case start > stop {
    True -> []
    False -> [start, ..inclusive_range(start + 1, stop)]
  }
}

fn nth_weekday_exists(
  day day: Int,
  occurrence occurrence: Int,
  year year: Int,
  month month: Int,
) -> Bool {
  let first_weekday = aws_day_of_week(year, month, 1)
  let offset = case day >= first_weekday {
    True -> day - first_weekday
    False -> day + 7 - first_weekday
  }
  let first_occurrence = 1 + offset
  let week_offset = { occurrence - 1 } * 7
  let nth_occurrence = first_occurrence + week_offset

  nth_occurrence <= days_in_month(year, month)
}

fn aws_day_of_week(year: Int, month: Int, day: Int) -> Int {
  weekday_index(year, month, day) + 1
}

fn weekday_index(year: Int, month: Int, day: Int) -> Int {
  let adjusted_year = case month < 3 {
    True -> year - 1
    False -> year
  }

  positive_modulo(
    adjusted_year
      + quotient(adjusted_year, 4)
      - quotient(adjusted_year, 100)
      + quotient(adjusted_year, 400)
      + month_offset(month)
      + day,
    7,
  )
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
  let by_4 = positive_modulo(year, 4)
  let by_100 = positive_modulo(year, 100)
  let by_400 = positive_modulo(year, 400)

  by_400 == 0 || { by_4 == 0 && by_100 != 0 }
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

fn positive_modulo(dividend: Int, divisor: Int) -> Int {
  case int.modulo(dividend, by: divisor) {
    Ok(result) -> result
    Error(_) -> 0
  }
}

fn parse_day_of_month_unix(value: String) -> Result(DayOfMonthField, ParseError) {
  case parse_basic_field(DayOfMonth, value, 1, 31, NoAliases) {
    Ok(All) -> Ok(AnyDayOfMonth)
    Ok(Values(items)) -> Ok(DayOfMonthValues(items))
    Error(error) -> Error(error)
  }
}

fn parse_day_of_week_unix(value: String) -> Result(DayOfWeekField, ParseError) {
  case parse_basic_field(DayOfWeek, value, 0, 7, UnixDayAliases) {
    Ok(All) -> Ok(AnyDayOfWeek)
    Ok(Values(items)) -> Ok(DayOfWeekValues(items))
    Error(error) -> Error(error)
  }
}

fn parse_day_of_month_aws(value: String) -> Result(DayOfMonthField, ParseError) {
  case value {
    "*" -> Ok(AnyDayOfMonth)
    "?" -> Ok(NoSpecificDayOfMonth)
    "L" -> Ok(LastDayOfMonth)
    _ ->
      case string.ends_with(value, "W") {
        True ->
          case string.is_empty(string.drop_end(value, up_to: 1)) {
            True -> Error(UnsupportedSyntax(field: DayOfMonth, value: value))
            False ->
              case
                parse_value(
                  DayOfMonth,
                  string.drop_end(value, up_to: 1),
                  1,
                  31,
                  NoAliases,
                )
              {
                Ok(day) -> Ok(NearestWeekday(day))
                Error(error) -> Error(error)
              }
          }
        False ->
          case parse_basic_field(DayOfMonth, value, 1, 31, NoAliases) {
            Ok(All) -> Ok(AnyDayOfMonth)
            Ok(Values(items)) -> Ok(DayOfMonthValues(items))
            Error(error) -> Error(error)
          }
      }
  }
}

fn parse_day_of_week_aws(value: String) -> Result(DayOfWeekField, ParseError) {
  case value {
    "*" -> Ok(AnyDayOfWeek)
    "?" -> Ok(NoSpecificDayOfWeek)
    _ ->
      case string.contains(value, contain: "#") {
        True -> parse_nth_weekday(value)
        False ->
          case string.ends_with(value, "L") {
            True -> parse_last_weekday(value)
            False ->
              case parse_basic_field(DayOfWeek, value, 1, 7, AwsDayAliases) {
                Ok(All) -> Ok(AnyDayOfWeek)
                Ok(Values(items)) -> Ok(DayOfWeekValues(items))
                Error(error) -> Error(error)
              }
          }
      }
  }
}

fn parse_nth_weekday(value: String) -> Result(DayOfWeekField, ParseError) {
  case string.split(value, on: "#") {
    [left, right] ->
      case left, right {
        "", _ -> Error(UnsupportedSyntax(field: DayOfWeek, value: value))
        _, "" -> Error(UnsupportedSyntax(field: DayOfWeek, value: value))
        _, _ ->
          case
            list.any(string.split(left, on: ","), string.is_empty)
            || string.contains(left, contain: ",")
            || string.contains(left, contain: "-")
            || string.contains(left, contain: "/")
          {
            True -> Error(UnsupportedSyntax(field: DayOfWeek, value: value))
            False ->
              case parse_value(DayOfWeek, left, 1, 7, AwsDayAliases) {
                Error(error) -> Error(error)
                Ok(day) ->
                  case int.parse(right) {
                    Ok(occurrence) ->
                      case occurrence >= 1 && occurrence <= 5 {
                        True -> Ok(NthWeekdayOfMonth(day, occurrence))
                        False ->
                          Error(OutOfRange(
                            field: DayOfWeek,
                            min: 1,
                            max: 5,
                            actual: occurrence,
                          ))
                      }
                    Error(_) ->
                      Error(InvalidNumber(field: DayOfWeek, value: value))
                  }
              }
          }
      }
    _ -> Error(UnsupportedSyntax(field: DayOfWeek, value: value))
  }
}

fn parse_last_weekday(value: String) -> Result(DayOfWeekField, ParseError) {
  let base = string.drop_end(value, up_to: 1)

  case base {
    "" -> Ok(LastWeekdayOfMonth(7))
    _ ->
      case
        string.contains(base, contain: ",")
        || string.contains(base, contain: "-")
        || string.contains(base, contain: "/")
      {
        True -> Error(UnsupportedSyntax(field: DayOfWeek, value: value))
        False ->
          case parse_value(DayOfWeek, base, 1, 7, AwsDayAliases) {
            Ok(day) -> Ok(LastWeekdayOfMonth(day))
            Error(error) -> Error(error)
          }
      }
  }
}

fn validate_aws_day_fields(
  raw_dom raw_dom: String,
  raw_dow raw_dow: String,
  day_of_month day_of_month: DayOfMonthField,
  day_of_week day_of_week: DayOfWeekField,
) -> Result(Nil, ParseError) {
  case day_of_month, day_of_week {
    NoSpecificDayOfMonth, NoSpecificDayOfWeek ->
      Error(InvalidDayFieldCombination(
        day_of_month: raw_dom,
        day_of_week: raw_dow,
      ))
    NoSpecificDayOfMonth, _ -> Ok(Nil)
    _, NoSpecificDayOfWeek -> Ok(Nil)
    _, _ ->
      Error(InvalidDayFieldCombination(
        day_of_month: raw_dom,
        day_of_week: raw_dow,
      ))
  }
}

fn parse_basic_field(
  field field: Field,
  value value: String,
  min min: Int,
  max max: Int,
  aliases aliases: AliasMode,
) -> Result(BasicField, ParseError) {
  case value {
    "*" -> Ok(All)
    "?" -> Error(UnsupportedSyntax(field: field, value: value))
    _ ->
      case list.any(string.split(value, on: ","), string.is_empty) {
        True -> Error(InvalidList(field: field, value: value))
        False ->
          case
            collect_basic_items(
              field,
              string.split(value, on: ","),
              min,
              max,
              aliases,
              [],
            )
          {
            Ok(items) -> Ok(Values(items))
            Error(error) -> Error(error)
          }
      }
  }
}

fn collect_basic_items(
  field: Field,
  parts: List(String),
  min: Int,
  max: Int,
  aliases: AliasMode,
  acc: List(BasicItem),
) -> Result(List(BasicItem), ParseError) {
  case parts {
    [] -> Ok(list.reverse(acc))
    [part, ..rest] ->
      case parse_basic_item(field, part, min, max, aliases) {
        Ok(item) ->
          collect_basic_items(field, rest, min, max, aliases, [item, ..acc])
        Error(error) -> Error(error)
      }
  }
}

fn parse_basic_item(
  field field: Field,
  part part: String,
  min min: Int,
  max max: Int,
  aliases aliases: AliasMode,
) -> Result(BasicItem, ParseError) {
  case string.contains(part, contain: "/") {
    True -> parse_step_item(field, part, min, max, aliases)
    False ->
      case string.contains(part, contain: "-") {
        True -> parse_range_item(field, part, min, max, aliases)
        False ->
          case parse_value(field, part, min, max, aliases) {
            Ok(value) -> Ok(Exact(value))
            Error(error) -> Error(error)
          }
      }
  }
}

fn parse_step_item(
  field field: Field,
  part part: String,
  min min: Int,
  max max: Int,
  aliases aliases: AliasMode,
) -> Result(BasicItem, ParseError) {
  case string.split(part, on: "/") {
    [base, step_text] ->
      case base, step_text {
        "", _ -> Error(InvalidStep(field: field, value: part))
        _, "" -> Error(InvalidStep(field: field, value: part))
        _, _ ->
          case int.parse(step_text) {
            Ok(step) ->
              case step > 0 {
                False -> Error(InvalidStep(field: field, value: part))
                True ->
                  case parse_step_base(field, base, min, max, aliases) {
                    Ok(step_base) -> Ok(Step(step_base, step))
                    Error(error) -> Error(error)
                  }
              }
            Error(_) -> Error(InvalidStep(field: field, value: part))
          }
      }
    _ -> Error(InvalidStep(field: field, value: part))
  }
}

fn parse_step_base(
  field field: Field,
  base base: String,
  min min: Int,
  max max: Int,
  aliases aliases: AliasMode,
) -> Result(StepBase, ParseError) {
  case base {
    "*" -> Ok(StepAll)
    _ ->
      case
        string.contains(base, contain: ",")
        || string.contains(base, contain: "/")
      {
        True -> Error(InvalidStep(field: field, value: base))
        False ->
          case string.contains(base, contain: "-") {
            True ->
              case string.split(base, on: "-") {
                [start_text, end_text] ->
                  case start_text, end_text {
                    "", _ -> Error(InvalidRange(field: field, value: base))
                    _, "" -> Error(InvalidRange(field: field, value: base))
                    _, _ ->
                      case parse_value(field, start_text, min, max, aliases) {
                        Error(error) -> Error(error)
                        Ok(start) ->
                          case parse_value(field, end_text, min, max, aliases) {
                            Error(error) -> Error(error)
                            Ok(end) ->
                              case start <= end {
                                True -> Ok(StepRange(start, end))
                                False ->
                                  Error(InvalidRange(field: field, value: base))
                              }
                          }
                      }
                  }
                _ -> Error(InvalidRange(field: field, value: base))
              }
            False ->
              case parse_value(field, base, min, max, aliases) {
                Ok(value) -> Ok(StepExact(value))
                Error(error) -> Error(error)
              }
          }
      }
  }
}

fn parse_range_item(
  field field: Field,
  part part: String,
  min min: Int,
  max max: Int,
  aliases aliases: AliasMode,
) -> Result(BasicItem, ParseError) {
  case string.split(part, on: "-") {
    [start_text, end_text] ->
      case start_text, end_text {
        "", _ -> Error(InvalidRange(field: field, value: part))
        _, "" -> Error(InvalidRange(field: field, value: part))
        _, _ ->
          case parse_value(field, start_text, min, max, aliases) {
            Error(error) -> Error(error)
            Ok(start) ->
              case parse_value(field, end_text, min, max, aliases) {
                Error(error) -> Error(error)
                Ok(end) ->
                  case start <= end {
                    True -> Ok(Range(start, end))
                    False -> Error(InvalidRange(field: field, value: part))
                  }
              }
          }
      }
    _ -> Error(InvalidRange(field: field, value: part))
  }
}

fn parse_value(
  field field: Field,
  value value: String,
  min min: Int,
  max max: Int,
  aliases aliases: AliasMode,
) -> Result(Int, ParseError) {
  case int.parse(value) {
    Ok(number) -> ensure_in_range(field, number, min, max)
    Error(_) ->
      case resolve_alias(aliases, value) {
        Ok(number) -> ensure_in_range(field, number, min, max)
        Error(Nil) ->
          case aliases {
            NoAliases -> Error(InvalidNumber(field: field, value: value))
            _ -> Error(InvalidAlias(field: field, value: value))
          }
      }
  }
}

fn ensure_in_range(
  field field: Field,
  number number: Int,
  min min: Int,
  max max: Int,
) -> Result(Int, ParseError) {
  case number < min || number > max {
    True -> Error(OutOfRange(field: field, min: min, max: max, actual: number))
    False -> Ok(number)
  }
}

fn resolve_alias(aliases: AliasMode, value: String) -> Result(Int, Nil) {
  let upper = string.uppercase(value)

  case aliases {
    NoAliases -> Error(Nil)
    MonthAliases ->
      case upper {
        "JAN" -> Ok(1)
        "FEB" -> Ok(2)
        "MAR" -> Ok(3)
        "APR" -> Ok(4)
        "MAY" -> Ok(5)
        "JUN" -> Ok(6)
        "JUL" -> Ok(7)
        "AUG" -> Ok(8)
        "SEP" -> Ok(9)
        "OCT" -> Ok(10)
        "NOV" -> Ok(11)
        "DEC" -> Ok(12)
        _ -> Error(Nil)
      }
    UnixDayAliases ->
      case upper {
        "SUN" -> Ok(0)
        "MON" -> Ok(1)
        "TUE" -> Ok(2)
        "WED" -> Ok(3)
        "THU" -> Ok(4)
        "FRI" -> Ok(5)
        "SAT" -> Ok(6)
        _ -> Error(Nil)
      }
    AwsDayAliases ->
      case upper {
        "SUN" -> Ok(1)
        "MON" -> Ok(2)
        "TUE" -> Ok(3)
        "WED" -> Ok(4)
        "THU" -> Ok(5)
        "FRI" -> Ok(6)
        "SAT" -> Ok(7)
        _ -> Error(Nil)
      }
  }
}

fn split_whitespace(input: String) -> List(String) {
  input
  |> string.to_graphemes
  |> list.fold(#([], ""), fn(acc, grapheme) {
    let #(parts, current) = acc
    case is_whitespace(grapheme) {
      True ->
        case current == "" {
          True -> #(parts, "")
          False -> #([current, ..parts], "")
        }
      False -> #(parts, current <> grapheme)
    }
  })
  |> flush_split_parts
}

fn flush_split_parts(parts: #(List(String), String)) -> List(String) {
  let #(collected, current) = parts

  case current == "" {
    True -> list.reverse(collected)
    False -> list.reverse([current, ..collected])
  }
}

fn is_whitespace(grapheme: String) -> Bool {
  case grapheme {
    " " -> True
    "\t" -> True
    "\n" -> True
    "\r" -> True
    _ -> False
  }
}

fn has_aws_only_syntax(day_of_month: String, day_of_week: String) -> Bool {
  day_of_month == "?"
  || day_of_month == "L"
  || string.ends_with(day_of_month, "W")
  || day_of_week == "?"
  || day_of_week == "L"
  || string.ends_with(day_of_week, "L")
  || string.contains(day_of_week, contain: "#")
}

fn basic_field_to_string(field: BasicField) -> String {
  case field {
    All -> "*"
    Values(items) ->
      items
      |> list.map(basic_item_to_string)
      |> string.join(with: ",")
  }
}

fn basic_item_to_string(item: BasicItem) -> String {
  case item {
    Exact(value) -> int.to_string(value)
    Range(start, end) -> int.to_string(start) <> "-" <> int.to_string(end)
    Step(base, step) -> step_base_to_string(base) <> "/" <> int.to_string(step)
  }
}

fn step_base_to_string(base: StepBase) -> String {
  case base {
    StepAll -> "*"
    StepExact(value) -> int.to_string(value)
    StepRange(start, end) -> int.to_string(start) <> "-" <> int.to_string(end)
  }
}

fn day_of_month_to_string(field: DayOfMonthField) -> String {
  case field {
    AnyDayOfMonth -> "*"
    NoSpecificDayOfMonth -> "?"
    LastDayOfMonth -> "L"
    NearestWeekday(day) -> int.to_string(day) <> "W"
    DayOfMonthValues(items) ->
      items
      |> list.map(basic_item_to_string)
      |> string.join(with: ",")
  }
}

fn day_of_week_to_string(field: DayOfWeekField) -> String {
  case field {
    AnyDayOfWeek -> "*"
    NoSpecificDayOfWeek -> "?"
    LastWeekdayOfMonth(day) -> int.to_string(day) <> "L"
    NthWeekdayOfMonth(day, occurrence) ->
      int.to_string(day) <> "#" <> int.to_string(occurrence)
    DayOfWeekValues(items) ->
      items
      |> list.map(basic_item_to_string)
      |> string.join(with: ",")
  }
}
