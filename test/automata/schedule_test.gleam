import automata/cron
import automata/cron/validator as cron_validator
import automata/rrule
import automata/rrule/validator as rule_validator
import automata/schedule
import automata/schedule/ast as schedule_ast
import automata/schedule/evaluator as schedule_evaluator
import automata/schedule/iterator as schedule_iterator
import automata/schedule/next as schedule_next
import gleam/option.{Some}
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

pub fn shared_schedule_matches_cron_test() {
  let compiled =
    schedule.from_cron(parse_and_validate_cron("*/30 9-17 * * 1-5"))

  schedule_evaluator.matches(
    compiled,
    at: schedule_ast.datetime(2026, 5, 11, 10, 0, 0),
  )
  |> should.equal(True)

  schedule_next.next_after(
    compiled,
    after: schedule_ast.datetime(2026, 5, 11, 10, 7, 0),
  )
  |> should.equal(Some(schedule_ast.datetime(2026, 5, 11, 10, 30, 0)))
}

pub fn shared_schedule_iterates_rrule_test() {
  let spec = parse_and_validate_rrule("FREQ=DAILY;COUNT=2;BYHOUR=9;BYMINUTE=0")
  let anchor = schedule_ast.datetime(2026, 5, 1, 9, 0, 0)
  let assert Ok(compiled) = schedule.from_rrule(spec, anchor: anchor)

  let iterator =
    schedule_iterator.after(
      compiled,
      boundary: schedule_ast.Exclusive(schedule_ast.datetime(
        2026,
        5,
        1,
        8,
        0,
        0,
      )),
    )

  let assert schedule.Yield(first_at, next_iterator) =
    schedule_iterator.step(iterator)
  first_at |> should.equal(schedule_ast.datetime(2026, 5, 1, 9, 0, 0))

  let assert schedule.Yield(second_at, _) =
    schedule_iterator.step(next_iterator)
  second_at |> should.equal(schedule_ast.datetime(2026, 5, 2, 9, 0, 0))
}

pub fn shared_schedule_next_after_preserves_rrule_seconds_test() {
  let spec = parse_and_validate_rrule("FREQ=DAILY;BYHOUR=9;BYMINUTE=0")
  let anchor = schedule_ast.datetime(2026, 5, 1, 9, 0, 30)
  let assert Ok(compiled) = schedule.from_rrule(spec, anchor: anchor)

  schedule_next.next_after(
    compiled,
    after: schedule_ast.datetime(2026, 5, 1, 9, 0, 0),
  )
  |> should.equal(Some(schedule_ast.datetime(2026, 5, 1, 9, 0, 30)))

  schedule_next.next_after(
    compiled,
    after: schedule_ast.datetime(2026, 5, 1, 9, 0, 30),
  )
  |> should.equal(Some(schedule_ast.datetime(2026, 5, 2, 9, 0, 30)))
}
