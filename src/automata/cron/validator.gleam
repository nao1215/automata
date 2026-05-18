import automata/cron/ast.{
  type Field, type RawCron, DayOfMonth, DayOfWeek, Hour, Minute, Month,
}
import automata/internal/calendar
import gleam/int
import gleam/list
import gleam/string

pub type Selector {
  Any
  Values(List(Item))
}

pub type Item {
  Exact(Int)
  Range(Int, Int)
  Step(StepBase, Int)
}

pub type StepBase {
  StepAny
  StepExact(Int)
  StepRange(Int, Int)
}

/// A cron expression that has passed `validate/1`. `opaque` so the
/// only way to obtain a value is through validation, preventing
/// callers from forging "validated" inputs.
pub opaque type ValidCron {
  ValidCron(
    minute: Selector,
    hour: Selector,
    day_of_month: Selector,
    month: Selector,
    day_of_week: Selector,
  )
}

pub fn minute(spec: ValidCron) -> Selector {
  spec.minute
}

pub fn hour(spec: ValidCron) -> Selector {
  spec.hour
}

pub fn day_of_month(spec: ValidCron) -> Selector {
  spec.day_of_month
}

pub fn month(spec: ValidCron) -> Selector {
  spec.month
}

pub fn day_of_week(spec: ValidCron) -> Selector {
  spec.day_of_week
}

pub type ValidationError {
  UnsupportedSyntax(field: Field, value: String)
  InvalidNumber(field: Field, value: String)
  InvalidAlias(field: Field, value: String)
  InvalidRange(field: Field, value: String)
  InvalidStep(field: Field, value: String)
  InvalidList(field: Field, value: String)
  OutOfRange(field: Field, min: Int, max: Int, actual: Int)
  ImpossibleDate(day_of_month: String, month: String)
}

type AliasMode {
  NoAliases
  MonthAliases
  DayAliases
}

pub fn validate(raw raw: RawCron) -> Result(ValidCron, ValidationError) {
  case parse_selector(Minute, raw.minute, 0, 59, NoAliases) {
    Error(error) -> Error(error)
    Ok(minute) ->
      case parse_selector(Hour, raw.hour, 0, 23, NoAliases) {
        Error(error) -> Error(error)
        Ok(hour) ->
          case parse_selector(DayOfMonth, raw.day_of_month, 1, 31, NoAliases) {
            Error(error) -> Error(error)
            Ok(day_of_month) ->
              case parse_selector(Month, raw.month, 1, 12, MonthAliases) {
                Error(error) -> Error(error)
                Ok(month) ->
                  case
                    parse_selector(DayOfWeek, raw.day_of_week, 0, 7, DayAliases)
                  {
                    Error(error) -> Error(error)
                    Ok(day_of_week) -> {
                      let spec =
                        ValidCron(
                          minute:,
                          hour:,
                          day_of_month:,
                          month:,
                          day_of_week:,
                        )

                      case validate_semantics(spec) {
                        Ok(_) -> Ok(spec)
                        Error(error) -> Error(error)
                      }
                    }
                  }
              }
          }
      }
  }
}

pub fn to_string(spec: ValidCron) -> String {
  string.join(
    [
      selector_to_string(spec.minute),
      selector_to_string(spec.hour),
      selector_to_string(spec.day_of_month),
      selector_to_string(spec.month),
      selector_to_string(spec.day_of_week),
    ],
    with: " ",
  )
}

fn validate_semantics(spec: ValidCron) -> Result(Nil, ValidationError) {
  case day_of_week_is_any(spec.day_of_week) {
    False -> Ok(Nil)
    True ->
      case schedule_possible(spec.day_of_month, spec.month) {
        True -> Ok(Nil)
        False ->
          Error(ImpossibleDate(
            day_of_month: selector_to_string(spec.day_of_month),
            month: selector_to_string(spec.month),
          ))
      }
  }
}

