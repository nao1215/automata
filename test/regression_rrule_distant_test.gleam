import automata as a
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should
import regression_support as support

pub fn yearly_interval_11000_has_a_next_occurrence_test() {
  let rule = support.rule("FREQ=YEARLY;INTERVAL=11000")
  let anchor = support.valid(2026, 1, 1, 9, 30, 17)
  let assert Ok(Some(next)) =
    a.schedule_next(a.schedule_from_rrule(rule, anchor: anchor), after: anchor)
  support.parts(next) |> should.equal(#(13_026, 1, 1, 9, 30, 17))
}

pub fn distant_boundary_inclusive_and_exclusive_test() {
  let rule = support.rule("FREQ=YEARLY;INTERVAL=11000")
  let anchor = support.valid(2026, 1, 1, 9, 30, 17)
  let next = support.valid(13_026, 1, 1, 9, 30, 17)
  support.expect_rule(
    rule,
    anchor,
    a.Inclusive(anchor),
    [#(2026, 1, 1, 9, 30, 17), #(13_026, 1, 1, 9, 30, 17)],
    False,
  )
  support.expect_rule(
    rule,
    anchor,
    a.Inclusive(next),
    [#(13_026, 1, 1, 9, 30, 17)],
    False,
  )
  support.expect_rule(
    rule,
    anchor,
    a.Exclusive(next),
    [#(24_026, 1, 1, 9, 30, 17)],
    False,
  )
}

pub fn query_one_second_before_distant_occurrence_test() {
  let rule = support.rule("FREQ=YEARLY;INTERVAL=11000")
  let anchor = support.valid(2026, 1, 1, 9, 30, 17)
  let before = support.valid(13_026, 1, 1, 9, 30, 16)
  list.each([a.Inclusive(before), a.Exclusive(before)], fn(boundary) {
    support.expect_rule(
      rule,
      anchor,
      boundary,
      [#(13_026, 1, 1, 9, 30, 17)],
      False,
    )
  })
}

pub fn query_before_anchor_keeps_the_anchor_test() {
  let rule = support.rule("FREQ=YEARLY;INTERVAL=11000")
  let anchor = support.valid(2026, 1, 1, 9, 30, 17)
  let before = support.valid(2026, 1, 1, 9, 30, 16)
  list.each([a.Inclusive(before), a.Exclusive(before)], fn(boundary) {
    support.expect_rule(
      rule,
      anchor,
      boundary,
      [#(2026, 1, 1, 9, 30, 17)],
      False,
    )
  })
}

pub fn distant_matching_preserves_the_anchor_second_test() {
  let rule = support.rule("FREQ=YEARLY;INTERVAL=11000")
  let anchor = support.valid(2026, 1, 1, 9, 30, 17)
  a.schedule_matches(
    a.schedule_from_rrule(rule, anchor: anchor),
    at: support.valid(13_026, 1, 1, 9, 30, 17),
  )
  |> should.equal(Ok(True))
  a.schedule_matches(
    a.schedule_from_rrule(rule, anchor: anchor),
    at: support.valid(13_026, 1, 1, 9, 30, 16),
  )
  |> should.equal(Ok(False))
  a.schedule_matches(
    a.schedule_from_rrule(rule, anchor: anchor),
    at: support.valid(13_026, 1, 1, 9, 30, 18),
  )
  |> should.equal(Ok(False))
}

pub fn count_two_yields_anchor_and_distant_value_then_done_test() {
  let rule = support.rule("FREQ=YEARLY;INTERVAL=11000;COUNT=2")
  let anchor = support.valid(2026, 1, 1, 9, 30, 17)
  support.expect_rule(
    rule,
    anchor,
    a.Inclusive(anchor),
    [#(2026, 1, 1, 9, 30, 17), #(13_026, 1, 1, 9, 30, 17)],
    True,
  )
}

pub fn count_two_does_not_admit_the_third_occurrence_test() {
  let rule = support.rule("FREQ=YEARLY;INTERVAL=11000;COUNT=2")
  let anchor = support.valid(2026, 1, 1, 9, 30, 17)
  a.schedule_matches(
    a.schedule_from_rrule(rule, anchor: anchor),
    at: support.valid(24_026, 1, 1, 9, 30, 17),
  )
  |> should.equal(Ok(False))
}

pub fn count_two_query_near_second_value_keeps_remaining_count_test() {
  let rule = support.rule("FREQ=YEARLY;INTERVAL=11000;COUNT=2")
  let anchor = support.valid(2026, 1, 1, 9, 30, 17)
  let before = support.valid(13_026, 1, 1, 9, 30, 16)
  let second = support.valid(13_026, 1, 1, 9, 30, 17)
  list.each(
    [a.Inclusive(before), a.Exclusive(before), a.Inclusive(second)],
    fn(boundary) {
      support.expect_rule(
        rule,
        anchor,
        boundary,
        [#(13_026, 1, 1, 9, 30, 17)],
        True,
      )
    },
  )
}

pub fn count_two_query_after_second_value_is_done_test() {
  let rule = support.rule("FREQ=YEARLY;INTERVAL=11000;COUNT=2")
  let anchor = support.valid(2026, 1, 1, 9, 30, 17)
  let second = support.valid(13_026, 1, 1, 9, 30, 17)
  support.expect_rule(rule, anchor, a.Exclusive(second), [], True)
  support.expect_rule(
    rule,
    anchor,
    a.Inclusive(support.valid(24_026, 1, 1, 9, 30, 17)),
    [],
    True,
  )
  a.schedule_next(a.schedule_from_rrule(rule, anchor: anchor), after: second)
  |> should.equal(Ok(None))
}

pub fn count_one_finishes_without_distant_search_test() {
  let rule = support.rule("FREQ=YEARLY;INTERVAL=11000;COUNT=1")
  let anchor = support.valid(2026, 1, 1, 9, 30, 17)
  support.expect_rule(
    rule,
    anchor,
    a.Inclusive(anchor),
    [#(2026, 1, 1, 9, 30, 17)],
    True,
  )
  support.expect_rule(rule, anchor, a.Exclusive(anchor), [], True)
}

pub fn distant_count_is_preserved_by_unified_schedule_test() {
  let anchor = support.valid(2026, 1, 1, 9, 30, 17)
  let value =
    a.schedule_from_rrule(
      support.rule("FREQ=YEARLY;INTERVAL=11000;COUNT=2"),
      anchor:,
    )
  support.expect_schedule(
    value,
    a.Inclusive(anchor),
    [#(2026, 1, 1, 9, 30, 17), #(13_026, 1, 1, 9, 30, 17)],
    True,
  )
  a.schedule_matches(value, at: support.valid(24_026, 1, 1, 9, 30, 17))
  |> should.equal(Ok(False))
}

pub fn distant_datetime_until_is_inclusive_test() {
  let rule = support.rule("FREQ=YEARLY;INTERVAL=11000;UNTIL=90000101T093017Z")
  let anchor = support.valid(-2000, 1, 1, 9, 30, 17)
  let last = support.valid(9000, 1, 1, 9, 30, 17)
  support.expect_rule(
    rule,
    anchor,
    a.Exclusive(anchor),
    [#(9000, 1, 1, 9, 30, 17)],
    True,
  )
  a.schedule_matches(a.schedule_from_rrule(rule, anchor: anchor), at: last)
  |> should.equal(Ok(True))
  support.expect_rule(
    rule,
    anchor,
    a.Inclusive(last),
    [#(9000, 1, 1, 9, 30, 17)],
    True,
  )
  support.expect_rule(rule, anchor, a.Exclusive(last), [], True)
}

pub fn until_one_second_before_distant_value_excludes_it_test() {
  let rule = support.rule("FREQ=YEARLY;INTERVAL=11000;UNTIL=90000101T093016Z")
  let anchor = support.valid(-2000, 1, 1, 9, 30, 17)
  a.schedule_next(a.schedule_from_rrule(rule, anchor: anchor), after: anchor)
  |> should.equal(Ok(None))
  a.schedule_matches(
    a.schedule_from_rrule(rule, anchor: anchor),
    at: support.valid(9000, 1, 1, 9, 30, 17),
  )
  |> should.equal(Ok(False))
}

pub fn distant_date_until_includes_the_whole_day_test() {
  let rule = support.rule("FREQ=YEARLY;INTERVAL=11000;UNTIL=90000101")
  let anchor = support.valid(-2000, 1, 1, 9, 30, 17)
  support.expect_rule(
    rule,
    anchor,
    a.Exclusive(anchor),
    [#(9000, 1, 1, 9, 30, 17)],
    True,
  )
}

pub fn nonleap_four_hundred_year_phase_is_truly_empty_test() {
  let rule = support.rule("FREQ=YEARLY;INTERVAL=400;BYMONTH=2;BYMONTHDAY=29")
  let anchor = support.valid(2025, 1, 1, 0, 0, 0)
  a.schedule_next(a.schedule_from_rrule(rule, anchor: anchor), after: anchor)
  |> should.equal(Ok(None))
  support.expect_rule(rule, anchor, a.Inclusive(anchor), [], True)
}

pub fn leap_four_hundred_year_phase_has_concrete_occurrences_test() {
  let rule = support.rule("FREQ=YEARLY;INTERVAL=400;BYMONTH=2;BYMONTHDAY=29")
  let anchor = support.valid(2024, 1, 1, 0, 0, 0)
  support.expect_rule(
    rule,
    anchor,
    a.Inclusive(anchor),
    [#(2024, 2, 29, 0, 0, 0), #(2424, 2, 29, 0, 0, 0)],
    False,
  )
}
