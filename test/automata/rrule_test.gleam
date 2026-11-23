import automata as a
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/time/calendar
import gleeunit/should

fn parse_and_validate(input: String) -> a.RecurrenceRule {
  let assert Ok(raw) = a.rrule_parse_raw(input: input)
  let assert Ok(spec) = a.rrule_validate(raw: raw)
  spec
}

fn vdt(
  year: Int,
  month: Int,
  day: Int,
  hour: Int,
  minute: Int,
  second: Int,
) -> a.ValidDateTime {
  let assert Ok(value) =
    make_valid_datetime(year:, month:, day:, hour:, minute:, second:)
  value
}

pub fn parse_accepts_property_prefix_test() {
  let assert Ok(raw) =
    a.rrule_parse_raw(
      input: "RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;BYHOUR=9;BYMINUTE=30",
    )
  let assert Ok(spec) = a.rrule_validate(raw: raw)

  a.rrule_to_string(spec: spec)
  |> should.equal("FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;BYHOUR=9;BYMINUTE=30")
}

pub fn parse_rejects_malformed_part_test() {
  a.rrule_parse_raw(input: "FREQ=DAILY;COUNT")
  |> should.equal(Error(a.RruleParseInvalidPartSyntax(value: "COUNT")))
}

pub fn validate_rejects_unsupported_parts_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=DAILY;BYSECOND=30")

  a.rrule_validate(raw: raw)
  |> should.equal(Error(a.RruleUnsupportedPart(name: "BYSECOND")))
}

pub fn validate_rejects_count_until_conflict_test() {
  let assert Ok(raw) =
    a.rrule_parse_raw(input: "FREQ=DAILY;COUNT=3;UNTIL=20260503")

  a.rrule_validate(raw: raw)
  |> should.equal(
    Error(a.RruleMutuallyExclusiveParts(left: a.CountPart, right: a.UntilPart)),
  )
}

pub fn normalize_inherits_anchor_components_test() {
  let spec = parse_and_validate("FREQ=MONTHLY")
  let anchor = vdt(2026, 5, 10, 9, 30, 15)
  next_rrule(spec: spec, anchor: anchor, after: anchor)
  |> should.equal(Ok(Some(vdt(2026, 6, 10, 9, 30, 15))))
}

pub fn matches_weekly_interval_rule_test() {
  let spec =
    parse_and_validate(
      "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;BYHOUR=9;BYMINUTE=30",
    )
  let anchor = vdt(2026, 1, 5, 9, 30, 0)

  matches_rrule(spec: spec, anchor: anchor, at: vdt(2026, 1, 19, 9, 30, 0))
  |> should.equal(Ok(True))

  matches_rrule(spec: spec, anchor: anchor, at: vdt(2026, 1, 12, 9, 30, 0))
  |> should.equal(Ok(False))
}

pub fn next_after_respects_count_limit_test() {
  let spec = parse_and_validate("FREQ=DAILY;COUNT=3;BYHOUR=9;BYMINUTE=0")
  let anchor = vdt(2026, 5, 1, 9, 0, 0)

  next_rrule(spec: spec, anchor: anchor, after: vdt(2026, 5, 2, 9, 0, 0))
  |> should.equal(Ok(Some(vdt(2026, 5, 3, 9, 0, 0))))

  next_rrule(spec: spec, anchor: anchor, after: vdt(2026, 5, 3, 9, 0, 0))
  |> should.equal(Ok(None))
}

pub fn until_date_includes_last_matching_day_test() {
  let spec = parse_and_validate("FREQ=DAILY;UNTIL=20260503;BYHOUR=9;BYMINUTE=0")
  let anchor = vdt(2026, 5, 1, 9, 0, 0)

  matches_rrule(spec: spec, anchor: anchor, at: vdt(2026, 5, 3, 9, 0, 0))
  |> should.equal(Ok(True))

  matches_rrule(spec: spec, anchor: anchor, at: vdt(2026, 5, 4, 9, 0, 0))
  |> should.equal(Ok(False))
}

pub fn iterator_yields_rrule_occurrences_in_order_test() {
  let spec = parse_and_validate("FREQ=WEEKLY;BYDAY=MO,WE;BYHOUR=9;BYMINUTE=30")
  let anchor = vdt(2026, 1, 5, 9, 30, 0)
  let assert Ok(iterator) =
    iterate_rrule(
      spec: spec,
      anchor: anchor,
      boundary: a.Exclusive(vdt(2026, 1, 5, 8, 0, 0)),
    )

  let assert a.Yield(first_at, second_iterator) =
    step_schedule(iterator: iterator)
  first_at |> should.equal(vdt(2026, 1, 5, 9, 30, 0))

  let assert a.Yield(second_at, _) = step_schedule(iterator: second_iterator)
  second_at |> should.equal(vdt(2026, 1, 7, 9, 30, 0))
}

pub fn builder_round_trips_to_valid_rrule_test() {
  a.rrule_options(a.Weekly)
  |> old_rrule_with_interval(2)
  |> old_rrule_with_by_day([
    old_rrule_weekday(day: calendar.Monday),
    old_rrule_weekday(day: calendar.Wednesday),
  ])
  |> old_rrule_with_by_hour([9])
  |> old_rrule_with_by_minute([30])
  |> old_rrule_build
  |> should.equal(
    Ok(parse_and_validate(
      "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;BYHOUR=9;BYMINUTE=30",
    )),
  )
}

pub fn next_after_preserves_anchor_seconds_test() {
  let spec = parse_and_validate("FREQ=DAILY;BYHOUR=9;BYMINUTE=0")
  let anchor = vdt(2026, 5, 1, 9, 0, 30)

  next_rrule(spec: spec, anchor: anchor, after: vdt(2026, 5, 1, 9, 0, 0))
  |> should.equal(Ok(Some(vdt(2026, 5, 1, 9, 0, 30))))

  next_rrule(spec: spec, anchor: anchor, after: vdt(2026, 5, 1, 9, 0, 30))
  |> should.equal(Ok(Some(vdt(2026, 5, 2, 9, 0, 30))))
}

