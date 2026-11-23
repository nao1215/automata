import automata as a
import gleam/option.{None}
import gleeunit/should
import regression_canonical_support as s

// An explicit filter makes the count depend on the calendar, so it is counted
// one occurrence at a time and runs into the search limit.
fn counted_schedule() -> a.Schedule {
  s.schedule(
    "FREQ=SECONDLY;COUNT=2000010;BYHOUR=0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23",
    s.valid(2026, 1, 1, 0, 0, 0),
  )
}

pub fn unfiltered_count_is_computed_without_search_test() {
  let anchor = s.valid(2026, 1, 1, 0, 0, 0)
  let daily = s.schedule("FREQ=DAILY;COUNT=300000", anchor)
  let late = s.valid(2800, 1, 2, 0, 0, 0)
  a.schedule_matches(daily, at: late) |> should.equal(Ok(True))
  s.expect(daily, a.Inclusive(late), [#(2800, 1, 2, 0, 0, 0)], False)
  // 2026-01-01 plus 299,999 days is the last occurrence.
  let last = s.valid(2847, 5, 16, 0, 0, 0)
  a.schedule_matches(daily, at: last) |> should.equal(Ok(True))
  s.expect(daily, a.Inclusive(last), [#(2847, 5, 16, 0, 0, 0)], True)
  a.schedule_next(daily, after: last) |> should.equal(Ok(None))

  let secondly = s.schedule("FREQ=SECONDLY;COUNT=2000010", anchor)
  a.schedule_matches(secondly, at: distant()) |> should.equal(Ok(True))
  s.expect(secondly, a.Exclusive(distant()), [#(2026, 1, 24, 3, 33, 21)], False)
}

pub fn unfiltered_weekly_and_hourly_counts_use_the_interval_test() {
  let anchor = s.valid(2026, 1, 1, 9, 30, 17)
  let weekly = s.schedule("FREQ=WEEKLY;INTERVAL=3;COUNT=3", anchor)
  s.expect(
    weekly,
    a.Exclusive(s.valid(2026, 1, 22, 9, 30, 17)),
    [#(2026, 2, 12, 9, 30, 17)],
    True,
  )
  let hourly = s.schedule("FREQ=HOURLY;INTERVAL=5;COUNT=4", anchor)
  s.expect(
    hourly,
    a.Inclusive(s.valid(2026, 1, 1, 14, 30, 17)),
    [
      #(2026, 1, 1, 14, 30, 17),
      #(2026, 1, 1, 19, 30, 17),
      #(2026, 1, 2, 0, 30, 17),
    ],
    True,
  )
}

fn distant() -> a.ValidDateTime {
  s.valid(2026, 1, 24, 3, 33, 20)
}

pub fn count_before_failure_reaches_matches_test() {
  a.schedule_matches(counted_schedule(), at: distant())
  |> should.equal(Error(a.ScheduleSearchLimitReached(1_000_000)))
}

pub fn count_before_failure_reaches_iterator_test() {
  a.schedule_iterator(counted_schedule(), boundary: a.Inclusive(distant()))
  |> should.equal(Error(a.ScheduleSearchLimitReached(1_000_000)))
}

pub fn count_before_failure_reaches_next_test() {
  a.schedule_next(counted_schedule(), after: distant())
  |> should.equal(Error(a.ScheduleSearchLimitReached(1_000_000)))
}

pub fn exhausted_count_is_done_at_distant_query_test() {
  let schedule =
    s.schedule("FREQ=SECONDLY;COUNT=1", s.valid(2026, 1, 1, 0, 0, 0))
  s.expect(schedule, a.Inclusive(distant()), [], True)
  a.schedule_matches(schedule, at: distant()) |> should.equal(Ok(False))
  a.schedule_next(schedule, after: distant()) |> should.equal(Ok(None))
}

pub fn expired_until_is_done_at_distant_query_test() {
  let schedule =
    s.schedule(
      "FREQ=SECONDLY;UNTIL=20260101T000000Z",
      s.valid(2026, 1, 1, 0, 0, 0),
    )
  s.expect(schedule, a.Inclusive(distant()), [], True)
  a.schedule_matches(schedule, at: distant()) |> should.equal(Ok(False))
  a.schedule_next(schedule, after: distant()) |> should.equal(Ok(None))
}

pub fn unreachable_minute_is_an_empty_sequence_test() {
  // Every period starts at minute zero, so BYMINUTE=1 is never reached.
  let anchor = s.valid(2026, 1, 1, 0, 0, 17)
  let schedule = s.schedule("FREQ=MINUTELY;INTERVAL=60;BYMINUTE=1", anchor)
  s.expect(schedule, a.Inclusive(anchor), [], True)
  a.schedule_next(schedule, after: anchor) |> should.equal(Ok(None))
}

pub fn unreachable_hour_is_an_empty_sequence_test() {
  // Hours 16, 19, 22, 1, ... never reach 18.
  let anchor = s.valid(2041, 4, 14, 16, 18, 38)
  let schedule = s.schedule("FREQ=HOURLY;INTERVAL=3;COUNT=7;BYHOUR=18", anchor)
  s.expect(schedule, a.Inclusive(anchor), [], True)
}

pub fn hourly_periods_are_clock_hours_test() {
  // RFC 5545 HOURLY periods are clock hours counted from the DTSTART hour:
  // 09:00, 11:00, 13:00. 09:15:17 precedes the anchor.
  let anchor = s.valid(2026, 1, 1, 9, 30, 17)
  s.expect(
    s.schedule("FREQ=HOURLY;INTERVAL=2;BYMINUTE=15", anchor),
    a.Inclusive(anchor),
    [#(2026, 1, 1, 11, 15, 17), #(2026, 1, 1, 13, 15, 17)],
    False,
  )
  let anchor = s.valid(2013, 5, 15, 6, 36, 50)
  s.expect(
    s.schedule("FREQ=HOURLY;INTERVAL=4;COUNT=2;BYMINUTE=23", anchor),
    a.Inclusive(anchor),
    [#(2013, 5, 15, 10, 23, 50), #(2013, 5, 15, 14, 23, 50)],
    True,
  )
}

pub fn hourly_clock_periods_match_test() {
  let anchor = s.valid(2026, 1, 1, 9, 30, 17)
  let schedule = s.schedule("FREQ=HOURLY;INTERVAL=2;BYMINUTE=15", anchor)
  a.schedule_matches(schedule, at: s.valid(2026, 1, 1, 11, 15, 17))
  |> should.equal(Ok(True))
  a.schedule_matches(schedule, at: s.valid(2026, 1, 1, 10, 15, 17))
  |> should.equal(Ok(False))
}

pub fn minutely_periods_are_clock_minutes_test() {
  let anchor = s.valid(2004, 1, 4, 0, 30, 19)
  s.expect(
    s.schedule("FREQ=HOURLY;INTERVAL=3;BYMONTHDAY=-31,15;BYMINUTE=5,32", anchor),
    a.Inclusive(anchor),
    [
      #(2004, 1, 15, 0, 5, 19),
      #(2004, 1, 15, 0, 32, 19),
      #(2004, 1, 15, 3, 5, 19),
    ],
    False,
  )
  let anchor = s.valid(2026, 1, 1, 0, 0, 40)
  s.expect(
    s.schedule("FREQ=MINUTELY;INTERVAL=2;BYHOUR=1", anchor),
    a.Inclusive(anchor),
    [#(2026, 1, 1, 1, 0, 40), #(2026, 1, 1, 1, 2, 40)],
    False,
  )
}

pub fn secondly_filters_skip_whole_days_test() {
  let anchor = s.valid(2035, 8, 20, 17, 11, 9)
  s.expect(
    s.schedule("FREQ=SECONDLY;BYMONTHDAY=31", anchor),
    a.Inclusive(anchor),
    [#(2035, 8, 31, 0, 0, 0), #(2035, 8, 31, 0, 0, 1)],
    False,
  )
  let anchor = s.valid(2026, 6, 6, 5, 50, 53)
  s.expect(
    s.schedule(
      "FREQ=SECONDLY;INTERVAL=4;COUNT=2;BYDAY=SU,TU,SA;BYMONTHDAY=-2;BYMINUTE=13,27",
      anchor,
    ),
    a.Inclusive(anchor),
    [#(2026, 8, 30, 0, 13, 1), #(2026, 8, 30, 0, 13, 5)],
    True,
  )
}

pub fn secondly_filters_skip_within_a_day_test() {
  let anchor = s.valid(2026, 1, 1, 0, 0, 0)
  s.expect(
    s.schedule("FREQ=SECONDLY;BYHOUR=23;BYMINUTE=59", anchor),
    a.Inclusive(anchor),
    [#(2026, 1, 1, 23, 59, 0), #(2026, 1, 1, 23, 59, 1)],
    False,
  )
  s.expect(
    s.schedule("FREQ=SECONDLY;BYHOUR=23;BYMINUTE=59", anchor),
    a.Exclusive(s.valid(2026, 1, 1, 23, 59, 59)),
    [#(2026, 1, 2, 23, 59, 0)],
    False,
  )
}

pub fn minutely_jump_returns_period_start_without_query_offset_test() {
  let anchor = s.valid(2026, 1, 1, 0, 0, 17)
  s.expect(
    s.schedule("FREQ=MINUTELY;INTERVAL=2", anchor),
    a.Exclusive(s.valid(2026, 1, 1, 0, 1, 30)),
    [#(2026, 1, 1, 0, 2, 17), #(2026, 1, 1, 0, 4, 17)],
    False,
  )
}

pub fn partial_year_with_past_candidate_is_not_a_whole_empty_cycle_test() {
  let anchor = s.valid(2024, 1, 1, 0, 0, 0)
  s.expect(
    s.schedule("FREQ=YEARLY;INTERVAL=400;BYMONTH=2;BYMONTHDAY=29", anchor),
    a.Exclusive(s.valid(2024, 3, 1, 0, 0, 0)),
    [#(2424, 2, 29, 0, 0, 0)],
    False,
  )
}
