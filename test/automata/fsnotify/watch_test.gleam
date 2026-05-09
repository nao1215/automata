import automata/fsnotify/ast.{Chmod, Create, Remove, Rename, Write}
import automata/fsnotify/op
import automata/fsnotify/watch
import gleam/set
import gleeunit/should

pub fn default_watch_observes_all_ops_test() {
  let w = watch.watch()
  watch.watch_observes(watch: w, op: Create) |> should.equal(True)
  watch.watch_observes(watch: w, op: Write) |> should.equal(True)
  watch.watch_observes(watch: w, op: Remove) |> should.equal(True)
  watch.watch_observes(watch: w, op: Rename) |> should.equal(True)
  watch.watch_observes(watch: w, op: Chmod) |> should.equal(True)
}

pub fn default_watch_is_not_silent_test() {
  watch.watch_is_silent(watch: watch.watch()) |> should.equal(False)
}

pub fn watch_no_ops_is_silent_test() {
  watch.watch_is_silent(watch: watch.watch_no_ops()) |> should.equal(True)
}

pub fn unwatch_op_removes_only_specified_test() {
  let w = watch.unwatch_op(watch: watch.watch(), op: Chmod)
  watch.watch_observes(watch: w, op: Chmod) |> should.equal(False)
  watch.watch_observes(watch: w, op: Create) |> should.equal(True)
  watch.watch_observes(watch: w, op: Write) |> should.equal(True)
  watch.watch_observes(watch: w, op: Remove) |> should.equal(True)
  watch.watch_observes(watch: w, op: Rename) |> should.equal(True)
}

pub fn watch_op_adds_to_silent_watch_test() {
  let w =
    watch.watch_no_ops()
    |> watch.watch_op(op: Write)
    |> watch.watch_op(op: Rename)
  watch.watch_observes(watch: w, op: Write) |> should.equal(True)
  watch.watch_observes(watch: w, op: Rename) |> should.equal(True)
  watch.watch_observes(watch: w, op: Create) |> should.equal(False)
}

pub fn watch_op_idempotent_test() {
  let w =
    watch.watch_no_ops()
    |> watch.watch_op(op: Write)
    |> watch.watch_op(op: Write)
  watch.watch_op_mask(watch: w) |> set.size |> should.equal(1)
}

pub fn unwatch_op_idempotent_test() {
  let w =
    watch.watch()
    |> watch.unwatch_op(op: Chmod)
    |> watch.unwatch_op(op: Chmod)
  watch.watch_op_mask(watch: w) |> set.size |> should.equal(4)
}

pub fn with_ops_replaces_mask_test() {
  let w = watch.with_ops(watch.watch(), ops: op.single_op(Write))
  watch.watch_op_mask(watch: w) |> set.size |> should.equal(1)
  watch.watch_observes(watch: w, op: Write) |> should.equal(True)
  watch.watch_observes(watch: w, op: Create) |> should.equal(False)
}
