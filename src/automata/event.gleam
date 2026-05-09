import automata/event/metadata.{type Metadata}
import automata/event/source.{type Source}
import automata/schedule/ast.{type ValidDateTime}
import gleam/option.{Some}

/// An immutable record describing "something happened".
///
/// `body` is a type parameter so callers can pipeline typed events
/// (`Event(MyDomainBody)`) while ecosystem-wide layers can use the
/// `BuiltinEvent` alias backed by `automata/event/builtin/body.EventBody`.
pub type Event(body) {
  Event(
    id: String,
    occurred_at: ValidDateTime,
    source: Source,
    body: body,
    metadata: Metadata,
  )
}

/// Construct an event with empty metadata.
///
/// The caller supplies `id`. The library does not generate identifiers;
/// pick a strategy (UUIDv7 / ULID / monotonic counter) that fits your
/// transport.
pub fn new(
  id id: String,
  occurred_at occurred_at: ValidDateTime,
  source source: Source,
  body body: body,
) -> Event(body) {
  Event(
    id: id,
    occurred_at: occurred_at,
    source: source,
    body: body,
    metadata: metadata.empty(),
  )
}

pub fn with_metadata(
  event event: Event(body),
  metadata meta: Metadata,
) -> Event(body) {
  Event(..event, metadata: meta)
}

pub fn with_correlation_id(
  event event: Event(body),
  id id: String,
) -> Event(body) {
  Event(..event, metadata: metadata.with_correlation_id(event.metadata, id))
}

pub fn with_causation_id(event event: Event(body), id id: String) -> Event(body) {
  Event(..event, metadata: metadata.with_causation_id(event.metadata, id))
}

pub fn with_trace_id(event event: Event(body), id id: String) -> Event(body) {
  Event(..event, metadata: metadata.with_trace_id(event.metadata, id))
}

pub fn with_attribute(
  event event: Event(body),
  key key: String,
  value value: String,
) -> Event(body) {
  Event(..event, metadata: metadata.with_attribute(event.metadata, key, value))
}

/// Derive a new event whose metadata chains from `parent`.
///
/// Inherits the parent's `correlation_id`, `trace_id`, and the full
/// `attributes` dict, and sets `causation_id` to `parent.id`. Use this
/// when one event triggers another so the chain of custody — and any
/// attributes that describe the chain itself (tenant, user, request id,
/// etc.) — is preserved without manual bookkeeping. Reach for
/// `event.new` plus `with_metadata(metadata.empty())` when the child
/// should start with a fresh attribute set; the inherited identifiers
/// are the same value the parent had, so the child can always rebuild
/// them explicitly when needed.
pub fn continue_from(
  parent parent: Event(parent_body),
  id id: String,
  occurred_at occurred_at: ValidDateTime,
  source source: Source,
  body body: body,
) -> Event(body) {
  let parent_meta = parent.metadata
  let chained =
    metadata.Metadata(
      correlation_id: parent_meta.correlation_id,
      causation_id: Some(parent.id),
      trace_id: parent_meta.trace_id,
      attributes: parent_meta.attributes,
    )
  Event(
    id: id,
    occurred_at: occurred_at,
    source: source,
    body: body,
    metadata: chained,
  )
}
