import automata/cron/validator

/// Mutable-style cron builder. `opaque` so the only way to populate
/// fields is the `with_*` API and the only way to extract a validated
/// value is `build/1`.
pub opaque type Builder {
  Builder(
    minute: validator.Selector,
    hour: validator.Selector,
    day_of_month: validator.Selector,
    month: validator.Selector,
    day_of_week: validator.Selector,
  )
}

pub fn builder() -> Builder {
  Builder(
    minute: validator.Any,
    hour: validator.Any,
    day_of_month: validator.Any,
    month: validator.Any,
    day_of_week: validator.Any,
  )
}

pub fn any() -> validator.Selector {
  validator.Any
}

pub fn at(value value: Int) -> validator.Selector {
  validator.Values([validator.Exact(value)])
}

pub fn between(from start: Int, to end: Int) -> validator.Selector {
  validator.Values([validator.Range(start, end)])
}

pub fn every(step step: Int) -> validator.Selector {
  validator.Values([validator.Step(validator.StepAny, step)])
}

pub fn every_from(start start: Int, step step: Int) -> validator.Selector {
  validator.Values([validator.Step(validator.StepExact(start), step)])
}

pub fn every_between(
  from start: Int,
  to end: Int,
  step step: Int,
) -> validator.Selector {
  validator.Values([validator.Step(validator.StepRange(start, end), step)])
}

pub fn one_of(items items: List(validator.Item)) -> validator.Selector {
  validator.Values(items)
}

pub fn with_minute(builder: Builder, minute: validator.Selector) -> Builder {
  Builder(..builder, minute:)
}

pub fn with_hour(builder: Builder, hour: validator.Selector) -> Builder {
  Builder(..builder, hour:)
}

pub fn with_day_of_month(
  builder: Builder,
  day_of_month: validator.Selector,
) -> Builder {
  Builder(..builder, day_of_month:)
}

pub fn with_month(builder: Builder, month: validator.Selector) -> Builder {
  Builder(..builder, month:)
}

pub fn with_day_of_week(
  builder: Builder,
  day_of_week: validator.Selector,
) -> Builder {
  Builder(..builder, day_of_week:)
}

pub fn build(
  builder builder: Builder,
) -> Result(validator.ValidCron, validator.ValidationError) {
  validator.from_selectors(
    minute: builder.minute,
    hour: builder.hour,
    day_of_month: builder.day_of_month,
    month: builder.month,
    day_of_week: builder.day_of_week,
  )
}
