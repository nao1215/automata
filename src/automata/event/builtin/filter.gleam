import automata/event/builtin/body.{type EventBody, type ScheduleKind}
import automata/event/filter.{type Filter}
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

/// Match any file-system body variant (created/modified/deleted/renamed).
pub fn is_file_event() -> Filter(EventBody) {
  filter.on_body(fn(b) {
    case b {
      body.FileCreated(_) -> True
      body.FileModified(_) -> True
      body.FileDeleted(_) -> True
      body.FileRenamed(_, _) -> True
      _ -> False
    }
  })
}

pub fn is_file_modified() -> Filter(EventBody) {
  filter.on_body(fn(b) {
    case b {
      body.FileModified(_) -> True
      _ -> False
    }
  })
}

pub fn is_file_created() -> Filter(EventBody) {
  filter.on_body(fn(b) {
    case b {
      body.FileCreated(_) -> True
      _ -> False
    }
  })
}

pub fn is_file_deleted() -> Filter(EventBody) {
  filter.on_body(fn(b) {
    case b {
      body.FileDeleted(_) -> True
      _ -> False
    }
  })
}

pub fn is_file_renamed() -> Filter(EventBody) {
  filter.on_body(fn(b) {
    case b {
      body.FileRenamed(_, _) -> True
      _ -> False
    }
  })
}

/// Match any file-system event whose path (or `to` for rename) starts
/// with `prefix`.
pub fn by_path_prefix(prefix prefix: String) -> Filter(EventBody) {
  filter.on_body(fn(b) {
    case file_path(b) {
      Ok(path) -> string.starts_with(path, prefix)
      Error(_) -> False
    }
  })
}

/// Match any file-system event whose path (or `to` for rename) ends
/// with `suffix`. Useful for extension matching such as `".gleam"`.
pub fn by_path_suffix(suffix suffix: String) -> Filter(EventBody) {
  filter.on_body(fn(b) {
    case file_path(b) {
      Ok(path) -> string.ends_with(path, suffix)
      Error(_) -> False
    }
  })
}

/// Match any file-system event whose path (or `to` for rename) contains
/// `needle` as a substring.
pub fn by_path_contains(needle needle: String) -> Filter(EventBody) {
  filter.on_body(fn(b) {
    case file_path(b) {
      Ok(path) -> string.contains(path, needle)
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
    body.FileCreated(path) -> Ok(path)
    body.FileModified(path) -> Ok(path)
    body.FileDeleted(path) -> Ok(path)
    body.FileRenamed(_, to) -> Ok(to)
    _ -> Error(Nil)
  }
}
