import automata/cron/iterator
import automata/cron/normalize.{type CronPlan}
import automata/schedule/ast.{type DateTime, Exclusive} as schedule_ast
import gleam/option.{type Option, None, Some}

pub fn next_after(
  plan plan: CronPlan,
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
