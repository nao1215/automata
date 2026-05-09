import automata/cron/ast.{
  type Field, DayOfMonth, DayOfWeek, Expression, Hour, Minute, Month,
}
import automata/cron/parser
import automata/cron/validator
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

pub type Builder {
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
  case first_empty_selector(builder) {
    Some(field) -> Error(validator.InvalidList(field: field, value: ""))
    None -> {
      let rendered =
        string.join(
          [
            selector_to_string(builder.minute),
            selector_to_string(builder.hour),
            selector_to_string(builder.day_of_month),
            selector_to_string(builder.month),
            selector_to_string(builder.day_of_week),
          ],
          with: " ",
        )

      case parser.parse(input: rendered) {
        Ok(raw) -> validator.validate(raw)
        Error(error) ->
          Error(case error {
            parser.UnsupportedSyntax(field:, value:) ->
              validator.UnsupportedSyntax(field:, value:)
            parser.EmptyField(field:) ->
              validator.InvalidList(field:, value: rendered)
            parser.InvalidExpression(value:) ->
              validator.InvalidList(field: Expression, value:)
            parser.InvalidFieldCount(expected: _, actual: _) ->
              validator.InvalidList(field: Expression, value: rendered)
          })
      }
    }
  }
}

fn first_empty_selector(builder: Builder) -> Option(Field) {
  case selector_is_empty(builder.minute) {
    True -> Some(Minute)
    False ->
      case selector_is_empty(builder.hour) {
        True -> Some(Hour)
        False ->
          case selector_is_empty(builder.day_of_month) {
            True -> Some(DayOfMonth)
            False ->
              case selector_is_empty(builder.month) {
                True -> Some(Month)
                False ->
                  case selector_is_empty(builder.day_of_week) {
                    True -> Some(DayOfWeek)
                    False -> None
                  }
              }
          }
      }
  }
}

fn selector_is_empty(selector: validator.Selector) -> Bool {
  case selector {
    validator.Any -> False
    validator.Values(items) -> items == []
  }
}

fn selector_to_string(selector: validator.Selector) -> String {
  case selector {
    validator.Any -> "*"
    validator.Values(items) ->
      items
      |> list.map(item_to_string)
      |> string.join(with: ",")
  }
}

fn item_to_string(item: validator.Item) -> String {
  case item {
    validator.Exact(value) -> int.to_string(value)
    validator.Range(start, end) ->
      int.to_string(start) <> "-" <> int.to_string(end)
    validator.Step(base, step) ->
      step_base_to_string(base) <> "/" <> int.to_string(step)
  }
}

fn step_base_to_string(base: validator.StepBase) -> String {
  case base {
    validator.StepAny -> "*"
    validator.StepExact(value) -> int.to_string(value)
    validator.StepRange(start, end) ->
      int.to_string(start) <> "-" <> int.to_string(end)
  }
}
