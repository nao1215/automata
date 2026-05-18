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

fn vdt(
  year: Int,
  month: Int,
  day: Int,
  hour: Int,
  minute: Int,
  second: Int,
) -> schedule_ast.ValidDateTime {
  let assert Ok(value) =
    schedule_ast.try_valid_datetime(
      year:,
      month:,
      day:,
      hour:,
      minute:,
      second:,
    )
  value
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
  let anchor = vdt(2026, 5, 10, 9, 30, 15)
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
  let anchor = vdt(2026, 1, 5, 9, 30, 0)

  rrule.matches(spec, anchor: anchor, at: vdt(2026, 1, 19, 9, 30, 0))
  |> should.equal(Ok(True))

  rrule.matches(spec, anchor: anchor, at: vdt(2026, 1, 12, 9, 30, 0))
  |> should.equal(Ok(False))
}

pub fn next_after_respects_count_limit_test() {
  let spec = parse_and_validate("FREQ=DAILY;COUNT=3;BYHOUR=9;BYMINUTE=0")
  let anchor = vdt(2026, 5, 1, 9, 0, 0)

  rrule.next_after(spec, anchor: anchor, after: vdt(2026, 5, 2, 9, 0, 0))
  |> should.equal(Ok(Some(vdt(2026, 5, 3, 9, 0, 0))))

  rrule.next_after(spec, anchor: anchor, after: vdt(2026, 5, 3, 9, 0, 0))
  |> should.equal(Ok(None))
}

pub fn until_date_includes_last_matching_day_test() {
  let spec = parse_and_validate("FREQ=DAILY;UNTIL=20260503;BYHOUR=9;BYMINUTE=0")
  let anchor = vdt(2026, 5, 1, 9, 0, 0)

  rrule.matches(spec, anchor: anchor, at: vdt(2026, 5, 3, 9, 0, 0))
  |> should.equal(Ok(True))

  rrule.matches(spec, anchor: anchor, at: vdt(2026, 5, 4, 9, 0, 0))
  |> should.equal(Ok(False))
}

pub fn iterator_yields_rrule_occurrences_in_order_test() {
  let spec = parse_and_validate("FREQ=WEEKLY;BYDAY=MO,WE;BYHOUR=9;BYMINUTE=30")
  let anchor = vdt(2026, 1, 5, 9, 30, 0)
  let assert Ok(iterator) =
    rrule.iterator_after(
      spec,
      anchor: anchor,
      boundary: schedule_ast.Exclusive(vdt(2026, 1, 5, 8, 0, 0)),
    )

  let assert rule_iterator.Yield(first_at, second_iterator) =
    rule_iterator.step(iterator)
  first_at |> should.equal(vdt(2026, 1, 5, 9, 30, 0))

  let assert rule_iterator.Yield(second_at, _) =
    rule_iterator.step(second_iterator)
  second_at |> should.equal(vdt(2026, 1, 7, 9, 30, 0))
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
  let anchor = vdt(2026, 5, 1, 9, 0, 30)

  rrule.next_after(spec, anchor: anchor, after: vdt(2026, 5, 1, 9, 0, 0))
  |> should.equal(Ok(Some(vdt(2026, 5, 1, 9, 0, 30))))

  rrule.next_after(spec, anchor: anchor, after: vdt(2026, 5, 1, 9, 0, 30))
  |> should.equal(Ok(Some(vdt(2026, 5, 2, 9, 0, 30))))
}

pub fn iterator_after_preserves_anchor_seconds_test() {
  let spec = parse_and_validate("FREQ=DAILY;BYHOUR=9;BYMINUTE=0")
  let anchor = vdt(2026, 5, 1, 9, 0, 30)
  let assert Ok(iterator) =
    rrule.iterator_after(
      spec,
      anchor: anchor,
      boundary: schedule_ast.Exclusive(vdt(2026, 5, 1, 9, 0, 0)),
    )

  let assert rule_iterator.Yield(first_at, second_iterator) =
    rule_iterator.step(iterator)
  first_at |> should.equal(vdt(2026, 5, 1, 9, 0, 30))

  let assert rule_iterator.Yield(second_at, _) =
    rule_iterator.step(second_iterator)
  second_at |> should.equal(vdt(2026, 5, 2, 9, 0, 30))
}

