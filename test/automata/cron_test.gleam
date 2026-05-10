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

pub fn parse_accepts_yearly_nickname_test() {
  cron.parse("@yearly")
  |> should.equal(
    Ok(cron_ast.RawCron(
      minute: "0",
      hour: "0",
      day_of_month: "1",
      month: "1",
      day_of_week: "*",
    )),
  )
}

pub fn parse_accepts_annually_alias_for_yearly_test() {
  cron.parse("@annually")
  |> should.equal(cron.parse("@yearly"))
}

pub fn parse_accepts_monthly_nickname_test() {
  cron.parse("@monthly")
  |> should.equal(
    Ok(cron_ast.RawCron(
      minute: "0",
      hour: "0",
      day_of_month: "1",
      month: "*",
      day_of_week: "*",
    )),
  )
}

pub fn parse_accepts_weekly_nickname_test() {
  cron.parse("@weekly")
  |> should.equal(
    Ok(cron_ast.RawCron(
      minute: "0",
      hour: "0",
      day_of_month: "*",
      month: "*",
      day_of_week: "0",
    )),
  )
}

pub fn parse_accepts_daily_nickname_test() {
  cron.parse("@daily")
  |> should.equal(
    Ok(cron_ast.RawCron(
      minute: "0",
      hour: "0",
      day_of_month: "*",
      month: "*",
      day_of_week: "*",
    )),
  )
}

pub fn parse_accepts_midnight_alias_for_daily_test() {
  cron.parse("@midnight")
  |> should.equal(cron.parse("@daily"))
}

