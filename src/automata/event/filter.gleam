import automata/event.{type Event}
import automata/event/metadata
import automata/event/source.{type Source, type SourceKind}
import automata/internal/calendar
import automata/schedule/ast.{type DateTime}
import gleam/list
import gleam/option.{type Option, None, Some}

/// Pure predicate over events with a `body` payload type.
///
/// Filters are values, not callbacks: every constructor returns a
/// `Filter(body)` and combinators (`all_of`, `any_of`, `negate`) work
/// over those values. The opaque shape lets future versions introduce
/// structural inspection (e.g. logging which leaf rejected an event)
/// without a public API change.
pub opaque type Filter(body) {
  Filter(check: fn(Event(body)) -> Bool)
}

pub fn always() -> Filter(body) {
  Filter(fn(_) { True })
}

pub fn never() -> Filter(body) {
  Filter(fn(_) { False })
}

/// Build a filter from an arbitrary predicate.
///
/// The escape hatch for conditions that the built-in constructors do
/// not express. Prefer the typed constructors below when one fits.
pub fn predicate(check check: fn(Event(body)) -> Bool) -> Filter(body) {
  Filter(check)
}

pub fn by_source(source source: Source) -> Filter(body) {
  Filter(fn(event) { event.source == source })
}

pub fn by_source_kind(kind kind: SourceKind) -> Filter(body) {
  Filter(fn(event) { event.source.kind == kind })
}

pub fn by_source_id(id id: String) -> Filter(body) {
  Filter(fn(event) { event.source.id == id })
}

pub fn by_correlation_id(id id: String) -> Filter(body) {
  Filter(fn(event) { event.metadata.correlation_id == Some(id) })
}

pub fn by_causation_id(id id: String) -> Filter(body) {
  Filter(fn(event) { event.metadata.causation_id == Some(id) })
}

pub fn by_trace_id(id id: String) -> Filter(body) {
  Filter(fn(event) { event.metadata.trace_id == Some(id) })
}

pub fn by_attribute(key key: String, value value: String) -> Filter(body) {
  Filter(fn(event) {
    metadata.attribute(metadata: event.metadata, key: key) == Some(value)
  })
}

pub fn has_attribute(key key: String) -> Filter(body) {
  Filter(fn(event) {
    metadata.has_attribute(metadata: event.metadata, key: key)
  })
}

/// Match events whose `occurred_at` falls in `[from, until]` (inclusive).
pub fn occurred_between(
  from from: DateTime,
  until until: DateTime,
) -> Filter(body) {
  Filter(fn(event) {
    calendar.greater_or_equal(event.occurred_at, from)
    && calendar.less_or_equal(event.occurred_at, until)
  })
}

pub fn occurred_after(after after: DateTime) -> Filter(body) {
  Filter(fn(event) { calendar.greater_than(event.occurred_at, after) })
}

pub fn occurred_before(before before: DateTime) -> Filter(body) {
  Filter(fn(event) { calendar.less_than(event.occurred_at, before) })
}

/// Logical AND across all filters. An empty list is `always`.
pub fn all_of(filters filters: List(Filter(body))) -> Filter(body) {
  Filter(fn(event) { list.all(filters, fn(filter) { run(filter, event) }) })
}

/// Logical OR across all filters. An empty list is `never`.
pub fn any_of(filters filters: List(Filter(body))) -> Filter(body) {
  Filter(fn(event) { list.any(filters, fn(filter) { run(filter, event) }) })
}

/// Logical negation. Named `negate` because `not` is a reserved word.
pub fn negate(filter filter: Filter(body)) -> Filter(body) {
  Filter(fn(event) { !run(filter, event) })
}

pub fn matches(filter filter: Filter(body), event event: Event(body)) -> Bool {
  run(filter, event)
}

pub fn keep(
  filter filter: Filter(body),
  events events: List(Event(body)),
) -> List(Event(body)) {
  list.filter(events, fn(event) { run(filter, event) })
}

pub fn reject(
  filter filter: Filter(body),
  events events: List(Event(body)),
) -> List(Event(body)) {
  list.filter(events, fn(event) { !run(filter, event) })
}

/// Lift a body-only predicate into a `Filter(body)`. Useful for
/// constructing body-shape filters in `automata/event/builtin/filter`.
pub fn on_body(check check: fn(body) -> Bool) -> Filter(body) {
  Filter(fn(event) { check(event.body) })
}

/// Lift a body-to-`Option(value)` extractor and a value predicate.
///
/// Returns `False` when the extractor yields `None`. Used by builtin
/// filters that target a specific variant (e.g. `FileModified.path`).
pub fn on_body_option(
  extract extract: fn(body) -> Option(a),
  check check: fn(a) -> Bool,
) -> Filter(body) {
  Filter(fn(event) {
    case extract(event.body) {
      Some(value) -> check(value)
      None -> False
    }
  })
}

fn run(filter: Filter(body), event: Event(body)) -> Bool {
  filter.check(event)
}
