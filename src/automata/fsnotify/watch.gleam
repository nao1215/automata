import automata/fsnotify/ast.{type Op}
import automata/fsnotify/op
import gleam/set.{type Set}

/// Subscription specification handed to `diff/3`.
///
/// `opaque` so the only way to construct a value is through the smart
/// builder below, and so future fields (e.g. a path filter expressed
/// as a list of normalised prefixes) can be added without a public
/// API change. The watch holds a set of `Op` values that the caller
/// is interested in; events whose op set has empty intersection with
/// the watch are dropped before they reach the result list.
pub opaque type Watch {
  Watch(op_mask: Set(Op))
}

/// Default watch: subscribed to every op (`Create`, `Write`, `Remove`,
/// `Rename`, `Chmod`).
pub fn watch() -> Watch {
  watch_all_ops()
}

/// Watch every op.
pub fn watch_all_ops() -> Watch {
  Watch(op_mask: op.all_ops())
}

/// Watch no op. The differ will return an empty list for any input.
pub fn watch_no_ops() -> Watch {
  Watch(op_mask: op.empty_ops())
}

/// Replace the op mask with the given set.
pub fn with_ops(watch _watch: Watch, ops ops: Set(Op)) -> Watch {
  Watch(op_mask: ops)
}

/// Add a single op to `watch`'s mask. Idempotent.
pub fn watch_op(watch watch: Watch, op op: Op) -> Watch {
  Watch(op_mask: set.insert(watch.op_mask, op))
}

/// Remove a single op from `watch`'s mask. Idempotent.
pub fn unwatch_op(watch watch: Watch, op op: Op) -> Watch {
  Watch(op_mask: set.delete(watch.op_mask, op))
}

/// Recover the watch's op mask.
pub fn watch_op_mask(watch watch: Watch) -> Set(Op) {
  watch.op_mask
}

/// `True` when `watch` is interested in `op`.
pub fn watch_observes(watch watch: Watch, op op: Op) -> Bool {
  set.contains(watch.op_mask, op)
}

/// `True` when `watch`'s op mask is empty.
pub fn watch_is_silent(watch watch: Watch) -> Bool {
  set.size(watch.op_mask) == 0
}