pub fn iterator_after_preserves_anchor_seconds_test() {
  let spec = parse_and_validate("FREQ=DAILY;BYHOUR=9;BYMINUTE=0")
  let anchor = vdt(2026, 5, 1, 9, 0, 30)
  let assert Ok(iterator) =
    iterate_rrule(
      spec: spec,
      anchor: anchor,
      boundary: a.Exclusive(vdt(2026, 5, 1, 9, 0, 0)),
    )

  let assert a.Yield(first_at, second_iterator) =
    step_schedule(iterator: iterator)
  first_at |> should.equal(vdt(2026, 5, 1, 9, 0, 30))

  let assert a.Yield(second_at, _) = step_schedule(iterator: second_iterator)
  second_at |> should.equal(vdt(2026, 5, 2, 9, 0, 30))
}

pub fn yearly_numeric_byday_uses_year_scope_when_no_bymonth_test() {
  let spec = parse_and_validate("FREQ=YEARLY;BYDAY=1MO;BYHOUR=9;BYMINUTE=0")
  let anchor = vdt(2026, 1, 5, 9, 0, 0)

  matches_rrule(spec: spec, anchor: anchor, at: vdt(2026, 1, 5, 9, 0, 0))
  |> should.equal(Ok(True))

  matches_rrule(spec: spec, anchor: anchor, at: vdt(2027, 1, 4, 9, 0, 0))
  |> should.equal(Ok(True))

  matches_rrule(spec: spec, anchor: anchor, at: vdt(2026, 2, 2, 9, 0, 0))
  |> should.equal(Ok(False))
}

pub fn yearly_numeric_byday_with_bymonth_uses_month_scope_test() {
  let spec =
    parse_and_validate("FREQ=YEARLY;BYMONTH=3;BYDAY=1MO;BYHOUR=9;BYMINUTE=0")
  let anchor = vdt(2026, 3, 2, 9, 0, 0)

  matches_rrule(spec: spec, anchor: anchor, at: vdt(2026, 3, 2, 9, 0, 0))
  |> should.equal(Ok(True))

  matches_rrule(spec: spec, anchor: anchor, at: vdt(2027, 3, 1, 9, 0, 0))
  |> should.equal(Ok(True))

  matches_rrule(spec: spec, anchor: anchor, at: vdt(2026, 1, 5, 9, 0, 0))
  |> should.equal(Ok(False))
}

pub fn validate_rejects_weekly_with_by_month_day_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=WEEKLY;BYMONTHDAY=1")

  a.rrule_validate(raw: raw)
  |> should.equal(
    Error(a.RruleIncompatibleFrequencyAndPart(
      frequency: a.Weekly,
      part: a.ByMonthDayPart,
    )),
  )
}

pub fn builder_rejects_empty_by_day_test() {
  a.rrule_options(a.Weekly)
  |> old_rrule_with_by_day([])
  |> old_rrule_build
  |> should.equal(Error(a.RruleInvalidList(part: a.ByDayPart, value: "")))
}

pub fn builder_rejects_zero_ordinal_weekday_test() {
  a.rrule_options(a.Monthly)
  |> old_rrule_with_by_day([
    old_rrule_nth_weekday(ordinal: 0, day: calendar.Monday),
  ])
  |> old_rrule_build
  |> should.equal(
    Error(a.RruleInvalidPartValue(part: a.ByDayPart, value: "0MO")),
  )
}

pub fn try_datetime_validates_components_test() {
  make_checked_datetime(
    year: 2026,
    month: 2,
    day: 30,
    hour: 0,
    minute: 0,
    second: 0,
  )
  |> should.equal(Error(a.InvalidDate(2026, 2, 30)))

  make_checked_datetime(
    year: 2026,
    month: 5,
    day: 9,
    hour: 25,
    minute: 0,
    second: 0,
  )
  |> should.equal(Error(a.InvalidTime(25, 0, 0, 0)))

  make_checked_datetime(
    year: 2024,
    month: 2,
    day: 29,
    hour: 23,
    minute: 59,
    second: 59,
  )
  |> should.equal(
    Ok(make_datetime(
      year: 2024,
      month: 2,
      day: 29,
      hour: 23,
      minute: 59,
      second: 59,
    )),
  )
}

pub fn valid_datetime_round_trips_value_test() {
  let assert Ok(valid) =
    make_valid_datetime(
      year: 2026,
      month: 5,
      day: 9,
      hour: 12,
      minute: 0,
      second: 0,
    )

  a.datetime_value(valid)
  |> should.equal(make_datetime(
    year: 2026,
    month: 5,
    day: 9,
    hour: 12,
    minute: 0,
    second: 0,
  ))
}

pub fn validate_rejects_byday_ordinal_above_5_for_monthly_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=MONTHLY;BYDAY=6MO")

  a.rrule_validate(raw: raw)
  |> should.equal(
    Error(a.RruleInvalidPartValue(part: a.ByDayPart, value: "6MO")),
  )
}

pub fn validate_rejects_byday_ordinal_below_minus_5_for_monthly_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=MONTHLY;BYDAY=-6MO")

  a.rrule_validate(raw: raw)
  |> should.equal(
    Error(a.RruleInvalidPartValue(part: a.ByDayPart, value: "-6MO")),
  )
}

pub fn validate_rejects_byday_ordinal_above_53_for_yearly_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=YEARLY;BYDAY=99MO")

  a.rrule_validate(raw: raw)
  |> should.equal(
    Error(a.RruleInvalidPartValue(part: a.ByDayPart, value: "99MO")),
  )
}

pub fn validate_accepts_byday_ordinal_within_yearly_range_test() {
  let assert Ok(raw) =
    a.rrule_parse_raw(input: "FREQ=YEARLY;BYDAY=53MO;BYHOUR=9;BYMINUTE=0")
  let assert Ok(_) = a.rrule_validate(raw: raw)
}

