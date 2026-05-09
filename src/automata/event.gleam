import automata/event/metadata.{type Metadata}
import automata/event/source.{type Source}
import automata/schedule/ast.{type DateTime}
import gleam/option.{Some}

/// An immutable record describing "something happened".
///
/// `body` is a type parameter so callers can pipeline typed events
/// (`Event(MyDomainBody)`) while ecosystem-wide layers can use the
/// `BuiltinEvent` alias backed by `automata/event/builtin/body.EventBody`.
pub type Event(body) {
  Event(
    id: String,
    occurred_at: DateTime,
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
  occurred_at occurred_at: DateTime,
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
/// Copies `correlation_id` and `trace_id` and sets `causation_id` to
/// `parent.id`. Use this when one event triggers another so the chain
/// of custody is preserved without manual bookkeeping.
pub fn continue_from(
  parent parent: Event(parent_body),
  id id: String,
  occurred_at occurred_at: DateTime,
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
