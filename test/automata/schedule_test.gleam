import automata/cron
import automata/cron/validator as cron_validator
import automata/rrule
import automata/rrule/validator as rule_validator
import automata/schedule
import automata/schedule/ast as schedule_ast
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
  let compiled =
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

pub fn from_once_matches_only_at_target_test() {
  let target = vdt(2026, 5, 1, 12, 0, 0)
  let compiled = schedule.from_once(at: target)

  schedule.matches(compiled, at: target) |> should.equal(True)
  schedule.matches(compiled, at: vdt(2026, 5, 1, 12, 0, 1))
  |> should.equal(False)
  schedule.matches(compiled, at: vdt(2026, 5, 1, 11, 59, 59))
  |> should.equal(False)
}

pub fn from_once_next_after_returns_target_then_none_test() {
  let target = vdt(2026, 5, 1, 12, 0, 0)
  let compiled = schedule.from_once(at: target)

  schedule.next_after(compiled, after: vdt(2026, 4, 30, 23, 59, 59))
  |> should.equal(Some(target))

  schedule.next_after(compiled, after: target)
  |> should.equal(None)
}

pub fn from_once_iterator_terminates_after_one_yield_test() {
  let target = vdt(2026, 5, 1, 12, 0, 0)
  let compiled = schedule.from_once(at: target)

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
  let compiled = schedule.from_once(at: target)

  let it =
    schedule.iterator_after(compiled, boundary: schedule_ast.Exclusive(target))

  schedule.step(it) |> should.equal(schedule.Done)
}
