import automata as a
import gleam/list
import gleam/option.{Some}
import gleeunit/should
import regression_canonical_support as s

pub fn civil_rejects_every_nonzero_nanosecond_test() {
  list.each([-1, 1, 999_999_999, 1_000_000_000], fn(nanos) {
    s.raw(2026, 1, 1, 12, 34, 56, nanos)
    |> a.datetime_validate
    |> should.equal(Error(a.InvalidTime(12, 34, 56, nanos)))
  })
}

pub fn civil_invalid_date_precedes_time_test() {
  s.raw(2026, 2, 30, 24, 60, 60, 1)
  |> a.datetime_validate
  |> should.equal(Error(a.InvalidDate(2026, 2, 30)))
}

pub fn civil_whole_seconds_preserve_negative_zero_and_large_year_test() {
  list.each(
    [
      #(-1, "-0001-01-01T12:34:56"),
      #(0, "0000-01-01T12:34:56"),
      #(10_000, "10000-01-01T12:34:56"),
    ],
    fn(row) {
      s.valid(row.0, 1, 1, 12, 34, 56)
      |> a.datetime_to_string
      |> should.equal(row.1)
    },
  )
}

pub fn until_datetime_rejects_nanoseconds_with_diagnostic_test() {
  let options = a.rrule_options(a.Daily)
  let until = s.raw(2026, 1, 1, 0, 0, 0, 1)
  a.rrule_new(
    a.RecurrenceOptions(
      ..options,
      end_condition: a.Until(a.UntilDateTime(until)),
    ),
  )
  |> should.equal(
    Error(a.RruleUntilMalformedDateTime("20260101T000000.000000001Z")),
  )
}

pub fn until_whole_second_is_inclusive_test() {
  let options = a.rrule_options(a.Daily)
  let until = s.raw(2026, 1, 1, 0, 0, 0, 0)
  let assert Ok(rule) =
    a.rrule_new(
      a.RecurrenceOptions(
        ..options,
        end_condition: a.Until(a.UntilDateTime(until)),
      ),
    )
  let anchor = s.valid(2026, 1, 1, 0, 0, 0)
  s.expect(
    a.schedule_from_rrule(rule, anchor: anchor),
    a.Inclusive(anchor),
    [#(2026, 1, 1, 0, 0, 0)],
    True,
  )
}

@target(javascript)
pub fn javascript_unsafe_year_precedes_invalid_date_and_time_test() {
  let unsafe_year = 9_007_199_254_740_991 + 1
  s.raw(unsafe_year, 2, 30, 24, 60, 60, 1)
  |> a.datetime_validate
  |> should.equal(Error(a.DateTimeYearOutOfRange(unsafe_year)))
  s.raw(0 - unsafe_year, 1, 1, 0, 0, 0, 0)
  |> a.datetime_validate
  |> should.equal(Error(a.DateTimeYearOutOfRange(0 - unsafe_year)))
}

pub fn safe_year_end_once_yields_before_done_test() {
  let at = s.valid(9_007_199_254_740_991, 12, 31, 23, 59, 59)
  s.expect(
    a.schedule_once(at),
    a.Inclusive(at),
    [#(9_007_199_254_740_991, 12, 31, 23, 59, 59)],
    True,
  )
}

pub fn safe_year_end_count_one_finishes_before_next_addition_test() {
  let at = s.valid(9_007_199_254_740_991, 12, 31, 23, 59, 59)
  s.expect(
    s.schedule("FREQ=SECONDLY;COUNT=1", at),
    a.Inclusive(at),
    [#(9_007_199_254_740_991, 12, 31, 23, 59, 59)],
    True,
  )
}

@target(javascript)
pub fn javascript_every_overflow_is_not_done_test() {
  let at = s.valid(9_007_199_254_740_991, 12, 31, 23, 59, 59)
  let assert Ok(schedule) = a.schedule_every(interval_seconds: 1, anchor: at)
  let assert Ok(iterator) =
    a.schedule_iterator(schedule, boundary: a.Inclusive(at))
  let assert Ok(a.Yield(value, next)) = a.schedule_step(iterator)
  s.parts(value) |> should.equal(#(9_007_199_254_740_991, 12, 31, 23, 59, 59))
  a.schedule_step(next) |> should.equal(Error(a.ScheduleNumericOverflow))
  a.schedule_next(schedule, after: at)
  |> should.equal(Error(a.ScheduleNumericOverflow))
}

pub fn max_safe_year_keeps_one_second_resolution_test() {
  let before = s.valid(9_007_199_254_740_991, 12, 31, 23, 59, 58)
  let after = s.valid(9_007_199_254_740_991, 12, 31, 23, 59, 59)
  let assert Ok(schedule) =
    a.schedule_every(interval_seconds: 1, anchor: before)
  a.schedule_next(schedule, after: before) |> should.equal(Ok(Some(after)))
  a.schedule_matches(schedule, at: after) |> should.equal(Ok(True))
}

pub fn minimum_safe_year_crosses_month_with_exact_negative_era_test() {
  let at = s.valid(-9_007_199_254_740_991, 1, 31, 23, 59, 59)
  let assert Ok(schedule) = a.schedule_every(interval_seconds: 1, anchor: at)
  let assert Ok(Some(next)) = a.schedule_next(schedule, after: at)
  s.parts(next) |> should.equal(#(-9_007_199_254_740_991, 2, 1, 0, 0, 0))
}

pub fn until_finishes_before_a_numerically_unrepresentable_next_year_test() {
  let at = s.valid(9999, 1, 1, 0, 0, 0)
  s.expect(
    s.schedule(
      "FREQ=YEARLY;INTERVAL=9007199254740991;UNTIL=99990101T000000Z",
      at,
    ),
    a.Inclusive(at),
    [#(9999, 1, 1, 0, 0, 0)],
    True,
  )
}

@target(erlang)
pub fn erlang_retains_years_above_javascript_safe_range_test() {
  let at = s.valid(9_007_199_254_740_992, 12, 31, 23, 59, 59)
  let assert Ok(schedule) = a.schedule_every(interval_seconds: 1, anchor: at)
  let assert Ok(Some(next)) = a.schedule_next(schedule, after: at)
  s.parts(next) |> should.equal(#(9_007_199_254_740_993, 1, 1, 0, 0, 0))
}
