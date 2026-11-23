import automata as a
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/set
import gleam/time/calendar
import regression_surface_support as s

pub fn calendar_weekdays_use_ical_two_letter_names_test() {
  let days = [5, 6, 7, 8, 9, 10, 11]
  let labels =
    list.map(days, fn(day) {
      calendar.day_of_week(s.jan(day, 0).date) |> a.weekday_to_string
    })
  assert labels == ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]
}

pub fn scheduled_events_derive_schedule_source_for_both_schedule_kinds_test() {
  let assert Ok(at) = a.datetime_validate(s.jan(5, 9))
  list.each([a.CronSchedule, a.RRuleSchedule], fn(kind) {
    let body = a.Scheduled("working-hours", at, kind)
    assert a.event_body_source_kind(body) == a.ScheduleSource
    let event = a.builtin_event("fired-1", at, "scheduler", body)
    assert event.source == a.Source(a.ScheduleSource, "scheduler", None)
    assert a.event_body_kind(event.body) == "scheduled"
    assert event.body == a.Scheduled("working-hours", at, kind)
  })
}

pub fn filesystem_manual_and_custom_events_keep_distinct_source_classifications_test() {
  let assert Ok(at) = a.datetime_validate(s.jan(5, 9))
  let assert Ok(path) = a.path_normalize("/srv/input/report.csv")
  let assert Ok(change) =
    a.filesystem_event(path, set.from_list([a.Write]), None)
  let filesystem = a.FileSystem(change)
  let manual = a.Manual(Some("retry upload"), Some("operator"))
  let custom = a.Custom("invoice.paid", dict.from_list([#("invoice", "42")]))
  assert a.event_body_source_kind(filesystem) == a.FileSystemSource
  assert a.event_body_source_kind(manual) == a.ManualSource
  assert a.event_body_source_kind(custom) == a.CustomSource("invoice.paid")
  let file_event = a.builtin_event("changed-1", at, "upload-watch", filesystem)
  let manual_event = a.builtin_event("manual-1", at, "control-panel", manual)
  let paid_event = a.builtin_event("paid-1", at, "billing", custom)
  assert file_event.source == a.Source(a.FileSystemSource, "upload-watch", None)
  assert manual_event.source == a.Source(a.ManualSource, "control-panel", None)
  assert paid_event.source
    == a.Source(a.CustomSource("invoice.paid"), "billing", None)
  assert a.event_body_kind(file_event.body) == "file_system:write"
  assert a.event_body_kind(manual_event.body) == "manual"
  assert a.event_body_kind(paid_event.body) == "custom:invoice.paid"
  assert manual_event.body == a.Manual(Some("retry upload"), Some("operator"))
  assert paid_event.body
    == a.Custom("invoice.paid", dict.from_list([#("invoice", "42")]))
}
