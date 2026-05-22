import automata/internal/calendar
import automata/rrule/validator
import automata/schedule/ast.{type DateTime}
import gleam/option.{type Option, None, Some}

pub type NormalizeError {
  InvalidAnchor(DateTime)
}

pub type RRulePlan {
  RRulePlan(
    anchor: DateTime,
    frequency: validator.Frequency,
    interval: Int,
    end_condition: validator.EndCondition,
    by_day: Option(List(validator.WeekdaySpecifier)),
    by_month: Option(List(Int)),
    by_month_day: Option(List(Int)),
    by_hour: List(Int),
    by_minute: List(Int),
    seconds: List(Int),
  )
}

pub fn normalize(
  spec spec: validator.ValidRRule,
  anchor anchor: DateTime,
) -> Result(RRulePlan, NormalizeError) {
  case calendar.is_valid_datetime(anchor) {
    False -> Error(InvalidAnchor(anchor))
    True -> {
      let frequency = validator.frequency(spec)
      Ok(RRulePlan(
        anchor: anchor,
        frequency: frequency,
        interval: validator.interval(spec),
        end_condition: validator.end_condition(spec),
        by_day: default_by_day(spec, anchor),
        by_month: default_by_month(spec, anchor),
        by_month_day: default_by_month_day(spec, anchor),
        by_hour: case validator.by_hour(spec) {
          Some(values) -> values
          None -> default_by_hour(frequency, anchor)
        },
        by_minute: case validator.by_minute(spec) {
          Some(values) -> values
          None -> default_by_minute(frequency, anchor)
        },
        seconds: default_seconds(frequency, anchor),
      ))
    }
  }
}

// RFC 5545 §3.3.10: when the BY* part for a smaller unit than the
// frequency is omitted, the rule expands to cover the full natural range.
// Concretely:
//   - FREQ=SECONDLY without BYSECOND → every second in the minute
//   - FREQ=MINUTELY without BYMINUTE → every minute in the hour
//   - FREQ=HOURLY without BYHOUR → every hour in the day
// Without these defaults the iterator collapses sub-daily frequencies to
// the anchor's single hour-of-day / minute-of-hour / second-of-minute and
// the result is one occurrence per day instead of per hour/minute/second.

fn default_by_hour(
  frequency: validator.Frequency,
  anchor: DateTime,
) -> List(Int) {
  case frequency {
    validator.Secondly | validator.Minutely | validator.Hourly ->
      range_inclusive(0, 23)
    _ -> [anchor.time.hour]
  }
}

fn default_by_minute(
  frequency: validator.Frequency,
  anchor: DateTime,
) -> List(Int) {
  case frequency {
    validator.Secondly | validator.Minutely -> range_inclusive(0, 59)
    _ -> [anchor.time.minute]
  }
}

fn default_seconds(
  frequency: validator.Frequency,
  anchor: DateTime,
) -> List(Int) {
  case frequency {
    validator.Secondly -> range_inclusive(0, 59)
    _ -> [anchor.time.second]
  }
}

fn range_inclusive(from: Int, to: Int) -> List(Int) {
  range_loop(from, to, [])
}

fn range_loop(current: Int, to: Int, acc: List(Int)) -> List(Int) {
  case current > to {
    True -> reverse_list(acc)
    False -> range_loop(current + 1, to, [current, ..acc])
  }
}

fn reverse_list(xs: List(a)) -> List(a) {
  reverse_loop(xs, [])
}

fn reverse_loop(xs: List(a), acc: List(a)) -> List(a) {
  case xs {
    [] -> acc
    [x, ..rest] -> reverse_loop(rest, [x, ..acc])
  }
}

fn default_by_day(
  spec: validator.ValidRRule,
  anchor: DateTime,
) -> Option(List(validator.WeekdaySpecifier)) {
  case validator.by_day(spec) {
    Some(values) -> Some(values)
    None ->
      case validator.frequency(spec) {
        validator.Weekly ->
          Some([validator.EveryWeekday(calendar.weekday(anchor))])
        _ -> None
      }
  }
}

fn default_by_month(
  spec: validator.ValidRRule,
  anchor: DateTime,
) -> Option(List(Int)) {
  case validator.by_month(spec) {
    Some(values) -> Some(values)
    None ->
      case validator.frequency(spec) {
        validator.Yearly ->
          case validator.by_day(spec), validator.by_month_day(spec) {
            None, None -> Some([anchor.date.month])
            _, _ -> None
          }
        _ -> None
      }
  }
}

fn default_by_month_day(
  spec: validator.ValidRRule,
  anchor: DateTime,
) -> Option(List(Int)) {
  case validator.by_month_day(spec) {
    Some(values) -> Some(values)
    None ->
      case validator.by_day(spec) {
        Some(_) -> None
        None ->
          case validator.frequency(spec) {
            validator.Monthly -> Some([anchor.date.day])
            validator.Yearly -> Some([anchor.date.day])
            _ -> None
          }
      }
  }
}
