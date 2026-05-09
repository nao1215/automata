import automata/fsnotify
import automata/fsnotify/ast.{Create, EmptyPath, Write}
import automata/fsnotify/entry
import automata/fsnotify/event
import automata/fsnotify/path
import automata/fsnotify/snapshot
import automata/fsnotify/watch
import gleam/option.{None}
import gleeunit/should

pub fn facade_normalize_round_trip_test() {
  let assert Ok(p) = fsnotify.normalize(path: "/var/log/")
  path.path_to_string(p) |> should.equal("/var/log")
}

pub fn facade_normalize_propagates_errors_test() {
  fsnotify.normalize(path: "") |> should.equal(Error(EmptyPath))
}

pub fn facade_watch_is_default_watch_test() {
  let w = fsnotify.watch()
  watch.watch_observes(watch: w, op: Create) |> should.equal(True)
  watch.watch_observes(watch: w, op: Write) |> should.equal(True)
}

pub fn facade_diff_smoke_test() {
  let assert Ok(target_path) = fsnotify.normalize(path: "/tmp/a")
  let assert Ok(e1) =
    entry.entry_file(
      path: target_path,
      size: 10,
      mtime: 1,
      mode: 0,
      content_hash: None,
      file_id: None,
    )
  let assert Ok(e2) =
    entry.entry_file(
      path: target_path,
      size: 10,
      mtime: 2,
      mode: 0,
      content_hash: None,
      file_id: None,
    )
  let assert Ok(prev) = snapshot.from_entries(entries: [e1])
  let assert Ok(curr) = snapshot.from_entries(entries: [e2])
  let assert [ev] =
    fsnotify.diff(prev: prev, curr: curr, watch: fsnotify.watch())
  event.event_has(event: ev, op: Write) |> should.equal(True)
  path.path_to_string(event.event_path(event: ev))
  |> should.equal("/tmp/a")
}
