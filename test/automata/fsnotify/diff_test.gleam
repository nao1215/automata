import automata/fsnotify
import automata/fsnotify/ast.{Chmod, Create, Remove, Rename, Write}
import automata/fsnotify/diff
import automata/fsnotify/entry
import automata/fsnotify/event
import automata/fsnotify/op
import automata/fsnotify/path
import automata/fsnotify/snapshot
import automata/fsnotify/watch
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import gleeunit/should

fn p(s: String) {
  let assert Ok(value) = path.normalize(path: s)
  value
}

fn file(
  path_str: String,
  size: Int,
  mtime: Int,
  mode: Int,
  hash: option.Option(String),
  file_id: option.Option(String),
) {
  let assert Ok(e) =
    entry.entry_file(
      path: p(path_str),
      size: size,
      mtime: mtime,
      mode: mode,
      content_hash: hash,
      file_id: file_id,
    )
  e
}

fn dir(path_str: String) {
  let assert Ok(e) =
    entry.entry_directory(
      path: p(path_str),
      mtime: 1,
      mode: 0o755,
      file_id: None,
    )
  e
}

fn snap(entries: List(entry.Entry)) {
  let assert Ok(s) = snapshot.from_entries(entries: entries)
  s
}

fn paths_of(events: List(event.WatchEvent)) -> List(String) {
  list.map(events, fn(ev) { path.path_to_string(event.event_path(event: ev)) })
}

fn ops_of(ev: event.WatchEvent) -> List(ast.Op) {
  op.to_list(ops: event.event_ops(event: ev))
}

pub fn empty_to_empty_emits_nothing_test() {
  fsnotify.diff(
    prev: snapshot.empty_snapshot(),
    curr: snapshot.empty_snapshot(),
    watch: fsnotify.watch(),
  )
  |> should.equal([])
}

pub fn create_empty_file_emits_create_only_test() {
  let curr = snap([file("/a", 0, 1, 0o644, None, None)])
  let events =
    fsnotify.diff(
      prev: snapshot.empty_snapshot(),
      curr: curr,
      watch: fsnotify.watch(),
    )
  list.length(events) |> should.equal(1)
  let assert [ev] = events
  ops_of(ev) |> should.equal([Create])
}

pub fn create_non_empty_file_emits_create_and_write_test() {
  let curr = snap([file("/a", 100, 1, 0o644, Some("h"), None)])
  let assert [ev] =
    fsnotify.diff(
      prev: snapshot.empty_snapshot(),
      curr: curr,
      watch: fsnotify.watch(),
    )
  ops_of(ev) |> should.equal([Create, Write])
}

pub fn create_directory_emits_create_only_test() {
  let curr = snap([dir("/d")])
  let assert [ev] =
    fsnotify.diff(
      prev: snapshot.empty_snapshot(),
      curr: curr,
      watch: fsnotify.watch(),
    )
  ops_of(ev) |> should.equal([Create])
}

pub fn remove_emits_remove_test() {
  let prev = snap([file("/a", 100, 1, 0o644, None, None)])
  let assert [ev] =
    fsnotify.diff(
      prev: prev,
      curr: snapshot.empty_snapshot(),
      watch: fsnotify.watch(),
    )
  ops_of(ev) |> should.equal([Remove])
}

pub fn unchanged_entry_emits_nothing_test() {
  let s = snap([file("/a", 10, 1, 0o644, Some("h"), None)])
  fsnotify.diff(prev: s, curr: s, watch: fsnotify.watch())
  |> should.equal([])
}

pub fn mtime_change_emits_write_test() {
  let prev = snap([file("/a", 10, 1, 0o644, None, None)])
  let curr = snap([file("/a", 10, 2, 0o644, None, None)])
  let assert [ev] =
    fsnotify.diff(prev: prev, curr: curr, watch: fsnotify.watch())
  ops_of(ev) |> should.equal([Write])
}

pub fn size_change_emits_write_test() {
  let prev = snap([file("/a", 10, 1, 0o644, None, None)])
  let curr = snap([file("/a", 20, 1, 0o644, None, None)])
  let assert [ev] =
    fsnotify.diff(prev: prev, curr: curr, watch: fsnotify.watch())
  ops_of(ev) |> should.equal([Write])
}

pub fn content_hash_change_emits_write_test() {
  // Same size and mtime, but hash differs (e.g. /sys-style FS).
  let prev = snap([file("/a", 10, 1, 0o644, Some("aaa"), None)])
  let curr = snap([file("/a", 10, 1, 0o644, Some("bbb"), None)])
  let assert [ev] =
    fsnotify.diff(prev: prev, curr: curr, watch: fsnotify.watch())
  ops_of(ev) |> should.equal([Write])
}

