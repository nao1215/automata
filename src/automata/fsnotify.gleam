import automata/fsnotify/ast
import automata/fsnotify/diff as fs_diff
import automata/fsnotify/event as fs_event
import automata/fsnotify/path as fs_path
import automata/fsnotify/snapshot as fs_snapshot
import automata/fsnotify/watch as fs_watch

/// Pure-domain port of the Go fsnotify semantics: `Create`, `Write`,
/// `Remove`, `Rename`, `Chmod` operations derived from comparing two
/// filesystem `Snapshot` values. The library performs **no I/O**; the
/// caller produces snapshots by whatever means is appropriate (real
/// filesystem walk, mocked entries in tests, log replay) and feeds
/// pairs to `diff/3`.
///
/// This module is the user-facing facade. Each submodule remains a
/// fine-grained entry point: callers that only need path
/// normalisation can `import automata/fsnotify/path` directly without
/// pulling in the differ.
pub type Op =
  ast.Op

pub type EntryKind =
  ast.EntryKind

pub type FsnotifyError =
  ast.FsnotifyError

/// A default `Watch`: every op subscribed.
pub fn watch() -> fs_watch.Watch {
  fs_watch.watch()
}

/// Compute the events emitted when `prev` is replaced by `curr` under
/// the subscription described by `watch`.
pub fn diff(
  prev prev: fs_snapshot.Snapshot,
  curr curr: fs_snapshot.Snapshot,
  watch watch: fs_watch.Watch,
) -> List(fs_event.WatchEvent) {
  fs_diff.diff(prev: prev, curr: curr, watch: watch)
}

/// Canonicalise a string into a `NormalizedPath`.
pub fn normalize(
  path path: String,
) -> Result(fs_path.NormalizedPath, ast.FsnotifyError) {
  fs_path.normalize(path: path)
}
