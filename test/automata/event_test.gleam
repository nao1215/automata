import automata
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import gleam/string
import gleam/time/calendar
import gleeunit/should

fn at(day: Int) -> automata.ValidDateTime {
  let assert Ok(value) =
    automata.datetime_validate(automata.DateTime(
      calendar.Date(2026, calendar.May, day),
      calendar.TimeOfDay(9, 0, 0, 0),
    ))
  value
}

fn normalized(path: String) -> automata.NormalizedPath {
  let assert Ok(value) = automata.path_normalize(path: path)
  value
}

fn watch_event(path: String, operation: automata.Op) -> automata.WatchEvent {
  let assert Ok(value) =
    automata.filesystem_event(
      path: normalized(path),
      ops: set.from_list([operation]),
      renamed_from: None,
    )
  value
}

fn scheduled_event(
  id: String,
  plan: String,
) -> automata.Event(automata.EventBody) {
  automata.builtin_event(
    id: id,
    occurred_at: at(9),
    source_id: plan,
    body: automata.Scheduled(plan, at(9), automata.CronSchedule),
  )
}

fn file_event(id: String, path: String) -> automata.Event(automata.EventBody) {
  automata.builtin_event(
    id: id,
    occurred_at: at(9),
    source_id: "watch-1",
    body: automata.FileSystem(watch_event(path, automata.Write)),
  )
}

fn custom_event() -> automata.Event(automata.EventBody) {
  automata.builtin_event(
    id: "x",
    occurred_at: at(9),
    source_id: "ws-1",
    body: automata.Custom("slack.posted", dict.new()),
  )
}

fn manual_event() -> automata.Event(automata.EventBody) {
  automata.builtin_event(
    id: "m",
    occurred_at: at(9),
    source_id: "ops",
    body: automata.Manual(None, None),
  )
}

fn path_matches(
  event: automata.Event(automata.EventBody),
  check: fn(String) -> Bool,
) -> Bool {
  case event.body {
    automata.FileSystem(value) ->
      check(
        automata.path_to_string(path: automata.filesystem_event_path(
          event: value,
        )),
      )
    automata.Scheduled(..) | automata.Manual(..) | automata.Custom(..) -> False
  }
}

pub fn new_event_starts_with_empty_metadata_test() {
  let event = scheduled_event("evt-1", "daily-report")
  event.id |> should.equal("evt-1")
  event.metadata.correlation_id |> should.equal(None)
  event.metadata.causation_id |> should.equal(None)
  event.metadata.trace_id |> should.equal(None)
  dict.has_key(event.metadata.attributes, "x") |> should.equal(False)
}

