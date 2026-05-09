import automata/fsevent/ast.{type FseventError, DuplicatePath}
import automata/fsevent/entry.{type Entry}
import automata/fsevent/path.{type NormalizedPath}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// Immutable snapshot of one filesystem subtree at a single instant.
///
/// `opaque` because the only legitimate way to construct a snapshot
/// is through entries that have already passed `Entry`'s validation.
/// Snapshots are keyed on the canonical string rendering of each
/// entry's `NormalizedPath` so callers can `lookup` by either string
/// or `NormalizedPath` without constructing a new opaque value.
pub opaque type Snapshot {
  Snapshot(by_path: Dict(String, Entry))
}

/// A snapshot containing no entries.
pub fn empty_snapshot() -> Snapshot {
  Snapshot(by_path: dict.new())
}

/// Build a snapshot from a list of entries. Two entries with the
/// same path is rejected as `DuplicatePath`. Entries with the same
/// `file_id` but different paths are allowed (POSIX hard links).
pub fn from_entries(
  entries entries: List(Entry),
) -> Result(Snapshot, FseventError) {
  insert_all(empty_snapshot(), entries)
}

/// Insert a single entry. Rejected if the path is already present.
pub fn add_entry(
  snapshot snapshot: Snapshot,
  entry e: Entry,
) -> Result(Snapshot, FseventError) {
  let key = entry_key(e)
  case dict.has_key(snapshot.by_path, key) {
    True -> Error(DuplicatePath(path: key))
    False -> Ok(Snapshot(by_path: dict.insert(snapshot.by_path, key, e)))
  }
}

/// All entries the snapshot holds, sorted by canonical path so that
/// the order is deterministic across the BEAM and JavaScript targets.
pub fn entries(snapshot snapshot: Snapshot) -> List(Entry) {
  snapshot.by_path
  |> dict.to_list
  |> list.sort(fn(a, b) {
    let #(left_key, _) = a
    let #(right_key, _) = b
    string.compare(left_key, right_key)
  })
  |> list.map(fn(pair) { pair.1 })
}

/// Look up the entry at `path`, if any.
pub fn lookup(
  snapshot snapshot: Snapshot,
  path path: NormalizedPath,
) -> Option(Entry) {
  case dict.get(snapshot.by_path, path.path_to_string(path)) {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

/// Number of entries in the snapshot.
pub fn snapshot_size(snapshot snapshot: Snapshot) -> Int {
  dict.size(snapshot.by_path)
}

/// `True` when the snapshot has no entries.
pub fn is_empty(snapshot snapshot: Snapshot) -> Bool {
  dict.size(snapshot.by_path) == 0
}

@internal
pub fn entries_unsorted(snapshot: Snapshot) -> List(Entry) {
  dict.values(snapshot.by_path)
}

@internal
pub fn paths(snapshot: Snapshot) -> List(String) {
  dict.keys(snapshot.by_path)
}

@internal
pub fn entry_key(e: Entry) -> String {
  e
  |> entry.entry_path
  |> path.path_to_string
}

@internal
pub fn lookup_by_key(snapshot: Snapshot, key: String) -> Option(Entry) {
  case dict.get(snapshot.by_path, key) {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

fn insert_all(
  snapshot: Snapshot,
  remaining: List(Entry),
) -> Result(Snapshot, FseventError) {
  case remaining {
    [] -> Ok(snapshot)
    [head, ..rest] ->
      case add_entry(snapshot: snapshot, entry: head) {
        Error(error) -> Error(error)
        Ok(updated) -> insert_all(updated, rest)
      }
  }
}
