import automata/cron
import automata/cron/ast as cron_ast
import automata/cron/iterator as cron_iterator
import automata/cron/parser as cron_parser
import automata/cron/validator as cron_validator
import automata/schedule/ast as schedule_ast
import gleam/option.{Some}
import gleeunit/should

fn parse_and_validate(input: String) -> cron_validator.ValidCron {
  let assert Ok(raw) = cron.parse(input)
  let assert Ok(spec) = cron.validate(raw)
  spec
}

pub fn parse_splits_unix_fields_test() {
  cron.parse("*/15 9-17 * * MON-FRI")
  |> should.equal(
    Ok(cron_ast.RawCron(
      minute: "*/15",
      hour: "9-17",
      day_of_month: "*",
      month: "*",
      day_of_week: "MON-FRI",
    )),
  )
}

pub fn parse_rejects_macros_test() {
  cron.parse("@daily")
  |> should.equal(
    Error(cron_parser.UnsupportedSyntax(
      field: cron_ast.Expression,
      value: "@daily",
    )),
  )
}

pub fn validate_rejects_out_of_range_minute_test() {
  let assert Ok(raw) = cron.parse("60 * * * *")

  cron.validate(raw)
  |> should.equal(
    Error(cron_validator.OutOfRange(
      field: cron_ast.Minute,
      min: 0,
      max: 59,
      actual: 60,
    )),
  )
}

pub fn validate_rejects_impossible_date_test() {
  let assert Ok(raw) = cron.parse("0 0 31 4 *")

  cron.validate(raw)
  |> should.equal(
    Error(cron_validator.ImpossibleDate(day_of_month: "31", month: "4")),
  )
}

pub fn validate_keeps_dom_dow_or_semantics_test() {
  let spec = parse_and_validate("0 0 31 4 1")

  cron.to_string(spec) |> should.equal("0 0 31 4 1")
}

pub fn matches_business_hours_test() {
  let spec = parse_and_validate("*/15 9-17 * * 1-5")

  cron.matches(spec, at: schedule_ast.datetime(2026, 5, 11, 9, 30, 0))
  |> should.equal(True)
  cron.matches(spec, at: schedule_ast.datetime(2026, 5, 11, 9, 31, 0))
  |> should.equal(False)
  cron.matches(spec, at: schedule_ast.datetime(2026, 5, 16, 9, 30, 0))
  |> should.equal(False)
}

pub fn next_after_finds_next_minute_slot_test() {
  let spec = parse_and_validate("*/15 9-17 * * 1-5")

  cron.next_after(spec, after: schedule_ast.datetime(2026, 5, 11, 9, 7, 0))
  |> should.equal(Some(schedule_ast.datetime(2026, 5, 11, 9, 15, 0)))
}

pub fn iterator_yields_occurrences_in_order_test() {
  let spec = parse_and_validate("0 9 * * 1-5")

  let first_iterator =
    cron.iterator_after(
      spec,
      boundary: schedule_ast.Exclusive(schedule_ast.datetime(
        2026,
        5,
        11,
        8,
        0,
        0,
      )),
    )

  let assert cron_iterator.Yield(first_at, second_iterator) =
    cron_iterator.step(first_iterator)
  first_at |> should.equal(schedule_ast.datetime(2026, 5, 11, 9, 0, 0))

  let assert cron_iterator.Yield(second_at, _) =
    cron_iterator.step(second_iterator)
  second_at |> should.equal(schedule_ast.datetime(2026, 5, 12, 9, 0, 0))
}

pub fn builder_round_trips_to_valid_cron_test() {
  cron.builder()
  |> cron.with_minute(cron.every(15))
  |> cron.with_hour(cron.between(from: 9, to: 17))
  |> cron.with_day_of_week(cron.one_of([cron_validator.Range(1, 5)]))
  |> cron.build
  |> should.equal(Ok(parse_and_validate("*/15 9-17 * * 1-5")))
}

pub fn builder_rejects_empty_selector_test() {
  cron.builder()
  |> cron.with_minute(cron.one_of([]))
  |> cron.build
  |> should.equal(
    Error(cron_validator.InvalidList(field: cron_ast.Minute, value: "")),
  )
}

pub fn next_after_is_exclusive_test() {
  cron.next_after(
    parse_and_validate("0 0 1 1 *"),
    after: schedule_ast.datetime(2026, 1, 1, 0, 0, 0),
  )
  |> should.equal(Some(schedule_ast.datetime(2027, 1, 1, 0, 0, 0)))
}
