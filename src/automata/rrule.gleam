//// RFC 5545 RRULE stack for the supported subset (FREQ, INTERVAL,
//// COUNT, UNTIL, BYDAY, BYMONTH, BYMONTHDAY, BYHOUR, BYMINUTE).
//// Anchored at a `ValidDateTime`, an RRULE expands into a concrete
//// `RRulePlan` that the matcher and iterator consume. This module is
//// the user-facing facade; the typed phases live in the
//// `automata/rrule/{ast,parser,validator,normalize,evaluator,iterator,
//// next,builder}` submodules.

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

/// Parse an RFC 5545 RRULE string into a `RawRRule` AST. Returns a
/// `ParseError` for syntactic mistakes; semantic validation (FREQ in
/// range, UNTIL/COUNT mutual exclusion, etc.) happens in `validate/1`.
pub fn parse(
  input input: String,
) -> Result(rule_ast.RawRRule, parser.ParseError) {
  parser.parse(input: input)
}

/// Validate a `RawRRule` and return a `ValidRRule` (opaque) covering
/// the supported subset. Anchorless: anchor-dependent expansion is
/// done by `normalize/2`.
pub fn validate(
  raw raw: rule_ast.RawRRule,
) -> Result(validator.ValidRRule, validator.ValidationError) {
  validator.validate(raw)
}

/// Expand a `ValidRRule` against an anchor `ValidDateTime`, producing
/// an `RRulePlan` ready for matching/iteration. Reuse the plan across
/// calls if you evaluate the same spec/anchor pair many times — see
/// the `*_plan` variants.
pub fn normalize(
  spec spec: validator.ValidRRule,
  anchor anchor: ValidDateTime,
) -> Result(rule_normalize.RRulePlan, rule_normalize.NormalizeError) {
  rule_normalize.normalize(
    spec,
    anchor: schedule_ast.valid_datetime_value(anchor),
  )
}

/// Render a `ValidRRule` back to its canonical RRULE string form.
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
    Ok(plan) -> Ok(matches_plan(plan: plan, at: at))
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
    Ok(plan) -> Ok(iterator_after_plan(plan: plan, boundary: boundary))
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
    Ok(plan) -> Ok(next_after_plan(plan: plan, after: after))
    Error(error) -> Error(error)
  }
}

/// Plan-reuse counterpart to `matches/3`. Takes an already-normalised
/// `RRulePlan` so callers that evaluate the same spec/anchor pair many
/// times can pay the normalisation cost once.
pub fn matches_plan(
  plan plan: rule_normalize.RRulePlan,
  at at: ValidDateTime,
) -> Bool {
  rule_evaluator.matches(plan, at: schedule_ast.valid_datetime_value(at))
}

/// Plan-reuse counterpart to `iterator_after/3`.
pub fn iterator_after_plan(
  plan plan: rule_normalize.RRulePlan,
  boundary boundary: Boundary,
) -> rule_iterator.RRuleIterator {
  rule_iterator.after(plan, boundary: boundary)
}

/// Plan-reuse counterpart to `next_after/3`.
pub fn next_after_plan(
  plan plan: rule_normalize.RRulePlan,
  after after: ValidDateTime,
) -> Option(ValidDateTime) {
  rule_next.next_after(plan, after: schedule_ast.valid_datetime_value(after))
  |> option.map(schedule_ast.unsafe_assume_valid)
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
