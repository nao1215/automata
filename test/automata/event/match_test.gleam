import automata/event
import automata/event/builtin/body
import automata/event/match
import automata/event/source
import automata/schedule/ast as schedule_ast
import gleam/option.{None, Some}
import gleeunit/should

fn at(year: Int, month: Int, day: Int) {
  let assert Ok(value) =
    schedule_ast.try_valid_datetime(
      year:,
      month:,
      day:,
      hour: 9,
      minute: 0,
      second: 0,
    )
  value
}

fn scheduled_event(id: String, plan: String) {
  event.new(
    id: id,
    occurred_at: at(2026, 5, 9),
    source: source.schedule(id: plan),
    body: body.scheduled(
      plan_id: plan,
      fired_at: at(2026, 5, 9),
      schedule_kind: body.CronSchedule,
    ),
  )
}

pub fn has_source_kind_test() {
  let ev = scheduled_event("e", "p")

  match.has_source_kind(ev, kind: source.ScheduleSource)
  |> should.equal(True)
  match.has_source_kind(ev, kind: source.FileSystemSource)
  |> should.equal(False)
}

pub fn has_correlation_id_reflects_metadata_test() {
  let bare = scheduled_event("e", "p")
  match.has_correlation_id(bare) |> should.equal(False)

  let tagged = bare |> event.with_correlation_id("corr-1")
  match.has_correlation_id(tagged) |> should.equal(True)
}

pub fn has_causation_id_reflects_metadata_test() {
  let bare = scheduled_event("e", "p")
  match.has_causation_id(bare) |> should.equal(False)

  let tagged = bare |> event.with_causation_id("cause-1")
  match.has_causation_id(tagged) |> should.equal(True)
}

pub fn has_trace_id_reflects_metadata_test() {
  let bare = scheduled_event("e", "p")
  match.has_trace_id(bare) |> should.equal(False)

  let tagged = bare |> event.with_trace_id("trace-1")
  match.has_trace_id(tagged) |> should.equal(True)
}

pub fn continue_from_propagates_correlation_and_trace_test() {
  let parent =
    scheduled_event("parent", "p")
    |> event.with_correlation_id("corr-1")
    |> event.with_trace_id("trace-1")

  let child =
    event.continue_from(
      parent: parent,
      id: "child",
      occurred_at: at(2026, 5, 10),
      source: source.manual(id: "manual-1"),
      body: body.manual(reason: Some("rerun"), actor: None),
    )

  match.has_correlation_id(child) |> should.equal(True)
  match.has_causation_id(child) |> should.equal(True)
  match.has_trace_id(child) |> should.equal(True)
}