pub fn parse_accepts_hourly_nickname_test() {
  cron.parse("@hourly")
  |> should.equal(
    Ok(cron_ast.RawCron(
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
  cron.parse("@HOURLY") |> should.equal(cron.parse("@hourly"))
}

pub fn parse_rejects_reboot_nickname_test() {
  // `@reboot` is recognised but has no 5-field equivalent (it is a
  // startup hook, not a recurring schedule). The parser surfaces it
  // with a dedicated variant so callers can distinguish it from a
  // typo.
  cron.parse("@reboot")
  |> should.equal(Error(cron_parser.RebootNotSupported(value: "@reboot")))
}

pub fn parse_rejects_unknown_nickname_test() {
  cron.parse("@hourly_oops")
  |> should.equal(
    Error(cron_parser.UnsupportedSyntax(
      field: cron_ast.Expression,
      value: "@hourly_oops",
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

  cron.matches(spec, at: vdt(2026, 5, 11, 9, 30, 0))
  |> should.equal(True)
  cron.matches(spec, at: vdt(2026, 5, 11, 9, 31, 0))
  |> should.equal(False)
  cron.matches(spec, at: vdt(2026, 5, 16, 9, 30, 0))
  |> should.equal(False)
}

pub fn next_after_finds_next_minute_slot_test() {
  let spec = parse_and_validate("*/15 9-17 * * 1-5")

  cron.next_after(spec, after: vdt(2026, 5, 11, 9, 7, 0))
  |> should.equal(Some(vdt(2026, 5, 11, 9, 15, 0)))
}

pub fn iterator_yields_occurrences_in_order_test() {
  let spec = parse_and_validate("0 9 * * 1-5")

  let first_iterator =
    cron.iterator_after(
      spec,
      boundary: schedule_ast.Exclusive(vdt(2026, 5, 11, 8, 0, 0)),
    )

  let assert cron_iterator.Yield(first_at, second_iterator) =
    cron_iterator.step(first_iterator)
  first_at |> should.equal(vdt(2026, 5, 11, 9, 0, 0))

  let assert cron_iterator.Yield(second_at, _) =
    cron_iterator.step(second_iterator)
  second_at |> should.equal(vdt(2026, 5, 12, 9, 0, 0))
}

pub fn builder_round_trips_to_valid_cron_test() {
  cron.builder()
  |> cron.with_minute(cron.every(15))
  |> cron.with_hour(cron.between(from: 9, to: 17))
  |> cron.with_day_of_week(cron.one_of([cron.item_range(from: 1, to: 5)]))
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
    after: vdt(2026, 1, 1, 0, 0, 0),
  )
  |> should.equal(Some(vdt(2027, 1, 1, 0, 0, 0)))
}

pub fn valid_cron_accessors_expose_selectors_test() {
  let spec = parse_and_validate("0 0 1 1 *")

  cron_validator.day_of_month(spec)
  |> should.equal(cron_validator.Values([cron_validator.Exact(1)]))
  cron_validator.month(spec)
  |> should.equal(cron_validator.Values([cron_validator.Exact(1)]))
  cron_validator.minute(spec)
  |> should.equal(cron_validator.Values([cron_validator.Exact(0)]))
  cron_validator.hour(spec)
  |> should.equal(cron_validator.Values([cron_validator.Exact(0)]))
  cron_validator.day_of_week(spec)
  |> should.equal(cron_validator.Any)
}

pub fn parse_rejects_empty_input_test() {
  cron.parse("")
  |> should.equal(Error(cron_parser.InvalidExpression(value: "")))
}

pub fn parse_rejects_too_few_fields_test() {
  cron.parse("0 0 * *")
  |> should.equal(Error(cron_parser.InvalidFieldCount(expected: 5, actual: 4)))
}

pub fn parse_collapses_consecutive_whitespace_test() {
  // Multiple spaces are treated as a single separator; this should
  // succeed rather than produce an `EmptyField` error.
  cron.parse("0  *   *  *  *")
  |> should.equal(
    Ok(cron_ast.RawCron(
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

  cron_validator.month(spec)
  |> should.equal(cron_validator.Values([cron_validator.Exact(1)]))
}

pub fn validate_accepts_lowercase_month_aliases_test() {
  let spec = parse_and_validate("0 0 1 dec *")

  cron_validator.month(spec)
  |> should.equal(cron_validator.Values([cron_validator.Exact(12)]))
}

pub fn validate_accepts_day_of_week_aliases_test() {
  let spec = parse_and_validate("0 0 * * SUN")

  cron_validator.day_of_week(spec)
  |> should.equal(cron_validator.Values([cron_validator.Exact(0)]))
}

pub fn validate_rejects_unknown_alias_test() {
  let assert Ok(raw) = cron.parse("0 0 * * FOO")

  cron.validate(raw)
  |> should.equal(
    Error(cron_validator.InvalidAlias(field: cron_ast.DayOfWeek, value: "FOO")),
  )
}

pub fn validate_rejects_alias_in_numeric_field_test() {
  let assert Ok(raw) = cron.parse("JAN 0 * * *")

  cron.validate(raw)
  |> should.equal(
    Error(cron_validator.InvalidNumber(field: cron_ast.Minute, value: "JAN")),
  )
}

pub fn validate_rejects_unsupported_syntax_test() {
  let assert Ok(raw) = cron.parse("0 0 L * *")

  cron.validate(raw)
  |> should.equal(
    Error(cron_validator.UnsupportedSyntax(
      field: cron_ast.DayOfMonth,
      value: "L",
    )),
  )
}

pub fn validate_accepts_uppercase_day_of_week_comma_aliases_test() {
  // Regression for case-folding bug where the early reserved-Quartz-char
  // check rejected any input containing `L`, `W`, `H` as a substring,
  // including legitimate alias tokens like `WED`. Only the uppercase
  // comma path was affected because lowercase aliases use `w`, `l`, `h`
  // and dash-ranges did not include WED in the dropped substrings.
  let spec = parse_and_validate("0 0 * * MON,WED,FRI")

  cron_validator.day_of_week(spec)
  |> should.equal(
    cron_validator.Values([
      cron_validator.Exact(1),
      cron_validator.Exact(3),
      cron_validator.Exact(5),
    ]),
  )
}

pub fn validate_accepts_uppercase_month_comma_aliases_test() {
  // Same bug as above, surfaced via the `L` in `JUL`.
  let spec = parse_and_validate("0 0 1 JAN,JUL *")

  cron_validator.month(spec)
  |> should.equal(
    cron_validator.Values([cron_validator.Exact(1), cron_validator.Exact(7)]),
  )
}

pub fn validate_unsupported_syntax_reported_per_token_test() {
  // After moving the reserved-syntax check past the comma split, a
  // multi-token field with one Quartz-extension token reports the
  // offending token, not the whole field. `15W` is Quartz "nearest
  // weekday to the 15th" — unsupported here.
  let assert Ok(raw) = cron.parse("0 0 15W,20 * *")

  cron.validate(raw)
  |> should.equal(
    Error(cron_validator.UnsupportedSyntax(
      field: cron_ast.DayOfMonth,
      value: "15W",
    )),
  )
}

pub fn validate_rejects_zero_step_test() {
  let assert Ok(raw) = cron.parse("*/0 * * * *")

  cron.validate(raw)
  |> should.equal(
    Error(cron_validator.InvalidStep(field: cron_ast.Minute, value: "*/0")),
  )
}

pub fn validate_rejects_reversed_range_test() {
  let assert Ok(raw) = cron.parse("0 17-9 * * *")

  cron.validate(raw)
  |> should.equal(
    Error(cron_validator.InvalidRange(field: cron_ast.Hour, value: "17-9")),
  )
}

pub fn validate_rejects_empty_list_item_test() {
  let assert Ok(raw) = cron.parse("0,, * * * *")

  cron.validate(raw)
  |> should.equal(
    Error(cron_validator.InvalidList(field: cron_ast.Minute, value: "0,,")),
  )
}

pub fn validate_rejects_bare_comma_in_minute_test() {
  let assert Ok(raw) = cron.parse(", * * * *")

  cron.validate(raw)
  |> should.equal(
    Error(cron_validator.InvalidList(field: cron_ast.Minute, value: ",")),
  )
}

pub fn validate_rejects_bare_comma_in_hour_test() {
  let assert Ok(raw) = cron.parse("* , * * *")

  cron.validate(raw)
  |> should.equal(
    Error(cron_validator.InvalidList(field: cron_ast.Hour, value: ",")),
  )
}

pub fn validate_rejects_bare_comma_in_day_of_month_test() {
  let assert Ok(raw) = cron.parse("* * , * *")

  cron.validate(raw)
  |> should.equal(
    Error(cron_validator.InvalidList(field: cron_ast.DayOfMonth, value: ",")),
  )
}

pub fn validate_rejects_bare_comma_in_month_test() {
  let assert Ok(raw) = cron.parse("* * * , *")

  cron.validate(raw)
  |> should.equal(
    Error(cron_validator.InvalidList(field: cron_ast.Month, value: ",")),
  )
}

pub fn validate_rejects_bare_comma_in_day_of_week_test() {
  let assert Ok(raw) = cron.parse("* * * * ,")

  cron.validate(raw)
  |> should.equal(
    Error(cron_validator.InvalidList(field: cron_ast.DayOfWeek, value: ",")),
  )
}

pub fn day_of_week_normalizes_seven_to_zero_test() {
  // 0 and 7 both mean Sunday in UNIX cron; the normalised set must
  // contain a single 0.
  let spec = parse_and_validate("0 0 * * 0,7")

  cron_validator.selector_values(
    cron_validator.day_of_week(spec),
    0,
    6,
    normalize_day_of_week: True,
  )
  |> should.equal([0])
}

pub fn day_of_week_seven_alone_normalizes_to_zero_test() {
  let spec = parse_and_validate("0 0 * * 7")

  cron_validator.selector_values(
    cron_validator.day_of_week(spec),
    0,
    6,
    normalize_day_of_week: True,
  )
  |> should.equal([0])
}

pub fn matches_step_with_offset_test() {
  // 5/15 means: starting at 5, every 15. Concretely: 5, 20, 35, 50.
  let spec = parse_and_validate("5/15 * * * *")

  cron.matches(spec, at: vdt(2026, 5, 11, 9, 5, 0)) |> should.equal(True)
  cron.matches(spec, at: vdt(2026, 5, 11, 9, 20, 0)) |> should.equal(True)
  cron.matches(spec, at: vdt(2026, 5, 11, 9, 35, 0)) |> should.equal(True)
  cron.matches(spec, at: vdt(2026, 5, 11, 9, 50, 0)) |> should.equal(True)
  cron.matches(spec, at: vdt(2026, 5, 11, 9, 0, 0)) |> should.equal(False)
}

pub fn matches_range_step_test() {
  // 9-17/2 means: 9, 11, 13, 15, 17.
  let spec = parse_and_validate("0 9-17/2 * * *")

  cron.matches(spec, at: vdt(2026, 5, 11, 9, 0, 0)) |> should.equal(True)
  cron.matches(spec, at: vdt(2026, 5, 11, 13, 0, 0)) |> should.equal(True)
  cron.matches(spec, at: vdt(2026, 5, 11, 17, 0, 0)) |> should.equal(True)
  cron.matches(spec, at: vdt(2026, 5, 11, 10, 0, 0)) |> should.equal(False)
}

pub fn matches_dom_dow_or_semantics_test() {
  // UNIX cron: when both DOM and DOW are restricted, a date matches
  // if either constraint is satisfied (OR, not AND). 4/31 is itself
  // impossible, but 4 month + Monday DOW must still produce hits.
  let spec = parse_and_validate("0 0 31 4 1")

  cron.matches(spec, at: vdt(2026, 4, 6, 0, 0, 0)) |> should.equal(True)
  cron.matches(spec, at: vdt(2026, 4, 5, 0, 0, 0)) |> should.equal(False)
}

pub fn builder_every_from_round_trips_test() {
  cron.builder()
  |> cron.with_minute(cron.every_from(start: 5, step: 15))
  |> cron.with_hour(cron.any())
  |> cron.with_day_of_month(cron.any())
  |> cron.with_month(cron.any())
  |> cron.with_day_of_week(cron.any())
  |> cron.build
  |> should.equal(Ok(parse_and_validate("5/15 * * * *")))
}

pub fn builder_every_between_round_trips_test() {
  cron.builder()
  |> cron.with_minute(cron.at(value: 0))
  |> cron.with_hour(cron.every_between(from: 9, to: 17, step: 2))
  |> cron.with_day_of_month(cron.any())
  |> cron.with_month(cron.any())
  |> cron.with_day_of_week(cron.any())
  |> cron.build
  |> should.equal(Ok(parse_and_validate("0 9-17/2 * * *")))
}
