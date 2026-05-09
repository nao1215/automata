import automata/event.{type Event}
import automata/event/builtin/body.{type EventBody, type ScheduleKind}

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

pub fn is_file_event(event event: Event(EventBody)) -> Bool {
  case event.body {
    body.FileCreated(_) -> True
    body.FileModified(_) -> True
    body.FileDeleted(_) -> True
    body.FileRenamed(_, _) -> True
    _ -> False
  }
}

pub fn is_file_created(event event: Event(EventBody)) -> Bool {
  case event.body {
    body.FileCreated(_) -> True
    _ -> False
  }
}

pub fn is_file_modified(event event: Event(EventBody)) -> Bool {
  case event.body {
    body.FileModified(_) -> True
    _ -> False
  }
}

pub fn is_file_deleted(event event: Event(EventBody)) -> Bool {
  case event.body {
    body.FileDeleted(_) -> True
    _ -> False
  }
}

pub fn is_file_renamed(event event: Event(EventBody)) -> Bool {
  case event.body {
    body.FileRenamed(_, _) -> True
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
