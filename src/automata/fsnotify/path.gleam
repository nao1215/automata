import automata/fsnotify/ast.{
  type FsnotifyError, EmptyPath, PathContainsDotSegment, PathContainsNullByte,
}
import gleam/list
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
pub fn normalize(path path: String) -> Result(NormalizedPath, FsnotifyError) {
  case path {
    "" -> Error(EmptyPath)
    _ ->
      case string.contains(path, "\u{0000}") {
        True -> Error(PathContainsNullByte(path: path))
        False -> {
          let unified = string.replace(path, "\\", "/")
          let absolute = string.starts_with(unified, "/")
          let raw_segments = string.split(unified, "/")
          let segments = list.filter(raw_segments, fn(s) { s != "" })
          case validate_segments(path, segments) {
            Error(error) -> Error(error)
            Ok(_) -> Ok(build(absolute, segments, path))
          }
        }
      }
  }
}

/// The canonical string rendering of a normalised path.
pub fn path_to_string(path path: NormalizedPath) -> String {
  path.value
}

/// The path's segments in source order (the empty root has no segments).
pub fn path_segments(path path: NormalizedPath) -> List(String) {
  path.segments
}

/// `True` when the path begins with a leading separator after
/// normalisation. Paths normalised from `C:\foo` are treated as
/// absolute because `C:` becomes the first segment of an absolute
/// path; paths normalised from `\\srv\share` are likewise absolute.
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
) -> Result(Nil, FsnotifyError) {
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

fn build(
  absolute: Bool,
  segments: List(String),
  original: String,
) -> NormalizedPath {
  let joined = string.join(segments, "/")
  let value = case absolute, joined {
    True, "" -> "/"
    True, _ -> "/" <> joined
    False, "" -> original
    False, _ -> joined
  }
  NormalizedPath(value: value, segments: segments, absolute: absolute)
}
