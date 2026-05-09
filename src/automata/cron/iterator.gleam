import automata/cron/evaluator
import automata/cron/normalize.{type CronPlan, AnyValue, Values}
import automata/internal/calendar
import automata/schedule/ast.{
  type Boundary, type DateTime, type ValidDateTime, DateTime, Exclusive,
  Inclusive, Time,
} as schedule_ast
import gleam/option.{type Option, None, Some}

/// Cron iterator state. `opaque` because the cursor must stay
/// synchronised with the embedded plan; constructing one with an
/// arbitrary cursor would skip occurrences.
pub opaque type CronIterator {
  CronIterator(plan: CronPlan, cursor: DateTime)
}

/// Outcome of one `step` on a `CronIterator`.
///
/// `Yield(at:, next:)` carries the next occurrence and a fresh
/// iterator positioned just after it. `Done` indicates the search
/// could not find a next occurrence within its internal recursion
/// guard (~5,000,000 candidate minute steps, ≈ 9.5 years) or before
/// the maximum representable `DateTime` boundary. UNIX cron is
/// non-terminating, so for `CronPlan`s derived from a validated
/// `ValidCron` the `Done` arm is unreachable in practice and exists
/// purely as a safety net for pathological inputs.
pub type Step {
  Yield(at: ValidDateTime, next: CronIterator)
  Done
}

pub fn after(plan plan: CronPlan, boundary boundary: Boundary) -> CronIterator {
  CronIterator(plan:, cursor: start_cursor(boundary))
}

pub fn step(iterator: CronIterator) -> Step {
  case find_next(iterator.plan, iterator.cursor, 0) {
    Some(at) ->
      Yield(
        at: schedule_ast.unsafe_assume_valid(at),
        next: CronIterator(
          plan: iterator.plan,
          cursor: calendar.add_minutes(at, 1),
        ),
      )
    None -> Done
  }
}

fn start_cursor(boundary: Boundary) -> DateTime {
  case boundary {
    Inclusive(valid) -> {
      let datetime = schedule_ast.valid_datetime_value(valid)
      case datetime.time.second == 0 {
        True -> datetime
        False -> calendar.ceil_to_next_minute(datetime)
      }
    }
    Exclusive(valid) -> {
      let datetime = schedule_ast.valid_datetime_value(valid)
      case datetime.time.second == 0 {
        True -> calendar.add_minutes(datetime, 1)
        False -> calendar.ceil_to_next_minute(datetime)
      }
    }
  }
}

fn find_next(
  plan: CronPlan,
  candidate: DateTime,
  guard: Int,
) -> Option(DateTime) {
  case guard > 5_000_000 {
    True -> None
    False ->
      case evaluator.int_set_contains(plan.month, candidate.date.month) {
        False -> {
          let next_month = roll_to_next_matching_month(plan, candidate)
          find_next(plan, next_month, guard + 1)
        }
        True ->
          case day_matches(plan, candidate) {
            False -> find_next(plan, next_day_start(candidate), guard + 1)
            True ->
              case align_hour(plan, candidate) {
                None -> find_next(plan, next_day_start(candidate), guard + 1)
                Some(aligned_hour) ->
                  case align_minute(plan, aligned_hour) {
                    None ->
                      find_next(plan, next_hour_start(aligned_hour), guard + 1)
                    Some(aligned_minute) ->
                      case evaluator.matches(plan, aligned_minute) {
                        True -> Some(aligned_minute)
                        False ->
                          find_next(
                            plan,
                            calendar.add_minutes(aligned_minute, 1),
                            guard + 1,
                          )
                      }
                  }
              }
          }
      }
  }
}

fn day_matches(plan: CronPlan, candidate: DateTime) -> Bool {
  let dom_match =
    evaluator.int_set_contains(plan.day_of_month, candidate.date.day)
  let dow_match =
    evaluator.int_set_contains(
      plan.day_of_week,
      calendar.day_of_week_number(candidate),
    )

  let dom_any = case plan.day_of_month {
    AnyValue(_, _) -> True
    Values(_) -> False
  }
  let dow_any = case plan.day_of_week {
    AnyValue(_, _) -> True
    Values(_) -> False
  }

  case dom_any, dow_any {
    True, True -> True
    True, False -> dow_match
    False, True -> dom_match
    False, False -> dom_match || dow_match
  }
}

fn align_hour(plan: CronPlan, candidate: DateTime) -> Option(DateTime) {
  case evaluator.next_value_at_or_after(plan.hour, candidate.time.hour) {
    None -> None
    Some(hour) ->
      case hour == candidate.time.hour {
        True ->
          Some(DateTime(
            date: candidate.date,
            time: Time(hour:, minute: candidate.time.minute, second: 0),
          ))
        False ->
          Some(DateTime(
            date: candidate.date,
            time: Time(
              hour:,
              minute: evaluator.first_value(plan.minute),
              second: 0,
            ),
          ))
      }
  }
}

fn align_minute(plan: CronPlan, candidate: DateTime) -> Option(DateTime) {
  case evaluator.next_value_at_or_after(plan.minute, candidate.time.minute) {
    None -> None
    Some(minute) ->
      Some(DateTime(
        date: candidate.date,
        time: Time(hour: candidate.time.hour, minute:, second: 0),
      ))
  }
}

fn next_day_start(candidate: DateTime) -> DateTime {
  calendar.next_day(candidate)
}

fn next_hour_start(candidate: DateTime) -> DateTime {
  let next = calendar.add_minutes(candidate, 60 - candidate.time.minute)
  DateTime(
    date: next.date,
    time: Time(hour: next.time.hour, minute: 0, second: 0),
  )
}

fn roll_to_next_matching_month(plan: CronPlan, candidate: DateTime) -> DateTime {
  let next = calendar.next_month(candidate)

  case evaluator.int_set_contains(plan.month, next.date.month) {
    True -> next
    False -> roll_to_next_matching_month(plan, next)
  }
}