fn day_of_week_is_any(selector: Selector) -> Bool {
  case selector {
    Any -> True
    Values(_) -> False
  }
}

fn schedule_possible(day_of_month: Selector, month: Selector) -> Bool {
  let months = selector_values(month, 1, 12, normalize_day_of_week: False)
  let days = selector_values(day_of_month, 1, 31, normalize_day_of_week: False)

  list.any(months, fn(month) {
    let maximum = calendar.days_in_month(2024, month)
    list.any(days, fn(day) { day <= maximum })
    || list.any(days, fn(day) { calendar.days_in_month(2025, month) >= day })
  })
}

fn parse_selector(
  field: Field,
  value: String,
  min: Int,
  max: Int,
  aliases: AliasMode,
) -> Result(Selector, ValidationError) {
  case value {
    "*" -> Ok(Any)
    _ ->
      case list.any(string.split(value, on: ","), string.is_empty) {
        True -> Error(InvalidList(field: field, value: value))
        False ->
          parse_items(
            string.split(value, on: ","),
            field,
            min,
            max,
            aliases,
            [],
          )
      }
  }
}

fn parse_items(
  parts: List(String),
  field: Field,
  min: Int,
  max: Int,
  aliases: AliasMode,
  acc: List(Item),
) -> Result(Selector, ValidationError) {
  case parts {
    [] -> Ok(Values(list.reverse(acc)))
    [part, ..rest] ->
      case parse_item(field, part, min, max, aliases) {
        Ok(item) -> parse_items(rest, field, min, max, aliases, [item, ..acc])
        Error(error) -> Error(error)
      }
  }
}

fn parse_item(
  field: Field,
  part: String,
  min: Int,
  max: Int,
  aliases: AliasMode,
) -> Result(Item, ValidationError) {
  case string.contains(part, contain: "/") {
    True -> parse_step(field, part, min, max, aliases)
    False ->
      case string.contains(part, contain: "-") {
        True -> parse_range(field, part, min, max, aliases)
        False ->
          case parse_value(field, part, min, max, aliases) {
            Ok(value) -> Ok(Exact(value))
            Error(error) -> Error(error)
          }
      }
  }
}

fn parse_step(
  field: Field,
  part: String,
  min: Int,
  max: Int,
  aliases: AliasMode,
) -> Result(Item, ValidationError) {
  case string.split(part, on: "/") {
    [base, step_text] ->
      case base == "" || step_text == "" {
        True -> Error(InvalidStep(field: field, value: part))
        False ->
          case int.parse(step_text) {
            Error(_) -> Error(InvalidStep(field: field, value: part))
            Ok(step) ->
              case step > 0 && step <= max - min {
                False -> Error(InvalidStep(field: field, value: part))
                True ->
                  case parse_step_base(field, base, min, max, aliases) {
                    Ok(step_base) -> Ok(Step(step_base, step))
                    Error(error) -> Error(error)
                  }
              }
          }
      }
    _ -> Error(InvalidStep(field: field, value: part))
  }
}

