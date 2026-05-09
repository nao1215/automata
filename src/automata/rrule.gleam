import automata/rrule/ast as rule_ast
import automata/rrule/builder as rule_builder
import automata/rrule/evaluator as rule_evaluator
import automata/rrule/iterator as rule_iterator
import automata/rrule/next as rule_next
import automata/rrule/normalize as rule_normalize
import automata/rrule/parser
import automata/rrule/validator
import automata/schedule/ast.{
  type Boundary, type Date, type ValidDateTime, type Weekday,
} as schedule_ast
import gleam/option.{type Option}

pub fn parse(
  input input: String,
) -> Result(rule_ast.RawRRule, parser.ParseError) {
  parser.parse(input: input)
}

pub fn validate(
  raw raw: rule_ast.RawRRule,
) -> Result(validator.ValidRRule, validator.ValidationError) {
  validator.validate(raw)
}

pub fn normalize(
  spec spec: validator.ValidRRule,
  anchor anchor: ValidDateTime,
) -> Result(rule_normalize.RRulePlan, rule_normalize.NormalizeError) {
  rule_normalize.normalize(
    spec,
    anchor: schedule_ast.valid_datetime_value(anchor),
  )
}

pub fn to_string(spec spec: validator.ValidRRule) -> String {
  validator.to_string(spec)
}

pub fn matches(
  spec spec: validator.ValidRRule,
  anchor anchor: ValidDateTime,
  at at: ValidDateTime,
) -> Result(Bool, rule_normalize.NormalizeError) {
  case
    rule_normalize.normalize(
      spec,
      anchor: schedule_ast.valid_datetime_value(anchor),
    )
  {
    Ok(plan) ->
      Ok(rule_evaluator.matches(plan, at: schedule_ast.valid_datetime_value(at)))
    Error(error) -> Error(error)
  }
}

pub fn iterator_after(
  spec spec: validator.ValidRRule,
  anchor anchor: ValidDateTime,
  boundary boundary: Boundary,
) -> Result(rule_iterator.RRuleIterator, rule_normalize.NormalizeError) {
  case
    rule_normalize.normalize(
      spec,
      anchor: schedule_ast.valid_datetime_value(anchor),
    )
  {
    Ok(plan) -> Ok(rule_iterator.after(plan, boundary: boundary))
    Error(error) -> Error(error)
  }
}

pub fn next_after(
  spec spec: validator.ValidRRule,
  anchor anchor: ValidDateTime,
  after after: ValidDateTime,
) -> Result(Option(ValidDateTime), rule_normalize.NormalizeError) {
  case
    rule_normalize.normalize(
      spec,
      anchor: schedule_ast.valid_datetime_value(anchor),
    )
  {
    Ok(plan) ->
      Ok(
        rule_next.next_after(
          plan,
          after: schedule_ast.valid_datetime_value(after),
        )
        |> option.map(schedule_ast.unsafe_assume_valid),
      )
    Error(error) -> Error(error)
  }
}

pub fn builder(frequency frequency: validator.Frequency) -> rule_builder.Builder {
  rule_builder.builder(frequency: frequency)
}

pub fn weekday(day day: Weekday) -> validator.WeekdaySpecifier {
  rule_builder.weekday(day: day)
}

pub fn nth_weekday(
  ordinal ordinal: Int,
  day day: Weekday,
) -> validator.WeekdaySpecifier {
  rule_builder.nth_weekday(ordinal: ordinal, day: day)
}

pub fn with_interval(
  builder: rule_builder.Builder,
  interval: Int,
) -> rule_builder.Builder {
  rule_builder.with_interval(builder, interval)
}

pub fn with_count(
  builder: rule_builder.Builder,
  count: Int,
) -> rule_builder.Builder {
  rule_builder.with_count(builder, count)
}

pub fn with_until_date(
  builder: rule_builder.Builder,
  until: Date,
) -> rule_builder.Builder {
  rule_builder.with_until_date(builder, until)
}

pub fn with_until_datetime(
  builder: rule_builder.Builder,
  until: ValidDateTime,
) -> rule_builder.Builder {
  rule_builder.with_until_datetime(
    builder,
    schedule_ast.valid_datetime_value(until),
  )
}

pub fn without_end_condition(
  builder: rule_builder.Builder,
) -> rule_builder.Builder {
  rule_builder.without_end_condition(builder)
}

pub fn with_by_day(
  builder: rule_builder.Builder,
  values: List(validator.WeekdaySpecifier),
) -> rule_builder.Builder {
  rule_builder.with_by_day(builder, values)
}

pub fn with_by_month(
  builder: rule_builder.Builder,
  values: List(Int),
) -> rule_builder.Builder {
  rule_builder.with_by_month(builder, values)
}

pub fn with_by_month_day(
  builder: rule_builder.Builder,
  values: List(Int),
) -> rule_builder.Builder {
  rule_builder.with_by_month_day(builder, values)
}

pub fn with_by_hour(
  builder: rule_builder.Builder,
  values: List(Int),
) -> rule_builder.Builder {
  rule_builder.with_by_hour(builder, values)
}

pub fn with_by_minute(
  builder: rule_builder.Builder,
  values: List(Int),
) -> rule_builder.Builder {
  rule_builder.with_by_minute(builder, values)
}

pub fn build(
  builder builder: rule_builder.Builder,
) -> Result(validator.ValidRRule, validator.ValidationError) {
  rule_builder.build(builder)
}
