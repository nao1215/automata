import automata/fsnotify/ast.{Chmod, Create, Remove, Rename, Write}
import automata/fsnotify/op
import gleam/set
import gleeunit/should

pub fn empty_ops_size_zero_test() {
  set.size(op.empty_ops()) |> should.equal(0)
}

pub fn all_ops_contains_five_test() {
  let all = op.all_ops()
  set.size(all) |> should.equal(5)
  set.contains(all, Create) |> should.equal(True)
  set.contains(all, Write) |> should.equal(True)
  set.contains(all, Remove) |> should.equal(True)
  set.contains(all, Rename) |> should.equal(True)
  set.contains(all, Chmod) |> should.equal(True)
}

pub fn single_op_contains_only_self_test() {
  let s = op.single_op(op: Write)
  set.size(s) |> should.equal(1)
  set.contains(s, Write) |> should.equal(True)
  set.contains(s, Create) |> should.equal(False)
}

pub fn ops_from_list_collapses_duplicates_test() {
  set.size(op.ops_from_list([Write, Write, Create])) |> should.equal(2)
}

pub fn combine_is_union_test() {
  let combined =
    op.combine(left: op.single_op(Create), right: op.single_op(Write))
  set.size(combined) |> should.equal(2)
  set.contains(combined, Create) |> should.equal(True)
  set.contains(combined, Write) |> should.equal(True)
}

pub fn has_returns_true_when_member_test() {
  op.has(ops: op.ops_from_list([Create, Write]), op: Write)
  |> should.equal(True)
  op.has(ops: op.ops_from_list([Create, Write]), op: Remove)
  |> should.equal(False)
}

pub fn to_list_returns_canonical_order_test() {
  // Insertion order is reversed; canonical order must still win.
  let s = op.ops_from_list([Chmod, Rename, Remove, Write, Create])
  op.to_list(ops: s) |> should.equal([Create, Write, Remove, Rename, Chmod])
}

pub fn to_list_subset_keeps_canonical_order_test() {
  op.to_list(ops: op.ops_from_list([Rename, Create]))
  |> should.equal([Create, Rename])
}

pub fn to_list_empty_test() {
  op.to_list(ops: op.empty_ops()) |> should.equal([])
}

pub fn op_to_string_uppercase_test() {
  op.op_to_string(op: Create) |> should.equal("CREATE")
  op.op_to_string(op: Write) |> should.equal("WRITE")
  op.op_to_string(op: Remove) |> should.equal("REMOVE")
  op.op_to_string(op: Rename) |> should.equal("RENAME")
  op.op_to_string(op: Chmod) |> should.equal("CHMOD")
}

pub fn ops_to_string_pipe_separator_test() {
  op.ops_to_string(ops: op.ops_from_list([Create, Write]))
  |> should.equal("CREATE|WRITE")
}

pub fn ops_to_string_canonical_order_test() {
  // Out-of-order insert: result must still be canonical.
  op.ops_to_string(ops: op.ops_from_list([Chmod, Create]))
  |> should.equal("CREATE|CHMOD")
}

pub fn ops_to_string_empty_test() {
  op.ops_to_string(ops: op.empty_ops()) |> should.equal("")
}

pub fn ops_to_string_single_test() {
  op.ops_to_string(ops: op.single_op(Rename)) |> should.equal("RENAME")
}