pub fn builder_rejects_byday_ordinal_above_5_for_monthly_test() {
  a.rrule_options(a.Monthly)
  |> old_rrule_with_by_day([
    old_rrule_nth_weekday(ordinal: 6, day: calendar.Monday),
  ])
  |> old_rrule_build
  |> should.equal(
    Error(a.RruleInvalidPartValue(part: a.ByDayPart, value: "6MO")),
  )
}

pub fn builder_rejects_byday_ordinal_above_53_for_yearly_test() {
  a.rrule_options(a.Yearly)
  |> old_rrule_with_by_day([
    old_rrule_nth_weekday(ordinal: 99, day: calendar.Monday),
  ])
  |> old_rrule_build
  |> should.equal(
    Error(a.RruleInvalidPartValue(part: a.ByDayPart, value: "99MO")),
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

  next_rrule(spec: spec, anchor: anchor, after: vdt(2026, 1, 1, 0, 0, 0))
  |> should.equal(Ok(Some(vdt(2526, 1, 1, 0, 0, 0))))
}

pub fn try_valid_datetime_rejects_impossible_calendar_dates_test() {
  // Lock-in for the public API contract: callers must obtain a
  // `ValidDateTime` via `try_valid_datetime`, so impossible dates such
  // as 2026-02-30 cannot reach `rrule.matches` / `rrule.next_after`.
  make_valid_datetime(
    year: 2026,
    month: 2,
    day: 30,
    hour: 0,
    minute: 0,
    second: 0,
  )
  |> should.equal(Error(a.InvalidDate(2026, 2, 30)))
}

pub fn valid_rrule_accessors_expose_components_test() {
  let spec = parse_and_validate("FREQ=YEARLY;INTERVAL=2;BYHOUR=9;BYMINUTE=0")

  rrule_frequency(spec) |> should.equal(a.Yearly)
  rrule_interval(spec) |> should.equal(2)
  rrule_end_condition(spec) |> should.equal(a.Forever)
  rrule_by_hour(spec) |> should.equal(Some([9]))
  rrule_by_minute(spec) |> should.equal(Some([0]))
  rrule_by_day(spec) |> should.equal(None)
  rrule_by_month(spec) |> should.equal(None)
  rrule_by_month_day(spec) |> should.equal(None)
}

pub fn validate_rejects_missing_freq_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "INTERVAL=2;BYHOUR=9")

  a.rrule_validate(raw: raw)
  |> should.equal(Error(a.RruleMissingPart(part: a.FreqPart)))
}

pub fn validate_rejects_unknown_part_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=DAILY;XYZZY=1")

  a.rrule_validate(raw: raw)
  |> should.equal(Error(a.RruleUnknownPart(name: "XYZZY")))
}

pub fn validate_rejects_duplicate_part_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=DAILY;COUNT=2;COUNT=3")

  a.rrule_validate(raw: raw)
  |> should.equal(Error(a.RruleDuplicatePart(part: a.CountPart)))
}

pub fn validate_rejects_duplicate_byhour_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=DAILY;BYHOUR=9;BYHOUR=10")

  a.rrule_validate(raw: raw)
  |> should.equal(Error(a.RruleDuplicatePart(part: a.ByHourPart)))
}

pub fn validate_rejects_invalid_freq_value_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=BIWEEKLY")

  a.rrule_validate(raw: raw)
  |> should.equal(
    Error(a.RruleInvalidPartValue(part: a.FreqPart, value: "BIWEEKLY")),
  )
}

pub fn validate_rejects_non_numeric_interval_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=DAILY;INTERVAL=two")

  a.rrule_validate(raw: raw)
  |> should.equal(
    Error(a.RruleInvalidNumber(part: a.IntervalPart, value: "two")),
  )
}

pub fn validate_rejects_zero_interval_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=DAILY;INTERVAL=0")

  a.rrule_validate(raw: raw)
  |> should.equal(Error(a.RruleMustBePositive(part: a.IntervalPart, actual: 0)))
}

pub fn validate_rejects_count_zero_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=DAILY;COUNT=0")

  a.rrule_validate(raw: raw)
  |> should.equal(Error(a.RruleMustBePositive(part: a.CountPart, actual: 0)))
}

pub fn validate_rejects_byhour_out_of_range_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=DAILY;BYHOUR=24")

  a.rrule_validate(raw: raw)
  |> should.equal(
    Error(a.RruleOutOfRange(part: a.ByHourPart, min: 0, max: 23, actual: 24)),
  )
}

pub fn validate_rejects_byminute_out_of_range_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=DAILY;BYMINUTE=60")

  a.rrule_validate(raw: raw)
  |> should.equal(
    Error(a.RruleOutOfRange(part: a.ByMinutePart, min: 0, max: 59, actual: 60)),
  )
}

pub fn validate_rejects_bymonthday_zero_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=MONTHLY;BYMONTHDAY=0")

  a.rrule_validate(raw: raw)
  |> should.equal(
    Error(a.RruleInvalidPartValue(part: a.ByMonthDayPart, value: "0")),
  )
}

pub fn validate_rejects_numeric_byday_for_daily_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=DAILY;BYDAY=1MO")

  a.rrule_validate(raw: raw)
  |> should.equal(
    Error(a.RruleNumericWeekdayRequiresMonthlyOrYearly(frequency: a.Daily)),
  )
}

pub fn validate_rejects_numeric_byday_for_weekly_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=WEEKLY;BYDAY=2WE")

  a.rrule_validate(raw: raw)
  |> should.equal(
    Error(a.RruleNumericWeekdayRequiresMonthlyOrYearly(frequency: a.Weekly)),
  )
}

