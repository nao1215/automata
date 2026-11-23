import automata as a
import gleam/option.{None, Some}
import gleam/set
import gleeunit/should

fn p(s: String) {
  let assert Ok(value) = a.path_normalize(path: s)
  value
}

pub fn created_has_only_create_op_test() {
  let ev = old_fsevent_event_created(path: p("/tmp/a"))
  old_fsevent_event_event_has(event: ev, op: a.Create) |> should.equal(True)
  old_fsevent_event_event_has(event: ev, op: a.Write) |> should.equal(False)
  a.filesystem_event_renamed_from(event: ev) |> should.equal(None)
}

pub fn written_has_only_write_op_test() {
  let ev = old_fsevent_event_written(path: p("/tmp/a"))
  old_fsevent_event_event_has(event: ev, op: a.Write) |> should.equal(True)
  old_fsevent_event_event_has(event: ev, op: a.Create) |> should.equal(False)
}

pub fn removed_has_only_remove_op_test() {
  let ev = old_fsevent_event_removed(path: p("/tmp/a"))
  old_fsevent_event_event_has(event: ev, op: a.Remove) |> should.equal(True)
}

pub fn chmoded_has_only_chmod_op_test() {
  let ev = old_fsevent_event_chmoded(path: p("/tmp/a"))
  old_fsevent_event_event_has(event: ev, op: a.Chmod) |> should.equal(True)
}

pub fn renamed_attaches_renamed_from_test() {
  let ev = old_fsevent_event_renamed(to: p("/tmp/b"), from: p("/tmp/a"))
  old_fsevent_event_event_has(event: ev, op: a.Rename) |> should.equal(True)
  case a.filesystem_event_renamed_from(event: ev) {
    Some(from) -> a.path_to_string(path: from) |> should.equal("/tmp/a")
    None -> should.fail()
  }
}

pub fn multi_op_combines_ops_test() {
  let assert Ok(ev) =
    a.filesystem_event(
      path: p("/tmp/a"),
      ops: old_fsevent_op_ops_from_list(ops: [a.Create, a.Write]),
      renamed_from: None,
    )
  old_fsevent_event_event_has(event: ev, op: a.Create) |> should.equal(True)
  old_fsevent_event_event_has(event: ev, op: a.Write) |> should.equal(True)
  old_fsevent_event_event_has(event: ev, op: a.Remove) |> should.equal(False)
}

pub fn multi_op_empty_set_returns_error_test() {
  case
    a.filesystem_event(
      path: p("/tmp/a"),
      ops: old_fsevent_op_empty_ops(),
      renamed_from: None,
    )
  {
    Error(a.EmptyOps) -> Nil
    _ -> should.fail()
  }
}

pub fn multi_op_renamed_from_without_rename_op_returns_error_test() {
  case
    a.filesystem_event(
      path: p("/tmp/a"),
      ops: old_fsevent_op_single_op(op: a.Write),
      renamed_from: Some(p("/tmp/b")),
    )
  {
    Error(a.RenamedFromWithoutRenameOp(path: "/tmp/a")) -> Nil
    _ -> should.fail()
  }
}

pub fn multi_op_rename_with_renamed_from_allowed_test() {
  let assert Ok(_) =
    a.filesystem_event(
      path: p("/tmp/b"),
      ops: old_fsevent_op_ops_from_list(ops: [a.Rename, a.Write]),
      renamed_from: Some(p("/tmp/a")),
    )
}

pub fn multi_op_rename_without_renamed_from_allowed_test() {
  // The differ never produces this, but the type-level invariant only
  // forbids the *opposite* mismatch. Document the choice explicitly so
  // the test pins the behaviour.
  let assert Ok(_) =
    a.filesystem_event(
      path: p("/tmp/a"),
      ops: old_fsevent_op_single_op(op: a.Rename),
      renamed_from: None,
    )
}

pub fn event_to_string_single_op_test() {
  let ev = old_fsevent_event_written(path: p("/tmp/a"))
  a.filesystem_event_to_string(event: ev) |> should.equal("WRITE /tmp/a")
}

pub fn event_to_string_compound_op_test() {
  let assert Ok(ev) =
    a.filesystem_event(
      path: p("/tmp/new"),
      ops: old_fsevent_op_ops_from_list(ops: [a.Create, a.Write]),
      renamed_from: None,
    )
  a.filesystem_event_to_string(event: ev)
  |> should.equal("CREATE|WRITE /tmp/new")
}

pub fn event_to_string_rename_test() {
  let ev = old_fsevent_event_renamed(to: p("/tmp/b"), from: p("/tmp/a"))
  a.filesystem_event_to_string(event: ev)
  |> should.equal("RENAME /tmp/b <- /tmp/a")
}

fn old_fsevent_event_chmoded(path path: a.NormalizedPath) -> a.WatchEvent {
  let assert Ok(event) =
    a.filesystem_event(
      path: path,
      ops: set.from_list([a.Chmod]),
      renamed_from: option.None,
    )
  event
}

fn old_fsevent_event_created(path path: a.NormalizedPath) -> a.WatchEvent {
  let assert Ok(event) =
    a.filesystem_event(
      path: path,
      ops: set.from_list([a.Create]),
      renamed_from: option.None,
    )
  event
}

fn old_fsevent_event_event_has(event event: a.WatchEvent, op op: a.Op) -> Bool {
  set.contains(a.filesystem_event_ops(event: event), op)
}

fn old_fsevent_event_removed(path path: a.NormalizedPath) -> a.WatchEvent {
  let assert Ok(event) =
    a.filesystem_event(
      path: path,
      ops: set.from_list([a.Remove]),
      renamed_from: option.None,
    )
  event
}

fn old_fsevent_event_renamed(
  from from: a.NormalizedPath,
  to to: a.NormalizedPath,
) -> a.WatchEvent {
  let assert Ok(event) =
    a.filesystem_event(
      path: to,
      ops: set.from_list([a.Rename]),
      renamed_from: option.Some(from),
    )
  event
}

fn old_fsevent_event_written(path path: a.NormalizedPath) -> a.WatchEvent {
  let assert Ok(event) =
    a.filesystem_event(
      path: path,
      ops: set.from_list([a.Write]),
      renamed_from: option.None,
    )
  event
}

fn old_fsevent_op_empty_ops() -> set.Set(a.Op) {
  set.new()
}

fn old_fsevent_op_ops_from_list(ops ops: List(a.Op)) -> set.Set(a.Op) {
  set.from_list(ops)
}

fn old_fsevent_op_single_op(op op: a.Op) -> set.Set(a.Op) {
  set.from_list([op])
}
