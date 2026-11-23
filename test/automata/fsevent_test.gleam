import automata as a
import gleam/option.{None}
import gleam/set
import gleeunit/should

pub fn facade_normalize_round_trip_test() {
  let assert Ok(p) = a.path_normalize(path: "/var/log/")
  a.path_to_string(path: p) |> should.equal("/var/log")
}

pub fn facade_normalize_propagates_errors_test() {
  a.path_normalize(path: "") |> should.equal(Error(a.EmptyPath))
}

pub fn facade_watch_is_default_watch_test() {
  let w = old_fsevent_watch()
  old_fsevent_watch_watch_observes(watch: w, op: a.Create) |> should.equal(True)
  old_fsevent_watch_watch_observes(watch: w, op: a.Write) |> should.equal(True)
}

pub fn facade_diff_smoke_test() {
  let assert Ok(target_path) = a.path_normalize(path: "/tmp/a")
  let assert Ok(e1) =
    a.entry_file(
      path: target_path,
      size: 10,
      mtime: 1,
      mode: 0,
      content_hash: None,
      file_id: None,
    )
  let assert Ok(e2) =
    a.entry_file(
      path: target_path,
      size: 10,
      mtime: 2,
      mode: 0,
      content_hash: None,
      file_id: None,
    )
  let assert Ok(prev) = a.snapshot_from_entries(entries: [e1])
  let assert Ok(curr) = a.snapshot_from_entries(entries: [e2])
  let assert [ev] =
    old_fsevent_diff(prev: prev, curr: curr, watch: old_fsevent_watch())
  old_fsevent_event_event_has(event: ev, op: a.Write) |> should.equal(True)
  a.path_to_string(path: a.filesystem_event_path(event: ev))
  |> should.equal("/tmp/a")
}

fn old_fsevent_diff(
  prev prev: a.Snapshot,
  curr curr: a.Snapshot,
  watch watch: set.Set(a.Op),
) -> List(a.WatchEvent) {
  a.diff_snapshots(prev, curr, observing: watch)
}

fn old_fsevent_event_event_has(event event: a.WatchEvent, op op: a.Op) -> Bool {
  set.contains(a.filesystem_event_ops(event: event), op)
}

fn old_fsevent_watch() -> set.Set(a.Op) {
  a.all_ops()
}

fn old_fsevent_watch_watch_observes(
  watch watch: set.Set(a.Op),
  op op: a.Op,
) -> Bool {
  set.contains(watch, op)
}
