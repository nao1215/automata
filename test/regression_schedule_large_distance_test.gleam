import automata as a
import gleam/option.{Some}
import gleeunit/should
import regression_support as support

pub fn every_one_hundred_thousand_gregorian_cycles_test() {
  let anchor = support.valid(2000, 3, 1, 0, 0, 0)
  let assert Ok(value) =
    a.schedule_every(interval_seconds: 1_262_278_080_000_000, anchor:)
  let assert Ok(Some(next)) = a.schedule_next(value, after: anchor)
  support.parts(next) |> should.equal(#(40_002_000, 3, 1, 0, 0, 0))
}

pub fn every_quadrillion_seconds_has_exact_day_and_time_test() {
  let anchor = support.valid(2000, 3, 1, 0, 0, 0)
  let assert Ok(value) =
    a.schedule_every(interval_seconds: 1_000_000_000_000_000, anchor:)
  let assert Ok(Some(next)) = a.schedule_next(value, after: anchor)
  support.parts(next) |> should.equal(#(31_690_738, 9, 3, 1, 46, 40))
}

pub fn every_second_huge_occurrence_preserves_remainder_test() {
  let anchor = support.valid(2000, 3, 1, 0, 0, 0)
  let first = support.valid(31_690_738, 9, 3, 1, 46, 40)
  let assert Ok(value) =
    a.schedule_every(interval_seconds: 1_000_000_000_000_000, anchor:)
  let assert Ok(Some(next)) = a.schedule_next(value, after: first)
  support.parts(next) |> should.equal(#(63_379_477, 3, 6, 3, 33, 20))
}

pub fn huge_every_boundaries_are_exact_test() {
  let anchor = support.valid(2000, 3, 1, 0, 0, 0)
  let first = support.valid(31_690_738, 9, 3, 1, 46, 40)
  let before = support.valid(31_690_738, 9, 3, 1, 46, 39)
  let assert Ok(value) =
    a.schedule_every(interval_seconds: 1_000_000_000_000_000, anchor:)
  support.expect_schedule(
    value,
    a.Exclusive(before),
    [#(31_690_738, 9, 3, 1, 46, 40)],
    False,
  )
  support.expect_schedule(
    value,
    a.Inclusive(first),
    [#(31_690_738, 9, 3, 1, 46, 40)],
    False,
  )
  support.expect_schedule(
    value,
    a.Exclusive(first),
    [#(63_379_477, 3, 6, 3, 33, 20)],
    False,
  )
}

pub fn huge_every_matching_keeps_one_second_resolution_test() {
  let anchor = support.valid(2000, 3, 1, 0, 0, 0)
  let assert Ok(value) =
    a.schedule_every(interval_seconds: 1_000_000_000_000_000, anchor:)
  a.schedule_matches(value, at: support.valid(31_690_738, 9, 3, 1, 46, 40))
  |> should.equal(Ok(True))
  a.schedule_matches(value, at: support.valid(31_690_738, 9, 3, 1, 46, 39))
  |> should.equal(Ok(False))
  a.schedule_matches(value, at: support.valid(31_690_738, 9, 3, 1, 46, 41))
  |> should.equal(Ok(False))
  a.schedule_matches(value, at: support.valid(63_379_477, 3, 6, 3, 33, 20))
  |> should.equal(Ok(True))
}

pub fn every_four_hundred_years_crosses_negative_and_zero_years_test() {
  let anchor = support.valid(-400, 3, 1, 0, 0, 0)
  let assert Ok(value) =
    a.schedule_every(interval_seconds: 12_622_780_800, anchor:)
  support.expect_schedule(
    value,
    a.Exclusive(anchor),
    [#(0, 3, 1, 0, 0, 0), #(400, 3, 1, 0, 0, 0)],
    False,
  )
}

pub fn secondly_rrule_uses_the_same_exact_large_distance_test() {
  let anchor = support.valid(2000, 3, 1, 0, 0, 0)
  let rule = support.rule("FREQ=SECONDLY;INTERVAL=1000000000000000;COUNT=2")
  let value = a.schedule_from_rrule(rule, anchor:)
  support.expect_schedule(
    value,
    a.Inclusive(anchor),
    [#(2000, 3, 1, 0, 0, 0), #(31_690_738, 9, 3, 1, 46, 40)],
    True,
  )
}
