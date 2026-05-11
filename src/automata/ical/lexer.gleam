import automata/ical/ast.{
  type Parameter, type RawProperty, Parameter, RawProperty,
}
import gleam/list
import gleam/string

/// 物理行を unfold した後の論理行。
/// text: unfold 済みの 1 論理行の生テキスト
/// line: 論理行の開始物理行番号 (1-origin)
pub type LogicalLine {
  LogicalLine(text: String, line: Int)
}

pub type LexError {
  EmptyInput
  MalformedLine(line: Int, raw: String)
  MalformedParameter(line: Int, raw: String)
}

/// 入力文字列を RFC 5545 §3.1 に従って unfold し、
/// 空行を除いた `LogicalLine` のリストを返す。
pub fn unfold(input: String) -> Result(List(LogicalLine), LexError) {
  case input {
    "" -> Error(EmptyInput)
    _ -> {
      let stripped = strip_bom(input)
      let normalized =
        stripped
        |> string.replace("\r\n", "\n")
        |> string.replace("\r", "\n")
      let physical_lines = string.split(normalized, "\n")
      let folded = fold_lines(physical_lines, 1, [])
      let non_empty =
        list.filter(folded, fn(line) {
          let LogicalLine(text: text, ..) = line
          text != ""
        })
      case non_empty {
        [] -> Error(EmptyInput)
        _ -> Ok(non_empty)
      }
    }
  }
}

fn strip_bom(input: String) -> String {
  case string.starts_with(input, "\u{FEFF}") {
    True -> string.replace(input, "\u{FEFF}", "")
    False -> input
  }
}

/// 物理行を順番に走査して unfold した結果を順序保持で返す。
fn fold_lines(
  physical_lines: List(String),
  current_line: Int,
  acc: List(LogicalLine),
) -> List(LogicalLine) {
  case physical_lines {
    [] -> list.reverse(acc)
    [first, ..rest] -> {
      let is_continuation =
        string.starts_with(first, " ") || string.starts_with(first, "\t")
      case is_continuation, acc {
        True, [LogicalLine(text: prev_text, line: prev_ln), ..tail] -> {
          let appended = prev_text <> string.drop_start(first, 1)
          let new_acc = [LogicalLine(text: appended, line: prev_ln), ..tail]
          fold_lines(rest, current_line + 1, new_acc)
        }
        // 先頭が継続行の場合は仕様外だが、ロバストに新規行として扱う。
        True, [] ->
          fold_lines(rest, current_line + 1, [
            LogicalLine(text: first, line: current_line),
            ..acc
          ])
        False, _ ->
          fold_lines(rest, current_line + 1, [
            LogicalLine(text: first, line: current_line),
            ..acc
          ])
      }
    }
  }
}

