import automata/fsevent/ast.{
  Chmod, Create, EmptyOps, Remove, Rename, RenamedFromWithoutRenameOp, Write,
}
import automata/fsevent/event
import automata/fsevent/op
import automata/fsevent/path
import gleam/option.{None, Some}
import gleeunit/should

fn p(s: String) {
  let assert Ok(value) = path.normalize(path: s)
  value
}

pub fn created_has_only_create_op_test() {
  let ev = event.created(path: p("/tmp/a"))
  event.event_has(event: ev, op: Create) |> should.equal(True)
  event.event_has(event: ev, op: Write) |> should.equal(False)
  event.event_renamed_from(event: ev) |> should.equal(None)
}

pub fn written_has_only_write_op_test() {
  let ev = event.written(path: p("/tmp/a"))
  event.event_has(event: ev, op: Write) |> should.equal(True)
  event.event_has(event: ev, op: Create) |> should.equal(False)
}

pub fn removed_has_only_remove_op_test() {
  let ev = event.removed(path: p("/tmp/a"))
  event.event_has(event: ev, op: Remove) |> should.equal(True)
}

pub fn chmoded_has_only_chmod_op_test() {
  let ev = event.chmoded(path: p("/tmp/a"))
  event.event_has(event: ev, op: Chmod) |> should.equal(True)
}

pub fn renamed_attaches_renamed_from_test() {
  let ev = event.renamed(to: p("/tmp/b"), from: p("/tmp/a"))
  event.event_has(event: ev, op: Rename) |> should.equal(True)
  case event.event_renamed_from(event: ev) {
    Some(from) -> path.path_to_string(from) |> should.equal("/tmp/a")
    None -> should.fail()
  }
}

pub fn multi_op_combines_ops_test() {
  let assert Ok(ev) =
    event.multi_op(
      path: p("/tmp/a"),
      ops: op.ops_from_list([Create, Write]),
      renamed_from: None,
    )
  event.event_has(event: ev, op: Create) |> should.equal(True)
  event.event_has(event: ev, op: Write) |> should.equal(True)
  event.event_has(event: ev, op: Remove) |> should.equal(False)
}

pub fn multi_op_empty_set_returns_error_test() {
  case
    event.multi_op(path: p("/tmp/a"), ops: op.empty_ops(), renamed_from: None)
  {
    Error(EmptyOps) -> Nil
    _ -> should.fail()
  }
}

pub fn multi_op_renamed_from_without_rename_op_returns_error_test() {
  case
    event.multi_op(
      path: p("/tmp/a"),
      ops: op.single_op(Write),
      renamed_from: Some(p("/tmp/b")),
    )
  {
    Error(RenamedFromWithoutRenameOp(path: "/tmp/a")) -> Nil
    _ -> should.fail()
  }
}

pub fn multi_op_rename_with_renamed_from_allowed_test() {
  let assert Ok(_) =
    event.multi_op(
      path: p("/tmp/b"),
      ops: op.ops_from_list([Rename, Write]),
      renamed_from: Some(p("/tmp/a")),
    )
}

pub fn multi_op_rename_without_renamed_from_allowed_test() {
  // The differ never produces this, but the type-level invariant only
  // forbids the *opposite* mismatch. Document the choice explicitly so
  // the test pins the behaviour.
  let assert Ok(_) =
    event.multi_op(
      path: p("/tmp/a"),
      ops: op.single_op(Rename),
      renamed_from: None,
    )
}

pub fn event_to_string_single_op_test() {
  let ev = event.written(path: p("/tmp/a"))
  event.event_to_string(event: ev) |> should.equal("WRITE /tmp/a")
}

pub fn event_to_string_compound_op_test() {
  let assert Ok(ev) =
    event.multi_op(
      path: p("/tmp/new"),
      ops: op.ops_from_list([Create, Write]),
      renamed_from: None,
    )
  event.event_to_string(event: ev) |> should.equal("CREATE|WRITE /tmp/new")
}

pub fn event_to_string_rename_test() {
  let ev = event.renamed(to: p("/tmp/b"), from: p("/tmp/a"))
  event.event_to_string(event: ev) |> should.equal("RENAME /tmp/b <- /tmp/a")
}
