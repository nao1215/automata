import automata/fsevent/ast.{
  type FseventError, EmptyPath, PathContainsDotSegment, PathContainsNullByte,
  UncPathNotSupported,
}
import gleam/list
import gleam/result
import gleam/string

/// A path that has been canonicalised into a portable form: backslashes
/// become forward slashes, repeated separators are collapsed, trailing
/// separators are stripped, and segments are validated.
///
/// `opaque` so the only way to obtain a value is through `normalize/1`.
/// The differ keys snapshots and watch events on `NormalizedPath`, so
/// this is the type that pins down equality and ordering of paths.
pub opaque type NormalizedPath {
  NormalizedPath(value: String, segments: List(String), absolute: Bool)
}

/// Canonicalise a string into a `NormalizedPath`.
///
/// The library does not call `os.path.realpath`-style resolution: it
/// works at the string level so it stays pure and produces the same
/// output on every platform regardless of the underlying filesystem.
pub fn normalize(path path: String) -> Result(NormalizedPath, FseventError) {
  use _ <- result.try(reject_empty(path))
  use _ <- result.try(reject_null_byte(path))
  let unified = string.replace(path, "\\", "/")
  use _ <- result.try(reject_unc_prefix(path, unified))
  let raw_segments = string.split(unified, "/")
  let segments = list.filter(raw_segments, fn(s) { s != "" })
  use _ <- result.try(validate_segments(path, segments))
  Ok(build(unified, segments))
}

fn reject_empty(path: String) -> Result(Nil, FseventError) {
  case path {
    "" -> Error(EmptyPath)
    _ -> Ok(Nil)
  }
}

fn reject_null_byte(path: String) -> Result(Nil, FseventError) {
  case string.contains(path, "\u{0000}") {
    True -> Error(PathContainsNullByte(path: path))
    False -> Ok(Nil)
  }
}

fn reject_unc_prefix(
  original: String,
  unified: String,
) -> Result(Nil, FseventError) {
  case is_unc_prefix(unified) {
    True -> Error(UncPathNotSupported(path: original))
    False -> Ok(Nil)
  }
}

/// `True` when `unified` has exactly two leading forward slashes —
/// the case POSIX `IEEE Std 1003.1-2017 §4.13` flags as
/// implementation-defined and Windows uses for UNC paths
/// (`//server/share` or `\\server\share` after backslash unification).
/// Three or more leading slashes are POSIX-equivalent to a single
/// slash and remain accepted.
fn is_unc_prefix(unified: String) -> Bool {
  string.starts_with(unified, "//") && !string.starts_with(unified, "///")
}

/// The canonical string rendering of a normalised path.
pub fn path_to_string(path path: NormalizedPath) -> String {
  path.value
}

/// The path's segments in source order (the empty root has no segments).
pub fn path_segments(path path: NormalizedPath) -> List(String) {
  path.segments
}

/// `True` when the path is rooted: it either begins with a leading
/// separator after normalisation (`/foo`, `\\srv\share` → `//srv/share`)
/// or its first segment is a Windows drive letter (`C:\foo` → first
/// segment `C:`). Relative paths return `False`.
pub fn path_is_absolute(path path: NormalizedPath) -> Bool {
  path.absolute
}

/// Structural equality on the canonicalised representation.
pub fn path_equals(
  left left: NormalizedPath,
  right right: NormalizedPath,
) -> Bool {
  left.value == right.value
}

/// `True` when `path` is `prefix` itself or sits beneath `prefix` as a
/// proper ancestor relation (segment-wise; `/var/log` does not start
/// with `/var/lo`).
pub fn path_starts_with(
  path path: NormalizedPath,
  prefix prefix: NormalizedPath,
) -> Bool {
  case prefix.absolute == path.absolute {
    False -> False
    True -> segments_start_with(path.segments, prefix.segments)
  }
}

fn segments_start_with(path: List(String), prefix: List(String)) -> Bool {
  case prefix {
    [] -> True
    [head_prefix, ..rest_prefix] ->
      case path {
        [] -> False
        [head_path, ..rest_path] ->
          case head_path == head_prefix {
            False -> False
            True -> segments_start_with(rest_path, rest_prefix)
          }
      }
  }
}

fn validate_segments(
  original: String,
  segments: List(String),
) -> Result(Nil, FseventError) {
  case segments {
    [] -> Ok(Nil)
    [head, ..rest] ->
      case head {
        "." -> Error(PathContainsDotSegment(path: original, segment: "."))
        ".." -> Error(PathContainsDotSegment(path: original, segment: ".."))
        _ -> validate_segments(original, rest)
      }
  }
}

fn starts_with_drive_letter(segments: List(String)) -> Bool {
  case segments {
    [first, ..] -> is_drive_letter(first)
    [] -> False
  }
}

fn is_drive_letter(segment: String) -> Bool {
  case segment {
    "A:"
    | "B:"
    | "C:"
    | "D:"
    | "E:"
    | "F:"
    | "G:"
    | "H:"
    | "I:"
    | "J:"
    | "K:"
    | "L:"
    | "M:"
    | "N:"
    | "O:"
    | "P:"
    | "Q:"
    | "R:"
    | "S:"
    | "T:"
    | "U:"
    | "V:"
    | "W:"
    | "X:"
    | "Y:"
    | "Z:" -> True
    "a:"
    | "b:"
    | "c:"
    | "d:"
    | "e:"
    | "f:"
    | "g:"
    | "h:"
    | "i:"
    | "j:"
    | "k:"
    | "l:"
    | "m:"
    | "n:"
    | "o:"
    | "p:"
    | "q:"
    | "r:"
    | "s:"
    | "t:"
    | "u:"
    | "v:"
    | "w:"
    | "x:"
    | "y:"
    | "z:" -> True
    _ -> False
  }
}

fn build(unified: String, segments: List(String)) -> NormalizedPath {
  let joined = string.join(segments, "/")
  let slash_prefix = string.starts_with(unified, "/")
  let absolute = slash_prefix || starts_with_drive_letter(segments)
  let value = case slash_prefix, joined {
    True, "" -> "/"
    True, _ -> "/" <> joined
    False, _ -> joined
  }
  NormalizedPath(value: value, segments: segments, absolute: absolute)
}
