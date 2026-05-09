import automata/schedule
import automata/schedule/ast.{type ValidDateTime, Exclusive}
import automata/schedule/iterator
import gleam/option.{type Option, None, Some}

pub fn next_after(
  schedule schedule: schedule.Schedule,
  after after: ValidDateTime,
) -> Option(ValidDateTime) {
  case iterator.step(iterator.after(schedule, boundary: Exclusive(after))) {
    schedule.Yield(at:, next: _) -> Some(at)
    schedule.Done -> None
  }
}
