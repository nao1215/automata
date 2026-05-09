import automata/event.{type Event}
import automata/event/source.{type SourceKind}
import gleam/option.{None, Some}

/// Body-agnostic predicates and routing helpers.
///
/// For body-shape predicates, see `automata/event/builtin/match`.
/// Native Gleam `case` is the preferred mechanism for matching event
/// bodies; this module only covers source/metadata level routing.
pub fn has_source_kind(event event: Event(body), kind kind: SourceKind) -> Bool {
  event.source.kind == kind
}

pub fn has_correlation_id(event event: Event(body)) -> Bool {
  case event.metadata.correlation_id {
    Some(_) -> True
    None -> False
  }
}

pub fn has_causation_id(event event: Event(body)) -> Bool {
  case event.metadata.causation_id {
    Some(_) -> True
    None -> False
  }
}

pub fn has_trace_id(event event: Event(body)) -> Bool {
  case event.metadata.trace_id {
    Some(_) -> True
    None -> False
  }
}
