import automata/rrule/iterator
import automata/rrule/normalize.{type RRulePlan}
import automata/schedule/ast.{type DateTime, Exclusive}
import gleam/option.{type Option, None, Some}

pub fn next_after(
  plan plan: RRulePlan,
  after after: DateTime,
) -> Option(DateTime) {
  case iterator.step(iterator.after(plan, boundary: Exclusive(after))) {
    iterator.Yield(at:, next: _) -> Some(at)
    iterator.Done -> None
  }
}
