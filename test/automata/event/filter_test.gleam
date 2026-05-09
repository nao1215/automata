import automata/event
import automata/event/builtin/body
import automata/event/builtin/filter as builtin_filter
import automata/event/filter
import automata/event/source
import automata/fsevent/ast as fs_ast
import automata/fsevent/event as fs_event
import automata/fsevent/path as fs_path
import automata/schedule/ast as schedule_ast
import gleam/dict
import gleam/option
import gleeunit/should

fn normalized(path: String) {
  let assert Ok(value) = fs_path.normalize(path: path)
  value
}

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

fn file_event(id: String, path: String) {
  event.new(
    id: id,
    occurred_at: at(2026, 5, 9),
    source: source.file_system(id: "watch-1"),
    body: body.file_system(event: fs_event.written(path: normalized(path))),
  )
}

pub fn always_and_never_test() {
  let ev = scheduled_event("e", "p")
  filter.matches(filter.always(), ev) |> should.equal(True)
  filter.matches(filter.never(), ev) |> should.equal(False)
}

pub fn all_of_empty_is_always_test() {
  let ev = scheduled_event("e", "p")
  filter.matches(filter.all_of([]), ev) |> should.equal(True)
}

pub fn any_of_empty_is_never_test() {
  let ev = scheduled_event("e", "p")
  filter.matches(filter.any_of([]), ev) |> should.equal(False)
}

pub fn not_inverts_test() {
  let ev = scheduled_event("e", "p")
  filter.matches(filter.negate(filter.always()), ev) |> should.equal(False)
  filter.matches(filter.negate(filter.never()), ev) |> should.equal(True)
}

pub fn de_morgan_law_test() {
  let ev = file_event("e", "/var/log/app.log")
  let f1 = builtin_filter.is_file_with_op(op: fs_ast.Write)
  let f2 = builtin_filter.by_path_prefix(prefix: "/etc/")

  filter.matches(filter.negate(filter.any_of([f1, f2])), ev)
  |> should.equal(filter.matches(
    filter.all_of([filter.negate(f1), filter.negate(f2)]),
    ev,
  ))
}

pub fn by_source_kind_filters_test() {
  let ev = scheduled_event("e", "p")
  filter.matches(filter.by_source_kind(kind: source.ScheduleSource), ev)
  |> should.equal(True)
  filter.matches(filter.by_source_kind(kind: source.FileSystemSource), ev)
  |> should.equal(False)
}

pub fn by_correlation_id_filters_test() {
  let ev = scheduled_event("e", "p") |> event.with_correlation_id("corr-1")
  filter.matches(filter.by_correlation_id(id: "corr-1"), ev)
  |> should.equal(True)
  filter.matches(filter.by_correlation_id(id: "corr-2"), ev)
  |> should.equal(False)
}

pub fn occurred_between_inclusive_test() {
  let ev = scheduled_event("e", "p")
  let from = at(2026, 5, 9)
  let until = at(2026, 5, 9)

  filter.matches(filter.occurred_between(from: from, until: until), ev)
  |> should.equal(True)

  filter.matches(
    filter.occurred_between(from: at(2026, 5, 10), until: at(2026, 5, 11)),
    ev,
  )
  |> should.equal(False)
}

pub fn keep_and_reject_partition_test() {
  let a = file_event("a", "/var/log/a.log")
  let b = file_event("b", "/etc/b.conf")
  let c = scheduled_event("c", "plan")

  let f = builtin_filter.by_path_prefix(prefix: "/var/log/")

  filter.keep(f, [a, b, c]) |> should.equal([a])
  filter.reject(f, [a, b, c]) |> should.equal([b, c])
}

pub fn builtin_path_filters_test() {
  let log = file_event("a", "/var/log/app.log")
  let tmp = file_event("b", "/tmp/scratch.tmp")

  filter.matches(builtin_filter.by_path_prefix(prefix: "/var/"), log)
  |> should.equal(True)
  filter.matches(builtin_filter.by_path_prefix(prefix: "/etc/"), log)
  |> should.equal(False)
  filter.matches(builtin_filter.by_path_suffix(suffix: ".log"), log)
  |> should.equal(True)
  filter.matches(builtin_filter.by_path_suffix(suffix: ".log"), tmp)
  |> should.equal(False)
  filter.matches(builtin_filter.by_path_contains(needle: "app"), log)
  |> should.equal(True)
  filter.matches(builtin_filter.by_path_contains(needle: "app"), tmp)
  |> should.equal(False)
}

pub fn builtin_schedule_kind_filter_test() {
  let cron_ev = scheduled_event("c", "p")
  let rrule_ev =
    event.new(
      id: "r",
      occurred_at: at(2026, 5, 9),
      source: source.schedule(id: "p"),
      body: body.scheduled(
        plan_id: "p",
        fired_at: at(2026, 5, 9),
        schedule_kind: body.RRuleSchedule,
      ),
    )

  filter.matches(
    builtin_filter.by_schedule_kind(kind: body.CronSchedule),
    cron_ev,
  )
  |> should.equal(True)
  filter.matches(
    builtin_filter.by_schedule_kind(kind: body.CronSchedule),
    rrule_ev,
  )
  |> should.equal(False)
}

