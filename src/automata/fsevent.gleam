import automata/fsevent/ast
import automata/fsevent/diff as fs_diff
import automata/fsevent/entry as fs_entry
import automata/fsevent/event as fs_event
import automata/fsevent/path as fs_path
import automata/fsevent/snapshot as fs_snapshot
import automata/fsevent/watch as fs_watch
import gleam/option.{type Option}
import gleam/set.{type Set}

/// Pure-domain port of Go fsnotify semantics: `Create`, `Write`,
/// `Remove`, `Rename`, and `Chmod` operations derived from comparing
/// two filesystem `Snapshot` values. The library performs no I/O; the
/// caller produces snapshots by whatever means is appropriate (real
/// filesystem walk, mocked entries in tests, log replay) and feeds
/// pairs to `diff/3`.
///
/// This module is the user-facing facade. The submodules
/// (`fsevent/{ast,path,op,entry,snapshot,watch,event,diff}`) remain
/// available for callers who only need a slice of the API.
pub type Op =
  ast.Op

pub type EntryKind =
  ast.EntryKind

pub type FseventError =
  ast.FseventError

pub type NormalizedPath =
  fs_path.NormalizedPath

pub type Entry =
  fs_entry.Entry

pub type Snapshot =
  fs_snapshot.Snapshot

pub type Watch =
  fs_watch.Watch

pub type WatchEvent =
  fs_event.WatchEvent

// Path -----------------------------------------------------------------

/// Canonicalise a string into a `NormalizedPath`.
pub fn normalize(path path: String) -> Result(NormalizedPath, FseventError) {
  fs_path.normalize(path: path)
}

pub fn path_to_string(path path: NormalizedPath) -> String {
  fs_path.path_to_string(path: path)
}

pub fn path_segments(path path: NormalizedPath) -> List(String) {
  fs_path.path_segments(path: path)
}

pub fn path_is_absolute(path path: NormalizedPath) -> Bool {
  fs_path.path_is_absolute(path: path)
}

pub fn path_starts_with(
  path path: NormalizedPath,
  prefix prefix: NormalizedPath,
) -> Bool {
  fs_path.path_starts_with(path: path, prefix: prefix)
}

// Entry ----------------------------------------------------------------

/// Build a `File` entry. `mtime` is unit-less; the differ only checks
/// equality, so pick a unit (seconds, milliseconds, nanoseconds, ...)
/// and use it consistently across snapshots.
pub fn entry_file(
  path path: NormalizedPath,
  size size: Int,
  mtime mtime: Int,
  mode mode: Int,
  content_hash content_hash: Option(String),
  file_id file_id: Option(String),
) -> Result(Entry, FseventError) {
  fs_entry.entry_file(
    path: path,
    size: size,
    mtime: mtime,
    mode: mode,
    content_hash: content_hash,
    file_id: file_id,
  )
}

pub fn entry_directory(
  path path: NormalizedPath,
  mtime mtime: Int,
  mode mode: Int,
  file_id file_id: Option(String),
) -> Result(Entry, FseventError) {
  fs_entry.entry_directory(
    path: path,
    mtime: mtime,
    mode: mode,
    file_id: file_id,
  )
}

pub fn entry_symlink(
  path path: NormalizedPath,
  mtime mtime: Int,
  mode mode: Int,
  file_id file_id: Option(String),
) -> Result(Entry, FseventError) {
  fs_entry.entry_symlink(path: path, mtime: mtime, mode: mode, file_id: file_id)
}

// Snapshot -------------------------------------------------------------

pub fn empty_snapshot() -> Snapshot {
  fs_snapshot.empty_snapshot()
}

pub fn from_entries(
  entries entries: List(Entry),
) -> Result(Snapshot, FseventError) {
  fs_snapshot.from_entries(entries: entries)
}

pub fn add_entry(
  snapshot snapshot: Snapshot,
  entry entry: Entry,
) -> Result(Snapshot, FseventError) {
  fs_snapshot.add_entry(snapshot: snapshot, entry: entry)
}

pub fn lookup(
  snapshot snapshot: Snapshot,
  path path: NormalizedPath,
) -> Option(Entry) {
  fs_snapshot.lookup(snapshot: snapshot, path: path)
}

pub fn snapshot_size(snapshot snapshot: Snapshot) -> Int {
  fs_snapshot.snapshot_size(snapshot: snapshot)
}

// Watch ----------------------------------------------------------------

/// Default `Watch`: subscribed to every op.
pub fn watch() -> Watch {
  fs_watch.watch()
}

pub fn watch_all_ops() -> Watch {
  fs_watch.watch_all_ops()
}

pub fn watch_no_ops() -> Watch {
  fs_watch.watch_no_ops()
}

pub fn watch_op(watch watch: Watch, op op: Op) -> Watch {
  fs_watch.watch_op(watch: watch, op: op)
}

pub fn unwatch_op(watch watch: Watch, op op: Op) -> Watch {
  fs_watch.unwatch_op(watch: watch, op: op)
}

pub fn with_ops(watch watch: Watch, ops ops: Set(Op)) -> Watch {
  fs_watch.with_ops(watch: watch, ops: ops)
}

// WatchEvent -----------------------------------------------------------

pub fn created(path path: NormalizedPath) -> WatchEvent {
  fs_event.created(path: path)
}

pub fn written(path path: NormalizedPath) -> WatchEvent {
  fs_event.written(path: path)
}

pub fn removed(path path: NormalizedPath) -> WatchEvent {
  fs_event.removed(path: path)
}

pub fn chmoded(path path: NormalizedPath) -> WatchEvent {
  fs_event.chmoded(path: path)
}

pub fn renamed(to to: NormalizedPath, from from: NormalizedPath) -> WatchEvent {
  fs_event.renamed(to: to, from: from)
}

pub fn event_path(event event: WatchEvent) -> NormalizedPath {
  fs_event.event_path(event: event)
}

pub fn event_ops(event event: WatchEvent) -> Set(Op) {
  fs_event.event_ops(event: event)
}

pub fn event_has(event event: WatchEvent, op op: Op) -> Bool {
  fs_event.event_has(event: event, op: op)
}

pub fn event_renamed_from(event event: WatchEvent) -> Option(NormalizedPath) {
  fs_event.event_renamed_from(event: event)
}

// Diff -----------------------------------------------------------------

/// Compute the events emitted when `prev` is replaced by `curr` under
/// the subscription described by `watch`.
pub fn diff(
  prev prev: Snapshot,
  curr curr: Snapshot,
  watch watch: Watch,
) -> List(WatchEvent) {
  fs_diff.diff(prev: prev, curr: curr, watch: watch)
}
