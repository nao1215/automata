import automata as a
import gleam/set
import gleeunit/should

pub fn empty_ops_size_zero_test() {
  set.size(old_fsevent_op_empty_ops()) |> should.equal(0)
}

pub fn all_ops_contains_five_test() {
  let all = a.all_ops()
  set.size(all) |> should.equal(5)
  set.contains(all, a.Create) |> should.equal(True)
  set.contains(all, a.Write) |> should.equal(True)
  set.contains(all, a.Remove) |> should.equal(True)
  set.contains(all, a.Rename) |> should.equal(True)
  set.contains(all, a.Chmod) |> should.equal(True)
}

pub fn single_op_contains_only_self_test() {
  let s = old_fsevent_op_single_op(op: a.Write)
  set.size(s) |> should.equal(1)
  set.contains(s, a.Write) |> should.equal(True)
  set.contains(s, a.Create) |> should.equal(False)
}

pub fn ops_from_list_collapses_duplicates_test() {
  set.size(old_fsevent_op_ops_from_list(ops: [a.Write, a.Write, a.Create]))
  |> should.equal(2)
}

pub fn combine_is_union_test() {
  let combined =
    old_fsevent_op_combine(
      left: old_fsevent_op_single_op(op: a.Create),
      right: old_fsevent_op_single_op(op: a.Write),
    )
  set.size(combined) |> should.equal(2)
  set.contains(combined, a.Create) |> should.equal(True)
  set.contains(combined, a.Write) |> should.equal(True)
}

pub fn has_returns_true_when_member_test() {
  old_fsevent_op_has(
    ops: old_fsevent_op_ops_from_list(ops: [a.Create, a.Write]),
    op: a.Write,
  )
  |> should.equal(True)
  old_fsevent_op_has(
    ops: old_fsevent_op_ops_from_list(ops: [a.Create, a.Write]),
    op: a.Remove,
  )
  |> should.equal(False)
}

pub fn to_list_returns_canonical_order_test() {
  // Insertion order is reversed; canonical order must still win.
  let s =
    old_fsevent_op_ops_from_list(ops: [
      a.Chmod,
      a.Rename,
      a.Remove,
      a.Write,
      a.Create,
    ])
  a.ops_to_list(ops: s)
  |> should.equal([a.Create, a.Write, a.Remove, a.Rename, a.Chmod])
}

pub fn to_list_subset_keeps_canonical_order_test() {
  a.ops_to_list(ops: old_fsevent_op_ops_from_list(ops: [a.Rename, a.Create]))
  |> should.equal([a.Create, a.Rename])
}

pub fn to_list_empty_test() {
  a.ops_to_list(ops: old_fsevent_op_empty_ops()) |> should.equal([])
}

pub fn op_to_string_uppercase_test() {
  a.op_to_string(op: a.Create) |> should.equal("CREATE")
  a.op_to_string(op: a.Write) |> should.equal("WRITE")
  a.op_to_string(op: a.Remove) |> should.equal("REMOVE")
  a.op_to_string(op: a.Rename) |> should.equal("RENAME")
  a.op_to_string(op: a.Chmod) |> should.equal("CHMOD")
}

pub fn ops_to_string_pipe_separator_test() {
  a.ops_to_string(ops: old_fsevent_op_ops_from_list(ops: [a.Create, a.Write]))
  |> should.equal("CREATE|WRITE")
}

pub fn ops_to_string_canonical_order_test() {
  // Out-of-order insert: result must still be canonical.
  a.ops_to_string(ops: old_fsevent_op_ops_from_list(ops: [a.Chmod, a.Create]))
  |> should.equal("CREATE|CHMOD")
}

pub fn ops_to_string_empty_test() {
  a.ops_to_string(ops: old_fsevent_op_empty_ops()) |> should.equal("")
}

pub fn ops_to_string_single_test() {
  a.ops_to_string(ops: old_fsevent_op_single_op(op: a.Rename))
  |> should.equal("RENAME")
}

fn old_fsevent_op_combine(
  left left: set.Set(a.Op),
  right right: set.Set(a.Op),
) -> set.Set(a.Op) {
  set.union(left, right)
}

fn old_fsevent_op_empty_ops() -> set.Set(a.Op) {
  set.new()
}

fn old_fsevent_op_has(ops ops: set.Set(a.Op), op op: a.Op) -> Bool {
  set.contains(ops, op)
}

fn old_fsevent_op_ops_from_list(ops ops: List(a.Op)) -> set.Set(a.Op) {
  set.from_list(ops)
}

fn old_fsevent_op_single_op(op op: a.Op) -> set.Set(a.Op) {
  set.from_list([op])
}