pub fn yearly_numeric_byday_uses_year_scope_when_no_bymonth_test() {
  let spec = parse_and_validate("FREQ=YEARLY;BYDAY=1MO;BYHOUR=9;BYMINUTE=0")
  let anchor = vdt(2026, 1, 5, 9, 0, 0)

  rrule.matches(spec, anchor: anchor, at: vdt(2026, 1, 5, 9, 0, 0))
  |> should.equal(Ok(True))

  rrule.matches(spec, anchor: anchor, at: vdt(2027, 1, 4, 9, 0, 0))
  |> should.equal(Ok(True))

  rrule.matches(spec, anchor: anchor, at: vdt(2026, 2, 2, 9, 0, 0))
  |> should.equal(Ok(False))
}

pub fn yearly_numeric_byday_with_bymonth_uses_month_scope_test() {
  let spec =
    parse_and_validate("FREQ=YEARLY;BYMONTH=3;BYDAY=1MO;BYHOUR=9;BYMINUTE=0")
  let anchor = vdt(2026, 3, 2, 9, 0, 0)

  rrule.matches(spec, anchor: anchor, at: vdt(2026, 3, 2, 9, 0, 0))
  |> should.equal(Ok(True))

  rrule.matches(spec, anchor: anchor, at: vdt(2027, 3, 1, 9, 0, 0))
  |> should.equal(Ok(True))

  rrule.matches(spec, anchor: anchor, at: vdt(2026, 1, 5, 9, 0, 0))
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

pub fn validate_rejects_byday_ordinal_above_5_for_monthly_test() {
  let assert Ok(raw) = rrule.parse("FREQ=MONTHLY;BYDAY=6MO")

  rrule.validate(raw)
  |> should.equal(
    Error(rule_validator.InvalidPartValue(
      part: rule_validator.ByDayPart,
      value: "6MO",
    )),
  )
}

pub fn validate_rejects_byday_ordinal_below_minus_5_for_monthly_test() {
  let assert Ok(raw) = rrule.parse("FREQ=MONTHLY;BYDAY=-6MO")

  rrule.validate(raw)
  |> should.equal(
    Error(rule_validator.InvalidPartValue(
      part: rule_validator.ByDayPart,
      value: "-6MO",
    )),
  )
}

pub fn validate_rejects_byday_ordinal_above_53_for_yearly_test() {
  let assert Ok(raw) = rrule.parse("FREQ=YEARLY;BYDAY=99MO")

  rrule.validate(raw)
  |> should.equal(
    Error(rule_validator.InvalidPartValue(
      part: rule_validator.ByDayPart,
      value: "99MO",
    )),
  )
}

pub fn validate_accepts_byday_ordinal_within_yearly_range_test() {
  let assert Ok(raw) = rrule.parse("FREQ=YEARLY;BYDAY=53MO;BYHOUR=9;BYMINUTE=0")
  let assert Ok(_) = rrule.validate(raw)
}

pub fn builder_rejects_byday_ordinal_above_5_for_monthly_test() {
  rrule.builder(rule_validator.Monthly)
  |> rrule.with_by_day([rrule.nth_weekday(ordinal: 6, day: schedule_ast.Monday)])
  |> rrule.build
  |> should.equal(
    Error(rule_validator.InvalidPartValue(
      part: rule_validator.ByDayPart,
      value: "6MO",
    )),
  )
}

pub fn builder_rejects_byday_ordinal_above_53_for_yearly_test() {
  rrule.builder(rule_validator.Yearly)
  |> rrule.with_by_day([
    rrule.nth_weekday(ordinal: 99, day: schedule_ast.Monday),
  ])
  |> rrule.build
  |> should.equal(
    Error(rule_validator.InvalidPartValue(
      part: rule_validator.ByDayPart,
      value: "99MO",
    )),
  )
}

pub fn yearly_interval_500_finds_distant_occurrence_test() {
  // INTERVAL=500 places occurrences ~500 years (~182,500 days) apart,
  // well past the previous 150,000-day search cap.
  let spec =
    parse_and_validate(
      "FREQ=YEARLY;INTERVAL=500;BYMONTH=1;BYMONTHDAY=1;BYHOUR=0;BYMINUTE=0",
    )
  let anchor = vdt(2026, 1, 1, 0, 0, 0)

  rrule.next_after(spec, anchor: anchor, after: vdt(2026, 1, 1, 0, 0, 0))
  |> should.equal(Ok(Some(vdt(2526, 1, 1, 0, 0, 0))))
}

pub fn try_valid_datetime_rejects_impossible_calendar_dates_test() {
  // Lock-in for the public API contract: callers must obtain a
  // `ValidDateTime` via `try_valid_datetime`, so impossible dates such
  // as 2026-02-30 cannot reach `rrule.matches` / `rrule.next_after`.
  schedule_ast.try_valid_datetime(
    year: 2026,
    month: 2,
    day: 30,
    hour: 0,
    minute: 0,
    second: 0,
  )
  |> should.equal(Error(schedule_ast.InvalidDate(2026, 2, 30)))
}

pub fn valid_rrule_accessors_expose_components_test() {
  let spec = parse_and_validate("FREQ=YEARLY;INTERVAL=2;BYHOUR=9;BYMINUTE=0")

  rule_validator.frequency(spec) |> should.equal(rule_validator.Yearly)
  rule_validator.interval(spec) |> should.equal(2)
  rule_validator.end_condition(spec) |> should.equal(rule_validator.Forever)
  rule_validator.by_hour(spec) |> should.equal(Some([9]))
  rule_validator.by_minute(spec) |> should.equal(Some([0]))
  rule_validator.by_day(spec) |> should.equal(None)
  rule_validator.by_month(spec) |> should.equal(None)
  rule_validator.by_month_day(spec) |> should.equal(None)
}

pub fn validate_rejects_missing_freq_test() {
  let assert Ok(raw) = rrule.parse("INTERVAL=2;BYHOUR=9")

  rrule.validate(raw)
  |> should.equal(
    Error(rule_validator.MissingPart(part: rule_validator.FreqPart)),
  )
}

pub fn validate_rejects_unknown_part_test() {
  let assert Ok(raw) = rrule.parse("FREQ=DAILY;XYZZY=1")

  rrule.validate(raw)
  |> should.equal(Error(rule_validator.UnknownPart(name: "XYZZY")))
}

pub fn validate_rejects_duplicate_part_test() {
  let assert Ok(raw) = rrule.parse("FREQ=DAILY;COUNT=2;COUNT=3")

  rrule.validate(raw)
  |> should.equal(
    Error(rule_validator.DuplicatePart(part: rule_validator.CountPart)),
  )
}

pub fn validate_rejects_duplicate_byhour_test() {
  let assert Ok(raw) = rrule.parse("FREQ=DAILY;BYHOUR=9;BYHOUR=10")

  rrule.validate(raw)
  |> should.equal(
    Error(rule_validator.DuplicatePart(part: rule_validator.ByHourPart)),
  )
}

pub fn validate_rejects_invalid_freq_value_test() {
  let assert Ok(raw) = rrule.parse("FREQ=BIWEEKLY")

  rrule.validate(raw)
  |> should.equal(
    Error(rule_validator.InvalidPartValue(
      part: rule_validator.FreqPart,
      value: "BIWEEKLY",
    )),
  )
}

pub fn validate_rejects_non_numeric_interval_test() {
  let assert Ok(raw) = rrule.parse("FREQ=DAILY;INTERVAL=two")

  rrule.validate(raw)
  |> should.equal(
    Error(rule_validator.InvalidNumber(
      part: rule_validator.IntervalPart,
      value: "two",
    )),
  )
}

pub fn validate_rejects_zero_interval_test() {
  let assert Ok(raw) = rrule.parse("FREQ=DAILY;INTERVAL=0")

  rrule.validate(raw)
  |> should.equal(
    Error(rule_validator.MustBePositive(
      part: rule_validator.IntervalPart,
      actual: 0,
    )),
  )
}

pub fn validate_rejects_count_zero_test() {
  let assert Ok(raw) = rrule.parse("FREQ=DAILY;COUNT=0")

  rrule.validate(raw)
  |> should.equal(
    Error(rule_validator.MustBePositive(
      part: rule_validator.CountPart,
      actual: 0,
    )),
  )
}

pub fn validate_rejects_byhour_out_of_range_test() {
  let assert Ok(raw) = rrule.parse("FREQ=DAILY;BYHOUR=24")

  rrule.validate(raw)
  |> should.equal(
    Error(rule_validator.OutOfRange(
      part: rule_validator.ByHourPart,
      min: 0,
      max: 23,
      actual: 24,
    )),
  )
}

pub fn validate_rejects_byminute_out_of_range_test() {
  let assert Ok(raw) = rrule.parse("FREQ=DAILY;BYMINUTE=60")

  rrule.validate(raw)
  |> should.equal(
    Error(rule_validator.OutOfRange(
      part: rule_validator.ByMinutePart,
      min: 0,
      max: 59,
      actual: 60,
    )),
  )
}

pub fn validate_rejects_bymonthday_zero_test() {
  let assert Ok(raw) = rrule.parse("FREQ=MONTHLY;BYMONTHDAY=0")

  rrule.validate(raw)
  |> should.equal(
    Error(rule_validator.InvalidPartValue(
      part: rule_validator.ByMonthDayPart,
      value: "0",
    )),
  )
}

pub fn validate_rejects_numeric_byday_for_daily_test() {
  let assert Ok(raw) = rrule.parse("FREQ=DAILY;BYDAY=1MO")

  rrule.validate(raw)
  |> should.equal(
    Error(rule_validator.NumericWeekdayRequiresMonthlyOrYearly(
      frequency: rule_validator.Daily,
    )),
  )
}

pub fn validate_rejects_numeric_byday_for_weekly_test() {
  let assert Ok(raw) = rrule.parse("FREQ=WEEKLY;BYDAY=2WE")

  rrule.validate(raw)
  |> should.equal(
    Error(rule_validator.NumericWeekdayRequiresMonthlyOrYearly(
      frequency: rule_validator.Weekly,
    )),
  )
}

pub fn validate_rejects_impossible_month_day_pair_test() {
  // BYMONTH=2 + BYMONTHDAY=30 is impossible in any year.
  let assert Ok(raw) = rrule.parse("FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30")

  rrule.validate(raw)
  |> should.equal(
    Error(rule_validator.ImpossibleDate(by_month: "2", by_month_day: "30")),
  )
}

pub fn validate_rejects_until_with_wrong_length_test() {
  let assert Ok(raw) = rrule.parse("FREQ=DAILY;UNTIL=2026")

  rrule.validate(raw)
  |> should.equal(
    Error(rule_validator.InvalidPartValue(
      part: rule_validator.UntilPart,
      value: "2026",
    )),
  )
}

pub fn validate_rejects_until_with_invalid_date_test() {
  let assert Ok(raw) = rrule.parse("FREQ=DAILY;UNTIL=20260230")

  rrule.validate(raw)
  |> should.equal(
    Error(rule_validator.InvalidPartValue(
      part: rule_validator.UntilPart,
      value: "20260230",
    )),
  )
}

pub fn validate_rejects_until_datetime_without_z_suffix_test() {
  let assert Ok(raw) = rrule.parse("FREQ=DAILY;UNTIL=20260101T120000X")

  rrule.validate(raw)
  |> should.equal(
    Error(rule_validator.InvalidPartValue(
      part: rule_validator.UntilPart,
      value: "20260101T120000X",
    )),
  )
}

pub fn validate_accepts_until_datetime_test() {
  let spec = parse_and_validate("FREQ=DAILY;UNTIL=20260601T120000Z")

  rule_validator.end_condition(spec)
  |> should.equal(
    rule_validator.Until(
      rule_validator.UntilDateTime(schedule_ast.datetime(2026, 6, 1, 12, 0, 0)),
    ),
  )
}

pub fn builder_with_count_round_trips_test() {
  rrule.builder(rule_validator.Daily)
  |> rrule.with_count(5)
  |> rrule.with_by_hour([9])
  |> rrule.with_by_minute([0])
  |> rrule.build
  |> should.equal(
    Ok(parse_and_validate("FREQ=DAILY;COUNT=5;BYHOUR=9;BYMINUTE=0")),
  )
}

pub fn builder_with_until_date_round_trips_test() {
  rrule.builder(rule_validator.Daily)
  |> rrule.with_until_date(schedule_ast.Date(year: 2026, month: 6, day: 1))
  |> rrule.with_by_hour([9])
  |> rrule.with_by_minute([0])
  |> rrule.build
  |> should.equal(
    Ok(parse_and_validate("FREQ=DAILY;UNTIL=20260601;BYHOUR=9;BYMINUTE=0")),
  )
}

pub fn builder_with_until_datetime_round_trips_test() {
  rrule.builder(rule_validator.Daily)
  |> rrule.with_until_datetime(vdt(2026, 6, 1, 12, 0, 0))
  |> rrule.with_by_hour([9])
  |> rrule.with_by_minute([0])
  |> rrule.build
  |> should.equal(
    Ok(parse_and_validate(
      "FREQ=DAILY;UNTIL=20260601T120000Z;BYHOUR=9;BYMINUTE=0",
    )),
  )
}

pub fn builder_with_by_month_round_trips_test() {
  rrule.builder(rule_validator.Yearly)
  |> rrule.with_by_month([3, 6, 9, 12])
  |> rrule.with_by_month_day([1])
  |> rrule.with_by_hour([0])
  |> rrule.with_by_minute([0])
  |> rrule.build
  |> should.equal(
    Ok(parse_and_validate(
      "FREQ=YEARLY;BYMONTH=3,6,9,12;BYMONTHDAY=1;BYHOUR=0;BYMINUTE=0",
    )),
  )
}

pub fn builder_rejects_zero_interval_test() {
  rrule.builder(rule_validator.Daily)
  |> rrule.with_interval(0)
  |> rrule.build
  |> should.equal(
    Error(rule_validator.MustBePositive(
      part: rule_validator.IntervalPart,
      actual: 0,
    )),
  )
}

pub fn builder_rejects_zero_count_test() {
  rrule.builder(rule_validator.Daily)
  |> rrule.with_count(0)
  |> rrule.build
  |> should.equal(
    Error(rule_validator.MustBePositive(
      part: rule_validator.CountPart,
      actual: 0,
    )),
  )
}

pub fn builder_rejects_empty_by_hour_test() {
  rrule.builder(rule_validator.Daily)
  |> rrule.with_by_hour([])
  |> rrule.build
  |> should.equal(
    Error(rule_validator.InvalidList(part: rule_validator.ByHourPart, value: "")),
  )
}

pub fn without_end_condition_clears_count_test() {
  rrule.builder(rule_validator.Daily)
  |> rrule.with_count(5)
  |> rrule.without_end_condition
  |> rrule.with_by_hour([9])
  |> rrule.with_by_minute([0])
  |> rrule.build
  |> should.equal(Ok(parse_and_validate("FREQ=DAILY;BYHOUR=9;BYMINUTE=0")))
}

// --- RFC 5545 §3.3.10 sub-daily FREQ values ---

pub fn validate_accepts_freq_hourly_test() {
  let assert Ok(raw) = rrule.parse("FREQ=HOURLY")
  let assert Ok(spec) = rrule.validate(raw)
  rrule.to_string(spec)
  |> should.equal("FREQ=HOURLY")
}

pub fn validate_accepts_freq_minutely_test() {
  let assert Ok(raw) = rrule.parse("FREQ=MINUTELY")
  let assert Ok(spec) = rrule.validate(raw)
  rrule.to_string(spec)
  |> should.equal("FREQ=MINUTELY")
}

pub fn validate_accepts_freq_secondly_test() {
  let assert Ok(raw) = rrule.parse("FREQ=SECONDLY")
  let assert Ok(spec) = rrule.validate(raw)
  rrule.to_string(spec)
  |> should.equal("FREQ=SECONDLY")
}

pub fn builder_accepts_freq_hourly_test() {
  rrule.builder(rule_validator.Hourly)
  |> rrule.build
  |> should.equal(Ok(parse_and_validate("FREQ=HOURLY")))
}

pub fn builder_accepts_freq_minutely_test() {
  rrule.builder(rule_validator.Minutely)
  |> rrule.build
  |> should.equal(Ok(parse_and_validate("FREQ=MINUTELY")))
}

pub fn builder_accepts_freq_secondly_test() {
  rrule.builder(rule_validator.Secondly)
  |> rrule.build
  |> should.equal(Ok(parse_and_validate("FREQ=SECONDLY")))
}

pub fn freq_hourly_with_interval_round_trips_test() {
  let assert Ok(raw) = rrule.parse("FREQ=HOURLY;INTERVAL=2")
  let assert Ok(spec) = rrule.validate(raw)
  rrule.to_string(spec)
  |> should.equal("FREQ=HOURLY;INTERVAL=2")
}
