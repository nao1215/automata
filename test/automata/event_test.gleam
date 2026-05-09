import automata/event
import automata/event/builtin/body
import automata/event/metadata
import automata/event/source
import automata/fsevent/event as fs_event
import automata/fsevent/path as fs_path
import automata/schedule/ast as schedule_ast
import gleam/dict
import gleam/option.{None, Some}
import gleeunit/should

fn normalized(path: String) {
  let assert Ok(value) = fs_path.normalize(path: path)
  value
}

fn fixed_now() {
  let assert Ok(value) =
    schedule_ast.try_valid_datetime(
      year: 2026,
      month: 5,
      day: 9,
      hour: 12,
      minute: 0,
      second: 0,
    )
  value
}

pub fn new_event_starts_with_empty_metadata_test() {
  let ev =
    event.new(
      id: "evt-1",
      occurred_at: fixed_now(),
      source: source.schedule(id: "daily-report"),
      body: body.scheduled(
        plan_id: "daily-report",
        fired_at: fixed_now(),
        schedule_kind: body.CronSchedule,
      ),
    )

  ev.id |> should.equal("evt-1")
  ev.metadata.correlation_id |> should.equal(None)
  ev.metadata.causation_id |> should.equal(None)
  ev.metadata.trace_id |> should.equal(None)
  metadata.has_attribute(ev.metadata, "x") |> should.equal(False)
}

pub fn with_helpers_compose_metadata_test() {
  let ev =
    event.new(
      id: "evt-1",
      occurred_at: fixed_now(),
      source: source.manual(id: "ops"),
      body: body.manual(reason: Some("on-call"), actor: Some("alice")),
    )
    |> event.with_correlation_id("corr-1")
    |> event.with_trace_id("trace-1")
    |> event.with_attribute("region", "ap-northeast-1")

  ev.metadata.correlation_id |> should.equal(Some("corr-1"))
  ev.metadata.trace_id |> should.equal(Some("trace-1"))
  metadata.attribute(ev.metadata, "region")
  |> should.equal(Some("ap-northeast-1"))
}

pub fn continue_from_chains_metadata_test() {
  let parent =
    event.new(
      id: "parent-1",
      occurred_at: fixed_now(),
      source: source.file_system(id: "/var/log"),
      body: body.file_system(
        event: fs_event.written(path: normalized("/var/log/app.log")),
      ),
    )
    |> event.with_correlation_id("corr-A")
    |> event.with_trace_id("trace-A")
    |> event.with_attribute("env", "prod")

  let child =
    event.continue_from(
      parent: parent,
      id: "child-1",
      occurred_at: fixed_now(),
      source: source.manual(id: "ingest-pipeline"),
      body: body.custom(
        kind: "ingest.normalized",
        attributes: parent.metadata.attributes,
      ),
    )

  child.id |> should.equal("child-1")
  child.metadata.correlation_id |> should.equal(Some("corr-A"))
  child.metadata.causation_id |> should.equal(Some("parent-1"))
  child.metadata.trace_id |> should.equal(Some("trace-A"))
  metadata.attribute(child.metadata, "env") |> should.equal(Some("prod"))
}

pub fn source_kind_string_labels_test() {
  source.kind_to_string(source.ScheduleSource) |> should.equal("schedule")
  source.kind_to_string(source.FileSystemSource) |> should.equal("file_system")
  source.kind_to_string(source.ManualSource) |> should.equal("manual")
  source.kind_to_string(source.WebhookSource) |> should.equal("webhook")
  source.kind_to_string(source.QueueSource) |> should.equal("queue")
  source.kind_to_string(source.SignalSource) |> should.equal("signal")
  source.kind_to_string(source.HttpSource) |> should.equal("http")
  source.kind_to_string(source.CloudEventSource) |> should.equal("cloud_event")
  source.kind_to_string(source.CustomSource("slack.bot"))
  |> should.equal("custom:slack.bot")
}

pub fn source_with_name_attaches_label_test() {
  let s =
    source.schedule(id: "daily-report")
    |> source.with_name(name: "Daily report")

  s.kind |> should.equal(source.ScheduleSource)
  s.id |> should.equal("daily-report")
  s.name |> should.equal(Some("Daily report"))
}

pub fn builtin_new_derives_schedule_source_for_scheduled_test() {
  let now = fixed_now()
  let ev =
    body.new(
      id: "evt-1",
      occurred_at: now,
      source_id: "daily-report",
      body: body.scheduled(
        plan_id: "daily-report",
        fired_at: now,
        schedule_kind: body.CronSchedule,
      ),
    )

  ev.source.kind |> should.equal(source.ScheduleSource)
  ev.source.id |> should.equal("daily-report")
  ev.source.name |> should.equal(None)
}

pub fn builtin_new_derives_file_system_source_for_file_body_test() {
  let now = fixed_now()
  let ev =
    body.new(
      id: "evt-1",
      occurred_at: now,
      source_id: "watch-1",
      body: body.file_system(
        event: fs_event.written(path: normalized("/var/log/app.log")),
      ),
    )

  ev.source.kind |> should.equal(source.FileSystemSource)
}

pub fn builtin_new_derives_manual_source_for_manual_body_test() {
  let now = fixed_now()
  let ev =
    body.new(
      id: "evt-1",
      occurred_at: now,
      source_id: "ops",
      body: body.manual(reason: None, actor: None),
    )

  ev.source.kind |> should.equal(source.ManualSource)
}

pub fn builtin_new_derives_custom_source_kind_from_custom_body_test() {
  let now = fixed_now()
  let ev =
    body.new(
      id: "evt-1",
      occurred_at: now,
      source_id: "ws-1",
      body: body.custom(kind: "slack.message_posted", attributes: dict.new()),
    )

  ev.source.kind |> should.equal(source.CustomSource("slack.message_posted"))
  ev.source.id |> should.equal("ws-1")
}

pub fn builtin_body_kind_strings_test() {
  body.kind(body.scheduled(
    plan_id: "p",
    fired_at: fixed_now(),
    schedule_kind: body.CronSchedule,
  ))
  |> should.equal("scheduled")

  body.kind(
    body.file_system(event: fs_event.created(path: normalized("/tmp/a"))),
  )
  |> should.equal("file_system:create")
  body.kind(
    body.file_system(event: fs_event.written(path: normalized("/tmp/a"))),
  )
  |> should.equal("file_system:write")
  body.kind(
    body.file_system(event: fs_event.removed(path: normalized("/tmp/a"))),
  )
  |> should.equal("file_system:remove")
  body.kind(
    body.file_system(event: fs_event.renamed(
      to: normalized("/b"),
      from: normalized("/a"),
    )),
  )
  |> should.equal("file_system:rename")
  body.kind(body.manual(reason: None, actor: None)) |> should.equal("manual")
  body.kind(body.custom(
    kind: "slack.message_posted",
    attributes: metadata.empty().attributes,
  ))
  |> should.equal("custom:slack.message_posted")
}
