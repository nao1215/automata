import automata/event.{type Event}
import automata/event/builtin/body.{type EventBody, type ScheduleKind}
import automata/fsnotify/ast.{type Op}
import automata/fsnotify/event as fs_event

pub fn is_scheduled(event event: Event(EventBody)) -> Bool {
  case event.body {
    body.Scheduled(_, _, _) -> True
    _ -> False
  }
}

pub fn is_schedule_kind(
  event event: Event(EventBody),
  kind kind: ScheduleKind,
) -> Bool {
  case event.body {
    body.Scheduled(_, _, k) -> k == kind
    _ -> False
  }
}

/// `True` when the event's body is a `FileSystem(_)` variant. Use
/// `is_file_with_op` to discriminate by `Op`.
pub fn is_file_event(event event: Event(EventBody)) -> Bool {
  case event.body {
    body.FileSystem(_) -> True
    _ -> False
  }
}

/// `True` when the event's body is `FileSystem(_)` and the wrapped
/// `WatchEvent` carries `op` in its op set. This replaces the legacy
/// `is_file_created/modified/deleted/renamed` helpers; pass `Create`,
/// `Write`, `Remove`, `Rename`, or `Chmod` for the same effect.
pub fn is_file_with_op(event event: Event(EventBody), op op: Op) -> Bool {
  case event.body {
    body.FileSystem(watch_event) -> fs_event.event_has(watch_event, op)
    _ -> False
  }
}

pub fn is_manual(event event: Event(EventBody)) -> Bool {
  case event.body {
    body.Manual(_, _) -> True
    _ -> False
  }
}

pub fn is_custom(event event: Event(EventBody)) -> Bool {
  case event.body {
    body.Custom(_, _) -> True
    _ -> False
  }
}

pub fn is_custom_kind(event event: Event(EventBody), kind kind: String) -> Bool {
  case event.body {
    body.Custom(name, _) -> name == kind
    _ -> False
  }
}
