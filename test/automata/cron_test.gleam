import automata as a
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/time/calendar
import gleeunit/should

fn parse_and_validate(input: String) -> a.Cron {
  let assert Ok(raw) = a.cron_parse_raw(input: input)
  let assert Ok(spec) = a.cron_validate(raw: raw)
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

pub fn parse_splits_unix_fields_test() {
  a.cron_parse_raw(input: "*/15 9-17 * * MON-FRI")
  |> should.equal(
    Ok(a.RawCron(
      minute: "*/15",
      hour: "9-17",
      day_of_month: "*",
      month: "*",
      day_of_week: "MON-FRI",
    )),
  )
}

pub fn parse_accepts_yearly_nickname_test() {
  a.cron_parse_raw(input: "@yearly")
  |> should.equal(
    Ok(a.RawCron(
      minute: "0",
      hour: "0",
      day_of_month: "1",
      month: "1",
      day_of_week: "*",
    )),
  )
}

pub fn parse_accepts_annually_alias_for_yearly_test() {
  a.cron_parse_raw(input: "@annually")
  |> should.equal(a.cron_parse_raw(input: "@yearly"))
}

pub fn parse_accepts_monthly_nickname_test() {
  a.cron_parse_raw(input: "@monthly")
  |> should.equal(
    Ok(a.RawCron(
      minute: "0",
      hour: "0",
      day_of_month: "1",
      month: "*",
      day_of_week: "*",
    )),
  )
}

pub fn parse_accepts_weekly_nickname_test() {
  a.cron_parse_raw(input: "@weekly")
  |> should.equal(
    Ok(a.RawCron(
      minute: "0",
      hour: "0",
      day_of_month: "*",
      month: "*",
      day_of_week: "0",
    )),
  )
}

pub fn parse_accepts_daily_nickname_test() {
  a.cron_parse_raw(input: "@daily")
  |> should.equal(
    Ok(a.RawCron(
      minute: "0",
      hour: "0",
      day_of_month: "*",
      month: "*",
      day_of_week: "*",
    )),
  )
}

pub fn parse_accepts_midnight_alias_for_daily_test() {
  a.cron_parse_raw(input: "@midnight")
  |> should.equal(a.cron_parse_raw(input: "@daily"))
}

pub fn parse_accepts_hourly_nickname_test() {
  a.cron_parse_raw(input: "@hourly")
  |> should.equal(
    Ok(a.RawCron(
      minute: "0",
      hour: "*",
      day_of_month: "*",
      month: "*",
      day_of_week: "*",
    )),
  )
}

pub fn parse_accepts_uppercase_nickname_test() {
  // The Vixie nickname table is case-insensitive in practice
  // (croniter, robfig/cron, node-cron, Quartz "@hourly" all accept
  // both cases).
  a.cron_parse_raw(input: "@HOURLY")
  |> should.equal(a.cron_parse_raw(input: "@hourly"))
}

pub fn parse_rejects_reboot_nickname_test() {
  // `@reboot` is recognised but has no 5-field equivalent (it is a
  // startup hook, not a recurring schedule). The parser surfaces it
  // with a dedicated variant so callers can distinguish it from a
  // typo.
  a.cron_parse_raw(input: "@reboot")
  |> should.equal(Error(a.CronParseRebootNotSupported(value: "@reboot")))
}

pub fn parse_rejects_unknown_nickname_test() {
  a.cron_parse_raw(input: "@hourly_oops")
  |> should.equal(
    Error(a.CronParseUnsupportedSyntax(
      field: a.CronExpression,
      value: "@hourly_oops",
    )),
  )
}

pub fn validate_rejects_out_of_range_minute_test() {
  let assert Ok(raw) = a.cron_parse_raw(input: "60 * * * *")

  a.cron_validate(raw: raw)
  |> should.equal(
    Error(a.CronOutOfRange(field: a.CronMinute, min: 0, max: 59, actual: 60)),
  )
}

pub fn validate_rejects_impossible_date_test() {
  let assert Ok(raw) = a.cron_parse_raw(input: "0 0 31 4 *")

  a.cron_validate(raw: raw)
  |> should.equal(Error(a.CronImpossibleDate(day_of_month: "31", month: "4")))
}

pub fn validate_keeps_dom_dow_or_semantics_test() {
  let spec = parse_and_validate("0 0 31 4 1")

  a.cron_to_string(spec: spec) |> should.equal("0 0 31 4 1")
}

pub fn matches_business_hours_test() {
  let spec = parse_and_validate("*/15 9-17 * * 1-5")

  matches_cron(spec: spec, at: vdt(2026, 5, 11, 9, 30, 0))
  |> should.equal(True)
  matches_cron(spec: spec, at: vdt(2026, 5, 11, 9, 31, 0))
  |> should.equal(False)
  matches_cron(spec: spec, at: vdt(2026, 5, 16, 9, 30, 0))
  |> should.equal(False)
}

pub fn next_after_finds_next_minute_slot_test() {
  let spec = parse_and_validate("*/15 9-17 * * 1-5")

  next_cron(spec: spec, after: vdt(2026, 5, 11, 9, 7, 0))
  |> should.equal(Some(vdt(2026, 5, 11, 9, 15, 0)))
}

pub fn iterator_yields_occurrences_in_order_test() {
  let spec = parse_and_validate("0 9 * * 1-5")

  let first_iterator =
    iterate_cron(spec: spec, boundary: a.Exclusive(vdt(2026, 5, 11, 8, 0, 0)))

  let assert a.Yield(first_at, second_iterator) =
    step_schedule(iterator: first_iterator)
  first_at |> should.equal(vdt(2026, 5, 11, 9, 0, 0))

  let assert a.Yield(second_at, _) = step_schedule(iterator: second_iterator)
  second_at |> should.equal(vdt(2026, 5, 12, 9, 0, 0))
}

pub fn builder_round_trips_to_valid_cron_test() {
  a.cron_options()
  |> old_cron_with_minute(old_cron_every(step: 15))
  |> old_cron_with_hour(old_cron_between(from: 9, to: 17))
  |> old_cron_with_day_of_week(
    old_cron_one_of(items: [old_cron_item_range(from: 1, to: 5)]),
  )
  |> old_cron_build
  |> should.equal(Ok(parse_and_validate("*/15 9-17 * * 1-5")))
}

pub fn builder_rejects_empty_selector_test() {
  a.cron_options()
  |> old_cron_with_minute(old_cron_one_of(items: []))
  |> old_cron_build
  |> should.equal(Error(a.CronInvalidList(field: a.CronMinute, value: "")))
}

pub fn builder_reports_negative_value_as_out_of_range_test() {
  // The builder used to render -1 into "-1" and parse it back, which
  // read as a malformed range.
  a.cron_options()
  |> old_cron_with_minute(old_cron_at(value: -1))
  |> old_cron_build
  |> should.equal(
    Error(a.CronOutOfRange(field: a.CronMinute, min: 0, max: 59, actual: -1)),
  )
}

pub fn builder_reports_negative_range_start_as_out_of_range_test() {
  a.cron_options()
  |> old_cron_with_hour(old_cron_between(from: -3, to: 5))
  |> old_cron_build
  |> should.equal(
    Error(a.CronOutOfRange(field: a.CronHour, min: 0, max: 23, actual: -3)),
  )
}

pub fn builder_reports_negative_step_start_as_out_of_range_test() {
  a.cron_options()
  |> old_cron_with_minute(old_cron_every_from(start: -5, step: 10))
  |> old_cron_build
  |> should.equal(
    Error(a.CronOutOfRange(field: a.CronMinute, min: 0, max: 59, actual: -5)),
  )
}

pub fn builder_reports_reversed_range_test() {
  a.cron_options()
  |> old_cron_with_hour(old_cron_between(from: 17, to: 9))
  |> old_cron_build
  |> should.equal(Error(a.CronInvalidRange(field: a.CronHour, value: "17-9")))
}

pub fn builder_reports_bad_step_test() {
  a.cron_options()
  |> old_cron_with_day_of_month(old_cron_every(step: 0))
  |> old_cron_build
  |> should.equal(
    Error(a.CronInvalidStep(field: a.CronDayOfMonth, value: "*/0")),
  )
}

pub fn builder_reports_impossible_date_test() {
  a.cron_options()
  |> old_cron_with_day_of_month(old_cron_at(value: 31))
  |> old_cron_with_month(old_cron_at(value: 2))
  |> old_cron_build
  |> should.equal(Error(a.CronImpossibleDate(day_of_month: "31", month: "2")))
}

pub fn next_after_is_exclusive_test() {
  next_cron(
    spec: parse_and_validate("0 0 1 1 *"),
    after: vdt(2026, 1, 1, 0, 0, 0),
  )
  |> should.equal(Some(vdt(2027, 1, 1, 0, 0, 0)))
}

// Regression for the year-wrap off-by-one in #30: when the cron spec
// fixes both month and day-of-month and the anchor falls after that
// day in some later month, the month-roll used to carry the anchor's
// day across the boundary, causing `find_next` to scan past day 1 of
// the matching month and land an extra year out.
pub fn next_after_fixed_month_and_day_wraps_year_test() {
  next_cron(
    spec: parse_and_validate("0 0 1 1 *"),
    after: vdt(2026, 12, 15, 0, 0, 0),
  )
  |> should.equal(Some(vdt(2027, 1, 1, 0, 0, 0)))
}

pub fn next_after_fixed_month_and_day_mid_year_test() {
  next_cron(
    spec: parse_and_validate("0 0 15 6 *"),
    after: vdt(2026, 12, 31, 0, 0, 0),
  )
  |> should.equal(Some(vdt(2027, 6, 15, 0, 0, 0)))
}

// The same root cause also affected fixed-month + wildcard-day specs:
// crossing the month boundary while preserving the anchor day meant
// the iterator missed every earlier day of the new matching month.
pub fn next_after_fixed_month_wildcard_day_starts_at_day_one_test() {
  next_cron(
    spec: parse_and_validate("0 0 * 6 *"),
    after: vdt(2026, 12, 31, 0, 0, 0),
  )
  |> should.equal(Some(vdt(2027, 6, 1, 0, 0, 0)))
}

pub fn iterator_after_fixed_month_and_day_wraps_year_test() {
  let spec = parse_and_validate("0 0 1 1 *")

  let assert a.Yield(first_at, _) =
    step_schedule(iterator: iterate_cron(
      spec: spec,
      boundary: a.Exclusive(vdt(2026, 12, 15, 0, 0, 0)),
    ))

  first_at |> should.equal(vdt(2027, 1, 1, 0, 0, 0))
}

pub fn valid_cron_accessors_expose_selectors_test() {
  let spec = parse_and_validate("0 0 1 1 *")

  cron_day_of_month(spec)
  |> should.equal(a.CronValues([a.CronExact(1)]))
  cron_month(spec)
  |> should.equal(a.CronValues([a.CronExact(1)]))
  cron_minute(spec)
  |> should.equal(a.CronValues([a.CronExact(0)]))
  cron_hour(spec)
  |> should.equal(a.CronValues([a.CronExact(0)]))
  cron_day_of_week(spec)
  |> should.equal(a.CronAny)
}

pub fn parse_rejects_empty_input_test() {
  a.cron_parse_raw(input: "")
  |> should.equal(Error(a.CronParseInvalidExpression(value: "")))
}

pub fn parse_rejects_too_few_fields_test() {
  a.cron_parse_raw(input: "0 0 * *")
  |> should.equal(Error(a.CronParseInvalidFieldCount(expected: 5, actual: 4)))
}

pub fn parse_collapses_consecutive_whitespace_test() {
  // Multiple spaces are treated as a single separator; this should
  // succeed rather than produce an `EmptyField` error.
  a.cron_parse_raw(input: "0  *   *  *  *")
  |> should.equal(
    Ok(a.RawCron(
      minute: "0",
      hour: "*",
      day_of_month: "*",
      month: "*",
      day_of_week: "*",
    )),
  )
}

pub fn validate_accepts_month_aliases_test() {
  let spec = parse_and_validate("0 0 1 JAN *")

  cron_month(spec)
  |> should.equal(a.CronValues([a.CronExact(1)]))
}

pub fn validate_accepts_lowercase_month_aliases_test() {
  let spec = parse_and_validate("0 0 1 dec *")

  cron_month(spec)
  |> should.equal(a.CronValues([a.CronExact(12)]))
}

pub fn validate_accepts_day_of_week_aliases_test() {
  let spec = parse_and_validate("0 0 * * SUN")

  cron_day_of_week(spec)
  |> should.equal(a.CronValues([a.CronExact(0)]))
}

pub fn validate_rejects_unknown_alias_test() {
  let assert Ok(raw) = a.cron_parse_raw(input: "0 0 * * FOO")

  a.cron_validate(raw: raw)
  |> should.equal(
    Error(a.CronInvalidAlias(field: a.CronDayOfWeek, value: "FOO")),
  )
}

pub fn validate_rejects_alias_in_numeric_field_test() {
  let assert Ok(raw) = a.cron_parse_raw(input: "JAN 0 * * *")

  a.cron_validate(raw: raw)
  |> should.equal(Error(a.CronInvalidNumber(field: a.CronMinute, value: "JAN")))
}

pub fn validate_rejects_unsupported_syntax_test() {
  let assert Ok(raw) = a.cron_parse_raw(input: "0 0 L * *")

  a.cron_validate(raw: raw)
  |> should.equal(
    Error(a.CronUnsupportedSyntax(field: a.CronDayOfMonth, value: "L")),
  )
}

pub fn validate_accepts_uppercase_day_of_week_comma_aliases_test() {
  // Regression for case-folding bug where the early reserved-Quartz-char
  // check rejected any input containing `L`, `W`, `H` as a substring,
  // including legitimate alias tokens like `WED`. Only the uppercase
  // comma path was affected because lowercase aliases use `w`, `l`, `h`
  // and dash-ranges did not include WED in the dropped substrings.
  let spec = parse_and_validate("0 0 * * MON,WED,FRI")

  cron_day_of_week(spec)
  |> should.equal(
    a.CronValues([
      a.CronExact(1),
      a.CronExact(3),
      a.CronExact(5),
    ]),
  )
}

pub fn validate_accepts_uppercase_month_comma_aliases_test() {
  // Same bug as above, surfaced via the `L` in `JUL`.
  let spec = parse_and_validate("0 0 1 JAN,JUL *")

  cron_month(spec)
  |> should.equal(a.CronValues([a.CronExact(1), a.CronExact(7)]))
}

pub fn validate_unsupported_syntax_reported_per_token_test() {
  // After moving the reserved-syntax check past the comma split, a
  // multi-token field with one Quartz-extension token reports the
  // offending token, not the whole field. `15W` is Quartz "nearest
  // weekday to the 15th" — unsupported here.
  let assert Ok(raw) = a.cron_parse_raw(input: "0 0 15W,20 * *")

  a.cron_validate(raw: raw)
  |> should.equal(
    Error(a.CronUnsupportedSyntax(field: a.CronDayOfMonth, value: "15W")),
  )
}

pub fn validate_rejects_zero_step_test() {
  let assert Ok(raw) = a.cron_parse_raw(input: "*/0 * * * *")

  a.cron_validate(raw: raw)
  |> should.equal(Error(a.CronInvalidStep(field: a.CronMinute, value: "*/0")))
}

pub fn validate_rejects_reversed_range_test() {
  let assert Ok(raw) = a.cron_parse_raw(input: "0 17-9 * * *")

  a.cron_validate(raw: raw)
  |> should.equal(Error(a.CronInvalidRange(field: a.CronHour, value: "17-9")))
}

pub fn validate_rejects_empty_list_item_test() {
  let assert Ok(raw) = a.cron_parse_raw(input: "0,, * * * *")

  a.cron_validate(raw: raw)
  |> should.equal(Error(a.CronInvalidList(field: a.CronMinute, value: "0,,")))
}

pub fn validate_rejects_bare_comma_in_minute_test() {
  let assert Ok(raw) = a.cron_parse_raw(input: ", * * * *")

  a.cron_validate(raw: raw)
  |> should.equal(Error(a.CronInvalidList(field: a.CronMinute, value: ",")))
}

pub fn validate_rejects_bare_comma_in_hour_test() {
  let assert Ok(raw) = a.cron_parse_raw(input: "* , * * *")

  a.cron_validate(raw: raw)
  |> should.equal(Error(a.CronInvalidList(field: a.CronHour, value: ",")))
}

pub fn validate_rejects_bare_comma_in_day_of_month_test() {
  let assert Ok(raw) = a.cron_parse_raw(input: "* * , * *")

  a.cron_validate(raw: raw)
  |> should.equal(Error(a.CronInvalidList(field: a.CronDayOfMonth, value: ",")))
}

pub fn validate_rejects_bare_comma_in_month_test() {
  let assert Ok(raw) = a.cron_parse_raw(input: "* * * , *")

  a.cron_validate(raw: raw)
  |> should.equal(Error(a.CronInvalidList(field: a.CronMonth, value: ",")))
}

pub fn validate_rejects_bare_comma_in_day_of_week_test() {
  let assert Ok(raw) = a.cron_parse_raw(input: "* * * * ,")

  a.cron_validate(raw: raw)
  |> should.equal(Error(a.CronInvalidList(field: a.CronDayOfWeek, value: ",")))
}

pub fn day_of_week_normalizes_seven_to_zero_test() {
  // 0 and 7 both mean Sunday in UNIX cron; the normalised set must
  // contain a single 0.
  let spec = parse_and_validate("0 0 * * 0,7")

  old_cron_validator_selector_values(
    cron_day_of_week(spec),
    0,
    6,
    normalize_day_of_week: True,
  )
  |> should.equal([0])
}

pub fn day_of_week_seven_alone_normalizes_to_zero_test() {
  let spec = parse_and_validate("0 0 * * 7")

  old_cron_validator_selector_values(
    cron_day_of_week(spec),
    0,
    6,
    normalize_day_of_week: True,
  )
  |> should.equal([0])
}

pub fn matches_step_with_offset_test() {
  // 5/15 means: starting at 5, every 15. Concretely: 5, 20, 35, 50.
  let spec = parse_and_validate("5/15 * * * *")

  matches_cron(spec: spec, at: vdt(2026, 5, 11, 9, 5, 0)) |> should.equal(True)
  matches_cron(spec: spec, at: vdt(2026, 5, 11, 9, 20, 0)) |> should.equal(True)
  matches_cron(spec: spec, at: vdt(2026, 5, 11, 9, 35, 0)) |> should.equal(True)
  matches_cron(spec: spec, at: vdt(2026, 5, 11, 9, 50, 0)) |> should.equal(True)
  matches_cron(spec: spec, at: vdt(2026, 5, 11, 9, 0, 0)) |> should.equal(False)
}

pub fn matches_range_step_test() {
  // 9-17/2 means: 9, 11, 13, 15, 17.
  let spec = parse_and_validate("0 9-17/2 * * *")

  matches_cron(spec: spec, at: vdt(2026, 5, 11, 9, 0, 0)) |> should.equal(True)
  matches_cron(spec: spec, at: vdt(2026, 5, 11, 13, 0, 0)) |> should.equal(True)
  matches_cron(spec: spec, at: vdt(2026, 5, 11, 17, 0, 0)) |> should.equal(True)
  matches_cron(spec: spec, at: vdt(2026, 5, 11, 10, 0, 0))
  |> should.equal(False)
}

pub fn matches_dom_dow_or_semantics_test() {
  // UNIX cron: when both DOM and DOW are restricted, a date matches
  // if either constraint is satisfied (OR, not AND). 4/31 is itself
  // impossible, but 4 month + Monday DOW must still produce hits.
  let spec = parse_and_validate("0 0 31 4 1")

  matches_cron(spec: spec, at: vdt(2026, 4, 6, 0, 0, 0)) |> should.equal(True)
  matches_cron(spec: spec, at: vdt(2026, 4, 5, 0, 0, 0)) |> should.equal(False)
}

pub fn builder_every_from_round_trips_test() {
  a.cron_options()
  |> old_cron_with_minute(old_cron_every_from(start: 5, step: 15))
  |> old_cron_with_hour(old_cron_any())
  |> old_cron_with_day_of_month(old_cron_any())
  |> old_cron_with_month(old_cron_any())
  |> old_cron_with_day_of_week(old_cron_any())
  |> old_cron_build
  |> should.equal(Ok(parse_and_validate("5/15 * * * *")))
}

pub fn builder_every_between_round_trips_test() {
  a.cron_options()
  |> old_cron_with_minute(old_cron_at(value: 0))
  |> old_cron_with_hour(old_cron_every_between(from: 9, to: 17, step: 2))
  |> old_cron_with_day_of_month(old_cron_any())
  |> old_cron_with_month(old_cron_any())
  |> old_cron_with_day_of_week(old_cron_any())
  |> old_cron_build
  |> should.equal(Ok(parse_and_validate("0 9-17/2 * * *")))
}

pub fn next_after_string_returns_next_occurrence_test() {
  old_cron_next_after_string(expr: "0 9 * * 1", at: vdt(2026, 5, 11, 8, 0, 0))
  |> should.equal(Ok(Some(vdt(2026, 5, 11, 9, 0, 0))))
}

pub fn next_after_string_matches_manual_pipeline_test() {
  let expr = "*/15 9-17 * * MON-FRI"
  let at = vdt(2026, 5, 11, 9, 7, 0)
  let manual =
    parse_and_validate(expr)
    |> next_cron(after: at)

  old_cron_next_after_string(expr: expr, at: at)
  |> should.equal(Ok(manual))
}

pub fn next_after_string_reports_parse_error_test() {
  old_cron_next_after_string(expr: "0 0 * *", at: vdt(2026, 5, 11, 0, 0, 0))
  |> should.equal(
    Error(ParseFailure(a.CronParseInvalidFieldCount(expected: 5, actual: 4))),
  )
}

pub fn next_after_string_reports_validation_error_test() {
  let assert Error(ValidationFailure(_)) =
    old_cron_next_after_string(
      expr: "60 0 * * *",
      at: vdt(2026, 5, 11, 0, 0, 0),
    )
  Nil
}

// --- minute-granularity contract ---

pub fn matches_ignores_seconds_test() {
  // UNIX cron is minute-granular — any second within a matching minute fires.
  let assert Ok(raw) = a.cron_parse_raw(input: "30 * * * *")
  let assert Ok(spec) = a.cron_validate(raw: raw)

  matches_cron(spec: spec, at: vdt(2026, 5, 11, 9, 30, 0)) |> should.equal(True)
  matches_cron(spec: spec, at: vdt(2026, 5, 11, 9, 30, 1)) |> should.equal(True)
  matches_cron(spec: spec, at: vdt(2026, 5, 11, 9, 30, 30))
  |> should.equal(True)
  matches_cron(spec: spec, at: vdt(2026, 5, 11, 9, 30, 59))
  |> should.equal(True)
  matches_cron(spec: spec, at: vdt(2026, 5, 11, 9, 29, 59))
  |> should.equal(False)
  matches_cron(spec: spec, at: vdt(2026, 5, 11, 9, 31, 0))
  |> should.equal(False)
}

pub fn matches_every_minute_ignores_seconds_test() {
  let assert Ok(raw) = a.cron_parse_raw(input: "* * * * *")
  let assert Ok(spec) = a.cron_validate(raw: raw)

  matches_cron(spec: spec, at: vdt(2026, 5, 11, 12, 0, 0)) |> should.equal(True)
  matches_cron(spec: spec, at: vdt(2026, 5, 11, 12, 0, 30))
  |> should.equal(True)
  matches_cron(spec: spec, at: vdt(2026, 5, 11, 12, 0, 59))
  |> should.equal(True)
}

// --- step value range validation ---
// A step may be as large as the number of values in the field
// (max - min + 1); such a step fires once per cycle. croniter and cronie
// accept these (cronie only prints a warning). Expected firings come
// from croniter 7.0.0.

fn next_step_firing(expr: String) -> String {
  let assert Ok(Some(at)) =
    old_cron_next_after_string(expr: expr, at: vdt(2026, 5, 11, 12, 30, 0))
  raw_datetime_to_string(a.datetime_value(at))
}

pub fn validate_accepts_step_equal_to_minute_range_test() {
  next_step_firing("*/60 * * * *") |> should.equal("2026-05-11T13:00:00")
}

pub fn validate_accepts_step_equal_to_hour_range_test() {
  next_step_firing("0 */24 * * *") |> should.equal("2026-05-12T00:00:00")
}

pub fn validate_accepts_step_equal_to_day_of_month_range_test() {
  next_step_firing("0 0 */31 * *") |> should.equal("2026-06-01T00:00:00")
}

pub fn validate_accepts_step_equal_to_month_range_test() {
  next_step_firing("0 0 1 */12 *") |> should.equal("2027-01-01T00:00:00")
}

pub fn validate_accepts_step_equal_to_day_of_week_range_test() {
  // DoW range is 0..=7 (POSIX with 7 as alternate Sunday), so */8 keeps
  // only Sunday.
  next_step_firing("0 0 * * */8") |> should.equal("2026-05-17T00:00:00")
}

pub fn validate_rejects_step_above_hour_range_test() {
  let assert Ok(raw) = a.cron_parse_raw(input: "* */25 * * *")
  let assert Error(a.CronInvalidStep(field: f, value: _)) =
    a.cron_validate(raw: raw)
  f |> should.equal(a.CronHour)
}

pub fn validate_rejects_step_above_day_of_week_range_test() {
  let assert Ok(raw) = a.cron_parse_raw(input: "* * * * */9")
  let assert Error(a.CronInvalidStep(field: f, value: _)) =
    a.cron_validate(raw: raw)
  f |> should.equal(a.CronDayOfWeek)
}

pub fn validate_rejects_step_far_above_range_test() {
  let assert Ok(raw) = a.cron_parse_raw(input: "*/61 * * * *")
  let assert Error(a.CronInvalidStep(_, _)) = a.cron_validate(raw: raw)
}

pub fn validate_accepts_step_within_minute_range_test() {
  let assert Ok(raw) = a.cron_parse_raw(input: "*/30 * * * *")
  let assert Ok(_) = a.cron_validate(raw: raw)
}

pub fn validate_accepts_step_at_max_minus_min_boundary_test() {
  // For minute field 0..=59, max - min = 59. */59 is the strictest accepted
  // step — it still fires twice (at 0 and 59).
  let assert Ok(raw) = a.cron_parse_raw(input: "*/59 * * * *")
  let assert Ok(_) = a.cron_validate(raw: raw)
}

fn cron_day_of_month(spec: a.Cron) -> a.CronSelector {
  a.cron_to_options(spec).day_of_month
}

fn cron_day_of_week(spec: a.Cron) -> a.CronSelector {
  a.cron_to_options(spec).day_of_week
}

fn cron_hour(spec: a.Cron) -> a.CronSelector {
  a.cron_to_options(spec).hour
}

fn cron_minute(spec: a.Cron) -> a.CronSelector {
  a.cron_to_options(spec).minute
}

fn cron_month(spec: a.Cron) -> a.CronSelector {
  a.cron_to_options(spec).month
}

fn iterate_cron(
  spec spec: a.Cron,
  boundary boundary: a.Boundary,
) -> a.OccurrenceIterator {
  iterate_schedule(schedule: a.schedule_from_cron(spec), boundary: boundary)
}

fn iterate_schedule(
  schedule schedule: a.Schedule,
  boundary boundary: a.Boundary,
) -> a.OccurrenceIterator {
  let assert Ok(value) = a.schedule_iterator(schedule, boundary: boundary)
  value
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

fn matches_cron(spec spec: a.Cron, at at: a.ValidDateTime) -> Bool {
  matches_schedule(schedule: a.schedule_from_cron(spec), at: at)
}

fn matches_schedule(
  schedule schedule: a.Schedule,
  at at: a.ValidDateTime,
) -> Bool {
  let assert Ok(value) = a.schedule_matches(schedule, at: at)
  value
}

fn next_cron(
  spec spec: a.Cron,
  after after: a.ValidDateTime,
) -> option.Option(a.ValidDateTime) {
  next_schedule(schedule: a.schedule_from_cron(spec), after: after)
}

fn next_schedule(
  schedule schedule: a.Schedule,
  after after: a.ValidDateTime,
) -> option.Option(a.ValidDateTime) {
  let assert Ok(value) = a.schedule_next(schedule, after: after)
  value
}

fn old_cron_any() -> a.CronSelector {
  a.CronAny
}

fn old_cron_at(value value: Int) -> a.CronSelector {
  a.CronValues([a.CronExact(value)])
}

fn old_cron_between(from start: Int, to end: Int) -> a.CronSelector {
  a.CronValues([a.CronRange(start, end)])
}

fn old_cron_build(
  builder builder: a.CronOptions,
) -> Result(a.Cron, a.CronValidationError) {
  a.cron_new(builder)
}

fn old_cron_every(step step: Int) -> a.CronSelector {
  a.CronValues([a.CronStep(a.CronStepAny, step)])
}

fn old_cron_every_between(
  from start: Int,
  to end: Int,
  step step: Int,
) -> a.CronSelector {
  a.CronValues([a.CronStep(a.CronStepRange(start, end), step)])
}

fn old_cron_every_from(start start: Int, step step: Int) -> a.CronSelector {
  a.CronValues([a.CronStep(a.CronStepExact(start), step)])
}

fn old_cron_item_range(from start: Int, to end: Int) -> a.CronItem {
  a.CronRange(start, end)
}

fn old_cron_one_of(items items: List(a.CronItem)) -> a.CronSelector {
  a.CronValues(items)
}

fn old_cron_with_day_of_month(
  options: a.CronOptions,
  day_of_month: a.CronSelector,
) -> a.CronOptions {
  a.CronOptions(..options, day_of_month: day_of_month)
}

fn old_cron_with_day_of_week(
  options: a.CronOptions,
  day_of_week: a.CronSelector,
) -> a.CronOptions {
  a.CronOptions(..options, day_of_week: day_of_week)
}

fn old_cron_with_hour(
  options: a.CronOptions,
  hour: a.CronSelector,
) -> a.CronOptions {
  a.CronOptions(..options, hour: hour)
}

fn old_cron_with_minute(
  options: a.CronOptions,
  minute: a.CronSelector,
) -> a.CronOptions {
  a.CronOptions(..options, minute: minute)
}

fn old_cron_with_month(
  options: a.CronOptions,
  month: a.CronSelector,
) -> a.CronOptions {
  a.CronOptions(..options, month: month)
}

fn raw_datetime_to_string(value: a.DateTime) -> String {
  let assert Ok(valid) = a.datetime_validate(value)
  a.datetime_to_string(valid)
}

fn step_schedule(iterator iterator: a.OccurrenceIterator) -> a.IterStep {
  let assert Ok(value) = a.schedule_step(iterator)
  value
}

type CronTextError {
  ParseFailure(a.CronParseError)
  ValidationFailure(a.CronValidationError)
}

fn old_cron_next_after_string(
  expr expr: String,
  at at: a.ValidDateTime,
) -> Result(option.Option(a.ValidDateTime), CronTextError) {
  use raw <- result.try(
    a.cron_parse_raw(input: expr) |> result.map_error(ParseFailure),
  )
  use cron <- result.try(
    a.cron_validate(raw: raw) |> result.map_error(ValidationFailure),
  )
  Ok(next_cron(spec: cron, after: at))
}

fn old_cron_validator_selector_values(
  selector: a.CronSelector,
  _minimum: Int,
  _maximum: Int,
  normalize_day_of_week _normalize: Bool,
) -> List(Int) {
  let options = a.cron_options()
  let assert Ok(cron) =
    a.cron_new(a.CronOptions(..options, day_of_week: selector))
  list.filter([0, 1, 2, 3, 4, 5, 6], fn(day) {
    let assert Ok(at) =
      make_valid_datetime(
        year: 2026,
        month: 5,
        day: 10 + day,
        hour: 0,
        minute: 0,
        second: 0,
      )
    matches_cron(spec: cron, at: at)
  })
}

pub fn validate_rejects_signed_numbers_test() {
  // Vixie cron and croniter read unsigned digits only.
  let validate = fn(input) {
    let assert Ok(raw) = a.cron_parse_raw(input: input)
    a.cron_validate(raw: raw)
  }
  validate("+5 * * * *")
  |> should.equal(Error(a.CronInvalidNumber(a.CronMinute, "+5")))
  validate("1-+5 * * * *")
  |> should.equal(Error(a.CronInvalidNumber(a.CronMinute, "+5")))
  validate("*/+2 * * * *")
  |> should.equal(Error(a.CronInvalidStep(a.CronMinute, "*/+2")))
  validate("0 0 * * +1")
  |> should.equal(Error(a.CronInvalidAlias(a.CronDayOfWeek, "+1")))
}

fn validate_text(input: String) -> Result(a.Cron, a.CronValidationError) {
  let assert Ok(raw) = a.cron_parse_raw(input: input)
  a.cron_validate(raw: raw)
}

pub fn parse_splits_fields_on_tab_newline_and_carriage_return_test() {
  assert a.cron_parse_raw(input: "1\t2\n3\r4 5")
    == Ok(a.RawCron(
      minute: "1",
      hour: "2",
      day_of_month: "3",
      month: "4",
      day_of_week: "5",
    ))
}

pub fn value_seven_is_not_sunday_outside_day_of_week_test() {
  // Only the day-of-week field folds 7 into 0 (Sunday). 2026-07-07 is a
  // Tuesday, so "7 7 7 7 *" fires at 07:07 on that date.
  let schedule = a.schedule_from_cron(parse_and_validate("7 7 7 7 *"))
  assert a.schedule_matches(schedule, at: vdt(2026, 7, 7, 7, 7, 0)) == Ok(True)
  assert a.schedule_next(schedule, after: vdt(2026, 1, 1, 0, 0, 0))
    == Ok(Some(vdt(2026, 7, 7, 7, 7, 0)))
}

pub fn validate_accepts_single_value_ranges_test() {
  // A range whose two ends are equal selects exactly that value.
  let assert Ok(spec) = validate_text("5-5 5-5/2 * * *")
  assert a.cron_to_string(spec: spec) == "5-5 5-5/2 * * *"
  let schedule = a.schedule_from_cron(spec)
  assert a.schedule_next(schedule, after: vdt(2026, 1, 1, 0, 0, 0))
    == Ok(Some(vdt(2026, 1, 1, 5, 5, 0)))
  let options = a.cron_options()
  let assert Ok(typed) =
    a.cron_new(
      a.CronOptions(
        ..options,
        minute: a.CronValues([a.CronRange(5, 5)]),
        hour: a.CronValues([a.CronStep(a.CronStepRange(5, 5), 2)]),
      ),
    )
  assert a.cron_to_string(spec: typed) == "5-5 5-5/2 * * *"
}

pub fn validate_accepts_july_thirty_first_test() {
  assert result.is_ok(validate_text("0 0 31 7 *"))
}

pub fn validate_step_must_fit_field_span_test() {
  // A step may be at most the number of values in its field: 12 for months,
  // 31 for days of the month, 60 for minutes.
  assert result.is_ok(validate_text("0 0 */31 */12 *"))
  assert validate_text("0 0 * */13 *")
    == Error(a.CronInvalidStep(field: a.CronMonth, value: "*/13"))
  assert validate_text("0 0 */32 * *")
    == Error(a.CronInvalidStep(field: a.CronDayOfMonth, value: "*/32"))
  assert validate_text("*/0 * * * *")
    == Error(a.CronInvalidStep(field: a.CronMinute, value: "*/0"))
  assert validate_text("*/61 * * * *")
    == Error(a.CronInvalidStep(field: a.CronMinute, value: "*/61"))
}

pub fn validate_reports_missing_range_and_step_operands_test() {
  assert validate_text("/5 * * * *")
    == Error(a.CronInvalidStep(field: a.CronMinute, value: "/5"))
  assert validate_text("5- * * * *")
    == Error(a.CronInvalidRange(field: a.CronMinute, value: "5-"))
  assert validate_text("-5 * * * *")
    == Error(a.CronInvalidRange(field: a.CronMinute, value: "-5"))
  assert validate_text("5-/2 * * * *")
    == Error(a.CronInvalidRange(field: a.CronMinute, value: "5-"))
  assert validate_text("-5/2 * * * *")
    == Error(a.CronInvalidRange(field: a.CronMinute, value: "-5"))
}

pub fn validate_rejects_quartz_hash_letter_test() {
  assert validate_text("H * * * *")
    == Error(a.CronUnsupportedSyntax(field: a.CronMinute, value: "H"))
}
