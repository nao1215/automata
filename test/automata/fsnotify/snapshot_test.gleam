import automata/fsnotify/ast.{DuplicatePath}
import automata/fsnotify/entry
import automata/fsnotify/path
import automata/fsnotify/snapshot
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

fn p(s: String) {
  let assert Ok(value) = path.normalize(path: s)
  value
}

fn file(path_str: String) {
  let assert Ok(e) =
    entry.entry_file(
      path: p(path_str),
      size: 0,
      mtime: 1,
      mode: 0,
      content_hash: None,
      file_id: None,
    )
  e
}

fn file_with_id(path_str: String, id: String) {
  let assert Ok(e) =
    entry.entry_file(
      path: p(path_str),
      size: 0,
      mtime: 1,
      mode: 0,
      content_hash: None,
      file_id: Some(id),
    )
  e
}

pub fn empty_snapshot_zero_entries_test() {
  let s = snapshot.empty_snapshot()
  snapshot.snapshot_size(snapshot: s) |> should.equal(0)
  snapshot.is_empty(snapshot: s) |> should.equal(True)
  snapshot.entries(snapshot: s) |> should.equal([])
}

pub fn from_entries_unique_paths_test() {
  let assert Ok(s) =
    snapshot.from_entries(entries: [file("/a"), file("/b"), file("/c")])
  snapshot.snapshot_size(snapshot: s) |> should.equal(3)
}

pub fn from_entries_duplicate_path_returns_error_test() {
  case snapshot.from_entries(entries: [file("/a"), file("/a")]) {
    Error(DuplicatePath(path: "/a")) -> Nil
    _ -> should.fail()
  }
}

pub fn from_entries_duplicate_after_normalisation_returns_error_test() {
  // "/a/" normalises to "/a", so this is a duplicate.
  case snapshot.from_entries(entries: [file("/a"), file("/a/")]) {
    Error(DuplicatePath(path: "/a")) -> Nil
    _ -> should.fail()
  }
}

pub fn add_entry_appends_test() {
  let assert Ok(s) =
    snapshot.add_entry(snapshot: snapshot.empty_snapshot(), entry: file("/x"))
  snapshot.snapshot_size(snapshot: s) |> should.equal(1)
}

pub fn add_entry_duplicate_returns_error_test() {
  let assert Ok(s) =
    snapshot.add_entry(snapshot: snapshot.empty_snapshot(), entry: file("/x"))
  case snapshot.add_entry(snapshot: s, entry: file("/x")) {
    Error(DuplicatePath(path: "/x")) -> Nil
    _ -> should.fail()
  }
}

pub fn lookup_existing_path_returns_some_test() {
  let assert Ok(s) = snapshot.from_entries(entries: [file("/a")])
  case snapshot.lookup(snapshot: s, path: p("/a")) {
    Some(_) -> Nil
    None -> should.fail()
  }
}

pub fn lookup_missing_path_returns_none_test() {
  let assert Ok(s) = snapshot.from_entries(entries: [file("/a")])
  snapshot.lookup(snapshot: s, path: p("/b")) |> should.equal(None)
}

pub fn entries_returned_in_canonical_path_order_test() {
  let assert Ok(s) =
    snapshot.from_entries(entries: [file("/c"), file("/a"), file("/b")])
  let paths =
    snapshot.entries(snapshot: s)
    |> list.map(fn(e) { path.path_to_string(entry.entry_path(entry: e)) })
  paths |> should.equal(["/a", "/b", "/c"])
}

pub fn hard_link_same_file_id_two_paths_allowed_test() {
  let assert Ok(s) =
    snapshot.from_entries(entries: [
      file_with_id("/a", "inode-1"),
      file_with_id("/b", "inode-1"),
    ])
  snapshot.snapshot_size(snapshot: s) |> should.equal(2)
}