pub fn validate_rejects_impossible_month_day_pair_test() {
  // BYMONTH=2 + BYMONTHDAY=30 is impossible in any year.
  let assert Ok(raw) =
    a.rrule_parse_raw(input: "FREQ=YEARLY;BYMONTH=2;BYMONTHDAY=30")

  a.rrule_validate(raw: raw)
  |> should.equal(
    Error(a.RruleImpossibleDate(by_month: "2", by_month_day: "30")),
  )
}

pub fn validate_rejects_until_with_wrong_length_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=DAILY;UNTIL=2026")

  a.rrule_validate(raw: raw)
  |> should.equal(Error(a.RruleUntilMalformedDateTime(value: "2026")))
}

pub fn validate_rejects_until_with_invalid_date_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=DAILY;UNTIL=20260230")

  a.rrule_validate(raw: raw)
  |> should.equal(Error(a.RruleUntilMalformedDateTime(value: "20260230")))
}

pub fn validate_rejects_until_datetime_without_z_suffix_test() {
  let assert Ok(raw) =
    a.rrule_parse_raw(input: "FREQ=DAILY;UNTIL=20260101T120000X")

  a.rrule_validate(raw: raw)
  |> should.equal(Error(a.RruleUntilMissingZ(value: "20260101T120000X")))
}

pub fn validate_accepts_until_date_form_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=DAILY;UNTIL=20260525")
  case a.rrule_validate(raw: raw) {
    Ok(_) -> Nil
    Error(_) -> should.fail()
  }
}

pub fn validate_accepts_until_utc_form_test() {
  let assert Ok(raw) =
    a.rrule_parse_raw(input: "FREQ=DAILY;UNTIL=20260525T000000Z")
  case a.rrule_validate(raw: raw) {
    Ok(_) -> Nil
    Error(_) -> should.fail()
  }
}

pub fn validate_rejects_until_local_form_with_specific_error_test() {
  let assert Ok(raw) =
    a.rrule_parse_raw(input: "FREQ=DAILY;UNTIL=20260525T000000")
  case a.rrule_validate(raw: raw) {
    Error(a.RruleUntilMissingZ(value: "20260525T000000")) -> Nil
    _ -> should.fail()
  }
}

pub fn validate_rejects_until_garbage_with_specific_error_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=DAILY;UNTIL=garbage")
  case a.rrule_validate(raw: raw) {
    Error(a.RruleUntilMalformedDateTime(value: "garbage")) -> Nil
    _ -> should.fail()
  }
}

pub fn validate_accepts_until_datetime_test() {
  let spec = parse_and_validate("FREQ=DAILY;UNTIL=20260601T120000Z")

  rrule_end_condition(spec)
  |> should.equal(
    a.Until(
      a.UntilDateTime(make_datetime(
        year: 2026,
        month: 6,
        day: 1,
        hour: 12,
        minute: 0,
        second: 0,
      )),
    ),
  )
}

pub fn builder_with_count_round_trips_test() {
  a.rrule_options(a.Daily)
  |> old_rrule_with_count(5)
  |> old_rrule_with_by_hour([9])
  |> old_rrule_with_by_minute([0])
  |> old_rrule_build
  |> should.equal(
    Ok(parse_and_validate("FREQ=DAILY;COUNT=5;BYHOUR=9;BYMINUTE=0")),
  )
}

pub fn builder_with_until_date_round_trips_test() {
  a.rrule_options(a.Daily)
  |> old_rrule_with_until_date(make_date(year: 2026, month: 6, day: 1))
  |> old_rrule_with_by_hour([9])
  |> old_rrule_with_by_minute([0])
  |> old_rrule_build
  |> should.equal(
    Ok(parse_and_validate("FREQ=DAILY;UNTIL=20260601;BYHOUR=9;BYMINUTE=0")),
  )
}

pub fn builder_with_until_datetime_round_trips_test() {
  a.rrule_options(a.Daily)
  |> old_rrule_with_until_datetime(vdt(2026, 6, 1, 12, 0, 0))
  |> old_rrule_with_by_hour([9])
  |> old_rrule_with_by_minute([0])
  |> old_rrule_build
  |> should.equal(
    Ok(parse_and_validate(
      "FREQ=DAILY;UNTIL=20260601T120000Z;BYHOUR=9;BYMINUTE=0",
    )),
  )
}

pub fn builder_with_by_month_round_trips_test() {
  a.rrule_options(a.Yearly)
  |> old_rrule_with_by_month([3, 6, 9, 12])
  |> old_rrule_with_by_month_day([1])
  |> old_rrule_with_by_hour([0])
  |> old_rrule_with_by_minute([0])
  |> old_rrule_build
  |> should.equal(
    Ok(parse_and_validate(
      "FREQ=YEARLY;BYMONTH=3,6,9,12;BYMONTHDAY=1;BYHOUR=0;BYMINUTE=0",
    )),
  )
}

pub fn builder_rejects_zero_interval_test() {
  a.rrule_options(a.Daily)
  |> old_rrule_with_interval(0)
  |> old_rrule_build
  |> should.equal(Error(a.RruleMustBePositive(part: a.IntervalPart, actual: 0)))
}

pub fn builder_rejects_zero_count_test() {
  a.rrule_options(a.Daily)
  |> old_rrule_with_count(0)
  |> old_rrule_build
  |> should.equal(Error(a.RruleMustBePositive(part: a.CountPart, actual: 0)))
}

pub fn builder_rejects_empty_by_hour_test() {
  a.rrule_options(a.Daily)
  |> old_rrule_with_by_hour([])
  |> old_rrule_build
  |> should.equal(Error(a.RruleInvalidList(part: a.ByHourPart, value: "")))
}

pub fn builder_sorts_and_dedups_lists_like_parse_test() {
  a.rrule_options(a.Monthly)
  |> old_rrule_with_by_month_day([15, -1, 15])
  |> old_rrule_with_by_hour([17, 9, 9])
  |> old_rrule_with_by_minute([30, 0])
  |> old_rrule_build
  |> should.equal(
    Ok(parse_and_validate(
      "FREQ=MONTHLY;BYMONTHDAY=-1,15;BYHOUR=9,17;BYMINUTE=0,30",
    )),
  )
}

