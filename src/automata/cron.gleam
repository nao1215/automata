import automata/cron/ast as cron_ast
import automata/cron/builder as cron_builder
import automata/cron/evaluator as cron_evaluator
import automata/cron/iterator as cron_iterator
import automata/cron/next as cron_next
import automata/cron/normalize as cron_normalize
import automata/cron/parser
import automata/cron/validator
import automata/schedule/ast.{type Boundary, type DateTime}
import gleam/option.{type Option}

pub fn parse(input input: String) -> Result(cron_ast.RawCron, parser.ParseError) {
  parser.parse(input: input)
}

pub fn validate(
  raw raw: cron_ast.RawCron,
) -> Result(validator.ValidCron, validator.ValidationError) {
  validator.validate(raw)
}

pub fn normalize(spec spec: validator.ValidCron) -> cron_normalize.CronPlan {
  cron_normalize.normalize(spec)
}

pub fn to_string(spec spec: validator.ValidCron) -> String {
  validator.to_string(spec)
}

pub fn matches(spec spec: validator.ValidCron, at at: DateTime) -> Bool {
  spec
  |> cron_normalize.normalize
  |> cron_evaluator.matches(at: at)
}

pub fn iterator_after(
  spec spec: validator.ValidCron,
  boundary boundary: Boundary,
) -> cron_iterator.CronIterator {
  spec
  |> cron_normalize.normalize
  |> cron_iterator.after(boundary: boundary)
}

pub fn next_after(
  spec spec: validator.ValidCron,
  after after: DateTime,
) -> Option(DateTime) {
  spec
  |> cron_normalize.normalize
  |> cron_next.next_after(after: after)
}

pub fn builder() -> cron_builder.Builder {
  cron_builder.builder()
}

pub fn any() -> validator.Selector {
  cron_builder.any()
}

pub fn at(value value: Int) -> validator.Selector {
  cron_builder.at(value: value)
}

pub fn between(from start: Int, to end: Int) -> validator.Selector {
  cron_builder.between(from: start, to: end)
}

pub fn every(step step: Int) -> validator.Selector {
  cron_builder.every(step: step)
}

pub fn every_from(start start: Int, step step: Int) -> validator.Selector {
  cron_builder.every_from(start: start, step: step)
}

pub fn every_between(
  from start: Int,
  to end: Int,
  step step: Int,
) -> validator.Selector {
  cron_builder.every_between(from: start, to: end, step: step)
}

pub fn one_of(items items: List(validator.Item)) -> validator.Selector {
  cron_builder.one_of(items: items)
}

pub fn with_minute(
  builder: cron_builder.Builder,
  minute: validator.Selector,
) -> cron_builder.Builder {
  cron_builder.with_minute(builder, minute)
}

pub fn with_hour(
  builder: cron_builder.Builder,
  hour: validator.Selector,
) -> cron_builder.Builder {
  cron_builder.with_hour(builder, hour)
}

pub fn with_day_of_month(
  builder: cron_builder.Builder,
  day_of_month: validator.Selector,
) -> cron_builder.Builder {
  cron_builder.with_day_of_month(builder, day_of_month)
}

pub fn with_month(
  builder: cron_builder.Builder,
  month: validator.Selector,
) -> cron_builder.Builder {
  cron_builder.with_month(builder, month)
}

pub fn with_day_of_week(
  builder: cron_builder.Builder,
  day_of_week: validator.Selector,
) -> cron_builder.Builder {
  cron_builder.with_day_of_week(builder, day_of_week)
}

pub fn build(
  builder builder: cron_builder.Builder,
) -> Result(validator.ValidCron, validator.ValidationError) {
  cron_builder.build(builder)
}
