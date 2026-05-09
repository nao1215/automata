import automata/event/builtin/body
import automata/event/metadata
import automata/event/source
import automata/schedule/ast as schedule_ast
import gleeunit/should

fn at() -> schedule_ast.ValidDateTime {
  let assert Ok(value) =
    schedule_ast.try_valid_datetime(
      year: 2026,
      month: 5,
      day: 9,
      hour: 9,
      minute: 0,
      second: 0,
    )
  value
}

pub fn scheduled_event_smart_constructor_matches_verbose_form_test() {
  // The smart constructor should produce a value structurally equal to
  // the verbose `new(...) + scheduled(...)` form when source_id == plan_id
  // and occurred_at == fired_at. This is the documented common case.
  let smart =
    body.scheduled_event(
      id: "evt-1",
      plan_id: "daily-report",
      at: at(),
      schedule_kind: body.CronSchedule,
    )

  let verbose =
    body.new(
      id: "evt-1",
      occurred_at: at(),
      source_id: "daily-report",
      body: body.scheduled(
        plan_id: "daily-report",
        fired_at: at(),
        schedule_kind: body.CronSchedule,
      ),
    )

  smart |> should.equal(verbose)
}

pub fn scheduled_event_derives_schedule_source_test() {
  let evt =
    body.scheduled_event(
      id: "evt-2",
      plan_id: "weekly-digest",
      at: at(),
      schedule_kind: body.RRuleSchedule,
    )

  evt.source
  |> should.equal(source.schedule(id: "weekly-digest"))
}

pub fn scheduled_event_round_trips_through_body_test() {
  // Both the body's plan_id and the parent source's id are derived from
  // the single `plan_id` argument, so they should match.
  let evt =
    body.scheduled_event(
      id: "evt-3",
      plan_id: "hourly-cleanup",
      at: at(),
      schedule_kind: body.CronSchedule,
    )

  case evt.body {
    body.Scheduled(plan_id: pid, fired_at: fa, schedule_kind: kind) -> {
      pid |> should.equal("hourly-cleanup")
      fa |> should.equal(at())
      kind |> should.equal(body.CronSchedule)
    }
    _ -> should.fail()
  }
  // The metadata is empty by default — same as the verbose `new`.
  evt.metadata |> should.equal(metadata.empty())
}
