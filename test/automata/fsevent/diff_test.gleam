import automata as a
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/set
import gleeunit/should

fn p(s: String) {
  let assert Ok(value) = a.path_normalize(path: s)
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
    a.entry_file(
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
    a.entry_directory(path: p(path_str), mtime: 1, mode: 0o755, file_id: None)
  e
}

fn snap(entries: List(a.Entry)) {
  let assert Ok(s) = a.snapshot_from_entries(entries: entries)
  s
}

fn paths_of(events: List(a.WatchEvent)) -> List(String) {
  list.map(events, fn(ev) {
    a.path_to_string(path: a.filesystem_event_path(event: ev))
  })
}

fn ops_of(ev: a.WatchEvent) -> List(a.Op) {
  a.ops_to_list(ops: a.filesystem_event_ops(event: ev))
}

pub fn empty_to_empty_emits_nothing_test() {
  old_fsevent_diff(
    prev: a.snapshot_empty(),
    curr: a.snapshot_empty(),
    watch: old_fsevent_watch(),
  )
  |> should.equal([])
}

pub fn create_empty_file_emits_create_only_test() {
  let curr = snap([file("/a", 0, 1, 0o644, None, None)])
  let events =
    old_fsevent_diff(
      prev: a.snapshot_empty(),
      curr: curr,
      watch: old_fsevent_watch(),
    )
  list.length(events) |> should.equal(1)
  let assert [ev] = events
  ops_of(ev) |> should.equal([a.Create])
}

pub fn create_non_empty_file_emits_create_and_write_test() {
  let curr = snap([file("/a", 100, 1, 0o644, Some("h"), None)])
  let assert [ev] =
    old_fsevent_diff(
      prev: a.snapshot_empty(),
      curr: curr,
      watch: old_fsevent_watch(),
    )
  ops_of(ev) |> should.equal([a.Create, a.Write])
}

pub fn create_directory_emits_create_only_test() {
  let curr = snap([dir("/d")])
  let assert [ev] =
    old_fsevent_diff(
      prev: a.snapshot_empty(),
      curr: curr,
      watch: old_fsevent_watch(),
    )
  ops_of(ev) |> should.equal([a.Create])
}

pub fn remove_emits_remove_test() {
  let prev = snap([file("/a", 100, 1, 0o644, None, None)])
  let assert [ev] =
    old_fsevent_diff(
      prev: prev,
      curr: a.snapshot_empty(),
      watch: old_fsevent_watch(),
    )
  ops_of(ev) |> should.equal([a.Remove])
}

pub fn unchanged_entry_emits_nothing_test() {
  let s = snap([file("/a", 10, 1, 0o644, Some("h"), None)])
  old_fsevent_diff(prev: s, curr: s, watch: old_fsevent_watch())
  |> should.equal([])
}

pub fn mtime_change_emits_write_test() {
  let prev = snap([file("/a", 10, 1, 0o644, None, None)])
  let curr = snap([file("/a", 10, 2, 0o644, None, None)])
  let assert [ev] =
    old_fsevent_diff(prev: prev, curr: curr, watch: old_fsevent_watch())
  ops_of(ev) |> should.equal([a.Write])
}

pub fn size_change_emits_write_test() {
  let prev = snap([file("/a", 10, 1, 0o644, None, None)])
  let curr = snap([file("/a", 20, 1, 0o644, None, None)])
  let assert [ev] =
    old_fsevent_diff(prev: prev, curr: curr, watch: old_fsevent_watch())
  ops_of(ev) |> should.equal([a.Write])
}

pub fn content_hash_change_emits_write_test() {
  // Same size and mtime, but hash differs (e.g. /sys-style FS).
  let prev = snap([file("/a", 10, 1, 0o644, Some("aaa"), None)])
  let curr = snap([file("/a", 10, 1, 0o644, Some("bbb"), None)])
  let assert [ev] =
    old_fsevent_diff(prev: prev, curr: curr, watch: old_fsevent_watch())
  ops_of(ev) |> should.equal([a.Write])
}

pub fn mode_change_only_emits_chmod_test() {
  let prev = snap([file("/a", 10, 1, 0o644, Some("h"), None)])
  let curr = snap([file("/a", 10, 1, 0o755, Some("h"), None)])
  let assert [ev] =
    old_fsevent_diff(prev: prev, curr: curr, watch: old_fsevent_watch())
  ops_of(ev) |> should.equal([a.Chmod])
}

pub fn write_and_chmod_combined_test() {
  let prev = snap([file("/a", 10, 1, 0o644, None, None)])
  let curr = snap([file("/a", 20, 2, 0o755, None, None)])
  let assert [ev] =
    old_fsevent_diff(prev: prev, curr: curr, watch: old_fsevent_watch())
  ops_of(ev) |> should.equal([a.Write, a.Chmod])
}

pub fn kind_change_emits_remove_and_create_test() {
  let prev = snap([file("/x", 10, 1, 0o644, None, None)])
  let curr = snap([dir("/x")])
  let assert [ev] =
    old_fsevent_diff(prev: prev, curr: curr, watch: old_fsevent_watch())
  ops_of(ev) |> should.equal([a.Create, a.Remove])
}

pub fn rename_with_file_id_emits_rename_test() {
  let prev = snap([file("/a", 10, 1, 0o644, None, Some("inode-1"))])
  let curr = snap([file("/b", 10, 1, 0o644, None, Some("inode-1"))])
  let assert [ev] =
    old_fsevent_diff(prev: prev, curr: curr, watch: old_fsevent_watch())
  ops_of(ev) |> should.equal([a.Rename])
  case a.filesystem_event_renamed_from(event: ev) {
    Some(from) -> a.path_to_string(path: from) |> should.equal("/a")
    None -> should.fail()
  }
}

pub fn rename_with_content_change_emits_rename_and_write_test() {
  let prev = snap([file("/a", 10, 1, 0o644, None, Some("inode-1"))])
  let curr = snap([file("/b", 20, 2, 0o644, None, Some("inode-1"))])
  let assert [ev] =
    old_fsevent_diff(prev: prev, curr: curr, watch: old_fsevent_watch())
  ops_of(ev) |> should.equal([a.Write, a.Rename])
}

pub fn rename_with_mode_change_only_emits_rename_and_chmod_test() {
  let prev = snap([file("/a", 10, 1, 0o644, Some("h"), Some("inode-1"))])
  let curr = snap([file("/b", 10, 1, 0o755, Some("h"), Some("inode-1"))])
  let assert [ev] =
    old_fsevent_diff(prev: prev, curr: curr, watch: old_fsevent_watch())
  ops_of(ev) |> should.equal([a.Rename, a.Chmod])
}

pub fn file_id_only_in_prev_does_not_pair_test() {
  // prev has a file_id, curr does not. Differ falls back to plain
  // Remove + Create because there is nothing to pair with.
  let prev = snap([file("/a", 10, 1, 0o644, None, Some("inode-1"))])
  let curr = snap([file("/b", 10, 1, 0o644, None, None)])
  let events =
    old_fsevent_diff(prev: prev, curr: curr, watch: old_fsevent_watch())
  list.length(events) |> should.equal(2)
  list.any(events, fn(ev) {
    old_fsevent_event_event_has(event: ev, op: a.Rename)
  })
  |> should.equal(False)
}

pub fn rename_without_file_id_falls_back_to_remove_create_test() {
  let prev = snap([file("/a", 10, 1, 0o644, None, None)])
  let curr = snap([file("/b", 10, 1, 0o644, None, None)])
  let events =
    old_fsevent_diff(prev: prev, curr: curr, watch: old_fsevent_watch())
  paths_of(events) |> should.equal(["/a", "/b"])
  let assert [a_ev, b_ev] = events
  ops_of(a_ev) |> should.equal([a.Remove])
  ops_of(b_ev) |> should.equal([a.Create, a.Write])
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
  let events =
    old_fsevent_diff(prev: prev, curr: curr, watch: old_fsevent_watch())
  // /a and /c removed, /b created. No Rename anywhere.
  list.length(events) |> should.equal(3)
  list.any(events, fn(ev) {
    old_fsevent_event_event_has(event: ev, op: a.Rename)
  })
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
  let events =
    old_fsevent_diff(prev: prev, curr: curr, watch: old_fsevent_watch())
  list.length(events) |> should.equal(1)
  let assert [ev] = events
  a.path_to_string(path: a.filesystem_event_path(event: ev))
  |> should.equal("/b")
  ops_of(ev) |> should.equal([a.Create, a.Write])
}

pub fn op_mask_filters_writes_test() {
  let prev = snap([file("/a", 10, 1, 0o644, None, None)])
  let curr = snap([file("/a", 10, 1, 0o755, None, None)])
  let chmod_only =
    old_fsevent_watch()
    |> old_fsevent_watch_with_ops(ops: old_fsevent_op_single_op(op: a.Chmod))
  let mtime_only_watch =
    old_fsevent_watch()
    |> old_fsevent_watch_with_ops(ops: old_fsevent_op_single_op(op: a.Write))

  let chmod_events = old_fsevent_diff(prev: prev, curr: curr, watch: chmod_only)
  let assert [ev] = chmod_events
  ops_of(ev) |> should.equal([a.Chmod])

  old_fsevent_diff(prev: prev, curr: curr, watch: mtime_only_watch)
  |> should.equal([])
}

pub fn op_mask_create_only_drops_other_ops_test() {
  let prev = snap([file("/a", 10, 1, 0o644, None, None)])
  let curr =
    snap([file("/a", 20, 2, 0o755, None, None), file("/b", 5, 1, 0, None, None)])
  let create_only =
    old_fsevent_watch()
    |> old_fsevent_watch_with_ops(ops: old_fsevent_op_single_op(op: a.Create))
  let events = old_fsevent_diff(prev: prev, curr: curr, watch: create_only)
  // Only /b's Create survives; /a's Write|Chmod are masked out.
  list.length(events) |> should.equal(1)
  let assert [ev] = events
  a.path_to_string(path: a.filesystem_event_path(event: ev))
  |> should.equal("/b")
  ops_of(ev) |> should.equal([a.Create])
}

pub fn silent_watch_emits_nothing_test() {
  let prev = snap([file("/a", 10, 1, 0o644, None, None)])
  let curr = snap([file("/b", 10, 1, 0o644, None, None)])
  old_fsevent_diff(
    prev: prev,
    curr: curr,
    watch: old_fsevent_watch_watch_no_ops(),
  )
  |> should.equal([])
}

pub fn rename_filtered_out_drops_renamed_from_when_only_write_remains_test() {
  // file_id matches but the watch only observes Write. The differ must
  // still emit a Write at the new path with renamed_from cleared.
  let prev = snap([file("/a", 10, 1, 0o644, None, Some("inode-1"))])
  let curr = snap([file("/b", 20, 2, 0o644, None, Some("inode-1"))])
  let watch_value =
    old_fsevent_watch()
    |> old_fsevent_watch_with_ops(ops: old_fsevent_op_single_op(op: a.Write))
  let assert [ev] = old_fsevent_diff(prev: prev, curr: curr, watch: watch_value)
  ops_of(ev) |> should.equal([a.Write])
  a.filesystem_event_renamed_from(event: ev) |> should.equal(None)
}

pub fn events_sorted_by_path_test() {
  let prev = snap([])
  let curr =
    snap([
      file("/c", 0, 1, 0, None, None),
      file("/a", 0, 1, 0, None, None),
      file("/b", 0, 1, 0, None, None),
    ])
  let events =
    old_fsevent_diff(prev: prev, curr: curr, watch: old_fsevent_watch())
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
  let events =
    old_fsevent_diff(prev: prev, curr: curr, watch: old_fsevent_watch())
  list.length(events) |> should.equal(200)
  // Each event is a single Write (mtime changed).
  list.all(events, fn(ev) { ops_of(ev) == [a.Write] }) |> should.equal(True)
}

fn build_n_files(n: Int, size: Int, mtime: Int) -> List(a.Entry) {
  build_n_files_acc(n, size, mtime, [])
}

fn build_n_files_acc(
  n: Int,
  size: Int,
  mtime: Int,
  acc: List(a.Entry),
) -> List(a.Entry) {
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
  old_fsevent_diff_compare_entry(old: Some(e), new: Some(e))
  |> set.size
  |> should.equal(0)
}

pub fn rename_masked_without_rename_reports_remove_and_create_test() {
  // A watch without Rename used to drop the whole move: the Remove at
  // the old path had been folded into a Rename that the mask removed.
  let prev = snap([file("/a", 10, 1, 0o644, None, Some("inode-1"))])
  let curr = snap([file("/b", 10, 1, 0o644, None, Some("inode-1"))])
  let create_and_remove =
    old_fsevent_watch_watch_no_ops()
    |> old_fsevent_watch_with_ops(
      ops: old_fsevent_op_ops_from_list(ops: [a.Create, a.Remove]),
    )
  let events =
    old_fsevent_diff(prev: prev, curr: curr, watch: create_and_remove)
  paths_of(events) |> should.equal(["/a", "/b"])
  let assert [a_ev, b_ev] = events
  ops_of(a_ev) |> should.equal([a.Remove])
  ops_of(b_ev) |> should.equal([a.Create])
  a.filesystem_event_renamed_from(event: b_ev) |> should.equal(None)
}

pub fn rename_over_existing_file_emits_rename_test() {
  // `mv /a /b` where /b already existed: /b now holds /a's file_id.
  let prev =
    snap([
      file("/a", 10, 1, 0o644, None, Some("inode-1")),
      file("/b", 5, 1, 0o644, None, Some("inode-2")),
    ])
  let curr = snap([file("/b", 10, 1, 0o644, None, Some("inode-1"))])
  let events =
    old_fsevent_diff(prev: prev, curr: curr, watch: old_fsevent_watch())
  let assert [ev] = events
  a.path_to_string(path: a.filesystem_event_path(event: ev))
  |> should.equal("/b")
  ops_of(ev) |> should.equal([a.Rename])
  a.filesystem_event_renamed_from(event: ev) |> should.equal(Some(p("/a")))
}

pub fn swapped_files_emit_two_renames_test() {
  let prev =
    snap([
      file("/a", 10, 1, 0o644, None, Some("inode-1")),
      file("/b", 5, 1, 0o644, None, Some("inode-2")),
    ])
  let curr =
    snap([
      file("/a", 5, 1, 0o644, None, Some("inode-2")),
      file("/b", 10, 1, 0o644, None, Some("inode-1")),
    ])
  let events =
    old_fsevent_diff(prev: prev, curr: curr, watch: old_fsevent_watch())
  paths_of(events) |> should.equal(["/a", "/b"])
  let assert [a_ev, b_ev] = events
  ops_of(a_ev) |> should.equal([a.Rename])
  a.filesystem_event_renamed_from(event: a_ev) |> should.equal(Some(p("/b")))
  ops_of(b_ev) |> should.equal([a.Rename])
  a.filesystem_event_renamed_from(event: b_ev) |> should.equal(Some(p("/a")))
}

pub fn rename_over_existing_file_without_rename_watch_reports_create_test() {
  // `mv /a /b` over an existing /b, watched without Rename: /b now holds
  // another file, so a Create subscriber must see it.
  let prev =
    snap([
      file("/a", 10, 1, 0o644, None, Some("inode-1")),
      file("/b", 5, 1, 0o644, None, Some("inode-2")),
    ])
  let curr = snap([file("/b", 10, 1, 0o644, None, Some("inode-1"))])
  let create_and_remove =
    old_fsevent_watch_watch_no_ops()
    |> old_fsevent_watch_with_ops(
      ops: old_fsevent_op_ops_from_list(ops: [a.Create, a.Remove]),
    )
  let events =
    old_fsevent_diff(prev: prev, curr: curr, watch: create_and_remove)
  paths_of(events) |> should.equal(["/a", "/b"])
  let assert [a_ev, b_ev] = events
  ops_of(a_ev) |> should.equal([a.Remove])
  ops_of(b_ev) |> list.sort(op_order) |> should.equal([a.Create, a.Remove])
}

fn op_order(a: a.Op, b: a.Op) -> order.Order {
  int.compare(op_rank(a), op_rank(b))
}

pub fn rename_with_recreated_source_reports_replacement_test() {
  let prev = snap([file("/a", 0, 1, 0o644, None, Some("inode-1"))])
  let curr =
    snap([
      file("/a", 0, 1, 0o644, None, Some("inode-2")),
      file("/b", 0, 1, 0o644, None, Some("inode-1")),
    ])
  let events =
    old_fsevent_diff(prev: prev, curr: curr, watch: old_fsevent_watch())
  paths_of(events) |> should.equal(["/a", "/b"])
  let assert [a_ev, b_ev] = events
  ops_of(a_ev) |> list.sort(op_order) |> should.equal([a.Create, a.Remove])
  a.filesystem_event_renamed_from(event: a_ev) |> should.equal(None)
  ops_of(b_ev) |> should.equal([a.Rename])
  a.filesystem_event_renamed_from(event: b_ev) |> should.equal(Some(p("/a")))
}

fn op_rank(o: a.Op) -> Int {
  case o {
    a.Create -> 0
    a.Write -> 1
    a.Remove -> 2
    a.Rename -> 3
    a.Chmod -> 4
  }
}

fn old_fsevent_diff(
  prev prev: a.Snapshot,
  curr curr: a.Snapshot,
  watch watch: set.Set(a.Op),
) -> List(a.WatchEvent) {
  a.diff_snapshots(prev, curr, observing: watch)
}

fn old_fsevent_diff_compare_entry(
  old old: option.Option(a.Entry),
  new new: option.Option(a.Entry),
) -> set.Set(a.Op) {
  let assert Ok(before) =
    a.snapshot_from_entries(entries: case old {
      option.Some(value) -> [value]
      option.None -> []
    })
  let assert Ok(after) =
    a.snapshot_from_entries(entries: case new {
      option.Some(value) -> [value]
      option.None -> []
    })
  a.diff_snapshots(before, after, observing: a.all_ops())
  |> list.fold(set.new(), fn(ops, event) {
    set.union(ops, a.filesystem_event_ops(event: event))
  })
}

fn old_fsevent_event_event_has(event event: a.WatchEvent, op op: a.Op) -> Bool {
  set.contains(a.filesystem_event_ops(event: event), op)
}

fn old_fsevent_op_ops_from_list(ops ops: List(a.Op)) -> set.Set(a.Op) {
  set.from_list(ops)
}

fn old_fsevent_op_single_op(op op: a.Op) -> set.Set(a.Op) {
  set.from_list([op])
}

fn old_fsevent_watch() -> set.Set(a.Op) {
  a.all_ops()
}

fn old_fsevent_watch_watch_no_ops() -> set.Set(a.Op) {
  set.new()
}

fn old_fsevent_watch_with_ops(
  watch _watch: set.Set(a.Op),
  ops ops: set.Set(a.Op),
) -> set.Set(a.Op) {
  ops
}
