import automata/cron/ast.{
  type Field, type RawCron, DayOfMonth, DayOfWeek, Expression, Hour, Minute,
  Month, RawCron,
}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type ParseError {
  InvalidExpression(value: String)
  InvalidFieldCount(expected: Int, actual: Int)
  EmptyField(field: Field)
  UnsupportedSyntax(field: Field, value: String)
  /// `@reboot` is recognised as a Vixie nickname but has no 5-field
  /// equivalent — it is a startup hook, not a recurring schedule.
  /// The library refuses to fabricate a schedule for it; callers that
  /// want startup behaviour should run their hook from the host
  /// process supervisor instead.
  RebootNotSupported(value: String)
}

pub fn parse(input input: String) -> Result(RawCron, ParseError) {
  let trimmed = string.trim(input)

  case trimmed {
    "" -> Error(InvalidExpression(value: input))
    _ ->
      case string.starts_with(trimmed, "@") {
        True -> parse_nickname(trimmed)
        False -> parse_five_field(trimmed)
      }
  }
}

fn parse_five_field(trimmed: String) -> Result(RawCron, ParseError) {
  case split_whitespace(trimmed) {
    [minute, hour, day_of_month, month, day_of_week] ->
      case first_empty_field([minute, hour, day_of_month, month, day_of_week]) {
        Some(field) -> Error(EmptyField(field: field))
        None ->
          Ok(RawCron(
            minute: minute,
            hour: hour,
            day_of_month: day_of_month,
            month: month,
            day_of_week: day_of_week,
          ))
      }
    fields -> Error(InvalidFieldCount(expected: 5, actual: list.length(fields)))
  }
}

/// Translate the Vixie cron nickname aliases (`@yearly`, `@annually`,
/// `@monthly`, `@weekly`, `@daily`, `@midnight`, `@hourly`) into their
/// canonical 5-field forms. Matching is case-insensitive, in line with
/// the spec and existing parsers (croniter, robfig/cron, node-cron).
/// `@reboot` is recognised but rejected with `RebootNotSupported`
/// (no 5-field equivalent — see the variant doc). Anything else
/// starting with `@` is `UnsupportedSyntax`.
fn parse_nickname(value: String) -> Result(RawCron, ParseError) {
  case string.lowercase(value) {
    "@yearly" | "@annually" ->
      Ok(RawCron(
        minute: "0",
        hour: "0",
        day_of_month: "1",
        month: "1",
        day_of_week: "*",
      ))
    "@monthly" ->
      Ok(RawCron(
        minute: "0",
        hour: "0",
        day_of_month: "1",
        month: "*",
        day_of_week: "*",
      ))
    "@weekly" ->
      Ok(RawCron(
        minute: "0",
        hour: "0",
        day_of_month: "*",
        month: "*",
        day_of_week: "0",
      ))
    "@daily" | "@midnight" ->
      Ok(RawCron(
        minute: "0",
        hour: "0",
        day_of_month: "*",
        month: "*",
        day_of_week: "*",
      ))
    "@hourly" ->
      Ok(RawCron(
        minute: "0",
        hour: "*",
        day_of_month: "*",
        month: "*",
        day_of_week: "*",
      ))
    "@reboot" -> Error(RebootNotSupported(value: value))
    _ -> Error(UnsupportedSyntax(field: Expression, value: value))
  }
}

fn first_empty_field(fields: List(String)) -> Option(Field) {
  case fields {
    [minute, hour, day_of_month, month, day_of_week] ->
      case minute == "" {
        True -> Some(Minute)
        False ->
          case hour == "" {
            True -> Some(Hour)
            False ->
              case day_of_month == "" {
                True -> Some(DayOfMonth)
                False ->
                  case month == "" {
                    True -> Some(Month)
                    False ->
                      case day_of_week == "" {
                        True -> Some(DayOfWeek)
                        False -> None
                      }
                  }
              }
          }
      }
    _ -> None
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
