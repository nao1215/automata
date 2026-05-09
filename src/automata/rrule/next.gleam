import automata/rrule/iterator
import automata/rrule/normalize.{type RRulePlan}
import automata/schedule/ast.{type DateTime, Exclusive} as schedule_ast
import gleam/option.{type Option, None, Some}

pub fn next_after(
  plan plan: RRulePlan,
  after after: DateTime,
) -> Option(DateTime) {
  case
    iterator.step(iterator.after(
      plan,
      boundary: Exclusive(schedule_ast.unsafe_assume_valid(value: after)),
    ))
  {
    iterator.Yield(at:, next: _) -> Some(schedule_ast.valid_datetime_value(at))
    iterator.Done -> None
  }
}
