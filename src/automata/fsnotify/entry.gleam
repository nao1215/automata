import automata/fsnotify/ast.{
  type EntryKind, type FsnotifyError, Directory, EmptyOptionalField,
  EntryFieldOverflow, File, NegativeEntryField, Symlink,
}
import automata/fsnotify/path.{type NormalizedPath}
import gleam/option.{type Option, None, Some}

/// Largest integer JavaScript's `Number` can represent without losing
/// precision. We reuse the cap from `automata/retry/ast` so a value
/// that round-trips through the BEAM and JavaScript targets always
/// produces the same answer.
const max_safe_int: Int = 9_007_199_254_740_991

/// One file-system entry observed at a single point in time.
///
/// `opaque` so the only way to construct a value is through the
/// validating smart constructors `entry_file`, `entry_directory`,
/// `entry_symlink`. They reject negative integers, integers above the
/// JS-safe range, and empty optional strings before a snapshot is
/// built. Differences detected later by the differ therefore reflect
/// the inputs the caller intended, not silently truncated data.
///
/// `mtime` is unit-less: pick seconds, milliseconds, microseconds,
/// nanoseconds, or anything else, and use the same unit consistently
/// across snapshots that you intend to compare. The differ only ever
/// checks `prev.mtime != curr.mtime`. Values must fit within
/// `max_safe_int` (JS `Number.MAX_SAFE_INTEGER`) so the same equality
/// check produces the same answer on both the BEAM and JS targets.
pub opaque type Entry {
  Entry(
    path: NormalizedPath,
    kind: EntryKind,
    size: Int,
    mtime: Int,
    mode: Int,
    content_hash: Option(String),
    file_id: Option(String),
  )
}

/// Build a `File` entry. `content_hash` and `file_id` are optional; if
/// provided as `Some(_)`, an empty string is rejected.
pub fn entry_file(
  path path: NormalizedPath,
  size size: Int,
  mtime mtime: Int,
  mode mode: Int,
  content_hash content_hash: Option(String),
  file_id file_id: Option(String),
) -> Result(Entry, FsnotifyError) {
  case validate_size(size) {
    Error(error) -> Error(error)
    Ok(_) ->
      case validate_mtime(mtime) {
        Error(error) -> Error(error)
        Ok(_) ->
          case validate_optional_string("content_hash", content_hash) {
            Error(error) -> Error(error)
            Ok(_) ->
              case validate_optional_string("file_id", file_id) {
                Error(error) -> Error(error)
                Ok(_) ->
                  Ok(Entry(
                    path: path,
                    kind: File,
                    size: size,
                    mtime: mtime,
                    mode: mode,
                    content_hash: content_hash,
                    file_id: file_id,
                  ))
              }
          }
      }
  }
}

/// Build a `Directory` entry. Directories have no meaningful size (the
/// differ never compares `size` for directories), so the field is
/// stored as `0`.
pub fn entry_directory(
  path path: NormalizedPath,
  mtime mtime: Int,
  mode mode: Int,
  file_id file_id: Option(String),
) -> Result(Entry, FsnotifyError) {
  build_non_file(path, Directory, mtime, mode, file_id)
}

/// Build a `Symlink` entry. Like directories, symlinks carry no
/// meaningful `size` for diffing purposes.
pub fn entry_symlink(
  path path: NormalizedPath,
  mtime mtime: Int,
  mode mode: Int,
  file_id file_id: Option(String),
) -> Result(Entry, FsnotifyError) {
  build_non_file(path, Symlink, mtime, mode, file_id)
}

pub fn entry_path(entry entry: Entry) -> NormalizedPath {
  entry.path
}

pub fn entry_kind(entry entry: Entry) -> EntryKind {
  entry.kind
}

pub fn entry_size(entry entry: Entry) -> Int {
  entry.size
}

pub fn entry_mtime(entry entry: Entry) -> Int {
  entry.mtime
}

pub fn entry_mode(entry entry: Entry) -> Int {
  entry.mode
}

pub fn entry_content_hash(entry entry: Entry) -> Option(String) {
  entry.content_hash
}

pub fn entry_file_id(entry entry: Entry) -> Option(String) {
  entry.file_id
}

/// `True` when both entries carry a hash and the hashes are equal.
/// Two entries with no hash are considered "unknown content"; the
/// caller decides what to do in that case.
@internal
pub fn entries_content_hash_equal(a a: Entry, b b: Entry) -> Bool {
  case a.content_hash, b.content_hash {
    Some(left), Some(right) -> left == right
    _, _ -> False
  }
}

/// `True` when both entries carry a hash. Used by the differ to decide
/// whether `entries_content_hash_equal` is meaningful.
@internal
pub fn entries_have_both_hashes(a a: Entry, b b: Entry) -> Bool {
  case a.content_hash, b.content_hash {
    Some(_), Some(_) -> True
    _, _ -> False
  }
}

fn build_non_file(
  path: NormalizedPath,
  kind: EntryKind,
  mtime: Int,
  mode: Int,
  file_id: Option(String),
) -> Result(Entry, FsnotifyError) {
  case validate_mtime(mtime) {
    Error(error) -> Error(error)
    Ok(_) ->
      case validate_optional_string("file_id", file_id) {
        Error(error) -> Error(error)
        Ok(_) ->
          Ok(Entry(
            path: path,
            kind: kind,
            size: 0,
            mtime: mtime,
            mode: mode,
            content_hash: None,
            file_id: file_id,
          ))
      }
  }
}

fn validate_size(size: Int) -> Result(Nil, FsnotifyError) {
  validate_non_negative_bounded("size", size)
}

fn validate_mtime(mtime: Int) -> Result(Nil, FsnotifyError) {
  validate_non_negative_bounded("mtime", mtime)
}

fn validate_non_negative_bounded(
  field: String,
  value: Int,
) -> Result(Nil, FsnotifyError) {
  case value < 0 {
    True -> Error(NegativeEntryField(field: field, actual: value))
    False ->
      case value > max_safe_int {
        True -> Error(EntryFieldOverflow(field: field, actual: value))
        False -> Ok(Nil)
      }
  }
}

fn validate_optional_string(
  field: String,
  value: Option(String),
) -> Result(Nil, FsnotifyError) {
  case value {
    None -> Ok(Nil)
    Some("") -> Error(EmptyOptionalField(field: field))
    Some(_) -> Ok(Nil)
  }
}