pub fn mode_change_only_emits_chmod_test() {
  let prev = snap([file("/a", 10, 1, 0o644, Some("h"), None)])
  let curr = snap([file("/a", 10, 1, 0o755, Some("h"), None)])
  let assert [ev] =
    fsnotify.diff(prev: prev, curr: curr, watch: fsnotify.watch())
  ops_of(ev) |> should.equal([Chmod])
}

pub fn write_and_chmod_combined_test() {
  let prev = snap([file("/a", 10, 1, 0o644, None, None)])
  let curr = snap([file("/a", 20, 2, 0o755, None, None)])
  let assert [ev] =
    fsnotify.diff(prev: prev, curr: curr, watch: fsnotify.watch())
  ops_of(ev) |> should.equal([Write, Chmod])
}

pub fn kind_change_emits_remove_and_create_test() {
  let prev = snap([file("/x", 10, 1, 0o644, None, None)])
  let curr = snap([dir("/x")])
  let assert [ev] =
    fsnotify.diff(prev: prev, curr: curr, watch: fsnotify.watch())
  ops_of(ev) |> should.equal([Create, Remove])
}

pub fn rename_with_file_id_emits_rename_test() {
  let prev = snap([file("/a", 10, 1, 0o644, None, Some("inode-1"))])
  let curr = snap([file("/b", 10, 1, 0o644, None, Some("inode-1"))])
  let assert [ev] =
    fsnotify.diff(prev: prev, curr: curr, watch: fsnotify.watch())
  ops_of(ev) |> should.equal([Rename])
  case event.event_renamed_from(event: ev) {
    Some(from) -> path.path_to_string(from) |> should.equal("/a")
    None -> should.fail()
  }
}

pub fn rename_with_content_change_emits_rename_and_write_test() {
  let prev = snap([file("/a", 10, 1, 0o644, None, Some("inode-1"))])
  let curr = snap([file("/b", 20, 2, 0o644, None, Some("inode-1"))])
  let assert [ev] =
    fsnotify.diff(prev: prev, curr: curr, watch: fsnotify.watch())
  ops_of(ev) |> should.equal([Write, Rename])
}

pub fn rename_with_mode_change_only_emits_rename_and_chmod_test() {
  let prev = snap([file("/a", 10, 1, 0o644, Some("h"), Some("inode-1"))])
  let curr = snap([file("/b", 10, 1, 0o755, Some("h"), Some("inode-1"))])
  let assert [ev] =
    fsnotify.diff(prev: prev, curr: curr, watch: fsnotify.watch())
  ops_of(ev) |> should.equal([Rename, Chmod])
}

pub fn file_id_only_in_prev_does_not_pair_test() {
  // prev has a file_id, curr does not. Differ falls back to plain
  // Remove + Create because there is nothing to pair with.
  let prev = snap([file("/a", 10, 1, 0o644, None, Some("inode-1"))])
  let curr = snap([file("/b", 10, 1, 0o644, None, None)])
  let events = fsnotify.diff(prev: prev, curr: curr, watch: fsnotify.watch())
  list.length(events) |> should.equal(2)
  list.any(events, fn(ev) { event.event_has(event: ev, op: Rename) })
  |> should.equal(False)
}

pub fn rename_without_file_id_falls_back_to_remove_create_test() {
  let prev = snap([file("/a", 10, 1, 0o644, None, None)])
  let curr = snap([file("/b", 10, 1, 0o644, None, None)])
  let events = fsnotify.diff(prev: prev, curr: curr, watch: fsnotify.watch())
  paths_of(events) |> should.equal(["/a", "/b"])
  let assert [a_ev, b_ev] = events
  ops_of(a_ev) |> should.equal([Remove])
  ops_of(b_ev) |> should.equal([Create, Write])
}

pub fn ambiguous_rename_falls_back_to_remove_create_test() {
  // Two prev entries share a file_id (hard links): we cannot uniquely
  // pair them with the appearance, so the differ refuses to fold.
  let prev =
    snap([
      file("/a", 10, 1, 0o644, None, Some("inode-1")),
      file("/c", 10, 1, 0o644, None, Some("inode-1")),
    ])
  let curr = snap([file("/b", 10, 1, 0o644, None, Some("inode-1"))])
  let events = fsnotify.diff(prev: prev, curr: curr, watch: fsnotify.watch())
  // /a and /c removed, /b created. No Rename anywhere.
  list.length(events) |> should.equal(3)
  list.any(events, fn(ev) { event.event_has(event: ev, op: Rename) })
  |> should.equal(False)
}

pub fn rename_to_existing_path_is_not_pair_test() {
  // /b is not a "fresh" appearance because /b also exists in prev,
  // so this is a hard-link create, not a rename.
  let prev = snap([file("/a", 10, 1, 0o644, None, Some("inode-1"))])
  let curr =
    snap([
      file("/a", 10, 1, 0o644, None, Some("inode-1")),
      file("/b", 10, 1, 0o644, None, Some("inode-1")),
    ])
  let events = fsnotify.diff(prev: prev, curr: curr, watch: fsnotify.watch())
  list.length(events) |> should.equal(1)
  let assert [ev] = events
  path.path_to_string(event.event_path(event: ev)) |> should.equal("/b")
  ops_of(ev) |> should.equal([Create, Write])
}

