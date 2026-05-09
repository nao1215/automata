import automata/fsnotify/ast.{type Op, Chmod, Create, Remove, Rename, Write}
import gleam/list
import gleam/set.{type Set}
import gleam/string

/// The empty op set. Used by `WatchEvent` constructors that build up
/// op sets incrementally.
pub fn empty_ops() -> Set(Op) {
  set.new()
}

/// All ops the differ knows about, in canonical order.
pub fn all_ops() -> Set(Op) {
  set.from_list(canonical_order())
}

/// A single-element op set.
pub fn single_op(op op: Op) -> Set(Op) {
  set.from_list([op])
}

/// Build an op set from a list. Duplicates are collapsed (set semantics).
pub fn ops_from_list(ops ops: List(Op)) -> Set(Op) {
  set.from_list(ops)
}

/// Union of two op sets.
pub fn combine(left left: Set(Op), right right: Set(Op)) -> Set(Op) {
  set.union(left, right)
}

/// `True` when `ops` contains `op`.
pub fn has(ops ops: Set(Op), op op: Op) -> Bool {
  set.contains(ops, op)
}

/// Convert an op set into a list whose order is fixed across runs and
/// targets: `[Create, Write, Remove, Rename, Chmod]`. Stable rendering
/// matters for tests that compare event sequences across the BEAM and
/// JavaScript targets.
pub fn to_list(ops ops: Set(Op)) -> List(Op) {
  list.filter(canonical_order(), fn(op) { set.contains(ops, op) })
}

/// Render an op as one of `"CREATE"`, `"WRITE"`, `"REMOVE"`,
/// `"RENAME"`, `"CHMOD"`.
pub fn op_to_string(op op: Op) -> String {
  case op {
    Create -> "CREATE"
    Write -> "WRITE"
    Remove -> "REMOVE"
    Rename -> "RENAME"
    Chmod -> "CHMOD"
  }
}

/// Render an op set as `"CREATE|WRITE"` (canonical order). Empty sets
/// render as the empty string.
pub fn ops_to_string(ops ops: Set(Op)) -> String {
  ops
  |> to_list
  |> list.map(op_to_string)
  |> string.join("|")
}

fn canonical_order() -> List(Op) {
  [Create, Write, Remove, Rename, Chmod]
}
