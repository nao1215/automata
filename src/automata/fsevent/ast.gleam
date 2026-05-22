//// Public runtime types for filesystem-event operations and the diff
//// snapshots produced by [`automata/fsevent`](./fsevent.html). Despite
//// the `ast` suffix, these are the domain types every fsevent caller
//// needs at runtime — `Op`, `Event`, `Snapshot`, etc. — not parser
//// internals.

/// File-system operation observed between two snapshots.
///
/// Mirrors Go fsnotify's `Op` constants: a single high-level event may
/// carry several `Op` values at once (for example a freshly created
/// non-empty file is reported as `Create` together with `Write`). Kept
/// as a regular sum (not opaque) so callers can pattern-match on each
/// op individually and exhaustively.
pub type Op {
  Create
  Write
  Remove
  Rename
  Chmod
}

/// Kind of file-system entry held in a snapshot.
///
/// `File`, `Directory`, and `Symlink` are the only cases the differ
/// distinguishes. Differences other than `kind` (size, mtime, mode,
/// content hash) are interpreted as `Write` or `Chmod`; a change of
/// `kind` (file replaced by a directory, etc.) is reported as
/// `Remove` followed by `Create` for the new kind.
pub type EntryKind {
  File
  Directory
  Symlink
}

/// Construction-time errors raised by the smart constructors in
/// `automata/fsevent` and friends.
///
/// Each variant carries enough structured context that an LLM or a
/// human operator can understand the rejection without parsing prose.
pub type FseventError {
  /// `path.normalize` was given an empty string.
  EmptyPath
  /// A path segment is the literal `.` or `..`. The differ does not
  /// resolve relative segments and refuses ambiguous input.
  PathContainsDotSegment(path: String, segment: String)
  /// A path contains a `\u{0000}` byte; rejected to keep keys safe
  /// for use as `Dict` keys and string-rendered identifiers.
  PathContainsNullByte(path: String)
  /// `path.normalize` was given a Windows UNC-style path (exactly
  /// two leading slashes after backslash unification, e.g.
  /// `//server/share` or `\\server\share`). The `fsevent` module is
  /// POSIX-only and rejects UNC paths so cross-platform code does
  /// not silently lose the UNC prefix as it normalises. Three or
  /// more leading slashes are still treated as a single leading
  /// slash per POSIX `IEEE Std 1003.1-2017 §4.13`.
  UncPathNotSupported(path: String)
  /// `Snapshot.from_entries` or `Snapshot.add_entry` saw two entries
  /// with the same normalised path.
  DuplicatePath(path: String)
  /// An `Entry` field was given a negative integer where a
  /// non-negative one is required.
  NegativeEntryField(field: String, actual: Int)
  /// An `Entry` numeric field exceeded `max_safe_int` (the limit JS
  /// can represent without precision loss).
  EntryFieldOverflow(field: String, actual: Int)
  /// An optional `Entry` field (content_hash, file_id) was provided
  /// as an empty string. Use `None` instead.
  EmptyOptionalField(field: String)
  /// `WatchEvent.multi_op` was called with an empty op set.
  EmptyOps
  /// `WatchEvent.multi_op` was given a `renamed_from` value but its
  /// op set does not include `Rename`.
  RenamedFromWithoutRenameOp(path: String)
}
