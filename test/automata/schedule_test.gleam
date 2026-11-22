import automata/cron
import automata/cron/validator as cron_validator
import automata/rrule
import automata/rrule/validator as rule_validator
import automata/schedule
import automata/schedule/ast as schedule_ast
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

fn parse_and_validate_cron(input: String) -> cron_validator.ValidCron {
  let assert Ok(raw) = cron.parse(input)
  let assert Ok(spec) = cron.validate(raw)
  spec
}

fn parse_and_validate_rrule(input: String) -> rule_validator.ValidRRule {
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

pub fn shared_schedule_matches_cron_test() {
  let assert Ok(compiled) =
    schedule.from_cron(parse_and_validate_cron("*/30 9-17 * * 1-5"))

  schedule.matches(compiled, at: vdt(2026, 5, 11, 10, 0, 0))
  |> should.equal(True)

  schedule.next_after(compiled, after: vdt(2026, 5, 11, 10, 7, 0))
  |> should.equal(Some(vdt(2026, 5, 11, 10, 30, 0)))
}

pub fn shared_schedule_iterates_rrule_test() {
  let spec = parse_and_validate_rrule("FREQ=DAILY;COUNT=2;BYHOUR=9;BYMINUTE=0")
  let anchor = vdt(2026, 5, 1, 9, 0, 0)
  let assert Ok(compiled) = schedule.from_rrule(spec, anchor: anchor)

  let iterator =
    schedule.iterator_after(
      compiled,
      boundary: schedule_ast.Exclusive(vdt(2026, 5, 1, 8, 0, 0)),
    )

  let assert schedule.Yield(first_at, next_iterator) = schedule.step(iterator)
  first_at |> should.equal(vdt(2026, 5, 1, 9, 0, 0))

  let assert schedule.Yield(second_at, _) = schedule.step(next_iterator)
  second_at |> should.equal(vdt(2026, 5, 2, 9, 0, 0))
}

pub fn shared_schedule_next_after_preserves_rrule_seconds_test() {
  let spec = parse_and_validate_rrule("FREQ=DAILY;BYHOUR=9;BYMINUTE=0")
  let anchor = vdt(2026, 5, 1, 9, 0, 30)
  let assert Ok(compiled) = schedule.from_rrule(spec, anchor: anchor)

  schedule.next_after(compiled, after: vdt(2026, 5, 1, 9, 0, 0))
  |> should.equal(Some(vdt(2026, 5, 1, 9, 0, 30)))

  schedule.next_after(compiled, after: vdt(2026, 5, 1, 9, 0, 30))
  |> should.equal(Some(vdt(2026, 5, 2, 9, 0, 30)))
}

pub fn from_every_rejects_non_positive_interval_test() {
  schedule.from_every(interval_seconds: 0, anchor: vdt(2026, 5, 1, 0, 0, 0))
  |> should.equal(Error(schedule.EveryIntervalMustBePositive(actual: 0)))

  schedule.from_every(interval_seconds: -10, anchor: vdt(2026, 5, 1, 0, 0, 0))
  |> should.equal(Error(schedule.EveryIntervalMustBePositive(actual: -10)))
}

pub fn from_every_iterates_at_fixed_interval_test() {
  let assert Ok(compiled) =
    schedule.from_every(interval_seconds: 300, anchor: vdt(2026, 5, 1, 0, 0, 0))

  schedule.matches(compiled, at: vdt(2026, 5, 1, 0, 5, 0))
  |> should.equal(True)
  schedule.matches(compiled, at: vdt(2026, 5, 1, 0, 4, 59))
  |> should.equal(False)
  schedule.matches(compiled, at: vdt(2026, 4, 30, 23, 55, 0))
  |> should.equal(False)

  schedule.next_after(compiled, after: vdt(2026, 5, 1, 0, 0, 0))
  |> should.equal(Some(vdt(2026, 5, 1, 0, 5, 0)))

  schedule.next_after(compiled, after: vdt(2026, 5, 1, 0, 4, 59))
  |> should.equal(Some(vdt(2026, 5, 1, 0, 5, 0)))
}

pub fn from_every_iterator_yields_in_order_test() {
  let assert Ok(compiled) =
    schedule.from_every(interval_seconds: 60, anchor: vdt(2026, 5, 1, 0, 0, 0))

  let it =
    schedule.iterator_after(
      compiled,
      boundary: schedule_ast.Inclusive(vdt(2026, 5, 1, 0, 0, 0)),
    )

  let assert schedule.Yield(first_at, it1) = schedule.step(it)
  first_at |> should.equal(vdt(2026, 5, 1, 0, 0, 0))

  let assert schedule.Yield(second_at, it2) = schedule.step(it1)
  second_at |> should.equal(vdt(2026, 5, 1, 0, 1, 0))

  let assert schedule.Yield(third_at, _) = schedule.step(it2)
  third_at |> should.equal(vdt(2026, 5, 1, 0, 2, 0))
}

pub fn from_every_advances_one_day_at_a_time_test() {
  let assert Ok(compiled) =
    schedule.from_every(
      interval_seconds: 86_400,
      anchor: vdt(2026, 5, 1, 9, 30, 0),
    )

  let it =
    schedule.iterator_after(
      compiled,
      boundary: schedule_ast.Inclusive(vdt(2026, 5, 1, 9, 30, 0)),
    )

  let assert schedule.Yield(d1, it1) = schedule.step(it)
  d1 |> should.equal(vdt(2026, 5, 1, 9, 30, 0))

  let assert schedule.Yield(d2, it2) = schedule.step(it1)
  d2 |> should.equal(vdt(2026, 5, 2, 9, 30, 0))

  let assert schedule.Yield(d3, _) = schedule.step(it2)
  d3 |> should.equal(vdt(2026, 5, 3, 9, 30, 0))
}

pub fn from_every_advances_one_week_at_a_time_test() {
  let assert Ok(compiled) =
    schedule.from_every(
      interval_seconds: 604_800,
      anchor: vdt(2026, 5, 1, 9, 30, 0),
    )

  schedule.next_after(compiled, after: vdt(2026, 5, 1, 9, 30, 0))
  |> should.equal(Some(vdt(2026, 5, 8, 9, 30, 0)))

  schedule.next_after(compiled, after: vdt(2026, 5, 8, 9, 30, 0))
  |> should.equal(Some(vdt(2026, 5, 15, 9, 30, 0)))
}

pub fn from_every_crosses_month_boundary_test() {
  let assert Ok(compiled) =
    schedule.from_every(
      interval_seconds: 86_400,
      anchor: vdt(2026, 5, 30, 12, 0, 0),
    )

  schedule.next_after(compiled, after: vdt(2026, 5, 30, 12, 0, 0))
  |> should.equal(Some(vdt(2026, 5, 31, 12, 0, 0)))

  schedule.next_after(compiled, after: vdt(2026, 5, 31, 12, 0, 0))
  |> should.equal(Some(vdt(2026, 6, 1, 12, 0, 0)))
}

pub fn from_once_matches_only_at_target_test() {
  let target = vdt(2026, 5, 1, 12, 0, 0)
  let assert Ok(compiled) = schedule.from_once(at: target)

  schedule.matches(compiled, at: target) |> should.equal(True)
  schedule.matches(compiled, at: vdt(2026, 5, 1, 12, 0, 1))
  |> should.equal(False)
  schedule.matches(compiled, at: vdt(2026, 5, 1, 11, 59, 59))
  |> should.equal(False)
}

pub fn from_once_next_after_returns_target_then_none_test() {
  let target = vdt(2026, 5, 1, 12, 0, 0)
  let assert Ok(compiled) = schedule.from_once(at: target)

  schedule.next_after(compiled, after: vdt(2026, 4, 30, 23, 59, 59))
  |> should.equal(Some(target))

  schedule.next_after(compiled, after: target)
  |> should.equal(None)
}

pub fn from_once_iterator_terminates_after_one_yield_test() {
  let target = vdt(2026, 5, 1, 12, 0, 0)
  let assert Ok(compiled) = schedule.from_once(at: target)

  let it =
    schedule.iterator_after(
      compiled,
      boundary: schedule_ast.Inclusive(vdt(2026, 4, 1, 0, 0, 0)),
    )

  let assert schedule.Yield(first_at, it1) = schedule.step(it)
  first_at |> should.equal(target)

  schedule.step(it1) |> should.equal(schedule.Done)
}

pub fn from_once_iterator_done_when_boundary_excludes_target_test() {
  let target = vdt(2026, 5, 1, 12, 0, 0)
  let assert Ok(compiled) = schedule.from_once(at: target)

  let it =
    schedule.iterator_after(compiled, boundary: schedule_ast.Exclusive(target))

  schedule.step(it) |> should.equal(schedule.Done)
}

// Issue #5: with all four constructors returning Result(Schedule, _),
// generic helpers can treat them uniformly. This test pins down that
// uniform shape by feeding all four through one tagged-union compiler.
type AnySpec {
  CronS(spec: cron_validator.ValidCron)
  RRuleS(spec: rule_validator.ValidRRule, anchor: schedule_ast.ValidDateTime)
  EveryS(seconds: Int, anchor: schedule_ast.ValidDateTime)
  OnceS(at: schedule_ast.ValidDateTime)
}

fn compile(s: AnySpec) -> Result(schedule.Schedule, schedule.ScheduleError) {
  case s {
    CronS(spec:) -> schedule.from_cron(spec: spec)
    RRuleS(spec:, anchor:) -> schedule.from_rrule(spec: spec, anchor: anchor)
    EveryS(seconds:, anchor:) ->
      schedule.from_every(interval_seconds: seconds, anchor: anchor)
    OnceS(at:) -> schedule.from_once(at: at)
  }
}

pub fn from_constructors_return_uniform_result_shape_test() {
  let cron_spec = parse_and_validate_cron("0 0 * * *")
  let rrule_spec = parse_and_validate_rrule("FREQ=DAILY;COUNT=2")
  let anchor = vdt(2026, 5, 9, 12, 0, 0)

  let assert Ok(_) = compile(CronS(spec: cron_spec))
  let assert Ok(_) = compile(RRuleS(spec: rrule_spec, anchor: anchor))
  let assert Ok(_) = compile(EveryS(seconds: 60, anchor: anchor))
  let assert Ok(_) = compile(OnceS(at: anchor))
}

pub fn from_every_zero_seconds_propagates_through_compile_test() {
  let anchor = vdt(2026, 5, 9, 12, 0, 0)

  compile(EveryS(seconds: 0, anchor: anchor))
  |> should.equal(Error(schedule.EveryIntervalMustBePositive(actual: 0)))
}

// --- years at or before 0 (proleptic Gregorian, astronomical numbering) ---
// 0001-01-01 is a Monday and year 0 is a leap year, so 0000-01-01 is a
// Saturday and -0001-12-31 is a Friday.

fn iso(value: schedule_ast.ValidDateTime) -> String {
  schedule_ast.to_string(schedule_ast.valid_datetime_value(value))
}

pub fn to_string_pads_negative_year_test() {
  schedule_ast.to_string(schedule_ast.datetime(-1, 12, 31, 0, 0, 0))
  |> should.equal("-0001-12-31T00:00:00")
  schedule_ast.to_string(schedule_ast.datetime(-12_345, 1, 2, 3, 4, 5))
  |> should.equal("-12345-01-02T03:04:05")
  schedule_ast.to_string(schedule_ast.datetime(0, 1, 1, 0, 0, 0))
  |> should.equal("0000-01-01T00:00:00")
}

pub fn cron_weekday_before_year_one_test() {
  let saturday = parse_and_validate_cron("0 0 * * 6")
  let assert Some(next) =
    cron.next_after(saturday, after: vdt(-1, 12, 31, 0, 0, 0))
  iso(next) |> should.equal("0000-01-01T00:00:00")
  cron.matches(
    parse_and_validate_cron("0 0 * * 5"),
    at: vdt(-1, 12, 31, 0, 0, 0),
  )
  |> should.equal(True)
}

pub fn cron_month_rollover_before_year_one_test() {
  let spec = parse_and_validate_cron("0 0 15 * *")
  let assert Some(first) =
    cron.next_after(spec, after: vdt(-1, 11, 20, 0, 0, 0))
  let assert Some(second) = cron.next_after(spec, after: first)
  iso(first) |> should.equal("-0001-12-15T00:00:00")
  iso(second) |> should.equal("0000-01-15T00:00:00")
}

pub fn rrule_daily_interval_across_leap_year_zero_test() {
  let spec = parse_and_validate_rrule("FREQ=DAILY;INTERVAL=2")
  let anchor = vdt(0, 12, 30, 0, 0, 0)
  let assert Ok(Some(first)) =
    rrule.next_after(spec, anchor: anchor, after: anchor)
  iso(first) |> should.equal("0001-01-01T00:00:00")
}

pub fn rrule_weekly_before_year_one_test() {
  let spec = parse_and_validate_rrule("FREQ=WEEKLY")
  let anchor = vdt(-1, 12, 31, 9, 0, 0)
  let assert Ok(Some(first)) =
    rrule.next_after(spec, anchor: anchor, after: anchor)
  iso(first) |> should.equal("0000-01-07T09:00:00")
}

// --- calendar rules through the public constructors ---

pub fn try_datetime_follows_gregorian_leap_years_test() {
  [#(2000, True), #(2024, True), #(1900, False), #(2100, False), #(2025, False)]
  |> list.each(fn(case_) {
    let #(year, leap) = case_
    case schedule_ast.try_datetime(year, 2, 29, 0, 0, 0) {
      Ok(_) -> leap |> should.equal(True)
      Error(_) -> leap |> should.equal(False)
    }
  })
}

pub fn try_datetime_accepts_only_the_wall_clock_range_test() {
  [
    #(0, 0, 0, True),
    #(23, 59, 59, True),
    #(24, 0, 0, False),
    #(23, 60, 0, False),
    #(23, 59, 60, False),
    #(-1, 0, 0, False),
    #(0, -1, 0, False),
    #(0, 0, -1, False),
  ]
  |> list.each(fn(case_) {
    let #(hour, minute, second, valid) = case_
    case schedule_ast.try_datetime(2026, 1, 1, hour, minute, second) {
      Ok(_) -> valid |> should.equal(True)
      Error(schedule_ast.InvalidTime(..)) -> valid |> should.equal(False)
      Error(schedule_ast.InvalidDate(..)) -> should.fail()
    }
  })
}

pub fn cron_month_rollover_clamps_to_month_end_test() {
  // The monthly search moves to the first day of the next month; the
  // 31st only exists in some months, and 29 February only in leap years.
  let spec = parse_and_validate_cron("0 9 31 * *")
  let assert Some(first) =
    cron.next_after(spec, after: vdt(2026, 1, 31, 9, 0, 0))
  iso(first) |> should.equal("2026-03-31T09:00:00")
  let leap = parse_and_validate_cron("0 0 29 2 *")
  let assert Some(next) = cron.next_after(leap, after: vdt(2024, 3, 1, 0, 0, 0))
  iso(next) |> should.equal("2028-02-29T00:00:00")
}