pub fn builtin_custom_kind_filter_test() {
  let ev =
    event.new(
      id: "x",
      occurred_at: at(2026, 5, 9),
      source: source.custom(kind: "slack", id: "ws-1"),
      body: body.custom(kind: "slack.message_posted", attributes: dict.new()),
    )

  filter.matches(builtin_filter.is_custom(), ev) |> should.equal(True)
  filter.matches(
    builtin_filter.by_custom_kind(kind: "slack.message_posted"),
    ev,
  )
  |> should.equal(True)
  filter.matches(builtin_filter.by_custom_kind(kind: "github.pr_opened"), ev)
  |> should.equal(False)
}

pub fn predicate_lifts_arbitrary_check_test() {
  let a = scheduled_event("alpha", "p")
  let b = scheduled_event("beta", "p")

  let f = filter.predicate(check: fn(event) { event.id == "alpha" })

  filter.matches(f, a) |> should.equal(True)
  filter.matches(f, b) |> should.equal(False)
}

pub fn by_source_filters_on_full_source_test() {
  let ev = scheduled_event("e", "plan-1")

  filter.matches(filter.by_source(source: source.schedule(id: "plan-1")), ev)
  |> should.equal(True)
  filter.matches(filter.by_source(source: source.schedule(id: "plan-2")), ev)
  |> should.equal(False)
  filter.matches(filter.by_source(source: source.file_system(id: "plan-1")), ev)
  |> should.equal(False)
}

pub fn by_source_id_filters_on_id_only_test() {
  let ev = scheduled_event("e", "plan-1")

  filter.matches(filter.by_source_id(id: "plan-1"), ev) |> should.equal(True)
  filter.matches(filter.by_source_id(id: "plan-2"), ev) |> should.equal(False)
}

pub fn by_causation_id_filters_test() {
  let ev = scheduled_event("e", "p") |> event.with_causation_id("cause-1")

  filter.matches(filter.by_causation_id(id: "cause-1"), ev)
  |> should.equal(True)
  filter.matches(filter.by_causation_id(id: "cause-2"), ev)
  |> should.equal(False)

  // No causation id at all → must reject.
  filter.matches(
    filter.by_causation_id(id: "cause-1"),
    scheduled_event("e", "p"),
  )
  |> should.equal(False)
}

pub fn by_trace_id_filters_test() {
  let ev = scheduled_event("e", "p") |> event.with_trace_id("trace-1")

  filter.matches(filter.by_trace_id(id: "trace-1"), ev) |> should.equal(True)
  filter.matches(filter.by_trace_id(id: "trace-2"), ev) |> should.equal(False)

  filter.matches(filter.by_trace_id(id: "trace-1"), scheduled_event("e", "p"))
  |> should.equal(False)
}

pub fn by_attribute_matches_present_value_test() {
  let ev =
    scheduled_event("e", "p")
    |> event.with_attribute(key: "team", value: "platform")

  filter.matches(filter.by_attribute(key: "team", value: "platform"), ev)
  |> should.equal(True)
  filter.matches(filter.by_attribute(key: "team", value: "data"), ev)
  |> should.equal(False)
  filter.matches(filter.by_attribute(key: "owner", value: "platform"), ev)
  |> should.equal(False)
}

pub fn has_attribute_checks_presence_only_test() {
  let ev =
    scheduled_event("e", "p")
    |> event.with_attribute(key: "team", value: "platform")

  filter.matches(filter.has_attribute(key: "team"), ev) |> should.equal(True)
  filter.matches(filter.has_attribute(key: "owner"), ev) |> should.equal(False)
}

pub fn occurred_after_is_strict_test() {
  let ev = scheduled_event("e", "p")
  // ev.occurred_at == 2026-05-09T09:00:00.

  filter.matches(filter.occurred_after(after: at(2026, 5, 8)), ev)
  |> should.equal(True)

  // Same instant → strict comparison must reject.
  filter.matches(filter.occurred_after(after: at(2026, 5, 9)), ev)
  |> should.equal(False)

  filter.matches(filter.occurred_after(after: at(2026, 5, 10)), ev)
  |> should.equal(False)
}

pub fn occurred_before_is_strict_test() {
  let ev = scheduled_event("e", "p")

  filter.matches(filter.occurred_before(before: at(2026, 5, 10)), ev)
  |> should.equal(True)

  filter.matches(filter.occurred_before(before: at(2026, 5, 9)), ev)
  |> should.equal(False)

  filter.matches(filter.occurred_before(before: at(2026, 5, 8)), ev)
  |> should.equal(False)
}

pub fn on_body_option_returns_false_when_extractor_yields_none_test() {
  // Use a `Scheduled` event with an extractor that only returns Some
  // for `FileSystem`. This forces the None branch to fire.
  let ev = scheduled_event("e", "p")

  let f =
    filter.on_body_option(
      extract: fn(b) {
        case b {
          body.FileSystem(watch_event) ->
            option.Some(
              fs_path.path_to_string(fs_event.event_path(watch_event)),
            )
          _ -> option.None
        }
      },
      check: fn(_) { True },
    )

  filter.matches(f, ev) |> should.equal(False)
}
