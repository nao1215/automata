import automata as a
import gleam/option.{None}
import gleeunit/should
import regression_canonical_support as s

fn counted_schedule() -> a.Schedule {
  s.schedule("FREQ=SECONDLY;COUNT=2000010", s.valid(2026, 1, 1, 0, 0, 0))
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

pub fn minute_phase_empty_cycle_exceeds_budget_in_step_test() {
  let anchor = s.valid(2026, 1, 1, 0, 0, 17)
  let schedule = s.schedule("FREQ=MINUTELY;INTERVAL=60;BYMINUTE=1", anchor)
  let assert Ok(iterator) =
    a.schedule_iterator(schedule, boundary: a.Inclusive(anchor))
  a.schedule_step(iterator)
  |> should.equal(Error(a.ScheduleSearchLimitReached(1_000_000)))
}

pub fn hourly_blocks_keep_anchor_phase_and_explicit_minute_test() {
  let anchor = s.valid(2026, 1, 1, 9, 30, 17)
  s.expect(
    s.schedule("FREQ=HOURLY;INTERVAL=2;BYMINUTE=15", anchor),
    a.Inclusive(anchor),
    [#(2026, 1, 1, 10, 15, 17), #(2026, 1, 1, 12, 15, 17)],
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
