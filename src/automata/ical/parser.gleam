import automata/ical/ast.{
  type RawCalendar, type RawComponent, type RawProperty, RawCalendar,
  RawComponent, RawProperty,
}
import automata/ical/lexer.{type LogicalLine}
import gleam/list
import gleam/result
import gleam/string

pub type ParseError {
  UnexpectedEnd(line: Int)
  MismatchedBlock(begin: String, end: String, line: Int)
  MalformedProperty(line: Int, raw: String)
  MalformedParameter(line: Int, raw: String)
  EmptyInputError
}

pub fn parse(input: String) -> Result(RawCalendar, ParseError) {
  use logical_lines <- result.try(
    lexer.unfold(input) |> result.map_error(lex_error_to_parse_error),
  )
  use properties <- result.try(tokenize_all(logical_lines, []))
  build_calendar(properties)
}

fn lex_error_to_parse_error(err: lexer.LexError) -> ParseError {
  case err {
    lexer.EmptyInput -> EmptyInputError
    lexer.MalformedLine(line: ln, raw: raw) ->
      MalformedProperty(line: ln, raw: raw)
    lexer.MalformedParameter(line: ln, raw: raw) ->
      MalformedParameter(line: ln, raw: raw)
  }
}

fn tokenize_all(
  lines: List(LogicalLine),
  acc: List(RawProperty),
) -> Result(List(RawProperty), ParseError) {
  case lines {
    [] -> Ok(list.reverse(acc))
    [first, ..rest] ->
      case lexer.tokenize_line(first) {
        Error(err) -> Error(lex_error_to_parse_error(err))
        Ok(prop) -> tokenize_all(rest, [prop, ..acc])
      }
  }
}

fn build_calendar(
  properties: List(RawProperty),
) -> Result(RawCalendar, ParseError) {
  case properties {
    [] -> Error(EmptyInputError)
    [RawProperty(name: name, raw_value: raw_value, line: ln, ..), ..rest] -> {
      let normalized_name = name
      let normalized_value = string.uppercase(raw_value)
      case normalized_name, normalized_value {
        "BEGIN", "VCALENDAR" -> {
          use #(vcal, leftover) <- result.try(
            consume_component("VCALENDAR", ln, rest, [], []),
          )
          case leftover {
            [] -> {
              let RawComponent(properties: props, children: children, ..) = vcal
              Ok(RawCalendar(properties: props, components: children))
            }
            [RawProperty(line: leftover_ln, ..), ..] ->
              Error(UnexpectedEnd(line: leftover_ln))
          }
        }
        _, _ -> Error(UnexpectedEnd(line: ln))
      }
    }
  }
}

/// BEGIN:kind の中を読み進めて、END:kind を見つけたらそこで切り上げる。
fn consume_component(
  kind: String,
  begin_line: Int,
  properties: List(RawProperty),
  acc_props: List(RawProperty),
  acc_children: List(RawComponent),
) -> Result(#(RawComponent, List(RawProperty)), ParseError) {
  case properties {
    [] -> Error(MismatchedBlock(begin: kind, end: "<eof>", line: begin_line))
    [first, ..rest] -> {
      let RawProperty(name: name, raw_value: raw_value, line: ln, ..) = first
      case name {
        "END" -> {
          let end_kind = string.uppercase(raw_value)
          case end_kind == kind {
            True -> {
              let component =
                RawComponent(
                  kind: kind,
                  properties: list.reverse(acc_props),
                  children: list.reverse(acc_children),
                  begin_line: begin_line,
                )
              Ok(#(component, rest))
            }
            False ->
              Error(MismatchedBlock(begin: kind, end: end_kind, line: ln))
          }
        }
        "BEGIN" -> {
          let child_kind = string.uppercase(raw_value)
          use #(child, after) <- result.try(
            consume_component(child_kind, ln, rest, [], []),
          )
          consume_component(kind, begin_line, after, acc_props, [
            child,
            ..acc_children
          ])
        }
        _ ->
          consume_component(
            kind,
            begin_line,
            rest,
            [first, ..acc_props],
            acc_children,
          )
      }
    }
  }
}
