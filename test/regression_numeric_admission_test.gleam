import automata as a
import gleam/time/calendar

fn typed_rule(interval, count) {
  let options = a.rrule_options(a.Daily)
  a.rrule_new(
    a.RecurrenceOptions(
      ..options,
      interval: interval,
      end_condition: a.Count(count),
    ),
  )
}

fn raw_rule(input) {
  let assert Ok(raw) = a.rrule_parse_raw(input: input)
  a.rrule_validate(raw: raw)
}

fn expect_numbers(result, interval, count) {
  let assert Ok(rule) = result
  let options = a.rrule_to_options(rule)
  assert options.interval == interval
  assert options.end_condition == a.Count(count)
}

fn anchor() {
  let assert Ok(at) =
    a.datetime_validate(a.DateTime(
      calendar.Date(2026, calendar.January, 1),
      calendar.TimeOfDay(0, 0, 0, 0),
    ))
  at
}

pub fn typed_rrule_accepts_safe_integer_maximum_test() {
  expect_numbers(
    typed_rule(9_007_199_254_740_991, 9_007_199_254_740_991),
    9_007_199_254_740_991,
    9_007_199_254_740_991,
  )
}

pub fn raw_rrule_accepts_safe_integer_maximum_test() {
  expect_numbers(
    raw_rule("FREQ=DAILY;INTERVAL=9007199254740991;COUNT=9007199254740991"),
    9_007_199_254_740_991,
    9_007_199_254_740_991,
  )
}

pub fn every_accepts_safe_integer_maximum_test() {
  let at = anchor()
  let assert Ok(schedule) =
    a.schedule_every(interval_seconds: 9_007_199_254_740_991, anchor: at)
  assert a.schedule_matches(schedule, at: at) == Ok(True)
}

@target(javascript)
pub fn javascript_typed_interval_rejects_unsafe_integer_test() {
  let unsafe = 9_007_199_254_740_991 + 1
  assert typed_rule(unsafe, 1)
    == Error(a.RruleIntegerOutOfRange(a.IntervalPart, unsafe))
}

@target(javascript)
pub fn javascript_typed_count_rejects_unsafe_integer_test() {
  let unsafe = 9_007_199_254_740_991 + 1
  assert typed_rule(1, unsafe)
    == Error(a.RruleIntegerOutOfRange(a.CountPart, unsafe))
}

@target(javascript)
pub fn javascript_raw_interval_preserves_original_unsafe_number_test() {
  assert raw_rule("FREQ=DAILY;INTERVAL=9007199254740992")
    == Error(a.RruleInvalidNumber(a.IntervalPart, "9007199254740992"))
  assert raw_rule("FREQ=DAILY;INTERVAL=09007199254740993")
    == Error(a.RruleInvalidNumber(a.IntervalPart, "09007199254740993"))
}

@target(javascript)
pub fn javascript_raw_count_preserves_original_unsafe_number_test() {
  assert raw_rule("FREQ=DAILY;COUNT=9007199254740992")
    == Error(a.RruleInvalidNumber(a.CountPart, "9007199254740992"))
  assert raw_rule("FREQ=DAILY;COUNT=09007199254740993")
    == Error(a.RruleInvalidNumber(a.CountPart, "09007199254740993"))
}

@target(javascript)
pub fn javascript_every_rejects_unsafe_interval_test() {
  let unsafe = 9_007_199_254_740_991 + 1
  assert a.schedule_every(interval_seconds: unsafe, anchor: anchor())
    == Error(a.ScheduleNumericOverflow)
}

@target(javascript)
pub fn javascript_numeric_admission_keeps_validation_order_test() {
  let unsafe = 9_007_199_254_740_991 + 1
  assert typed_rule(unsafe, 0)
    == Error(a.RruleIntegerOutOfRange(a.IntervalPart, unsafe))
  assert typed_rule(0 - unsafe, unsafe)
    == Error(a.RruleMustBePositive(a.IntervalPart, 0 - unsafe))
  assert typed_rule(1, 0 - unsafe)
    == Error(a.RruleMustBePositive(a.CountPart, 0 - unsafe))
  assert a.schedule_every(interval_seconds: 0 - unsafe, anchor: anchor())
    == Error(a.EveryIntervalMustBePositive(0 - unsafe))
}

@target(erlang)
pub fn erlang_typed_rrule_preserves_arbitrary_precision_test() {
  expect_numbers(
    typed_rule(
      123_456_789_012_345_678_901_234_567_890,
      123_456_789_012_345_678_901_234_567_891,
    ),
    123_456_789_012_345_678_901_234_567_890,
    123_456_789_012_345_678_901_234_567_891,
  )
}

@target(erlang)
pub fn erlang_raw_rrule_preserves_arbitrary_precision_test() {
  expect_numbers(
    raw_rule(
      "FREQ=DAILY;INTERVAL=123456789012345678901234567890;COUNT=123456789012345678901234567891",
    ),
    123_456_789_012_345_678_901_234_567_890,
    123_456_789_012_345_678_901_234_567_891,
  )
}

@target(erlang)
pub fn erlang_every_accepts_arbitrary_precision_interval_test() {
  let at = anchor()
  let assert Ok(schedule) =
    a.schedule_every(
      interval_seconds: 123_456_789_012_345_678_901_234_567_890,
      anchor: at,
    )
  assert a.schedule_matches(schedule, at: at) == Ok(True)
}
