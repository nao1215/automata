import automata as a
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/time/calendar
import gleeunit/should

fn parse_and_validate_cron(input: String) -> a.Cron {
  let assert Ok(raw) = a.cron_parse_raw(input: input)
  let assert Ok(spec) = a.cron_validate(raw: raw)
  spec
}

fn parse_and_validate_rrule(input: String) -> a.RecurrenceRule {
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

pub fn shared_schedule_matches_cron_test() {
  let assert Ok(compiled) =
    from_cron(spec: parse_and_validate_cron("*/30 9-17 * * 1-5"))

  matches_schedule(schedule: compiled, at: vdt(2026, 5, 11, 10, 0, 0))
  |> should.equal(True)

  next_schedule(schedule: compiled, after: vdt(2026, 5, 11, 10, 7, 0))
  |> should.equal(Some(vdt(2026, 5, 11, 10, 30, 0)))
}

pub fn shared_schedule_iterates_rrule_test() {
  let spec = parse_and_validate_rrule("FREQ=DAILY;COUNT=2;BYHOUR=9;BYMINUTE=0")
  let anchor = vdt(2026, 5, 1, 9, 0, 0)
  let assert Ok(compiled) = from_rrule(spec: spec, anchor: anchor)

  let iterator =
    iterate_schedule(
      schedule: compiled,
      boundary: a.Exclusive(vdt(2026, 5, 1, 8, 0, 0)),
    )

  let assert a.Yield(first_at, next_iterator) =
    step_schedule(iterator: iterator)
  first_at |> should.equal(vdt(2026, 5, 1, 9, 0, 0))

  let assert a.Yield(second_at, _) = step_schedule(iterator: next_iterator)
  second_at |> should.equal(vdt(2026, 5, 2, 9, 0, 0))
}

pub fn shared_schedule_next_after_preserves_rrule_seconds_test() {
  let spec = parse_and_validate_rrule("FREQ=DAILY;BYHOUR=9;BYMINUTE=0")
  let anchor = vdt(2026, 5, 1, 9, 0, 30)
  let assert Ok(compiled) = from_rrule(spec: spec, anchor: anchor)

  next_schedule(schedule: compiled, after: vdt(2026, 5, 1, 9, 0, 0))
  |> should.equal(Some(vdt(2026, 5, 1, 9, 0, 30)))

  next_schedule(schedule: compiled, after: vdt(2026, 5, 1, 9, 0, 30))
  |> should.equal(Some(vdt(2026, 5, 2, 9, 0, 30)))
}

pub fn from_every_rejects_non_positive_interval_test() {
  a.schedule_every(interval_seconds: 0, anchor: vdt(2026, 5, 1, 0, 0, 0))
  |> should.equal(Error(a.EveryIntervalMustBePositive(actual: 0)))

  a.schedule_every(interval_seconds: -10, anchor: vdt(2026, 5, 1, 0, 0, 0))
  |> should.equal(Error(a.EveryIntervalMustBePositive(actual: -10)))
}

pub fn from_every_iterates_at_fixed_interval_test() {
  let assert Ok(compiled) =
    a.schedule_every(interval_seconds: 300, anchor: vdt(2026, 5, 1, 0, 0, 0))

  matches_schedule(schedule: compiled, at: vdt(2026, 5, 1, 0, 5, 0))
  |> should.equal(True)
  matches_schedule(schedule: compiled, at: vdt(2026, 5, 1, 0, 4, 59))
  |> should.equal(False)
  matches_schedule(schedule: compiled, at: vdt(2026, 4, 30, 23, 55, 0))
  |> should.equal(False)

  next_schedule(schedule: compiled, after: vdt(2026, 5, 1, 0, 0, 0))
  |> should.equal(Some(vdt(2026, 5, 1, 0, 5, 0)))

  next_schedule(schedule: compiled, after: vdt(2026, 5, 1, 0, 4, 59))
  |> should.equal(Some(vdt(2026, 5, 1, 0, 5, 0)))
}

pub fn from_every_iterator_yields_in_order_test() {
  let assert Ok(compiled) =
    a.schedule_every(interval_seconds: 60, anchor: vdt(2026, 5, 1, 0, 0, 0))

  let it =
    iterate_schedule(
      schedule: compiled,
      boundary: a.Inclusive(vdt(2026, 5, 1, 0, 0, 0)),
    )

  let assert a.Yield(first_at, it1) = step_schedule(iterator: it)
  first_at |> should.equal(vdt(2026, 5, 1, 0, 0, 0))

  let assert a.Yield(second_at, it2) = step_schedule(iterator: it1)
  second_at |> should.equal(vdt(2026, 5, 1, 0, 1, 0))

  let assert a.Yield(third_at, _) = step_schedule(iterator: it2)
  third_at |> should.equal(vdt(2026, 5, 1, 0, 2, 0))
}

pub fn from_every_advances_one_day_at_a_time_test() {
  let assert Ok(compiled) =
    a.schedule_every(
      interval_seconds: 86_400,
      anchor: vdt(2026, 5, 1, 9, 30, 0),
    )

  let it =
    iterate_schedule(
      schedule: compiled,
      boundary: a.Inclusive(vdt(2026, 5, 1, 9, 30, 0)),
    )

  let assert a.Yield(d1, it1) = step_schedule(iterator: it)
  d1 |> should.equal(vdt(2026, 5, 1, 9, 30, 0))

  let assert a.Yield(d2, it2) = step_schedule(iterator: it1)
  d2 |> should.equal(vdt(2026, 5, 2, 9, 30, 0))

  let assert a.Yield(d3, _) = step_schedule(iterator: it2)
  d3 |> should.equal(vdt(2026, 5, 3, 9, 30, 0))
}

pub fn from_every_advances_one_week_at_a_time_test() {
  let assert Ok(compiled) =
    a.schedule_every(
      interval_seconds: 604_800,
      anchor: vdt(2026, 5, 1, 9, 30, 0),
    )

  next_schedule(schedule: compiled, after: vdt(2026, 5, 1, 9, 30, 0))
  |> should.equal(Some(vdt(2026, 5, 8, 9, 30, 0)))

  next_schedule(schedule: compiled, after: vdt(2026, 5, 8, 9, 30, 0))
  |> should.equal(Some(vdt(2026, 5, 15, 9, 30, 0)))
}

pub fn from_every_crosses_month_boundary_test() {
  let assert Ok(compiled) =
    a.schedule_every(
      interval_seconds: 86_400,
      anchor: vdt(2026, 5, 30, 12, 0, 0),
    )

  next_schedule(schedule: compiled, after: vdt(2026, 5, 30, 12, 0, 0))
  |> should.equal(Some(vdt(2026, 5, 31, 12, 0, 0)))

  next_schedule(schedule: compiled, after: vdt(2026, 5, 31, 12, 0, 0))
  |> should.equal(Some(vdt(2026, 6, 1, 12, 0, 0)))
}

pub fn from_once_matches_only_at_target_test() {
  let target = vdt(2026, 5, 1, 12, 0, 0)
  let assert Ok(compiled) = from_once(at: target)

  matches_schedule(schedule: compiled, at: target) |> should.equal(True)
  matches_schedule(schedule: compiled, at: vdt(2026, 5, 1, 12, 0, 1))
  |> should.equal(False)
  matches_schedule(schedule: compiled, at: vdt(2026, 5, 1, 11, 59, 59))
  |> should.equal(False)
}

pub fn from_once_next_after_returns_target_then_none_test() {
  let target = vdt(2026, 5, 1, 12, 0, 0)
  let assert Ok(compiled) = from_once(at: target)

  next_schedule(schedule: compiled, after: vdt(2026, 4, 30, 23, 59, 59))
  |> should.equal(Some(target))

  next_schedule(schedule: compiled, after: target)
  |> should.equal(None)
}

pub fn from_once_iterator_terminates_after_one_yield_test() {
  let target = vdt(2026, 5, 1, 12, 0, 0)
  let assert Ok(compiled) = from_once(at: target)

  let it =
    iterate_schedule(
      schedule: compiled,
      boundary: a.Inclusive(vdt(2026, 4, 1, 0, 0, 0)),
    )

  let assert a.Yield(first_at, it1) = step_schedule(iterator: it)
  first_at |> should.equal(target)

  step_schedule(iterator: it1) |> should.equal(a.Done)
}

pub fn from_once_iterator_done_when_boundary_excludes_target_test() {
  let target = vdt(2026, 5, 1, 12, 0, 0)
  let assert Ok(compiled) = from_once(at: target)

  let it = iterate_schedule(schedule: compiled, boundary: a.Exclusive(target))

  step_schedule(iterator: it) |> should.equal(a.Done)
}

// Issue #5: with all four constructors returning Result(Schedule, _),
// generic helpers can treat them uniformly. This test pins down that
// uniform shape by feeding all four through one tagged-union compiler.
type AnySpec {
  CronS(spec: a.Cron)
  RRuleS(spec: a.RecurrenceRule, anchor: a.ValidDateTime)
  EveryS(seconds: Int, anchor: a.ValidDateTime)
  OnceS(at: a.ValidDateTime)
}

fn compile(s: AnySpec) -> Result(a.Schedule, a.ScheduleError) {
  case s {
    CronS(spec:) -> from_cron(spec: spec)
    RRuleS(spec:, anchor:) -> from_rrule(spec: spec, anchor: anchor)
    EveryS(seconds:, anchor:) ->
      a.schedule_every(interval_seconds: seconds, anchor: anchor)
    OnceS(at:) -> from_once(at: at)
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
  |> should.equal(Error(a.EveryIntervalMustBePositive(actual: 0)))
}

// --- years at or before 0 (proleptic Gregorian, astronomical numbering) ---
// 0001-01-01 is a Monday and year 0 is a leap year, so 0000-01-01 is a
// Saturday and -0001-12-31 is a Friday.

fn iso(value: a.ValidDateTime) -> String {
  raw_datetime_to_string(a.datetime_value(value))
}

pub fn to_string_pads_negative_year_test() {
  raw_datetime_to_string(make_datetime(
    year: -1,
    month: 12,
    day: 31,
    hour: 0,
    minute: 0,
    second: 0,
  ))
  |> should.equal("-0001-12-31T00:00:00")
  raw_datetime_to_string(make_datetime(
    year: -12_345,
    month: 1,
    day: 2,
    hour: 3,
    minute: 4,
    second: 5,
  ))
  |> should.equal("-12345-01-02T03:04:05")
  raw_datetime_to_string(make_datetime(
    year: 0,
    month: 1,
    day: 1,
    hour: 0,
    minute: 0,
    second: 0,
  ))
  |> should.equal("0000-01-01T00:00:00")
}

pub fn cron_weekday_before_year_one_test() {
  let saturday = parse_and_validate_cron("0 0 * * 6")
  let assert Some(next) =
    next_cron(spec: saturday, after: vdt(-1, 12, 31, 0, 0, 0))
  iso(next) |> should.equal("0000-01-01T00:00:00")
  matches_cron(
    spec: parse_and_validate_cron("0 0 * * 5"),
    at: vdt(-1, 12, 31, 0, 0, 0),
  )
  |> should.equal(True)
}

pub fn cron_month_rollover_before_year_one_test() {
  let spec = parse_and_validate_cron("0 0 15 * *")
  let assert Some(first) =
    next_cron(spec: spec, after: vdt(-1, 11, 20, 0, 0, 0))
  let assert Some(second) = next_cron(spec: spec, after: first)
  iso(first) |> should.equal("-0001-12-15T00:00:00")
  iso(second) |> should.equal("0000-01-15T00:00:00")
}

pub fn rrule_daily_interval_across_leap_year_zero_test() {
  let spec = parse_and_validate_rrule("FREQ=DAILY;INTERVAL=2")
  let anchor = vdt(0, 12, 30, 0, 0, 0)
  let assert Ok(Some(first)) =
    next_rrule(spec: spec, anchor: anchor, after: anchor)
  iso(first) |> should.equal("0001-01-01T00:00:00")
}

pub fn rrule_weekly_before_year_one_test() {
  let spec = parse_and_validate_rrule("FREQ=WEEKLY")
  let anchor = vdt(-1, 12, 31, 9, 0, 0)
  let assert Ok(Some(first)) =
    next_rrule(spec: spec, anchor: anchor, after: anchor)
  iso(first) |> should.equal("0000-01-07T09:00:00")
}

// --- calendar rules through the public constructors ---

pub fn try_datetime_follows_gregorian_leap_years_test() {
  [#(2000, True), #(2024, True), #(1900, False), #(2100, False), #(2025, False)]
  |> list.each(fn(case_) {
    let #(year, leap) = case_
    case
      make_checked_datetime(
        year: year,
        month: 2,
        day: 29,
        hour: 0,
        minute: 0,
        second: 0,
      )
    {
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
    case
      make_checked_datetime(
        year: 2026,
        month: 1,
        day: 1,
        hour: hour,
        minute: minute,
        second: second,
      )
    {
      Ok(_) -> valid |> should.equal(True)
      Error(a.InvalidTime(..)) -> valid |> should.equal(False)
      Error(a.InvalidDate(..)) | Error(a.DateTimeYearOutOfRange(..)) ->
        should.fail()
    }
  })
}

pub fn cron_month_rollover_clamps_to_month_end_test() {
  // The monthly search moves to the first day of the next month; the
  // 31st only exists in some months, and 29 February only in leap years.
  let spec = parse_and_validate_cron("0 9 31 * *")
  let assert Some(first) =
    next_cron(spec: spec, after: vdt(2026, 1, 31, 9, 0, 0))
  iso(first) |> should.equal("2026-03-31T09:00:00")
  let leap = parse_and_validate_cron("0 0 29 2 *")
  let assert Some(next) = next_cron(spec: leap, after: vdt(2024, 3, 1, 0, 0, 0))
  iso(next) |> should.equal("2028-02-29T00:00:00")
}

fn from_cron(spec spec: a.Cron) -> Result(a.Schedule, a.ScheduleError) {
  Ok(a.schedule_from_cron(spec))
}

fn from_once(at at: a.ValidDateTime) -> Result(a.Schedule, a.ScheduleError) {
  Ok(a.schedule_once(at))
}

fn from_rrule(
  spec spec: a.RecurrenceRule,
  anchor anchor: a.ValidDateTime,
) -> Result(a.Schedule, a.ScheduleError) {
  Ok(a.schedule_from_rrule(spec, anchor: anchor))
}

fn iterate_schedule(
  schedule schedule: a.Schedule,
  boundary boundary: a.Boundary,
) -> a.OccurrenceIterator {
  let assert Ok(value) = a.schedule_iterator(schedule, boundary: boundary)
  value
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

fn next_rrule(
  spec spec: a.RecurrenceRule,
  anchor anchor: a.ValidDateTime,
  after after: a.ValidDateTime,
) -> Result(option.Option(a.ValidDateTime), a.ScheduleError) {
  a.schedule_next(a.schedule_from_rrule(spec, anchor: anchor), after: after)
}

fn next_schedule(
  schedule schedule: a.Schedule,
  after after: a.ValidDateTime,
) -> option.Option(a.ValidDateTime) {
  let assert Ok(value) = a.schedule_next(schedule, after: after)
  value
}

fn raw_datetime_to_string(value: a.DateTime) -> String {
  let assert Ok(valid) = a.datetime_validate(value)
  a.datetime_to_string(valid)
}

fn step_schedule(iterator iterator: a.OccurrenceIterator) -> a.IterStep {
  let assert Ok(value) = a.schedule_step(iterator)
  value
}
