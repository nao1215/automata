import automata/event/builtin/body.{type EventBody, type ScheduleKind}
import automata/event/filter.{type Filter}
import automata/fsnotify/ast.{type Op}
import automata/fsnotify/event as fs_event
import automata/fsnotify/path as fs_path
import gleam/string

/// Match any event whose body is `Scheduled(_, _, _)`.
pub fn is_scheduled() -> Filter(EventBody) {
  filter.on_body(fn(b) {
    case b {
      body.Scheduled(_, _, _) -> True
      _ -> False
    }
  })
}

/// Match scheduled events whose `schedule_kind` equals `kind`.
pub fn by_schedule_kind(kind kind: ScheduleKind) -> Filter(EventBody) {
  filter.on_body(fn(b) {
    case b {
      body.Scheduled(_, _, k) -> k == kind
      _ -> False
    }
  })
}

/// Match scheduled events whose `plan_id` equals `id`.
pub fn by_plan_id(id id: String) -> Filter(EventBody) {
  filter.on_body(fn(b) {
    case b {
      body.Scheduled(plan, _, _) -> plan == id
      _ -> False
    }
  })
}

/// Match any `FileSystem(_)` body, irrespective of op.
pub fn is_file_event() -> Filter(EventBody) {
  filter.on_body(fn(b) {
    case b {
      body.FileSystem(_) -> True
      _ -> False
    }
  })
}

/// Match `FileSystem(_)` bodies whose wrapped `WatchEvent` carries
/// `op`. Replaces the legacy `is_file_created/modified/deleted/renamed`
/// helpers.
pub fn is_file_with_op(op op: Op) -> Filter(EventBody) {
  filter.on_body(fn(b) {
    case b {
      body.FileSystem(watch_event) -> fs_event.event_has(watch_event, op)
      _ -> False
    }
  })
}

/// Match `FileSystem(_)` events whose path starts with `prefix`.
/// `prefix` is matched against the canonical string rendering of the
/// event's path (the new path for renames).
pub fn by_path_prefix(prefix prefix: String) -> Filter(EventBody) {
  filter.on_body(fn(b) {
    case file_path(b) {
      Ok(p) -> string.starts_with(p, prefix)
      Error(_) -> False
    }
  })
}

/// Match `FileSystem(_)` events whose path ends with `suffix`.
pub fn by_path_suffix(suffix suffix: String) -> Filter(EventBody) {
  filter.on_body(fn(b) {
    case file_path(b) {
      Ok(p) -> string.ends_with(p, suffix)
      Error(_) -> False
    }
  })
}

/// Match `FileSystem(_)` events whose path contains `needle`.
pub fn by_path_contains(needle needle: String) -> Filter(EventBody) {
  filter.on_body(fn(b) {
    case file_path(b) {
      Ok(p) -> string.contains(p, needle)
      Error(_) -> False
    }
  })
}

pub fn is_manual() -> Filter(EventBody) {
  filter.on_body(fn(b) {
    case b {
      body.Manual(_, _) -> True
      _ -> False
    }
  })
}

pub fn is_custom() -> Filter(EventBody) {
  filter.on_body(fn(b) {
    case b {
      body.Custom(_, _) -> True
      _ -> False
    }
  })
}

pub fn by_custom_kind(kind kind: String) -> Filter(EventBody) {
  filter.on_body(fn(b) {
    case b {
      body.Custom(name, _) -> name == kind
      _ -> False
    }
  })
}

fn file_path(b: EventBody) -> Result(String, Nil) {
  case b {
    body.FileSystem(watch_event) ->
      Ok(fs_path.path_to_string(fs_event.event_path(watch_event)))
    _ -> Error(Nil)
  }
}
