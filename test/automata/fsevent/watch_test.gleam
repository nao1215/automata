import automata as a
import gleam/set
import gleeunit/should

pub fn default_watch_observes_all_ops_test() {
  let w = old_fsevent_watch_watch()
  old_fsevent_watch_watch_observes(watch: w, op: a.Create) |> should.equal(True)
  old_fsevent_watch_watch_observes(watch: w, op: a.Write) |> should.equal(True)
  old_fsevent_watch_watch_observes(watch: w, op: a.Remove) |> should.equal(True)
  old_fsevent_watch_watch_observes(watch: w, op: a.Rename) |> should.equal(True)
  old_fsevent_watch_watch_observes(watch: w, op: a.Chmod) |> should.equal(True)
}

pub fn default_watch_is_not_silent_test() {
  old_fsevent_watch_watch_is_silent(watch: old_fsevent_watch_watch())
  |> should.equal(False)
}

pub fn watch_no_ops_is_silent_test() {
  old_fsevent_watch_watch_is_silent(watch: old_fsevent_watch_watch_no_ops())
  |> should.equal(True)
}

pub fn unwatch_op_removes_only_specified_test() {
  let w =
    old_fsevent_watch_unwatch_op(watch: old_fsevent_watch_watch(), op: a.Chmod)
  old_fsevent_watch_watch_observes(watch: w, op: a.Chmod) |> should.equal(False)
  old_fsevent_watch_watch_observes(watch: w, op: a.Create) |> should.equal(True)
  old_fsevent_watch_watch_observes(watch: w, op: a.Write) |> should.equal(True)
  old_fsevent_watch_watch_observes(watch: w, op: a.Remove) |> should.equal(True)
  old_fsevent_watch_watch_observes(watch: w, op: a.Rename) |> should.equal(True)
}

pub fn watch_op_adds_to_silent_watch_test() {
  let w =
    old_fsevent_watch_watch_no_ops()
    |> old_fsevent_watch_watch_op(op: a.Write)
    |> old_fsevent_watch_watch_op(op: a.Rename)
  old_fsevent_watch_watch_observes(watch: w, op: a.Write) |> should.equal(True)
  old_fsevent_watch_watch_observes(watch: w, op: a.Rename) |> should.equal(True)
  old_fsevent_watch_watch_observes(watch: w, op: a.Create)
  |> should.equal(False)
}

pub fn watch_op_idempotent_test() {
  let w =
    old_fsevent_watch_watch_no_ops()
    |> old_fsevent_watch_watch_op(op: a.Write)
    |> old_fsevent_watch_watch_op(op: a.Write)
  old_fsevent_watch_watch_op_mask(watch: w) |> set.size |> should.equal(1)
}

pub fn unwatch_op_idempotent_test() {
  let w =
    old_fsevent_watch_watch()
    |> old_fsevent_watch_unwatch_op(op: a.Chmod)
    |> old_fsevent_watch_unwatch_op(op: a.Chmod)
  old_fsevent_watch_watch_op_mask(watch: w) |> set.size |> should.equal(4)
}

pub fn with_ops_replaces_mask_test() {
  let w =
    old_fsevent_watch_with_ops(
      watch: old_fsevent_watch_watch(),
      ops: old_fsevent_op_single_op(op: a.Write),
    )
  old_fsevent_watch_watch_op_mask(watch: w) |> set.size |> should.equal(1)
  old_fsevent_watch_watch_observes(watch: w, op: a.Write) |> should.equal(True)
  old_fsevent_watch_watch_observes(watch: w, op: a.Create)
  |> should.equal(False)
}

fn old_fsevent_op_single_op(op op: a.Op) -> set.Set(a.Op) {
  set.from_list([op])
}

fn old_fsevent_watch_unwatch_op(
  watch watch: set.Set(a.Op),
  op op: a.Op,
) -> set.Set(a.Op) {
  set.delete(watch, op)
}

fn old_fsevent_watch_watch() -> set.Set(a.Op) {
  a.all_ops()
}

fn old_fsevent_watch_watch_is_silent(watch watch: set.Set(a.Op)) -> Bool {
  set.size(watch) == 0
}

fn old_fsevent_watch_watch_no_ops() -> set.Set(a.Op) {
  set.new()
}

fn old_fsevent_watch_watch_observes(
  watch watch: set.Set(a.Op),
  op op: a.Op,
) -> Bool {
  set.contains(watch, op)
}

fn old_fsevent_watch_watch_op(
  watch watch: set.Set(a.Op),
  op op: a.Op,
) -> set.Set(a.Op) {
  set.insert(watch, op)
}

fn old_fsevent_watch_watch_op_mask(
  watch watch: set.Set(a.Op),
) -> set.Set(a.Op) {
  watch
}

fn old_fsevent_watch_with_ops(
  watch _watch: set.Set(a.Op),
  ops ops: set.Set(a.Op),
) -> set.Set(a.Op) {
  ops
}