/// 論理行を name / parameters / raw_value に分解した `RawProperty` にする。
pub fn tokenize_line(line: LogicalLine) -> Result(RawProperty, LexError) {
  let LogicalLine(text: text, line: ln) = line
  case text {
    "" -> Error(MalformedLine(line: ln, raw: text))
    _ -> {
      let graphemes = string.to_graphemes(text)
      case split_at_unquoted(graphemes, ":") {
        Error(_) -> Error(MalformedLine(line: ln, raw: text))
        Ok(#(head, raw_value)) -> {
          let head_graphemes = string.to_graphemes(head)
          let head_parts = split_all_unquoted(head_graphemes, ";")
          case head_parts {
            [] -> Error(MalformedLine(line: ln, raw: text))
            [name_token, ..param_tokens] -> {
              case name_token {
                "" -> Error(MalformedLine(line: ln, raw: text))
                _ -> {
                  let normalized_name = string.uppercase(name_token)
                  case parse_parameters(param_tokens, ln, []) {
                    Error(err) -> Error(err)
                    Ok(parameters) ->
                      Ok(RawProperty(
                        name: normalized_name,
                        parameters: parameters,
                        raw_value: raw_value,
                        line: ln,
                      ))
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

fn parse_parameters(
  tokens: List(String),
  ln: Int,
  acc: List(Parameter),
) -> Result(List(Parameter), LexError) {
  case tokens {
    [] -> Ok(list.reverse(acc))
    [first, ..rest] ->
      case parse_parameter(first, ln) {
        Error(err) -> Error(err)
        Ok(param) -> parse_parameters(rest, ln, [param, ..acc])
      }
  }
}

fn parse_parameter(raw: String, ln: Int) -> Result(Parameter, LexError) {
  let graphemes = string.to_graphemes(raw)
  case split_at_unquoted(graphemes, "=") {
    Error(_) -> Error(MalformedParameter(line: ln, raw: raw))
    Ok(#(name, value)) ->
      case name, value {
        "", _ -> Error(MalformedParameter(line: ln, raw: raw))
        _, _ ->
          case strip_dquotes(value, raw, ln) {
            Error(err) -> Error(err)
            Ok(stripped) ->
              Ok(Parameter(name: string.uppercase(name), value: stripped))
          }
      }
  }
}

/// 値の両端を囲む `"` を剥がす。片方しか付いていなければエラー。
fn strip_dquotes(
  value: String,
  raw: String,
  ln: Int,
) -> Result(String, LexError) {
  let starts = string.starts_with(value, "\"")
  let ends = string.ends_with(value, "\"")
  case starts, ends {
    True, True -> {
      // 両端 quote。長さ 1 の場合は中身が空文字列 (というか不正) なので空扱い。
      let dropped_start = string.drop_start(value, 1)
      let stripped = string.drop_end(dropped_start, 1)
      Ok(stripped)
    }
    False, False -> Ok(value)
    _, _ -> Error(MalformedParameter(line: ln, raw: raw))
  }
}

/// quote 認識付きで最初に現れる separator で 1 回だけ分割する。
/// 見つからなければ Error(Nil)。
fn split_at_unquoted(
  graphemes: List(String),
  separator: String,
) -> Result(#(String, String), Nil) {
  do_split_at_unquoted(graphemes, separator, False, [])
}

fn do_split_at_unquoted(
  graphemes: List(String),
  separator: String,
  in_quote: Bool,
  acc: List(String),
) -> Result(#(String, String), Nil) {
  case graphemes {
    [] -> Error(Nil)
    [g, ..rest] ->
      case g, in_quote {
        "\"", _ -> do_split_at_unquoted(rest, separator, !in_quote, [g, ..acc])
        _, False ->
          case g == separator {
            True -> {
              let head = string.concat(list.reverse(acc))
              let tail = string.concat(rest)
              Ok(#(head, tail))
            }
            False -> do_split_at_unquoted(rest, separator, in_quote, [g, ..acc])
          }
        _, True -> do_split_at_unquoted(rest, separator, in_quote, [g, ..acc])
      }
  }
}

/// quote 認識付きで separator が現れる毎に分割し、トークン列を返す。
fn split_all_unquoted(
  graphemes: List(String),
  separator: String,
) -> List(String) {
  do_split_all_unquoted(graphemes, separator, False, [], [])
}

fn do_split_all_unquoted(
  graphemes: List(String),
  separator: String,
  in_quote: Bool,
  current: List(String),
  acc: List(String),
) -> List(String) {
  case graphemes {
    [] -> {
      let last = string.concat(list.reverse(current))
      list.reverse([last, ..acc])
    }
    [g, ..rest] ->
      case g, in_quote {
        "\"", _ ->
          do_split_all_unquoted(rest, separator, !in_quote, [g, ..current], acc)
        _, False ->
          case g == separator {
            True -> {
              let token = string.concat(list.reverse(current))
              do_split_all_unquoted(rest, separator, in_quote, [], [
                token,
                ..acc
              ])
            }
            False ->
              do_split_all_unquoted(
                rest,
                separator,
                in_quote,
                [g, ..current],
                acc,
              )
          }
        _, True ->
          do_split_all_unquoted(rest, separator, in_quote, [g, ..current], acc)
      }
  }
}
