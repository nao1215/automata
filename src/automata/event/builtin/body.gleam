import automata/event.{type Event}
import automata/event/metadata
import automata/event/source.{type Source, type SourceKind}
import automata/schedule/ast.{type ValidDateTime}
import gleam/dict.{type Dict}
import gleam/option.{type Option}

/// Built-in body sum used by the `BuiltinEvent` alias.
///
/// Closed for known kinds plus a `Custom` escape hatch. New kinds are
/// added as the ecosystem standardises on them; until then, callers
/// emit `Custom("vendor.kind", attributes)`.
pub type EventBody {
  Scheduled(
    plan_id: String,
    fired_at: ValidDateTime,
    schedule_kind: ScheduleKind,
  )
  FileCreated(path: String)
  FileModified(path: String)
  FileDeleted(path: String)
  FileRenamed(from: String, to: String)
  Manual(reason: Option(String), actor: Option(String))
  Custom(kind: String, attributes: Dict(String, String))
}

/// Distinguishes cron and RRULE plans inside `Scheduled` so a worker
/// can branch without inspecting the producing module.
pub type ScheduleKind {
  CronSchedule
  RRuleSchedule
}

/// Convenience alias used by ecosystem-wide layers (worker, runtime).
pub type BuiltinEvent =
  Event(EventBody)

/// Stable string label for routing tables, metrics, and structured logs.
///
/// `Custom("slack.message_posted", _)` becomes `"custom:slack.message_posted"`.
pub fn kind(body: EventBody) -> String {
  case body {
    Scheduled(_, _, _) -> "scheduled"
    FileCreated(_) -> "file_created"
    FileModified(_) -> "file_modified"
    FileDeleted(_) -> "file_deleted"
    FileRenamed(_, _) -> "file_renamed"
    Manual(_, _) -> "manual"
    Custom(name, _) -> "custom:" <> name
  }
}

pub fn scheduled(
  plan_id plan_id: String,
  fired_at fired_at: ValidDateTime,
  schedule_kind schedule_kind: ScheduleKind,
) -> EventBody {
  Scheduled(plan_id: plan_id, fired_at: fired_at, schedule_kind: schedule_kind)
}

pub fn file_created(path path: String) -> EventBody {
  FileCreated(path: path)
}

pub fn file_modified(path path: String) -> EventBody {
  FileModified(path: path)
}

pub fn file_deleted(path path: String) -> EventBody {
  FileDeleted(path: path)
}

pub fn file_renamed(from from: String, to to: String) -> EventBody {
  FileRenamed(from: from, to: to)
}

pub fn manual(
  reason reason: Option(String),
  actor actor: Option(String),
) -> EventBody {
  Manual(reason: reason, actor: actor)
}

pub fn custom(
  kind kind: String,
  attributes attributes: Dict(String, String),
) -> EventBody {
  Custom(kind: kind, attributes: attributes)
}

/// Construct a `BuiltinEvent` whose `source.kind` is derived from
/// `body`. This is the only sanctioned constructor for `BuiltinEvent`
/// because it makes source/body misclassification unrepresentable —
/// `Scheduled` always pairs with `ScheduleSource`, `FileModified` with
/// `FileSystemSource`, `Custom("vendor.kind", _)` with
/// `CustomSource("vendor.kind")`, etc.
pub fn new(
  id id: String,
  occurred_at occurred_at: ValidDateTime,
  source_id source_id: String,
  body body: EventBody,
) -> BuiltinEvent {
  event.Event(
    id: id,
    occurred_at: occurred_at,
    source: derived_source(body, source_id),
    body: body,
    metadata: metadata.empty(),
  )
}

/// Derive the canonical `Source` for an `EventBody`. Exposed so that
/// callers building events via `event.new` (for advanced cases like
/// attaching a source name) can stay consistent with `body.new`.
pub fn derived_source(body: EventBody, source_id: String) -> Source {
  source.new(kind: derived_source_kind(body), id: source_id)
}

/// Map an `EventBody` to its canonical `SourceKind`.
pub fn derived_source_kind(body: EventBody) -> SourceKind {
  case body {
    Scheduled(_, _, _) -> source.ScheduleSource
    FileCreated(_) -> source.FileSystemSource
    FileModified(_) -> source.FileSystemSource
    FileDeleted(_) -> source.FileSystemSource
    FileRenamed(_, _) -> source.FileSystemSource
    Manual(_, _) -> source.ManualSource
    Custom(name, _) -> source.CustomSource(name)
  }
}
