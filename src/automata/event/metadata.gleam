import gleam/dict.{type Dict}
import gleam/option.{type Option, None, Some}

/// Free-form attribute key/value pairs attached to an event.
pub type Attributes =
  Dict(String, String)

/// Tracing and correlation metadata shared by every event.
///
/// `correlation_id` groups events that belong to the same business
/// transaction. `causation_id` points to the immediate parent event's id.
/// `trace_id` is reserved for bridging with W3C TraceContext / OpenTelemetry.
/// `attributes` carries free-form string-keyed labels for routing and
/// observability.
pub type Metadata {
  Metadata(
    correlation_id: Option(String),
    causation_id: Option(String),
    trace_id: Option(String),
    attributes: Attributes,
  )
}

/// Empty metadata with no ids and no attributes.
pub fn empty() -> Metadata {
  Metadata(
    correlation_id: None,
    causation_id: None,
    trace_id: None,
    attributes: dict.new(),
  )
}

/// Tag this metadata with the correlation id that groups events
/// belonging to the same business transaction.
pub fn with_correlation_id(
  metadata metadata: Metadata,
  id id: String,
) -> Metadata {
  Metadata(..metadata, correlation_id: Some(id))
}

/// Set the causation id pointing at the immediate parent event.
pub fn with_causation_id(metadata metadata: Metadata, id id: String) -> Metadata {
  Metadata(..metadata, causation_id: Some(id))
}

/// Set the W3C/OpenTelemetry-style trace id.
pub fn with_trace_id(metadata metadata: Metadata, id id: String) -> Metadata {
  Metadata(..metadata, trace_id: Some(id))
}

/// Insert (or overwrite) a free-form attribute pair.
pub fn with_attribute(
  metadata metadata: Metadata,
  key key: String,
  value value: String,
) -> Metadata {
  Metadata(..metadata, attributes: dict.insert(metadata.attributes, key, value))
}

/// Look up an attribute by key. Returns `None` when no value is set.
pub fn attribute(metadata metadata: Metadata, key key: String) -> Option(String) {
  case dict.get(metadata.attributes, key) {
    Ok(value) -> Some(value)
    Error(_) -> None
  }
}

/// `True` when `key` is present in the attribute map (regardless of
/// its value).
pub fn has_attribute(metadata metadata: Metadata, key key: String) -> Bool {
  dict.has_key(metadata.attributes, key)
}

/// Return the configured `correlation_id`, if any.
///
/// Symmetric with `with_correlation_id/2` so callers can read and write
/// without reaching into the `Metadata` record's public fields directly.
pub fn correlation_id(metadata metadata: Metadata) -> Option(String) {
  metadata.correlation_id
}

/// Return the configured `causation_id`, if any.
pub fn causation_id(metadata metadata: Metadata) -> Option(String) {
  metadata.causation_id
}

/// Return the configured `trace_id`, if any.
pub fn trace_id(metadata metadata: Metadata) -> Option(String) {
  metadata.trace_id
}

/// Return the full attribute map.
pub fn attributes(metadata metadata: Metadata) -> Attributes {
  metadata.attributes
}