pub fn builder_rejects_out_of_range_minute_test() {
  a.rrule_options(a.Daily)
  |> old_rrule_with_by_minute([0, 60])
  |> old_rrule_build
  |> should.equal(
    Error(a.RruleOutOfRange(part: a.ByMinutePart, min: 0, max: 59, actual: 60)),
  )
}

pub fn builder_rejects_zero_month_day_test() {
  a.rrule_options(a.Monthly)
  |> old_rrule_with_by_month_day([0])
  |> old_rrule_build
  |> should.equal(
    Error(a.RruleInvalidPartValue(part: a.ByMonthDayPart, value: "0")),
  )
}

pub fn builder_rejects_impossible_until_date_test() {
  a.rrule_options(a.Daily)
  |> old_rrule_with_until_date(make_date(year: 2026, month: 2, day: 30))
  |> old_rrule_build
  |> should.equal(Error(a.RruleUntilMalformedDateTime(value: "20260230")))
}

pub fn builder_rejects_until_year_beyond_four_digits_test() {
  a.rrule_options(a.Daily)
  |> old_rrule_with_until_date(make_date(year: 12_026, month: 1, day: 1))
  |> old_rrule_build
  |> should.equal(Error(a.RruleUntilMalformedDateTime(value: "120260101")))
}

pub fn builder_rejects_numeric_weekday_for_weekly_test() {
  a.rrule_options(a.Weekly)
  |> old_rrule_with_by_day([
    old_rrule_nth_weekday(ordinal: 1, day: calendar.Monday),
  ])
  |> old_rrule_build
  |> should.equal(
    Error(a.RruleNumericWeekdayRequiresMonthlyOrYearly(frequency: a.Weekly)),
  )
}

pub fn without_end_condition_clears_count_test() {
  a.rrule_options(a.Daily)
  |> old_rrule_with_count(5)
  |> old_rrule_without_end_condition
  |> old_rrule_with_by_hour([9])
  |> old_rrule_with_by_minute([0])
  |> old_rrule_build
  |> should.equal(Ok(parse_and_validate("FREQ=DAILY;BYHOUR=9;BYMINUTE=0")))
}

// --- RFC 5545 §3.3.10 sub-daily FREQ values ---

pub fn validate_accepts_freq_hourly_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=HOURLY")
  let assert Ok(spec) = a.rrule_validate(raw: raw)
  a.rrule_to_string(spec: spec)
  |> should.equal("FREQ=HOURLY")
}

pub fn validate_accepts_freq_minutely_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=MINUTELY")
  let assert Ok(spec) = a.rrule_validate(raw: raw)
  a.rrule_to_string(spec: spec)
  |> should.equal("FREQ=MINUTELY")
}

pub fn validate_accepts_freq_secondly_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=SECONDLY")
  let assert Ok(spec) = a.rrule_validate(raw: raw)
  a.rrule_to_string(spec: spec)
  |> should.equal("FREQ=SECONDLY")
}

pub fn builder_accepts_freq_hourly_test() {
  a.rrule_options(a.Hourly)
  |> old_rrule_build
  |> should.equal(Ok(parse_and_validate("FREQ=HOURLY")))
}

pub fn builder_accepts_freq_minutely_test() {
  a.rrule_options(a.Minutely)
  |> old_rrule_build
  |> should.equal(Ok(parse_and_validate("FREQ=MINUTELY")))
}

pub fn builder_accepts_freq_secondly_test() {
  a.rrule_options(a.Secondly)
  |> old_rrule_build
  |> should.equal(Ok(parse_and_validate("FREQ=SECONDLY")))
}

pub fn freq_hourly_with_interval_round_trips_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=HOURLY;INTERVAL=2")
  let assert Ok(spec) = a.rrule_validate(raw: raw)
  a.rrule_to_string(spec: spec)
  |> should.equal("FREQ=HOURLY;INTERVAL=2")
}

// Issue #55: FREQ=HOURLY/MINUTELY/SECONDLY iterators should expand to all
// hours / minutes / seconds within each day when no BY* part is given.
// Matches python-dateutil.rrule and RFC 5545 §3.3.10.

pub fn hourly_default_expands_to_every_hour_test() {
  let spec = parse_and_validate("FREQ=HOURLY;COUNT=3")
  let anchor = vdt(2026, 1, 1, 0, 0, 0)
  let assert Ok(iterator) =
    iterate_rrule(spec: spec, anchor: anchor, boundary: a.Inclusive(anchor))
  let assert a.Yield(a, it2) = step_schedule(iterator: iterator)
  let assert a.Yield(b, it3) = step_schedule(iterator: it2)
  let assert a.Yield(c, _) = step_schedule(iterator: it3)
  a |> should.equal(vdt(2026, 1, 1, 0, 0, 0))
  b |> should.equal(vdt(2026, 1, 1, 1, 0, 0))
  c |> should.equal(vdt(2026, 1, 1, 2, 0, 0))
}

pub fn minutely_interval_15_expands_correctly_test() {
  let spec = parse_and_validate("FREQ=MINUTELY;INTERVAL=15;COUNT=3")
  let anchor = vdt(2026, 1, 1, 0, 0, 0)
  let assert Ok(iterator) =
    iterate_rrule(spec: spec, anchor: anchor, boundary: a.Inclusive(anchor))
  let assert a.Yield(a, it2) = step_schedule(iterator: iterator)
  let assert a.Yield(b, it3) = step_schedule(iterator: it2)
  let assert a.Yield(c, _) = step_schedule(iterator: it3)
  a |> should.equal(vdt(2026, 1, 1, 0, 0, 0))
  b |> should.equal(vdt(2026, 1, 1, 0, 15, 0))
  c |> should.equal(vdt(2026, 1, 1, 0, 30, 0))
}