pub fn continue_from_chains_metadata_test() {
  let bare = file_event("parent-1", "/var/log/app.log")
  let parent =
    automata.Event(
      ..bare,
      metadata: automata.Metadata(
        Some("corr-A"),
        None,
        Some("trace-A"),
        dict.from_list([#("env", "prod")]),
      ),
    )
  let child =
    automata.event_continue_from(
      parent: parent,
      id: "child-1",
      occurred_at: at(9),
      source: automata.Source(automata.ManualSource, "ingest-pipeline", None),
      body: automata.Custom("ingest.normalized", parent.metadata.attributes),
    )
  child.id |> should.equal("child-1")
  child.metadata.correlation_id |> should.equal(Some("corr-A"))
  child.metadata.causation_id |> should.equal(Some("parent-1"))
  child.metadata.trace_id |> should.equal(Some("trace-A"))
  dict.get(child.metadata.attributes, "env") |> should.equal(Ok("prod"))
}

pub fn continue_from_inherits_attributes_documented_test() {
  let bare = manual_event()
  let parent =
    automata.Event(
      ..bare,
      id: "p",
      metadata: automata.Metadata(
        Some("c"),
        None,
        Some("t"),
        dict.from_list([#("tenant", "acme"), #("user_id", "alice")]),
      ),
    )
  let child =
    automata.event_continue_from(
      parent: parent,
      id: "child",
      occurred_at: at(9),
      source: automata.Source(automata.ManualSource, "ops", None),
      body: automata.Manual(Some("escalated"), Some("ops")),
    )
  dict.get(child.metadata.attributes, "tenant") |> should.equal(Ok("acme"))
  dict.get(child.metadata.attributes, "user_id") |> should.equal(Ok("alice"))
  child.metadata.causation_id |> should.equal(Some("p"))
}

pub fn source_kind_string_labels_test() {
  let cases = [
    #(automata.ScheduleSource, "schedule"),
    #(automata.FileSystemSource, "file_system"),
    #(automata.ManualSource, "manual"),
    #(automata.WebhookSource, "webhook"),
    #(automata.QueueSource, "queue"),
    #(automata.SignalSource, "signal"),
    #(automata.HttpSource, "http"),
    #(automata.CloudEventSource, "cloud_event"),
    #(automata.CustomSource("slack.bot"), "custom:slack.bot"),
  ]
  list.each(cases, fn(pair) {
    automata.source_kind_to_string(pair.0) |> should.equal(pair.1)
  })
}

pub fn builtin_new_derives_schedule_source_for_scheduled_test() {
  let event = scheduled_event("evt-1", "daily-report")
  event.source.kind |> should.equal(automata.ScheduleSource)
  event.source.id |> should.equal("daily-report")
  event.source.name |> should.equal(None)
}

pub fn builtin_new_derives_file_system_source_for_file_body_test() {
  file_event("evt-1", "/var/log/app.log").source.kind
  |> should.equal(automata.FileSystemSource)
}

pub fn builtin_new_derives_manual_source_for_manual_body_test() {
  manual_event().source.kind |> should.equal(automata.ManualSource)
}

pub fn builtin_new_derives_custom_source_kind_from_custom_body_test() {
  let event =
    automata.builtin_event(
      id: "evt-1",
      occurred_at: at(9),
      source_id: "ws-1",
      body: automata.Custom("slack.message_posted", dict.new()),
    )
  event.source.kind
  |> should.equal(automata.CustomSource("slack.message_posted"))
  event.source.id |> should.equal("ws-1")
}

pub fn builtin_body_kind_strings_test() {
  automata.event_body_kind(automata.Scheduled("p", at(9), automata.CronSchedule))
  |> should.equal("scheduled")
  let cases = [
    #(automata.Create, "file_system:create"),
    #(automata.Write, "file_system:write"),
    #(automata.Remove, "file_system:remove"),
  ]
  list.each(cases, fn(pair) {
    automata.event_body_kind(automata.FileSystem(watch_event("/tmp/a", pair.0)))
    |> should.equal(pair.1)
  })
  let assert Ok(renamed) =
    automata.filesystem_event(
      path: normalized("/b"),
      ops: set.from_list([automata.Rename]),
      renamed_from: Some(normalized("/a")),
    )
  automata.event_body_kind(automata.FileSystem(renamed))
  |> should.equal("file_system:rename")
  automata.event_body_kind(automata.Manual(None, None))
  |> should.equal("manual")
  automata.event_body_kind(automata.Custom("slack.message_posted", dict.new()))
  |> should.equal("custom:slack.message_posted")
}

pub fn scheduled_event_derives_schedule_source_test() {
  let event =
    automata.builtin_event(
      id: "evt-2",
      occurred_at: at(9),
      source_id: "weekly-digest",
      body: automata.Scheduled("weekly-digest", at(9), automata.RRuleSchedule),
    )
  event.source
  |> should.equal(automata.Source(
    automata.ScheduleSource,
    "weekly-digest",
    None,
  ))
}

pub fn scheduled_event_round_trips_through_body_test() {
  let event = scheduled_event("evt-3", "hourly-cleanup")
  case event.body {
    automata.Scheduled(plan_id, fired_at, kind) -> {
      plan_id |> should.equal("hourly-cleanup")
      fired_at |> should.equal(at(9))
      kind |> should.equal(automata.CronSchedule)
    }
    automata.FileSystem(..) | automata.Manual(..) | automata.Custom(..) ->
      should.fail()
  }
  event.metadata
  |> should.equal(automata.Metadata(None, None, None, dict.new()))
}

pub fn is_scheduled_distinguishes_test() {
  let is_scheduled = fn(event: automata.Event(automata.EventBody)) {
    case event.body {
      automata.Scheduled(..) -> True
      automata.FileSystem(..) | automata.Manual(..) | automata.Custom(..) ->
        False
    }
  }
  is_scheduled(scheduled_event("c", "p")) |> should.equal(True)
  is_scheduled(file_event("f", "/var/log/app.log")) |> should.equal(False)
}

pub fn is_schedule_kind_filters_test() {
  let cron = scheduled_event("c", "p")
  let recurrence =
    automata.builtin_event(
      id: "r",
      occurred_at: at(9),
      source_id: "p",
      body: automata.Scheduled("p", at(9), automata.RRuleSchedule),
    )
  let by_kind = fn(events, kind) {
    list.filter(events, fn(event: automata.Event(automata.EventBody)) {
      case event.body {
        automata.Scheduled(_, _, actual) -> actual == kind
        automata.FileSystem(..) | automata.Manual(..) | automata.Custom(..) ->
          False
      }
    })
  }
  by_kind([cron, recurrence], automata.CronSchedule) |> should.equal([cron])
  by_kind([cron, recurrence], automata.RRuleSchedule)
  |> should.equal([recurrence])
}

pub fn is_file_event_includes_all_variants_test() {
  let is_file = fn(event: automata.Event(automata.EventBody)) {
    case event.body {
      automata.FileSystem(_) -> True
      automata.Scheduled(..) | automata.Manual(..) | automata.Custom(..) ->
        False
    }
  }
  is_file(file_event("f", "/var/log/app.log")) |> should.equal(True)
  is_file(scheduled_event("c", "p")) |> should.equal(False)
}

pub fn is_manual_and_custom_test() {
  let manual = manual_event()
  let custom = custom_event()
  let bodies = [manual.body, custom.body]
  list.filter(bodies, fn(body) {
    case body {
      automata.Manual(..) -> True
      automata.Scheduled(..) | automata.FileSystem(..) | automata.Custom(..) ->
        False
    }
  })
  |> should.equal([manual.body])
  list.filter(bodies, fn(body) {
    case body {
      automata.Custom(kind, _) -> kind == "slack.posted"
      automata.Scheduled(..) | automata.FileSystem(..) | automata.Manual(..) ->
        False
    }
  })
  |> should.equal([custom.body])
  list.any(bodies, fn(body) {
    case body {
      automata.Custom(kind, _) -> kind == "other.kind"
      automata.Scheduled(..) | automata.FileSystem(..) | automata.Manual(..) ->
        False
    }
  })
  |> should.equal(False)
}

pub fn by_source_kind_filters_test() {
  let event = scheduled_event("e", "p")
  { event.source.kind == automata.ScheduleSource } |> should.equal(True)
  { event.source.kind == automata.FileSystemSource } |> should.equal(False)
}

pub fn by_correlation_id_filters_test() {
  let bare = scheduled_event("e", "p")
  let event =
    automata.Event(
      ..bare,
      metadata: automata.Metadata(
        ..bare.metadata,
        correlation_id: Some("corr-1"),
      ),
    )
  { event.metadata.correlation_id == Some("corr-1") } |> should.equal(True)
  { event.metadata.correlation_id == Some("corr-2") } |> should.equal(False)
}

pub fn occurred_between_inclusive_test() {
  let event = scheduled_event("e", "p")
  automata.event_occurred_between(event, from: at(9), until: at(9))
  |> should.equal(True)
  automata.event_occurred_between(event, from: at(10), until: at(11))
  |> should.equal(False)
}

pub fn keep_and_reject_partition_test() {
  let first = file_event("a", "/var/log/a.log")
  let second = file_event("b", "/etc/b.conf")
  let third = scheduled_event("c", "plan")
  let matches = fn(event) {
    path_matches(event, string.starts_with(_, "/var/log/"))
  }
  list.filter([first, second, third], matches) |> should.equal([first])
  list.filter([first, second, third], fn(event) { !matches(event) })
  |> should.equal([second, third])
}

pub fn builtin_path_filters_test() {
  let log = file_event("a", "/var/log/app.log")
  let temp = file_event("b", "/tmp/scratch.tmp")
  path_matches(log, string.starts_with(_, "/var/")) |> should.equal(True)
  path_matches(log, string.starts_with(_, "/etc/")) |> should.equal(False)
  path_matches(log, string.ends_with(_, ".log")) |> should.equal(True)
  path_matches(temp, string.ends_with(_, ".log")) |> should.equal(False)
  path_matches(log, string.contains(_, "app")) |> should.equal(True)
  path_matches(temp, string.contains(_, "app")) |> should.equal(False)
}

pub fn builtin_schedule_kind_filter_test() {
  let cron = scheduled_event("c", "p")
  let recurrence =
    automata.builtin_event(
      id: "r",
      occurred_at: at(9),
      source_id: "p",
      body: automata.Scheduled("p", at(9), automata.RRuleSchedule),
    )
  list.filter([cron, recurrence], fn(event) {
    case event.body {
      automata.Scheduled(_, _, automata.CronSchedule) -> True
      automata.Scheduled(..)
      | automata.FileSystem(..)
      | automata.Manual(..)
      | automata.Custom(..) -> False
    }
  })
  |> should.equal([cron])
}

pub fn builtin_custom_kind_filter_test() {
  let event =
    automata.builtin_event(
      id: "x",
      occurred_at: at(9),
      source_id: "ws-1",
      body: automata.Custom("slack.message_posted", dict.new()),
    )
  case event.body {
    automata.Custom(kind, _) -> {
      kind |> should.equal("slack.message_posted")
      { kind == "github.pr_opened" } |> should.equal(False)
    }
    automata.Scheduled(..) | automata.FileSystem(..) | automata.Manual(..) ->
      should.fail()
  }
}

pub fn predicate_lifts_arbitrary_check_test() {
  let first = scheduled_event("alpha", "p")
  let second = scheduled_event("beta", "p")
  list.filter([first, second], fn(event) { event.id == "alpha" })
  |> should.equal([first])
}

pub fn by_source_filters_on_full_source_test() {
  let event = scheduled_event("e", "plan-1")
  { event.source == automata.Source(automata.ScheduleSource, "plan-1", None) }
  |> should.equal(True)
  { event.source == automata.Source(automata.ScheduleSource, "plan-2", None) }
  |> should.equal(False)
  { event.source == automata.Source(automata.FileSystemSource, "plan-1", None) }
  |> should.equal(False)
}

pub fn by_source_id_filters_on_id_only_test() {
  let event = scheduled_event("e", "plan-1")
  { event.source.id == "plan-1" } |> should.equal(True)
  { event.source.id == "plan-2" } |> should.equal(False)
}

pub fn by_causation_id_filters_test() {
  let bare = scheduled_event("e", "p")
  let event =
    automata.Event(
      ..bare,
      metadata: automata.Metadata(
        ..bare.metadata,
        causation_id: Some("cause-1"),
      ),
    )
  { event.metadata.causation_id == Some("cause-1") } |> should.equal(True)
  { event.metadata.causation_id == Some("cause-2") } |> should.equal(False)
  bare.metadata.causation_id |> should.equal(None)
}

pub fn by_trace_id_filters_test() {
  let bare = scheduled_event("e", "p")
  let event =
    automata.Event(
      ..bare,
      metadata: automata.Metadata(..bare.metadata, trace_id: Some("trace-1")),
    )
  { event.metadata.trace_id == Some("trace-1") } |> should.equal(True)
  { event.metadata.trace_id == Some("trace-2") } |> should.equal(False)
  bare.metadata.trace_id |> should.equal(None)
}

pub fn by_attribute_matches_present_value_test() {
  let bare = scheduled_event("e", "p")
  let event =
    automata.Event(
      ..bare,
      metadata: automata.Metadata(
        ..bare.metadata,
        attributes: dict.from_list([#("team", "platform")]),
      ),
    )
  dict.get(event.metadata.attributes, "team") |> should.equal(Ok("platform"))
  { dict.get(event.metadata.attributes, "team") == Ok("data") }
  |> should.equal(False)
  dict.get(event.metadata.attributes, "owner") |> should.equal(Error(Nil))
}

pub fn has_attribute_checks_presence_only_test() {
  let bare = scheduled_event("e", "p")
  let event =
    automata.Event(
      ..bare,
      metadata: automata.Metadata(
        ..bare.metadata,
        attributes: dict.from_list([#("team", "platform")]),
      ),
    )
  dict.has_key(event.metadata.attributes, "team") |> should.equal(True)
  dict.has_key(event.metadata.attributes, "owner") |> should.equal(False)
}

pub fn occurred_after_is_strict_test() {
  let event = scheduled_event("e", "p")
  automata.event_occurred_after(event, after: at(8)) |> should.equal(True)
  automata.event_occurred_after(event, after: at(9)) |> should.equal(False)
  automata.event_occurred_after(event, after: at(10)) |> should.equal(False)
}

pub fn occurred_before_is_strict_test() {
  let event = scheduled_event("e", "p")
  automata.event_occurred_before(event, before: at(10)) |> should.equal(True)
  automata.event_occurred_before(event, before: at(9)) |> should.equal(False)
  automata.event_occurred_before(event, before: at(8)) |> should.equal(False)
}

pub fn on_body_option_returns_false_when_extractor_yields_none_test() {
  let event = scheduled_event("e", "p")
  let path = case event.body {
    automata.FileSystem(value) ->
      Some(automata.filesystem_event_path(event: value))
    automata.Scheduled(..) | automata.Manual(..) | automata.Custom(..) -> None
  }
  option.is_some(path) |> should.equal(False)
}

pub fn has_source_kind_test() {
  let event = scheduled_event("e", "p")
  event.source.kind |> should.equal(automata.ScheduleSource)
  { event.source.kind == automata.FileSystemSource } |> should.equal(False)
}

pub fn has_correlation_id_reflects_metadata_test() {
  let bare = scheduled_event("e", "p")
  option.is_some(bare.metadata.correlation_id) |> should.equal(False)
  let tagged =
    automata.Event(
      ..bare,
      metadata: automata.Metadata(
        ..bare.metadata,
        correlation_id: Some("corr-1"),
      ),
    )
  option.is_some(tagged.metadata.correlation_id) |> should.equal(True)
}

pub fn has_causation_id_reflects_metadata_test() {
  let bare = scheduled_event("e", "p")
  option.is_some(bare.metadata.causation_id) |> should.equal(False)
  let tagged =
    automata.Event(
      ..bare,
      metadata: automata.Metadata(
        ..bare.metadata,
        causation_id: Some("cause-1"),
      ),
    )
  option.is_some(tagged.metadata.causation_id) |> should.equal(True)
}

pub fn has_trace_id_reflects_metadata_test() {
  let bare = scheduled_event("e", "p")
  option.is_some(bare.metadata.trace_id) |> should.equal(False)
  let tagged =
    automata.Event(
      ..bare,
      metadata: automata.Metadata(..bare.metadata, trace_id: Some("trace-1")),
    )
  option.is_some(tagged.metadata.trace_id) |> should.equal(True)
}

pub fn continue_from_propagates_correlation_and_trace_test() {
  let bare = scheduled_event("parent", "p")
  let parent =
    automata.Event(
      ..bare,
      metadata: automata.Metadata(
        ..bare.metadata,
        correlation_id: Some("corr-1"),
        trace_id: Some("trace-1"),
      ),
    )
  let child =
    automata.event_continue_from(
      parent: parent,
      id: "child",
      occurred_at: at(10),
      source: automata.Source(automata.ManualSource, "manual-1", None),
      body: automata.Manual(Some("rerun"), None),
    )
  child.metadata.correlation_id |> should.equal(Some("corr-1"))
  child.metadata.causation_id |> should.equal(Some("parent"))
  child.metadata.trace_id |> should.equal(Some("trace-1"))
}

pub fn occurred_between_includes_interior_time_test() {
  // The event occurs on 2026-05-09, strictly inside the 8th..10th.
  let event = scheduled_event("e", "p")
  assert automata.event_occurred_between(event, from: at(8), until: at(10))
  assert !automata.event_occurred_between(event, from: at(8), until: at(8))
}
