import automata/cron/iterator
import automata/cron/normalize.{type CronPlan}
import automata/schedule/ast.{type DateTime, Exclusive}
import gleam/option.{type Option, None, Some}

pub fn next_after(
  plan plan: CronPlan,
  after after: DateTime,
) -> Option(DateTime) {
  case iterator.step(iterator.after(plan, boundary: Exclusive(after))) {
    iterator.Yield(at:, next: _) -> Some(at)
    iterator.Done -> None
  }
}