pub fn secondly_default_expands_to_every_second_test() {
  let spec = parse_and_validate("FREQ=SECONDLY;COUNT=3")
  let anchor = vdt(2026, 1, 1, 0, 0, 0)
  let assert Ok(iterator) =
    iterate_rrule(spec: spec, anchor: anchor, boundary: a.Inclusive(anchor))
  let assert a.Yield(a, it2) = step_schedule(iterator: iterator)
  let assert a.Yield(b, it3) = step_schedule(iterator: it2)
  let assert a.Yield(c, _) = step_schedule(iterator: it3)
  a |> should.equal(vdt(2026, 1, 1, 0, 0, 0))
  b |> should.equal(vdt(2026, 1, 1, 0, 0, 1))
  c |> should.equal(vdt(2026, 1, 1, 0, 0, 2))
}

pub fn hourly_with_explicit_byhour_still_works_test() {
  // Regression guard: when BYHOUR is explicit, the iterator walks only
  // those hours, not the full 0..23.
  let spec = parse_and_validate("FREQ=HOURLY;BYHOUR=0,1,2;COUNT=3")
  let anchor = vdt(2026, 1, 1, 0, 0, 0)
  let assert Ok(iterator) =
    iterate_rrule(spec: spec, anchor: anchor, boundary: a.Inclusive(anchor))
  let assert a.Yield(a, it2) = step_schedule(iterator: iterator)
  let assert a.Yield(b, it3) = step_schedule(iterator: it2)
  let assert a.Yield(c, _) = step_schedule(iterator: it3)
  a |> should.equal(vdt(2026, 1, 1, 0, 0, 0))
  b |> should.equal(vdt(2026, 1, 1, 1, 0, 0))
  c |> should.equal(vdt(2026, 1, 1, 2, 0, 0))
}

pub fn daily_frequency_unaffected_by_subdaily_fix_test() {
  // Regression guard: DAILY and coarser frequencies still take the
  // anchor's hour/minute/second as their single occurrence per day.
  let spec = parse_and_validate("FREQ=DAILY;COUNT=3")
  let anchor = vdt(2026, 1, 1, 0, 0, 0)
  let assert Ok(iterator) =
    iterate_rrule(spec: spec, anchor: anchor, boundary: a.Inclusive(anchor))
  let assert a.Yield(a, it2) = step_schedule(iterator: iterator)
  let assert a.Yield(b, it3) = step_schedule(iterator: it2)
  let assert a.Yield(c, _) = step_schedule(iterator: it3)
  a |> should.equal(vdt(2026, 1, 1, 0, 0, 0))
  b |> should.equal(vdt(2026, 1, 2, 0, 0, 0))
  c |> should.equal(vdt(2026, 1, 3, 0, 0, 0))
}

fn first_occurrences(
  rule: String,
  anchor: a.ValidDateTime,
  count: Int,
) -> List(String) {
  let spec = parse_and_validate(rule)
  let assert Ok(iterator) =
    iterate_rrule(spec: spec, anchor: anchor, boundary: a.Inclusive(anchor))
  take_occurrences(iterator, count, [])
}

fn take_occurrences(
  iterator: a.OccurrenceIterator,
  count: Int,
  acc: List(String),
) -> List(String) {
  case count {
    0 -> list.reverse(acc)
    _ ->
      case step_schedule(iterator: iterator) {
        a.Done -> list.reverse(acc)
        a.Yield(at, next) ->
          take_occurrences(next, count - 1, [
            raw_datetime_to_string(a.datetime_value(at)),
            ..acc
          ])
      }
  }
}

// Reference values in the tests below come from python-dateutil 4.0.0
// (`rrulestr(rule, dtstart=anchor)`).

pub fn next_after_far_past_exhausted_count_returns_none_test() {
  // The 10 occurrences end at 2026-01-01T00:00:09. Asking a week later
  // used to walk every second since the anchor (about 19 seconds of
  // CPU); the count is now capped at COUNT.
  let spec = parse_and_validate("FREQ=SECONDLY;COUNT=10")
  next_rrule(
    spec: spec,
    anchor: vdt(2026, 1, 1, 0, 0, 0),
    after: vdt(2026, 1, 8, 0, 0, 0),
  )
  |> should.equal(Ok(None))
}

pub fn next_after_without_count_does_not_count_past_occurrences_test() {
  let spec = parse_and_validate("FREQ=MINUTELY")
  next_rrule(
    spec: spec,
    anchor: vdt(2025, 1, 1, 0, 0, 0),
    after: vdt(2026, 1, 1, 0, 0, 0),
  )
  |> should.equal(Ok(Some(vdt(2026, 1, 1, 0, 1, 0))))
}

pub fn matches_far_after_exhausted_count_is_false_test() {
  let spec = parse_and_validate("FREQ=SECONDLY;COUNT=10")
  matches_rrule(
    spec: spec,
    anchor: vdt(2026, 1, 1, 0, 0, 0),
    at: vdt(2026, 1, 3, 0, 0, 0),
  )
  |> should.equal(Ok(False))
}

pub fn matches_last_counted_occurrence_test() {
  let spec = parse_and_validate("FREQ=SECONDLY;COUNT=10")
  let anchor = vdt(2026, 1, 1, 0, 0, 0)
  matches_rrule(spec: spec, anchor: anchor, at: vdt(2026, 1, 1, 0, 0, 9))
  |> should.equal(Ok(True))
  matches_rrule(spec: spec, anchor: anchor, at: vdt(2026, 1, 1, 0, 0, 10))
  |> should.equal(Ok(False))
}

pub fn iterator_after_mid_count_keeps_remaining_occurrences_test() {
  let spec = parse_and_validate("FREQ=DAILY;COUNT=3")
  let assert Ok(iterator) =
    iterate_rrule(
      spec: spec,
      anchor: vdt(2026, 1, 1, 0, 0, 0),
      boundary: a.Exclusive(vdt(2026, 1, 1, 12, 0, 0)),
    )
  take_occurrences(iterator, 5, [])
  |> should.equal(["2026-01-02T00:00:00", "2026-01-03T00:00:00"])
}

