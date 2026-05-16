//// UNIX 5-field cron stack: parse a cron string, validate it,
//// normalise it into a fast-evaluation `CronPlan`, and ask whether a
//// given `ValidDateTime` matches or what the next match is. This
//// module is the user-facing facade; the typed phases live in the
//// `automata/cron/{ast,parser,validator,normalize,evaluator,iterator,
//// next,builder}` submodules.

import automata/cron/ast as cron_ast
import automata/cron/builder as cron_builder
import automata/cron/evaluator as cron_evaluator
import automata/cron/iterator as cron_iterator
import automata/cron/next as cron_next
import automata/cron/normalize as cron_normalize
import automata/cron/parser
import automata/cron/validator
import automata/schedule/ast.{type Boundary, type ValidDateTime} as schedule_ast
import gleam/option.{type Option}
import gleam/result

/// Wrapper error type for `next_after_string` and other facade helpers
/// that combine the `parse` / `validate` phases into a single call.
/// Power users that need to distinguish syntactic from semantic problems
/// can keep using `parse` / `validate` directly and receive the
/// underlying `parser.ParseError` / `validator.ValidationError`.
pub type CronError {
  ParseError(parser.ParseError)
  ValidationError(validator.ValidationError)
}

/// Parse a UNIX 5-field cron expression (`minute hour day-of-month
/// month day-of-week`) into a `RawCron` AST. Returns a `ParseError`
/// for syntactic problems such as wrong field count or empty fields.
/// Range and alias validation is done separately by `validate/1`.
pub fn parse(input input: String) -> Result(cron_ast.RawCron, parser.ParseError) {
  parser.parse(input: input)
}

/// Validate a `RawCron` and return a `ValidCron` (opaque) when every
/// field is in range and consistent. The returned value is the only
/// shape the rest of the pipeline accepts.
pub fn validate(
  raw raw: cron_ast.RawCron,
) -> Result(validator.ValidCron, validator.ValidationError) {
  validator.validate(raw)
}

/// Pre-compute the lookup tables `evaluator`/`iterator`/`next` need.
/// Reuse the resulting `CronPlan` across calls if you evaluate the
/// same spec many times — see the `*_plan` variants.
pub fn normalize(spec spec: validator.ValidCron) -> cron_normalize.CronPlan {
  cron_normalize.normalize(spec)
}

/// Render a `ValidCron` back to its canonical 5-field string form.
pub fn to_string(spec spec: validator.ValidCron) -> String {
  validator.to_string(spec)
}

pub fn matches(spec spec: validator.ValidCron, at at: ValidDateTime) -> Bool {
  spec
  |> cron_normalize.normalize
  |> matches_plan(at: at)
}

pub fn iterator_after(
  spec spec: validator.ValidCron,
  boundary boundary: Boundary,
) -> cron_iterator.CronIterator {
  spec
  |> cron_normalize.normalize
  |> iterator_after_plan(boundary: boundary)
}

/// Return the next `ValidDateTime` after `after` that the cron spec
/// fires at, or `None` when no such occurrence exists.
///
/// UNIX cron is non-terminating — every well-formed `ValidCron`
/// specification has infinitely many future firings — so for typical
/// inputs `None` is **unreachable in practice**. The `Option` shape
/// is preserved for two narrow cases:
///
/// 1. Internal recursion guard. The next-firing search bounds itself
///    at ~5,000,000 candidate steps (≈ 9.5 years of minute granularity)
///    so a misbehaving plan cannot loop forever. A sufficiently
///    pathological combination of selectors that has no firing within
///    that horizon is treated as "no next occurrence".
/// 2. The maximum representable `ValidDateTime` boundary. If the
///    search would have to advance past the calendar's representable
///    range to find the next firing, it returns `None` rather than
///    fabricating a value.
///
/// Callers that compose `next_after` into a pipeline can safely treat
/// `None` as "no next time" without distinguishing the two reasons —
/// both are degenerate cases that should never be reached for cron
/// specs that came out of `validate`. RRULE's `next_after` returns
/// `Option` for a different reason (a `COUNT=N` rule legitimately
/// exhausts); the cron variant has no such terminating clause.
pub fn next_after(
  spec spec: validator.ValidCron,
  after after: ValidDateTime,
) -> Option(ValidDateTime) {
  spec
  |> cron_normalize.normalize
  |> next_after_plan(after: after)
}

/// Parse, validate, and call `next_after/2` in a single step.
///
/// Equivalent to:
///
/// ```gleam
/// use raw <- result.try(cron.parse(expr) |> result.map_error(ParseError))
/// use spec <- result.try(cron.validate(raw) |> result.map_error(ValidationError))
/// Ok(cron.next_after(spec, after: at))
/// ```
///
/// Useful when the caller already holds a cron expression as a string
/// and a `ValidDateTime` and just wants the next firing — the common
/// "from a literal" path. Callers that evaluate the same expression
/// many times should keep using `parse` / `validate` / `normalize`
/// and the `*_plan` family to pay those costs once.
///
/// The `Option` in the success case has the same semantics as
/// `next_after/2`; see that function's doc-comment for the (very
/// narrow) cases where it can be `None`.
pub fn next_after_string(
  expr expr: String,
  at at: ValidDateTime,
) -> Result(Option(ValidDateTime), CronError) {
  use raw <- result.try(parse(expr) |> result.map_error(ParseError))
  use spec <- result.try(validate(raw) |> result.map_error(ValidationError))
  Ok(next_after(spec, after: at))
}

/// Same as `matches/2` but takes an already-`normalize`d `CronPlan`,
/// so callers that evaluate the same spec many times can pay the
/// normalisation cost once.
pub fn matches_plan(
  plan plan: cron_normalize.CronPlan,
  at at: ValidDateTime,
) -> Bool {
  cron_evaluator.matches(plan, at: schedule_ast.valid_datetime_value(at))
}

/// Plan-reuse counterpart to `iterator_after/2`.
pub fn iterator_after_plan(
  plan plan: cron_normalize.CronPlan,
  boundary boundary: Boundary,
) -> cron_iterator.CronIterator {
  cron_iterator.after(plan, boundary: boundary)
}

/// Plan-reuse counterpart to `next_after/2`. Same `None` semantics:
/// see the `next_after/2` doc-comment for the (very narrow) cases
/// where this can return `None` for a `ValidCron` that came out of
/// `validate`.
pub fn next_after_plan(
  plan plan: cron_normalize.CronPlan,
  after after: ValidDateTime,
) -> Option(ValidDateTime) {
  cron_next.next_after(plan, after: schedule_ast.valid_datetime_value(after))
  |> option.map(schedule_ast.unsafe_assume_valid)
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

/// Build an `Item` matching a single value (for use inside `one_of`).
pub fn item_exact(value value: Int) -> validator.Item {
  validator.Exact(value)
}

/// Build an `Item` matching every value in `[from, to]` inclusive.
pub fn item_range(from start: Int, to end: Int) -> validator.Item {
  validator.Range(start, end)
}

/// Build an `Item` of the form `*/step` (every `step`-th value across
/// the field's full range).
pub fn item_step_any(step step: Int) -> validator.Item {
  validator.Step(validator.StepAny, step)
}

/// Build an `Item` of the form `start/step`.
pub fn item_step_from(start start: Int, step step: Int) -> validator.Item {
  validator.Step(validator.StepExact(start), step)
}

/// Build an `Item` of the form `from-to/step`.
pub fn item_step_between(
  from start: Int,
  to end: Int,
  step step: Int,
) -> validator.Item {
  validator.Step(validator.StepRange(start, end), step)
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
