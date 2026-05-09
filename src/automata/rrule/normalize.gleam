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
    second: Int,
  )
}

pub fn normalize(
  spec spec: validator.ValidRRule,
  anchor anchor: DateTime,
) -> Result(RRulePlan, NormalizeError) {
  case calendar.is_valid_datetime(anchor) {
    False -> Error(InvalidAnchor(anchor))
    True ->
      Ok(RRulePlan(
        anchor: anchor,
        frequency: spec.frequency,
        interval: spec.interval,
        end_condition: spec.end_condition,
        by_day: default_by_day(spec, anchor),
        by_month: default_by_month(spec, anchor),
        by_month_day: default_by_month_day(spec, anchor),
        by_hour: case spec.by_hour {
          Some(values) -> values
          None -> [anchor.time.hour]
        },
        by_minute: case spec.by_minute {
          Some(values) -> values
          None -> [anchor.time.minute]
        },
        second: anchor.time.second,
      ))
  }
}

fn default_by_day(
  spec: validator.ValidRRule,
  anchor: DateTime,
) -> Option(List(validator.WeekdaySpecifier)) {
  case spec.by_day {
    Some(values) -> Some(values)
    None ->
      case spec.frequency {
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
  case spec.by_month {
    Some(values) -> Some(values)
    None ->
      case spec.frequency {
        validator.Yearly ->
          case spec.by_day, spec.by_month_day {
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
  case spec.by_month_day {
    Some(values) -> Some(values)
    None ->
      case spec.by_day {
        Some(_) -> None
        None ->
          case spec.frequency {
            validator.Monthly -> Some([anchor.date.day])
            validator.Yearly -> Some([anchor.date.day])
            _ -> None
          }
      }
  }
}