pub fn minutely_large_interval_reaches_next_step_test() {
  first_occurrences(
    "FREQ=MINUTELY;INTERVAL=4500000",
    vdt(2026, 1, 1, 0, 0, 0),
    3,
  )
  |> should.equal([
    "2026-01-01T00:00:00", "2034-07-23T00:00:00", "2043-02-11T00:00:00",
  ])
}

pub fn hourly_large_interval_reaches_next_step_test() {
  first_occurrences("FREQ=HOURLY;INTERVAL=100000", vdt(2026, 1, 1, 0, 0, 0), 2)
  |> should.equal(["2026-01-01T00:00:00", "2037-05-29T16:00:00"])
}

pub fn secondly_large_interval_reaches_next_step_test() {
  first_occurrences(
    "FREQ=SECONDLY;INTERVAL=300000000",
    vdt(2026, 1, 1, 0, 0, 0),
    2,
  )
  |> should.equal(["2026-01-01T00:00:00", "2035-07-05T05:20:00"])
}

pub fn hourly_large_interval_with_by_month_test() {
  first_occurrences(
    "FREQ=HOURLY;INTERVAL=5000;BYMONTH=6",
    vdt(2026, 1, 1, 0, 0, 0),
    3,
  )
  |> should.equal([
    "2029-06-04T00:00:00", "2033-06-01T08:00:00", "2070-06-29T00:00:00",
  ])
}

pub fn minutely_interval_with_by_hour_test() {
  first_occurrences(
    "FREQ=MINUTELY;INTERVAL=7;BYHOUR=9",
    vdt(2026, 1, 1, 0, 0, 0),
    3,
  )
  |> should.equal([
    "2026-01-01T09:06:00", "2026-01-01T09:13:00", "2026-01-01T09:20:00",
  ])
}

pub fn validate_accepts_default_wkst_test() {
  let spec = parse_and_validate("FREQ=WEEKLY;WKST=MO")
  a.rrule_to_string(spec: spec) |> should.equal("FREQ=WEEKLY")
  next_rrule(
    spec: spec,
    anchor: vdt(2026, 1, 5, 9, 0, 0),
    after: vdt(2026, 1, 5, 9, 0, 0),
  )
  |> should.equal(Ok(Some(vdt(2026, 1, 12, 9, 0, 0))))
}

pub fn validate_rejects_non_default_wkst_test() {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=WEEKLY;WKST=SU")
  a.rrule_validate(raw: raw)
  |> should.equal(Error(a.RruleUnsupportedPart(name: "WKST")))
}

pub fn validate_rejects_repeated_wkst_test() {
  // Each rule part may appear once. RulePart has no WKST variant, so a
  // second WKST is reported like an unsupported WKST value.
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=WEEKLY;WKST=MO;WKST=MO")
  a.rrule_validate(raw: raw)
  |> should.equal(Error(a.RruleUnsupportedPart(name: "WKST")))
}

pub fn daily_interval_keeps_all_times_on_aligned_dates_test() {
  first_occurrences(
    "FREQ=DAILY;INTERVAL=2;BYHOUR=9,17",
    vdt(2026, 1, 1, 17, 0, 0),
    4,
  )
  |> should.equal([
    "2026-01-01T17:00:00", "2026-01-03T09:00:00", "2026-01-03T17:00:00",
    "2026-01-05T09:00:00",
  ])
}

pub fn weekly_interval_uses_calendar_weeks_test() {
  first_occurrences(
    "FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE",
    vdt(2025, 12, 31, 9, 0, 0),
    4,
  )
  |> should.equal([
    "2025-12-31T09:00:00", "2026-01-12T09:00:00", "2026-01-14T09:00:00",
    "2026-01-26T09:00:00",
  ])
}

pub fn monthly_interval_uses_calendar_months_test() {
  first_occurrences(
    "FREQ=MONTHLY;INTERVAL=2;BYMONTHDAY=1,31",
    vdt(2026, 1, 31, 9, 0, 0),
    4,
  )
  |> should.equal([
    "2026-01-31T09:00:00", "2026-03-01T09:00:00", "2026-03-31T09:00:00",
    "2026-05-01T09:00:00",
  ])
}

pub fn yearly_interval_uses_calendar_years_test() {
  first_occurrences(
    "FREQ=YEARLY;INTERVAL=2;BYMONTH=1,12;BYMONTHDAY=31",
    vdt(2025, 12, 31, 9, 0, 0),
    4,
  )
  |> should.equal([
    "2025-12-31T09:00:00", "2027-01-31T09:00:00", "2027-12-31T09:00:00",
    "2029-01-31T09:00:00",
  ])
}

fn iterate_rrule(
  spec spec: a.RecurrenceRule,
  anchor anchor: a.ValidDateTime,
  boundary boundary: a.Boundary,
) -> Result(a.OccurrenceIterator, a.ScheduleError) {
  a.schedule_iterator(
    a.schedule_from_rrule(spec, anchor: anchor),
    boundary: boundary,
  )
}

fn make_checked_datetime(
  year year: Int,
  month month: Int,
  day day: Int,
  hour hour: Int,
  minute minute: Int,
  second second: Int,
) -> Result(a.DateTime, a.DateTimeError) {
  make_valid_datetime(
    year: year,
    month: month,
    day: day,
    hour: hour,
    minute: minute,
    second: second,
  )
  |> result.map(a.datetime_value)
}

fn make_date(year year: Int, month month: Int, day day: Int) -> calendar.Date {
  let assert Ok(month) = calendar.month_from_int(month)
  calendar.Date(year, month, day)
}

