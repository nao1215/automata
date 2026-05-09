import automata/event.{type Event}
import automata/event/metadata
import automata/event/source.{type Source, type SourceKind}
import automata/fsevent/ast as fs_ast
import automata/fsevent/event.{type WatchEvent} as fs_event
import automata/fsevent/op as fs_op
import automata/schedule/ast.{type ValidDateTime}
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{type Option}
import gleam/string

/// Built-in body sum used by the `BuiltinEvent` alias.
///
/// Closed for known kinds plus a `Custom` escape hatch. The
/// `FileSystem` variant carries an `automata/fsevent` `WatchEvent`
/// so the full set of ops (`Create`, `Write`, `Remove`, `Rename`,
/// `Chmod`) and the rename's old path can travel together with the
/// event without callers having to invent ad-hoc body kinds.
pub type EventBody {
  Scheduled(
    plan_id: String,
    fired_at: ValidDateTime,
    schedule_kind: ScheduleKind,
  )
  FileSystem(event: WatchEvent)
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
/// `FileSystem(_)` becomes `"file_system:create"` for a single-op
/// event, `"file_system:create+write"` when several ops are present
/// (lowercase ops joined by `+` in canonical order). `Custom("kind", _)`
/// becomes `"custom:kind"`.
pub fn kind(body: EventBody) -> String {
  case body {
    Scheduled(_, _, _) -> "scheduled"
    FileSystem(event) -> "file_system:" <> file_system_op_label(event)
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

/// Wrap an `automata/fsevent` `WatchEvent` in the canonical body.
pub fn file_system(event event: WatchEvent) -> EventBody {
  FileSystem(event: event)
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
/// `Scheduled` always pairs with `ScheduleSource`, `FileSystem(_)` with
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

/// Build a `Scheduled` `BuiltinEvent` from a single `(id, plan_id, at,
/// schedule_kind)` tuple.
///
/// Equivalent to:
///
/// ```gleam
/// new(
///   id: id,
///   occurred_at: at,
///   source_id: plan_id,
///   body: scheduled(plan_id: plan_id, fired_at: at, schedule_kind: kind),
/// )
/// ```
///
/// In the common case `source_id` equals `plan_id` and `occurred_at`
/// equals `fired_at`, so the verbose form forces the caller to type the
/// same value twice. This smart constructor halves the surface and
/// removes the "are these intentionally different?" cognitive load.
/// Reach for `new/4` only when the two values genuinely differ
/// (delayed dispatch recorded after the fact, fan-out under a
/// different `source_id`, etc.).
pub fn scheduled_event(
  id id: String,
  plan_id plan_id: String,
  at at: ValidDateTime,
  schedule_kind schedule_kind: ScheduleKind,
) -> BuiltinEvent {
  new(
    id: id,
    occurred_at: at,
    source_id: plan_id,
    body: scheduled(
      plan_id: plan_id,
      fired_at: at,
      schedule_kind: schedule_kind,
    ),
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
    FileSystem(_) -> source.FileSystemSource
    Manual(_, _) -> source.ManualSource
    Custom(name, _) -> source.CustomSource(name)
  }
}

fn file_system_op_label(event: WatchEvent) -> String {
  event
  |> fs_event.event_ops
  |> fs_op.to_list
  |> list.map(op_label)
  |> string.join("+")
}

fn op_label(op: fs_ast.Op) -> String {
  fs_op.op_to_string(op)
  |> string.lowercase
}
