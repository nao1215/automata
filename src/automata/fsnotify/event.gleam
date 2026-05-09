import automata/fsnotify/ast.{
  type FsnotifyError, type Op, Chmod, Create, EmptyOps, Remove, Rename,
  RenamedFromWithoutRenameOp, Write,
}
import automata/fsnotify/op
import automata/fsnotify/path.{type NormalizedPath}
import gleam/option.{type Option, None, Some}
import gleam/set.{type Set}

/// One file-system event derived from a snapshot diff.
///
/// `opaque` so the smart constructors can enforce two invariants the
/// type would otherwise leave open:
///
///   - `ops` is never empty (an event with nothing observed makes no
///     sense; the differ filters those out before constructing one).
///   - `renamed_from` is `Some(_)` only when `ops` contains `Rename`.
///
/// These rules mirror Go fsnotify's `Event` and notify-rs's
/// `RenameMode::Both`: the rename's old path is attached to the new
/// path event, not to a parallel `Remove`.
pub opaque type WatchEvent {
  WatchEvent(
    path: NormalizedPath,
    ops: Set(Op),
    renamed_from: Option(NormalizedPath),
  )
}

/// `Create`-only event for `path`.
pub fn created(path path: NormalizedPath) -> WatchEvent {
  WatchEvent(path: path, ops: op.single_op(Create), renamed_from: None)
}

/// `Write`-only event for `path`.
pub fn written(path path: NormalizedPath) -> WatchEvent {
  WatchEvent(path: path, ops: op.single_op(Write), renamed_from: None)
}

/// `Remove`-only event for `path`.
pub fn removed(path path: NormalizedPath) -> WatchEvent {
  WatchEvent(path: path, ops: op.single_op(Remove), renamed_from: None)
}

/// `Chmod`-only event for `path`.
pub fn chmoded(path path: NormalizedPath) -> WatchEvent {
  WatchEvent(path: path, ops: op.single_op(Chmod), renamed_from: None)
}

/// `Rename` event whose new path is `to` and whose old path was `from`.
pub fn renamed(to to: NormalizedPath, from from: NormalizedPath) -> WatchEvent {
  WatchEvent(path: to, ops: op.single_op(Rename), renamed_from: Some(from))
}

/// Build an event whose op set may carry several ops at once (for
/// example a freshly created non-empty file is `{Create, Write}`).
///
/// Validates the op set is non-empty and that `renamed_from` only
/// appears together with the `Rename` op.
pub fn multi_op(
  path path: NormalizedPath,
  ops ops: Set(Op),
  renamed_from from: Option(NormalizedPath),
) -> Result(WatchEvent, FsnotifyError) {
  case set.size(ops) == 0 {
    True -> Error(EmptyOps)
    False ->
      case from {
        None -> Ok(WatchEvent(path: path, ops: ops, renamed_from: None))
        Some(_) ->
          case set.contains(ops, Rename) {
            False ->
              Error(RenamedFromWithoutRenameOp(path: path.path_to_string(path)))
            True -> Ok(WatchEvent(path: path, ops: ops, renamed_from: from))
          }
      }
  }
}

pub fn event_path(event event: WatchEvent) -> NormalizedPath {
  event.path
}

pub fn event_ops(event event: WatchEvent) -> Set(Op) {
  event.ops
}

pub fn event_has(event event: WatchEvent, op op: Op) -> Bool {
  set.contains(event.ops, op)
}

pub fn event_renamed_from(event event: WatchEvent) -> Option(NormalizedPath) {
  event.renamed_from
}

/// Render an event in fsnotify-go style: `"WRITE /tmp/a"` for a
/// single-op event, `"CREATE|WRITE /tmp/a"` for compound ops, and
/// `"RENAME /tmp/b <- /tmp/a"` for renames. The arrow is ASCII (`<-`)
/// so the rendering is safe to use in any terminal.
pub fn event_to_string(event event: WatchEvent) -> String {
  let head =
    op.ops_to_string(event.ops) <> " " <> path.path_to_string(event.path)
  case event.renamed_from {
    None -> head
    Some(from) -> head <> " <- " <> path.path_to_string(from)
  }
}
