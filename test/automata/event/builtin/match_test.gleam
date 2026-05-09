import automata/event
import automata/event/builtin/body
import automata/event/builtin/match as builtin_match
import automata/event/source
import automata/fsevent/event as fs_event
import automata/fsevent/path as fs_path
import automata/schedule/ast as schedule_ast
import gleam/dict
import gleam/option.{None}
import gleeunit/should

fn normalized(path: String) {
  let assert Ok(value) = fs_path.normalize(path: path)
  value
}

fn now() {
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

fn cron_event() {
  event.new(
    id: "c",
    occurred_at: now(),
    source: source.schedule(id: "p"),
    body: body.scheduled(
      plan_id: "p",
      fired_at: now(),
      schedule_kind: body.CronSchedule,
    ),
  )
}

fn rrule_event() {
  event.new(
    id: "r",
    occurred_at: now(),
    source: source.schedule(id: "p"),
    body: body.scheduled(
      plan_id: "p",
      fired_at: now(),
      schedule_kind: body.RRuleSchedule,
    ),
  )
}

fn fs_modified_event() {
  event.new(
    id: "f",
    occurred_at: now(),
    source: source.file_system(id: "watch"),
    body: body.file_system(
      event: fs_event.written(path: normalized("/var/log/app.log")),
    ),
  )
}

fn manual_event() {
  event.new(
    id: "m",
    occurred_at: now(),
    source: source.manual(id: "ops"),
    body: body.manual(reason: None, actor: None),
  )
}

fn custom_event() {
  event.new(
    id: "x",
    occurred_at: now(),
    source: source.custom(kind: "slack", id: "ws-1"),
    body: body.custom(kind: "slack.posted", attributes: dict.new()),
  )
}

pub fn is_scheduled_distinguishes_test() {
  builtin_match.is_scheduled(cron_event()) |> should.equal(True)
  builtin_match.is_scheduled(fs_modified_event()) |> should.equal(False)
}

pub fn is_schedule_kind_filters_test() {
  builtin_match.is_schedule_kind(cron_event(), body.CronSchedule)
  |> should.equal(True)
  builtin_match.is_schedule_kind(rrule_event(), body.CronSchedule)
  |> should.equal(False)
  builtin_match.is_schedule_kind(rrule_event(), body.RRuleSchedule)
  |> should.equal(True)
}

pub fn is_file_event_includes_all_variants_test() {
  builtin_match.is_file_event(fs_modified_event()) |> should.equal(True)
  builtin_match.is_file_event(cron_event()) |> should.equal(False)
}

pub fn is_manual_and_custom_test() {
  builtin_match.is_manual(manual_event()) |> should.equal(True)
  builtin_match.is_manual(custom_event()) |> should.equal(False)
  builtin_match.is_custom(custom_event()) |> should.equal(True)
  builtin_match.is_custom_kind(custom_event(), kind: "slack.posted")
  |> should.equal(True)
  builtin_match.is_custom_kind(custom_event(), kind: "other.kind")
  |> should.equal(False)
}
