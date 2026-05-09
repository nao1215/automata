import automata/rrule/ast.{
  type RawRRule, type RawRulePart, RawRRule, RawRulePart,
}
import gleam/list
import gleam/string

pub type ParseError {
  InvalidRule(value: String)
  InvalidPartSyntax(value: String)
  EmptyPart(value: String)
}

pub fn parse(input input: String) -> Result(RawRRule, ParseError) {
  let trimmed = string.trim(input)

  case trimmed {
    "" -> Error(InvalidRule(value: input))
    _ -> parse_parts(strip_prefix(trimmed))
  }
}

fn strip_prefix(input: String) -> String {
  case string.starts_with(string.uppercase(input), "RRULE:") {
    True -> string.drop_start(input, up_to: 6)
    False -> input
  }
}

fn parse_parts(body: String) -> Result(RawRRule, ParseError) {
  case body {
    "" -> Error(InvalidRule(value: body))
    _ ->
      case list.any(string.split(body, on: ";"), string.is_empty) {
        True -> Error(InvalidRule(value: body))
        False -> collect_parts(string.split(body, on: ";"), [])
      }
  }
}

fn collect_parts(
  parts: List(String),
  acc: List(RawRulePart),
) -> Result(RawRRule, ParseError) {
  case parts {
    [] -> Ok(RawRRule(parts: list.reverse(acc)))
    [part, ..rest] ->
      case string.split_once(string.trim(part), on: "=") {
        Error(_) -> Error(InvalidPartSyntax(value: part))
        Ok(#(name, value)) ->
          case string.trim(name) == "" || string.trim(value) == "" {
            True -> Error(EmptyPart(value: part))
            False ->
              collect_parts(rest, [
                RawRulePart(
                  name: string.uppercase(string.trim(name)),
                  value: string.trim(value),
                ),
                ..acc
              ])
          }
      }
  }
}
