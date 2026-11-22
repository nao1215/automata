import automata/fsevent/ast.{type Op, Chmod, Create, Remove, Rename, Write}
import automata/fsevent/entry.{type Entry}
import automata/fsevent/event.{type WatchEvent}
import automata/fsevent/op
import automata/fsevent/path.{type NormalizedPath}
import automata/fsevent/snapshot.{type Snapshot}
import automata/fsevent/watch.{type Watch}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}
import gleam/string

/// Compute the events emitted when `prev` is replaced by `curr` under
/// the subscription described by `watch`.
///
/// The result list is sorted by canonical path so the output is
/// deterministic across the BEAM and JavaScript targets.
///
/// Rename detection: when the same `file_id` is observed at two
/// different paths across `prev` and `curr` and the disappearance and
/// appearance pair up one-to-one, the differ folds the would-be
/// `Remove` (at the old path) and `Create` (at the new path) into a
/// single `Rename` event whose `renamed_from` carries the old path.
/// If no `file_id` is available, the pairing is ambiguous, or `watch`
/// does not include `Rename`, the rename is reported as a `Remove` at
/// the old path and a `Create` at the new one (plus `Write` when the
/// new file is non-empty, as for any new file).
pub fn diff(
  prev prev: Snapshot,
  curr curr: Snapshot,
  watch watch: Watch,
) -> List(WatchEvent) {
  // A watch without Rename gets the Remove and Create pair, so a move is
  // still visible to a Create or Remove subscriber.
  let renames = case set.contains(watch.watch_op_mask(watch), Rename) {
    True -> detect_renames(prev, curr)
    False -> dict.new()
  }
  let suppressed_old_paths = renames_suppressed_paths(renames, curr)
  let union = path_union(prev, curr)

  union
  |> list.filter_map(fn(key) {
    case set.contains(suppressed_old_paths, key) {
      True -> Error(Nil)
      False ->
        build_event_for(key, prev, curr, renames)
        |> apply_op_mask(watch)
    }
  })
  |> list.sort(fn(a, b) {
    string.compare(
      path.path_to_string(event.event_path(a)),
      path.path_to_string(event.event_path(b)),
    )
  })
}

/// Pure decision table comparing two `Option(Entry)` values: returns
/// the canonical op set the differ would assign before rename
/// detection runs. Exposed for testing.
@internal
pub fn compare_entry(
  old old: Option(Entry),
  new new: Option(Entry),
) -> Set(Op) {
  case old, new {
    None, None -> op.empty_ops()
    None, Some(e) -> ops_for_creation(e)
    Some(_), None -> op.single_op(Remove)
    Some(o), Some(n) ->
      case entry.entry_kind(o) == entry.entry_kind(n) {
        False -> op.ops_from_list([Remove, Create])
        True -> ops_for_modification(o, n)
      }
  }
}

fn ops_for_creation(e: Entry) -> Set(Op) {
  case entry.entry_kind(e) {
    ast.File ->
      case entry.entry_size(e) > 0 {
        True -> op.ops_from_list([Create, Write])
        False -> op.single_op(Create)
      }
    _ -> op.single_op(Create)
  }
}

fn ops_for_modification(old: Entry, new: Entry) -> Set(Op) {
  let mode_changed = entry.entry_mode(old) != entry.entry_mode(new)
  let content_changed = content_changed(old, new)
  case content_changed, mode_changed {
    False, False -> op.empty_ops()
    False, True -> op.single_op(Chmod)
    True, False -> op.single_op(Write)
    True, True -> op.ops_from_list([Write, Chmod])
  }
}

fn content_changed(old: Entry, new: Entry) -> Bool {
  case entry.entries_have_both_hashes(old, new) {
    True -> !entry.entries_content_hash_equal(old, new)
    False ->
      entry.entry_size(old) != entry.entry_size(new)
      || entry.entry_mtime(old) != entry.entry_mtime(new)
  }
}

fn build_event_for(
  key: String,
  prev: Snapshot,
  curr: Snapshot,
  renames: Dict(String, NormalizedPath),
) -> Result(WatchEvent, Nil) {
  let prev_entry = lookup_by_key(prev, key)
  let curr_entry = lookup_by_key(curr, key)
  let base_ops = compare_entry(old: prev_entry, new: curr_entry)
  let #(final_ops, renamed_from) =
    apply_rename(key, base_ops, prev, curr_entry, renames)
  case set.size(final_ops) == 0 {
    True -> Error(Nil)
    False -> {
      let target_path = primary_path(curr_entry, prev_entry)
      case target_path {
        None -> Error(Nil)
        Some(p) ->
          case
            event.multi_op(path: p, ops: final_ops, renamed_from: renamed_from)
          {
            Ok(ev) -> Ok(ev)
            Error(_) -> Error(Nil)
          }
      }
    }
  }
}

