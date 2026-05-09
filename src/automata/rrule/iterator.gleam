import automata/internal/calendar
import automata/rrule/evaluator
import automata/rrule/normalize.{type RRulePlan}
import automata/rrule/validator
import automata/schedule/ast.{
  type Boundary, type DateTime, type ValidDateTime, Exclusive, Inclusive,
} as schedule_ast
import gleam/option.{None, Some}

/// RRULE iterator state. `opaque` because the cursor and `yielded`
/// counter must stay synchronised with the embedded plan; an
/// externally-constructed iterator could break COUNT enforcement.
pub opaque type RRuleIterator {
  RRuleIterator(plan: RRulePlan, cursor: DateTime, yielded: Int)
}

pub type Step {
  Yield(at: ValidDateTime, next: RRuleIterator)
  Done
}

pub fn after(plan plan: RRulePlan, boundary boundary: Boundary) -> RRuleIterator {
  let cursor = start_cursor(plan, boundary)
  RRuleIterator(
    plan: plan,
    cursor: cursor,
    yielded: evaluator.yielded_before(plan, cursor: cursor),
  )
}

pub fn step(iterator: RRuleIterator) -> Step {
  case iterator.plan.end_condition {
    validator.Count(limit) ->
      case iterator.yielded >= limit {
        True -> Done
        False -> yield_next(iterator)
      }
    _ -> yield_next(iterator)
  }
}

fn yield_next(iterator: RRuleIterator) -> Step {
  case evaluator.next_occurrence(iterator.plan, iterator.cursor, 0) {
    Some(at) ->
      Yield(
        at: schedule_ast.unsafe_assume_valid(at),
        next: RRuleIterator(
          plan: iterator.plan,
          cursor: calendar.add_seconds(at, 1),
          yielded: iterator.yielded + 1,
        ),
      )
    None -> Done
  }
}

fn start_cursor(plan: RRulePlan, boundary: Boundary) -> DateTime {
  case boundary {
    Inclusive(valid) -> {
      let datetime = schedule_ast.valid_datetime_value(valid)
      case calendar.less_than(datetime, plan.anchor) {
        True -> plan.anchor
        False -> datetime
      }
    }
    Exclusive(valid) -> {
      let datetime = schedule_ast.valid_datetime_value(valid)
      case calendar.less_than(datetime, plan.anchor) {
        True -> plan.anchor
        False -> calendar.add_seconds(datetime, 1)
      }
    }
  }
}
