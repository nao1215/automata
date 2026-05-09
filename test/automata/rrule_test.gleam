import automata/rrule
import automata/rrule/iterator as rule_iterator
import automata/rrule/parser as rule_parser
import automata/rrule/validator as rule_validator
import automata/schedule/ast as schedule_ast
import gleam/option.{None, Some}
import gleeunit/should

fn parse_and_validate(input: String) -> rule_validator.ValidRRule {
  let assert Ok(raw) = rrule.parse(input)
  let assert Ok(spec) = rrule.validate(raw)
  spec
}

pub fn parse_accepts_property_prefix_test() {
  let assert Ok(raw) =
    rrule.parse("RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;BYHOUR=9;BYMINUTE=30")
  let assert Ok(spec) = rrule.validate(raw)

  rrule.to_string(spec)
  |> should.equal("FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;BYHOUR=9;BYMINUTE=30")
}

pub fn parse_rejects_malformed_part_test() {
  rrule.parse("FREQ=DAILY;COUNT")
  |> should.equal(Error(rule_parser.InvalidPartSyntax(value: "COUNT")))
}

pub fn validate_rejects_unsupported_parts_test() {
  let assert Ok(raw) = rrule.parse("FREQ=DAILY;BYSECOND=30")

  rrule.validate(raw)
  |> should.equal(Error(rule_validator.UnsupportedPart(name: "BYSECOND")))
}

pub fn validate_rejects_count_until_conflict_test() {
  let assert Ok(raw) = rrule.parse("FREQ=DAILY;COUNT=3;UNTIL=20260503")

  rrule.validate(raw)
  |> should.equal(
    Error(rule_validator.MutuallyExclusiveParts(
      left: rule_validator.CountPart,
      right: rule_validator.UntilPart,
    )),
  )
}

pub fn normalize_inherits_anchor_components_test() {
  let spec = parse_and_validate("FREQ=MONTHLY")
  let anchor = schedule_ast.datetime(2026, 5, 10, 9, 30, 15)
  let assert Ok(plan) = rrule.normalize(spec, anchor: anchor)

  plan.by_hour |> should.equal([9])
  plan.by_minute |> should.equal([30])
  plan.second |> should.equal(15)
  plan.by_month_day |> should.equal(Some([10]))
}

pub fn matches_weekly_interval_rule_test() {
  let spec =
    parse_and_validate(
      "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;BYHOUR=9;BYMINUTE=30",
    )
  let anchor = schedule_ast.datetime(2026, 1, 5, 9, 30, 0)

  rrule.matches(
    spec,
    anchor: anchor,
    at: schedule_ast.datetime(2026, 1, 19, 9, 30, 0),
  )
  |> should.equal(Ok(True))

  rrule.matches(
    spec,
    anchor: anchor,
    at: schedule_ast.datetime(2026, 1, 12, 9, 30, 0),
  )
  |> should.equal(Ok(False))
}

pub fn next_after_respects_count_limit_test() {
  let spec = parse_and_validate("FREQ=DAILY;COUNT=3;BYHOUR=9;BYMINUTE=0")
  let anchor = schedule_ast.datetime(2026, 5, 1, 9, 0, 0)

  rrule.next_after(
    spec,
    anchor: anchor,
    after: schedule_ast.datetime(2026, 5, 2, 9, 0, 0),
  )
  |> should.equal(Ok(Some(schedule_ast.datetime(2026, 5, 3, 9, 0, 0))))

  rrule.next_after(
    spec,
    anchor: anchor,
    after: schedule_ast.datetime(2026, 5, 3, 9, 0, 0),
  )
  |> should.equal(Ok(None))
}

pub fn until_date_includes_last_matching_day_test() {
  let spec = parse_and_validate("FREQ=DAILY;UNTIL=20260503;BYHOUR=9;BYMINUTE=0")
  let anchor = schedule_ast.datetime(2026, 5, 1, 9, 0, 0)

  rrule.matches(
    spec,
    anchor: anchor,
    at: schedule_ast.datetime(2026, 5, 3, 9, 0, 0),
  )
  |> should.equal(Ok(True))

  rrule.matches(
    spec,
    anchor: anchor,
    at: schedule_ast.datetime(2026, 5, 4, 9, 0, 0),
  )
  |> should.equal(Ok(False))
}

pub fn iterator_yields_rrule_occurrences_in_order_test() {
  let spec = parse_and_validate("FREQ=WEEKLY;BYDAY=MO,WE;BYHOUR=9;BYMINUTE=30")
  let anchor = schedule_ast.datetime(2026, 1, 5, 9, 30, 0)
  let assert Ok(iterator) =
    rrule.iterator_after(
      spec,
      anchor: anchor,
      boundary: schedule_ast.Exclusive(schedule_ast.datetime(
        2026,
        1,
        5,
        8,
        0,
        0,
      )),
    )

  let assert rule_iterator.Yield(first_at, second_iterator) =
    rule_iterator.step(iterator)
  first_at |> should.equal(schedule_ast.datetime(2026, 1, 5, 9, 30, 0))

  let assert rule_iterator.Yield(second_at, _) =
    rule_iterator.step(second_iterator)
  second_at |> should.equal(schedule_ast.datetime(2026, 1, 7, 9, 30, 0))
}

pub fn builder_round_trips_to_valid_rrule_test() {
  rrule.builder(rule_validator.Weekly)
  |> rrule.with_interval(2)
  |> rrule.with_by_day([
    rrule.weekday(day: schedule_ast.Monday),
    rrule.weekday(day: schedule_ast.Wednesday),
  ])
  |> rrule.with_by_hour([9])
  |> rrule.with_by_minute([30])
  |> rrule.build
  |> should.equal(
    Ok(parse_and_validate(
      "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;BYHOUR=9;BYMINUTE=30",
    )),
  )
}
