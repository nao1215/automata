import automata/event.{type Event}
import automata/event/metadata
import automata/event/source.{type Source}
import automata/schedule/ast.{type DateTime}
import gleam/dict.{type Dict}
import gleam/option.{type Option}

/// Built-in body sum used by the `BuiltinEvent` alias.
///
/// Closed for known kinds plus a `Custom` escape hatch. New kinds are
/// added as the ecosystem standardises on them; until then, callers
/// emit `Custom("vendor.kind", attributes)`.
pub type EventBody {
  Scheduled(plan_id: String, fired_at: DateTime, schedule_kind: ScheduleKind)
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
  fired_at fired_at: DateTime,
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

/// Construct a `BuiltinEvent` directly. Equivalent to `event.new/4`
/// specialised to `EventBody`, kept here so callers can stay inside
/// `automata/event/builtin/body` for the common path.
pub fn new(
  id id: String,
  occurred_at occurred_at: DateTime,
  source source: Source,
  body body: EventBody,
) -> BuiltinEvent {
  event.Event(
    id: id,
    occurred_at: occurred_at,
    source: source,
    body: body,
    metadata: metadata.empty(),
  )
}