fn make_datetime(
  year year: Int,
  month month: Int,
  day day: Int,
  hour hour: Int,
  minute minute: Int,
  second second: Int,
) -> a.DateTime {
  a.DateTime(
    make_date(year: year, month: month, day: day),
    make_time(hour: hour, minute: minute, second: second),
  )
}

fn make_time(
  hour hour: Int,
  minute minute: Int,
  second second: Int,
) -> calendar.TimeOfDay {
  calendar.TimeOfDay(hour, minute, second, 0)
}

fn make_valid_datetime(
  year year: Int,
  month month: Int,
  day day: Int,
  hour hour: Int,
  minute minute: Int,
  second second: Int,
) -> Result(a.ValidDateTime, a.DateTimeError) {
  case calendar.month_from_int(month) {
    Error(_) -> Error(a.InvalidDate(year, month, day))
    Ok(month) ->
      a.datetime_validate(a.DateTime(
        calendar.Date(year, month, day),
        make_time(hour: hour, minute: minute, second: second),
      ))
  }
}

fn matches_rrule(
  spec spec: a.RecurrenceRule,
  anchor anchor: a.ValidDateTime,
  at at: a.ValidDateTime,
) -> Result(Bool, a.ScheduleError) {
  a.schedule_matches(a.schedule_from_rrule(spec, anchor: anchor), at: at)
}

fn next_rrule(
  spec spec: a.RecurrenceRule,
  anchor anchor: a.ValidDateTime,
  after after: a.ValidDateTime,
) -> Result(option.Option(a.ValidDateTime), a.ScheduleError) {
  a.schedule_next(a.schedule_from_rrule(spec, anchor: anchor), after: after)
}

fn old_rrule_build(
  builder builder: a.RecurrenceOptions,
) -> Result(a.RecurrenceRule, a.RruleValidationError) {
  a.rrule_new(builder)
}

fn old_rrule_nth_weekday(
  ordinal ordinal: Int,
  day day: calendar.DayOfWeek,
) -> a.WeekdaySpecifier {
  a.NthWeekday(ordinal, day)
}

fn old_rrule_weekday(day day: calendar.DayOfWeek) -> a.WeekdaySpecifier {
  a.EveryWeekday(day)
}

fn old_rrule_with_by_day(
  options: a.RecurrenceOptions,
  values: List(a.WeekdaySpecifier),
) -> a.RecurrenceOptions {
  a.RecurrenceOptions(..options, by_day: option.Some(values))
}

fn old_rrule_with_by_hour(
  options: a.RecurrenceOptions,
  values: List(Int),
) -> a.RecurrenceOptions {
  a.RecurrenceOptions(..options, by_hour: option.Some(values))
}

fn old_rrule_with_by_minute(
  options: a.RecurrenceOptions,
  values: List(Int),
) -> a.RecurrenceOptions {
  a.RecurrenceOptions(..options, by_minute: option.Some(values))
}

fn old_rrule_with_by_month(
  options: a.RecurrenceOptions,
  values: List(Int),
) -> a.RecurrenceOptions {
  a.RecurrenceOptions(..options, by_month: option.Some(values))
}

fn old_rrule_with_by_month_day(
  options: a.RecurrenceOptions,
  values: List(Int),
) -> a.RecurrenceOptions {
  a.RecurrenceOptions(..options, by_month_day: option.Some(values))
}

fn old_rrule_with_count(
  options: a.RecurrenceOptions,
  count: Int,
) -> a.RecurrenceOptions {
  a.RecurrenceOptions(..options, end_condition: a.Count(count))
}

fn old_rrule_with_interval(
  options: a.RecurrenceOptions,
  interval: Int,
) -> a.RecurrenceOptions {
  a.RecurrenceOptions(..options, interval: interval)
}

fn old_rrule_with_until_date(
  options: a.RecurrenceOptions,
  until: calendar.Date,
) -> a.RecurrenceOptions {
  a.RecurrenceOptions(..options, end_condition: a.Until(a.UntilDate(until)))
}

fn old_rrule_with_until_datetime(
  options: a.RecurrenceOptions,
  until: a.ValidDateTime,
) -> a.RecurrenceOptions {
  a.RecurrenceOptions(
    ..options,
    end_condition: a.Until(a.UntilDateTime(a.datetime_value(until))),
  )
}

fn old_rrule_without_end_condition(
  options: a.RecurrenceOptions,
) -> a.RecurrenceOptions {
  a.RecurrenceOptions(..options, end_condition: a.Forever)
}

fn raw_datetime_to_string(value: a.DateTime) -> String {
  let assert Ok(valid) = a.datetime_validate(value)
  a.datetime_to_string(valid)
}

fn rrule_by_day(
  rule: a.RecurrenceRule,
) -> option.Option(List(a.WeekdaySpecifier)) {
  a.rrule_to_options(rule).by_day
}

fn rrule_by_hour(rule: a.RecurrenceRule) -> option.Option(List(Int)) {
  a.rrule_to_options(rule).by_hour
}

fn rrule_by_minute(rule: a.RecurrenceRule) -> option.Option(List(Int)) {
  a.rrule_to_options(rule).by_minute
}

fn rrule_by_month(rule: a.RecurrenceRule) -> option.Option(List(Int)) {
  a.rrule_to_options(rule).by_month
}

fn rrule_by_month_day(rule: a.RecurrenceRule) -> option.Option(List(Int)) {
  a.rrule_to_options(rule).by_month_day
}

fn rrule_end_condition(rule: a.RecurrenceRule) -> a.EndCondition {
  a.rrule_to_options(rule).end_condition
}

fn rrule_frequency(rule: a.RecurrenceRule) -> a.Frequency {
  a.rrule_to_options(rule).frequency
}

fn rrule_interval(rule: a.RecurrenceRule) -> Int {
  a.rrule_to_options(rule).interval
}

fn step_schedule(iterator iterator: a.OccurrenceIterator) -> a.IterStep {
  let assert Ok(value) = a.schedule_step(iterator)
  value
}
