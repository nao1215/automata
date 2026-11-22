import automata/rrule/validator
import automata/schedule/ast.{type Date, type DateTime, type Weekday}
import gleam/option.{type Option, None, Some}

/// Mutable-style RRULE builder. `opaque` so the only way to populate
/// fields is the `with_*` API and the only way to extract a validated
/// value is `build/1`.
pub opaque type Builder {
  Builder(
    frequency: validator.Frequency,
    interval: Int,
    end_condition: validator.EndCondition,
    by_day: Option(List(validator.WeekdaySpecifier)),
    by_month: Option(List(Int)),
    by_month_day: Option(List(Int)),
    by_hour: Option(List(Int)),
    by_minute: Option(List(Int)),
  )
}

pub fn builder(frequency frequency: validator.Frequency) -> Builder {
  Builder(
    frequency: frequency,
    interval: 1,
    end_condition: validator.Forever,
    by_day: None,
    by_month: None,
    by_month_day: None,
    by_hour: None,
    by_minute: None,
  )
}

pub fn weekday(day day: Weekday) -> validator.WeekdaySpecifier {
  validator.EveryWeekday(day)
}

pub fn nth_weekday(
  ordinal ordinal: Int,
  day day: Weekday,
) -> validator.WeekdaySpecifier {
  validator.NthWeekday(ordinal, day)
}

pub fn with_interval(builder: Builder, interval: Int) -> Builder {
  Builder(..builder, interval:)
}

pub fn with_count(builder: Builder, count: Int) -> Builder {
  Builder(..builder, end_condition: validator.Count(count))
}

pub fn with_until_date(builder: Builder, until: Date) -> Builder {
  Builder(..builder, end_condition: validator.Until(validator.UntilDate(until)))
}

pub fn with_until_datetime(builder: Builder, until: DateTime) -> Builder {
  Builder(
    ..builder,
    end_condition: validator.Until(validator.UntilDateTime(until)),
  )
}

pub fn without_end_condition(builder: Builder) -> Builder {
  Builder(..builder, end_condition: validator.Forever)
}

pub fn with_by_day(
  builder: Builder,
  values: List(validator.WeekdaySpecifier),
) -> Builder {
  Builder(..builder, by_day: Some(values))
}

pub fn with_by_month(builder: Builder, values: List(Int)) -> Builder {
  Builder(..builder, by_month: Some(values))
}

pub fn with_by_month_day(builder: Builder, values: List(Int)) -> Builder {
  Builder(..builder, by_month_day: Some(values))
}

pub fn with_by_hour(builder: Builder, values: List(Int)) -> Builder {
  Builder(..builder, by_hour: Some(values))
}

pub fn with_by_minute(builder: Builder, values: List(Int)) -> Builder {
  Builder(..builder, by_minute: Some(values))
}

pub fn build(
  builder builder: Builder,
) -> Result(validator.ValidRRule, validator.ValidationError) {
  validator.from_parts(
    frequency: builder.frequency,
    interval: builder.interval,
    end_condition: builder.end_condition,
    by_day: builder.by_day,
    by_month: builder.by_month,
    by_month_day: builder.by_month_day,
    by_hour: builder.by_hour,
    by_minute: builder.by_minute,
  )
}
