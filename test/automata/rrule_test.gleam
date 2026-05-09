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

pub fn next_after_preserves_anchor_seconds_test() {
  let spec = parse_and_validate("FREQ=DAILY;BYHOUR=9;BYMINUTE=0")
  let anchor = schedule_ast.datetime(2026, 5, 1, 9, 0, 30)

  rrule.next_after(
    spec,
    anchor: anchor,
    after: schedule_ast.datetime(2026, 5, 1, 9, 0, 0),
  )
  |> should.equal(Ok(Some(schedule_ast.datetime(2026, 5, 1, 9, 0, 30))))

  rrule.next_after(
    spec,
    anchor: anchor,
    after: schedule_ast.datetime(2026, 5, 1, 9, 0, 30),
  )
  |> should.equal(Ok(Some(schedule_ast.datetime(2026, 5, 2, 9, 0, 30))))
}

pub fn iterator_after_preserves_anchor_seconds_test() {
  let spec = parse_and_validate("FREQ=DAILY;BYHOUR=9;BYMINUTE=0")
  let anchor = schedule_ast.datetime(2026, 5, 1, 9, 0, 30)
  let assert Ok(iterator) =
    rrule.iterator_after(
      spec,
      anchor: anchor,
      boundary: schedule_ast.Exclusive(schedule_ast.datetime(
        2026,
        5,
        1,
        9,
        0,
        0,
      )),
    )

  let assert rule_iterator.Yield(first_at, second_iterator) =
    rule_iterator.step(iterator)
  first_at |> should.equal(schedule_ast.datetime(2026, 5, 1, 9, 0, 30))

  let assert rule_iterator.Yield(second_at, _) =
    rule_iterator.step(second_iterator)
  second_at |> should.equal(schedule_ast.datetime(2026, 5, 2, 9, 0, 30))
}

pub fn yearly_numeric_byday_uses_year_scope_when_no_bymonth_test() {
  let spec = parse_and_validate("FREQ=YEARLY;BYDAY=1MO;BYHOUR=9;BYMINUTE=0")
  let anchor = schedule_ast.datetime(2026, 1, 5, 9, 0, 0)

  rrule.matches(
    spec,
    anchor: anchor,
    at: schedule_ast.datetime(2026, 1, 5, 9, 0, 0),
  )
  |> should.equal(Ok(True))

  rrule.matches(
    spec,
    anchor: anchor,
    at: schedule_ast.datetime(2027, 1, 4, 9, 0, 0),
  )
  |> should.equal(Ok(True))

  rrule.matches(
    spec,
    anchor: anchor,
    at: schedule_ast.datetime(2026, 2, 2, 9, 0, 0),
  )
  |> should.equal(Ok(False))
}

pub fn yearly_numeric_byday_with_bymonth_uses_month_scope_test() {
  let spec =
    parse_and_validate("FREQ=YEARLY;BYMONTH=3;BYDAY=1MO;BYHOUR=9;BYMINUTE=0")
  let anchor = schedule_ast.datetime(2026, 3, 2, 9, 0, 0)

  rrule.matches(
    spec,
    anchor: anchor,
    at: schedule_ast.datetime(2026, 3, 2, 9, 0, 0),
  )
  |> should.equal(Ok(True))

  rrule.matches(
    spec,
    anchor: anchor,
    at: schedule_ast.datetime(2027, 3, 1, 9, 0, 0),
  )
  |> should.equal(Ok(True))

  rrule.matches(
    spec,
    anchor: anchor,
    at: schedule_ast.datetime(2026, 1, 5, 9, 0, 0),
  )
  |> should.equal(Ok(False))
}

pub fn validate_rejects_weekly_with_by_month_day_test() {
  let assert Ok(raw) = rrule.parse("FREQ=WEEKLY;BYMONTHDAY=1")

  rrule.validate(raw)
  |> should.equal(
    Error(rule_validator.IncompatibleFrequencyAndPart(
      frequency: rule_validator.Weekly,
      part: rule_validator.ByMonthDayPart,
    )),
  )
}

pub fn builder_rejects_empty_by_day_test() {
  rrule.builder(rule_validator.Weekly)
  |> rrule.with_by_day([])
  |> rrule.build
  |> should.equal(
    Error(rule_validator.InvalidList(part: rule_validator.ByDayPart, value: "")),
  )
}

pub fn builder_rejects_zero_ordinal_weekday_test() {
  rrule.builder(rule_validator.Monthly)
  |> rrule.with_by_day([rrule.nth_weekday(ordinal: 0, day: schedule_ast.Monday)])
  |> rrule.build
  |> should.equal(
    Error(rule_validator.InvalidPartValue(
      part: rule_validator.ByDayPart,
      value: "0MO",
    )),
  )
}

pub fn try_datetime_validates_components_test() {
  schedule_ast.try_datetime(
    year: 2026,
    month: 2,
    day: 30,
    hour: 0,
    minute: 0,
    second: 0,
  )
  |> should.equal(Error(schedule_ast.InvalidDate(2026, 2, 30)))

  schedule_ast.try_datetime(
    year: 2026,
    month: 5,
    day: 9,
    hour: 25,
    minute: 0,
    second: 0,
  )
  |> should.equal(Error(schedule_ast.InvalidTime(25, 0, 0)))

  schedule_ast.try_datetime(
    year: 2024,
    month: 2,
    day: 29,
    hour: 23,
    minute: 59,
    second: 59,
  )
  |> should.equal(Ok(schedule_ast.datetime(2024, 2, 29, 23, 59, 59)))
}

pub fn valid_datetime_round_trips_value_test() {
  let assert Ok(valid) =
    schedule_ast.try_valid_datetime(
      year: 2026,
      month: 5,
      day: 9,
      hour: 12,
      minute: 0,
      second: 0,
    )

  schedule_ast.valid_datetime_value(valid)
  |> should.equal(schedule_ast.datetime(2026, 5, 9, 12, 0, 0))
}