fn apply_rename(
  key: String,
  base_ops: Set(Op),
  prev: Snapshot,
  curr_entry: Option(Entry),
  renames: Dict(String, NormalizedPath),
) -> #(Set(Op), Option(NormalizedPath)) {
  case curr_entry {
    None -> #(base_ops, None)
    Some(curr) ->
      case dict.get(renames, key) {
        Error(_) -> #(base_ops, None)
        Ok(from) -> {
          // For renames we recompute the modification ops between the
          // entry at the *old* path and the new path's entry: a pure
          // rename emits {Rename}, a rename whose contents also changed
          // emits {Rename, Write} or {Rename, Write, Chmod}.
          let from_key = path.path_to_string(from)
          let prev_at_from = snapshot.lookup_by_key(prev, from_key)
          let modification_ops = case prev_at_from {
            Some(old) -> ops_for_modification(old, curr)
            None -> set.delete(base_ops, Create)
          }
          let with_rename = set.insert(modification_ops, Rename)
          #(with_rename, Some(from))
        }
      }
  }
}

fn apply_op_mask(
  result: Result(WatchEvent, Nil),
  watch: Watch,
) -> Result(WatchEvent, Nil) {
  case result {
    Error(_) -> result
    Ok(ev) -> {
      let masked =
        set.intersection(event.event_ops(ev), watch.watch_op_mask(watch))
      case set.size(masked) == 0 {
        True -> Error(Nil)
        False ->
          case
            event.multi_op(
              path: event.event_path(ev),
              ops: masked,
              renamed_from: case set.contains(masked, Rename) {
                True -> event.event_renamed_from(ev)
                False -> None
              },
            )
          {
            Ok(masked_ev) -> Ok(masked_ev)
            Error(_) -> Error(Nil)
          }
      }
    }
  }
}

fn primary_path(
  curr_entry: Option(Entry),
  prev_entry: Option(Entry),
) -> Option(NormalizedPath) {
  case curr_entry {
    Some(e) -> Some(entry.entry_path(e))
    None ->
      case prev_entry {
        Some(e) -> Some(entry.entry_path(e))
        None -> None
      }
  }
}

fn path_union(prev: Snapshot, curr: Snapshot) -> List(String) {
  let prev_keys = set.from_list(snapshot.paths(prev))
  let curr_keys = set.from_list(snapshot.paths(curr))
  set.union(prev_keys, curr_keys)
  |> set.to_list
}

fn lookup_by_key(s: Snapshot, key: String) -> Option(Entry) {
  snapshot.lookup_by_key(s, key)
}

fn detect_renames(
  prev: Snapshot,
  curr: Snapshot,
) -> Dict(String, NormalizedPath) {
  let prev_groups = group_by_file_id(snapshot.entries_unsorted(prev))
  let curr_groups = group_by_file_id(snapshot.entries_unsorted(curr))

  prev_groups
  |> dict.to_list
  |> list.fold(dict.new(), fn(acc, pair) {
    let #(file_id, prev_entries) = pair
    case dict.get(curr_groups, file_id) {
      Error(_) -> acc
      Ok(curr_entries) ->
        match_disappearance_to_appearance(
          file_id,
          prev_entries,
          curr_entries,
          prev,
          curr,
          acc,
        )
    }
  })
}

// An entry has left its path when the path is gone from `curr` or now
// holds a different file_id, and has arrived at a path that was absent
// from `prev` or held a different file_id. The second case covers a
// rename over an existing file and two files swapping paths.
fn match_disappearance_to_appearance(
  file_id: String,
  prev_entries: List(Entry),
  curr_entries: List(Entry),
  prev: Snapshot,
  curr: Snapshot,
  acc: Dict(String, NormalizedPath),
) -> Dict(String, NormalizedPath) {
  let disappeared =
    list.filter(prev_entries, fn(e) {
      !holds_file_id(curr, snapshot.entry_key(e), file_id)
    })
  let appeared =
    list.filter(curr_entries, fn(e) {
      !holds_file_id(prev, snapshot.entry_key(e), file_id)
    })
  case disappeared, appeared {
    [old], [new] ->
      dict.insert(acc, snapshot.entry_key(new), entry.entry_path(old))
    _, _ -> acc
  }
}

fn holds_file_id(s: Snapshot, key: String, file_id: String) -> Bool {
  case snapshot.lookup_by_key(s, key) {
    Some(e) -> entry.entry_file_id(e) == Some(file_id)
    None -> False
  }
}

fn group_by_file_id(entries: List(Entry)) -> Dict(String, List(Entry)) {
  list.fold(entries, dict.new(), fn(acc, e) {
    case entry.entry_file_id(e) {
      None -> acc
      Some(id) ->
        case dict.get(acc, id) {
          Ok(existing) -> dict.insert(acc, id, [e, ..existing])
          Error(_) -> dict.insert(acc, id, [e])
        }
    }
  })
}

// Old paths of renames that are gone from `curr`. An old path that is
// still present (a swap, or a new file at the old path) keeps its own
// event.
fn renames_suppressed_paths(
  renames: Dict(String, NormalizedPath),
  curr: Snapshot,
) -> Set(String) {
  renames
  |> dict.values
  |> list.map(path.path_to_string)
  |> list.filter(fn(key) { snapshot.lookup_by_key(curr, key) == None })
  |> set.from_list
}