fn parse_step_base(
  field: Field,
  base: String,
  min: Int,
  max: Int,
  aliases: AliasMode,
) -> Result(StepBase, ValidationError) {
  case base {
    "*" -> Ok(StepAny)
    _ ->
      case string.contains(base, contain: "-") {
        True ->
          case string.split(base, on: "-") {
            [start_text, end_text] ->
              case start_text == "" || end_text == "" {
                True -> Error(InvalidRange(field: field, value: base))
                False ->
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

fn parse_range(
  field: Field,
  part: String,
  min: Int,
  max: Int,
  aliases: AliasMode,
) -> Result(Item, ValidationError) {
  case string.split(part, on: "-") {
    [start_text, end_text] ->
      case start_text == "" || end_text == "" {
        True -> Error(InvalidRange(field: field, value: part))
        False ->
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
  field: Field,
  value: String,
  min: Int,
  max: Int,
  aliases: AliasMode,
) -> Result(Int, ValidationError) {
  case int.parse(value) {
    Ok(number) -> ensure_range(field, number, min, max)
    Error(_) ->
      case parse_alias(field, value, aliases) {
        Ok(number) -> ensure_range(field, number, min, max)
        Error(Nil) ->
          case has_reserved_quartz_syntax(value) {
            True -> Error(UnsupportedSyntax(field: field, value: value))
            False ->
              case aliases {
                NoAliases -> Error(InvalidNumber(field: field, value: value))
                _ -> Error(InvalidAlias(field: field, value: value))
              }
          }
      }
  }
}

/// Detect reserved Quartz-style extensions (`?`, `L`, `W`, `H`, `#`) that
/// the validator does not support. Run only after `int.parse` and
/// `parse_alias` have both failed, so that perfectly valid alias tokens
/// like `WED`, `JUL`, `THU` (which contain `W`, `L`, `H` as substrings)
/// still reach the alias resolver before being misclassified.
fn has_reserved_quartz_syntax(value: String) -> Bool {
  string.contains(value, contain: "?")
  || string.contains(value, contain: "L")
  || string.contains(value, contain: "W")
  || string.contains(value, contain: "#")
  || string.contains(value, contain: "H")
}

fn ensure_range(
  field: Field,
  number: Int,
  min: Int,
  max: Int,
) -> Result(Int, ValidationError) {
  case number < min || number > max {
    True -> Error(OutOfRange(field: field, min: min, max: max, actual: number))
    False -> Ok(number)
  }
}

fn parse_alias(
  _field: Field,
  value: String,
  aliases: AliasMode,
) -> Result(Int, Nil) {
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
    DayAliases ->
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
  }
}

pub fn selector_values(
  selector: Selector,
  min: Int,
  max: Int,
  normalize_day_of_week normalize_day_of_week: Bool,
) -> List(Int) {
  let values = case selector {
    Any -> inclusive_range(min, max)
    Values(items) ->
      items
      |> list.flat_map(fn(item) { item_values(item, min, max) })
  }

  case normalize_day_of_week {
    True ->
      values
      |> list.map(fn(value) {
        case value == 7 {
          True -> 0
          False -> value
        }
      })
      |> dedup_sort([])
    False -> dedup_sort(values, [])
  }
}

fn item_values(item: Item, min: Int, max: Int) -> List(Int) {
  case item {
    Exact(value) -> [value]
    Range(start, end) -> inclusive_range(start, end)
    Step(base, step) ->
      case base {
        StepAny -> stepped_values(min, max, step)
        StepExact(start) -> stepped_values(start, max, step)
        StepRange(start, end) -> stepped_values(start, end, step)
      }
  }
}

fn stepped_values(start: Int, stop: Int, step: Int) -> List(Int) {
  case start > stop {
    True -> []
    False -> [start, ..stepped_values(start + step, stop, step)]
  }
}

fn inclusive_range(start: Int, stop: Int) -> List(Int) {
  case start > stop {
    True -> []
    False -> [start, ..inclusive_range(start + 1, stop)]
  }
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

fn selector_to_string(selector: Selector) -> String {
  case selector {
    Any -> "*"
    Values(items) -> string.join(list.map(items, item_to_string), with: ",")
  }
}

fn item_to_string(item: Item) -> String {
  case item {
    Exact(value) -> int.to_string(value)
    Range(start, end) -> int.to_string(start) <> "-" <> int.to_string(end)
    Step(base, step) -> step_base_to_string(base) <> "/" <> int.to_string(step)
  }
}

fn step_base_to_string(base: StepBase) -> String {
  case base {
    StepAny -> "*"
    StepExact(value) -> int.to_string(value)
    StepRange(start, end) -> int.to_string(start) <> "-" <> int.to_string(end)
  }
}