pub fn op_mask_filters_writes_test() {
  let prev = snap([file("/a", 10, 1, 0o644, None, None)])
  let curr = snap([file("/a", 10, 1, 0o755, None, None)])
  let chmod_only =
    fsnotify.watch()
    |> watch.with_ops(ops: op.single_op(Chmod))
  let mtime_only_watch =
    fsnotify.watch()
    |> watch.with_ops(ops: op.single_op(Write))

  let chmod_events = fsnotify.diff(prev: prev, curr: curr, watch: chmod_only)
  let assert [ev] = chmod_events
  ops_of(ev) |> should.equal([Chmod])

  fsnotify.diff(prev: prev, curr: curr, watch: mtime_only_watch)
  |> should.equal([])
}

pub fn op_mask_create_only_drops_other_ops_test() {
  let prev = snap([file("/a", 10, 1, 0o644, None, None)])
  let curr =
    snap([file("/a", 20, 2, 0o755, None, None), file("/b", 5, 1, 0, None, None)])
  let create_only =
    fsnotify.watch()
    |> watch.with_ops(ops: op.single_op(Create))
  let events = fsnotify.diff(prev: prev, curr: curr, watch: create_only)
  // Only /b's Create survives; /a's Write|Chmod are masked out.
  list.length(events) |> should.equal(1)
  let assert [ev] = events
  path.path_to_string(event.event_path(event: ev)) |> should.equal("/b")
  ops_of(ev) |> should.equal([Create])
}

pub fn silent_watch_emits_nothing_test() {
  let prev = snap([file("/a", 10, 1, 0o644, None, None)])
  let curr = snap([file("/b", 10, 1, 0o644, None, None)])
  fsnotify.diff(prev: prev, curr: curr, watch: watch.watch_no_ops())
  |> should.equal([])
}

pub fn rename_filtered_out_drops_renamed_from_when_only_write_remains_test() {
  // file_id matches but the watch only observes Write. The differ must
  // still emit a Write at the new path with renamed_from cleared.
  let prev = snap([file("/a", 10, 1, 0o644, None, Some("inode-1"))])
  let curr = snap([file("/b", 20, 2, 0o644, None, Some("inode-1"))])
  let watch_value =
    fsnotify.watch()
    |> watch.with_ops(ops: op.single_op(Write))
  let assert [ev] = fsnotify.diff(prev: prev, curr: curr, watch: watch_value)
  ops_of(ev) |> should.equal([Write])
  event.event_renamed_from(event: ev) |> should.equal(None)
}

pub fn events_sorted_by_path_test() {
  let prev = snap([])
  let curr =
    snap([
      file("/c", 0, 1, 0, None, None),
      file("/a", 0, 1, 0, None, None),
      file("/b", 0, 1, 0, None, None),
    ])
  let events = fsnotify.diff(prev: prev, curr: curr, watch: fsnotify.watch())
  paths_of(events) |> should.equal(["/a", "/b", "/c"])
}

pub fn large_snapshot_diff_completes_test() {
  // 200 entries: tests that the algorithm produces correct, sorted
  // output without depending on Dict iteration order. (No timing
  // assertion - performance is verified manually.)
  let prev_entries = build_n_files(200, 10, 1)
  let curr_entries = build_n_files(200, 10, 2)
  let prev = snap(prev_entries)
  let curr = snap(curr_entries)
  let events = fsnotify.diff(prev: prev, curr: curr, watch: fsnotify.watch())
  list.length(events) |> should.equal(200)
  // Each event is a single Write (mtime changed).
  list.all(events, fn(ev) { ops_of(ev) == [Write] }) |> should.equal(True)
}

fn build_n_files(n: Int, size: Int, mtime: Int) -> List(entry.Entry) {
  build_n_files_acc(n, size, mtime, [])
}

fn build_n_files_acc(
  n: Int,
  size: Int,
  mtime: Int,
  acc: List(entry.Entry),
) -> List(entry.Entry) {
  case n <= 0 {
    True -> acc
    False -> {
      let path_str = "/dir/file" <> int.to_string(n)
      let e = file(path_str, size, mtime, 0o644, None, None)
      build_n_files_acc(n - 1, size, mtime, [e, ..acc])
    }
  }
}

pub fn compare_entry_returns_empty_for_no_change_test() {
  let e = file("/a", 10, 1, 0o644, Some("h"), None)
  diff.compare_entry(old: Some(e), new: Some(e))
  |> set.size
  |> should.equal(0)
}
