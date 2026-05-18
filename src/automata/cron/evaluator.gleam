import automata/cron/normalize.{type CronPlan, type IntSet, AnyValue, Values}
import automata/internal/calendar
import automata/schedule/ast.{type DateTime}
import gleam/list
import gleam/option.{type Option, None, Some}

pub fn matches(plan plan: CronPlan, at at: DateTime) -> Bool {
  let minute_match = int_set_contains(plan.minute, at.time.minute)
  let hour_match = int_set_contains(plan.hour, at.time.hour)
  let month_match = int_set_contains(plan.month, at.date.month)
  let day_of_month_match = int_set_contains(plan.day_of_month, at.date.day)
  let day_of_week_match =
    int_set_contains(plan.day_of_week, calendar.day_of_week_number(at))

  // UNIX cron is minute-granular per POSIX — the five fields are minute /
  // hour / day-of-month / month / day-of-week with no second field. Any
  // instant within a matching minute is a firing, regardless of seconds.
  minute_match
  && hour_match
  && month_match
  && matches_day(plan, day_of_month_match, day_of_week_match)
}

pub fn int_set_contains(int_set: IntSet, value: Int) -> Bool {
  case int_set {
    AnyValue(min:, max:) -> value >= min && value <= max
    Values(values) -> list.any(values, fn(item) { item == value })
  }
}

pub fn first_value(int_set: IntSet) -> Int {
  case int_set {
    AnyValue(min:, max: _) -> min
    Values([first, ..]) -> first
    Values([]) -> 0
  }
}

pub fn next_value_at_or_after(int_set: IntSet, current: Int) -> Option(Int) {
  case int_set {
    AnyValue(min:, max:) ->
      case current < min {
        True -> Some(min)
        False ->
          case current > max {
            True -> None
            False -> Some(current)
          }
      }
    Values(values) -> next_list_value(values, current)
  }
}

fn next_list_value(values: List(Int), current: Int) -> Option(Int) {
  case values {
    [] -> None
    [value, ..rest] ->
      case value >= current {
        True -> Some(value)
        False -> next_list_value(rest, current)
      }
  }
}

fn matches_day(
  plan: CronPlan,
  day_of_month_match: Bool,
  day_of_week_match: Bool,
) -> Bool {
  let dom_any = is_any(plan.day_of_month)
  let dow_any = is_any(plan.day_of_week)

  case dom_any, dow_any {
    True, True -> True
    True, False -> day_of_week_match
    False, True -> day_of_month_match
    False, False -> day_of_month_match || day_of_week_match
  }
}

fn is_any(int_set: IntSet) -> Bool {
  case int_set {
    AnyValue(_, _) -> True
    Values(_) -> False
  }
}
