import automata as a
import gleam/dict
import gleam/list
import gleam/option.{Some}
import regression_surface_support as s

pub fn editing_calendar_headers_retains_all_component_collections_test() {
  let updated =
    s.imported_calendar()
    |> a.ical_with_method("PUBLISH")
    |> a.ical_with_calscale("GREGORIAN")
    |> a.ical_with_calendar_x_property("X-CALENDAR", "updated")
  let encoded = s.wire(updated)
  s.contains_line(encoded, "METHOD:PUBLISH")
  s.contains_line(encoded, "CALSCALE:GREGORIAN")
  s.contains_line(encoded, "X-CALENDAR:updated")
  s.contains_line(encoded, "X-KEEP:calendar-kept")
  s.excludes_text(encoded, "METHOD;X-OLD")
  s.excludes_text(encoded, "CALSCALE;X-OLD")
  s.excludes_text(encoded, "X-CALENDAR;X-OLD")
  s.contains_line(encoded, "DESCRIPTION;LANGUAGE=en:Old details")
  s.contains_line(encoded, "TZNAME;LANGUAGE=en:First standard")
  let assert Ok(parsed) = a.ical_parse(encoded)
  assert a.ical_method(parsed) == Some("PUBLISH")
  assert a.ical_calscale(parsed) == Some("GREGORIAN")
  assert list.map(a.ical_events(parsed), a.ical_event_uid)
    == ["event-1", "event-2"]
  assert list.map(a.ical_todos(parsed), a.ical_todo_uid) == ["todo-1"]
  assert list.map(a.ical_journals(parsed), a.ical_journal_uid) == ["journal-1"]
  assert list.map(a.ical_freebusy(parsed), a.ical_freebusy_uid)
    == ["freebusy-1"]
  assert list.map(a.ical_timezones(parsed), a.ical_timezone_tzid)
    == ["Test/Office"]
}

pub fn editing_event_timezone_labels_keeps_wall_time_and_other_parameters_test() {
  let assert [event, _] = a.ical_events(s.imported_calendar())
  let updated =
    event
    |> a.ical_with_dtstart_tzid("Asia/Tokyo")
    |> a.ical_with_dtend_tzid("Asia/Tokyo")
  let encoded = s.wire(s.fresh() |> a.ical_add_event(updated))
  s.contains_line(
    encoded,
    "DTSTART;TZID=Asia/Tokyo;X-WALL=start:20260101T090000",
  )
  s.contains_line(encoded, "DTEND;TZID=Asia/Tokyo;X-WALL=end:20260101T100000")
  s.contains_line(encoded, "EXDATE;TZID=Europe/Paris:20260102T090000")
  let assert Ok(parsed) = a.ical_parse(encoded)
  let assert [event] = a.ical_events(parsed)
  assert a.ical_event_dtstart(event) == Some(s.jan(1, 9))
  assert a.ical_event_dtend(event) == Some(s.jan(1, 10))
  assert a.ical_event_dtstart_tzid(event) == Some("Asia/Tokyo")
  assert a.ical_event_dtend_tzid(event) == Some("Asia/Tokyo")
}

pub fn editing_event_scalars_resets_only_their_forms_even_for_same_sequence_test() {
  let assert [event, _] = a.ical_events(s.imported_calendar())
  let rule =
    a.RawRRule([a.RawRulePart("FREQ", "WEEKLY"), a.RawRulePart("COUNT", "4")])
  let updated =
    event
    |> a.ical_with_organizer("mailto:new-owner@example.org")
    |> a.ical_with_sequence(1)
    |> a.ical_with_rrule(rule)
  let encoded = s.wire(s.fresh() |> a.ical_add_event(updated))
  s.contains_line(encoded, "ORGANIZER:mailto:new-owner@example.org")
  s.contains_line(encoded, "SEQUENCE:1")
  s.contains_line(encoded, "RRULE:FREQ=WEEKLY;COUNT=4")
  s.excludes_text(encoded, "ORGANIZER;CN")
  s.excludes_text(encoded, "SEQUENCE;X-OLD")
  s.excludes_text(encoded, "RRULE;X-OLD")
  s.contains_line(encoded, "SUMMARY;LANGUAGE=en:Planning")
  s.contains_line(encoded, "ATTENDEE;CN=Alice:mailto:alice@example.org")
  let assert Ok(parsed) = a.ical_parse(encoded)
  let assert [event] = a.ical_events(parsed)
  assert a.ical_event_organizer(event) == Some("mailto:new-owner@example.org")
  assert a.ical_event_sequence(event) == 1
  assert a.ical_event_rrule(event) == Some(rule)
  assert a.ical_event_description(event) == Some("Keep this description")
  assert a.ical_event_rdates(event) == [s.jan(3, 0), s.jan(4, 0)]
}

pub fn editing_todo_preserves_date_forms_and_appends_categories_and_alarms_test() {
  let assert [task] = a.ical_todos(s.imported_calendar())
  let rule =
    a.RawRRule([a.RawRulePart("FREQ", "WEEKLY"), a.RawRulePart("COUNT", "2")])
  let new_alarm =
    a.ical_new_alarm("DISPLAY", "-PT5M")
    |> a.ical_with_alarm_description("Second reminder")
  let updated =
    task
    |> a.ical_with_todo_description("New details")
    |> a.ical_with_todo_status("COMPLETED")
    |> a.ical_with_todo_percent_complete(100)
    |> a.ical_with_todo_priority(1)
    |> a.ical_add_todo_category("finished")
    |> a.ical_with_todo_rrule(rule)
    |> a.ical_add_todo_alarm(new_alarm)
    |> a.ical_with_todo_x_property("X-TODO", "todo-new")
  let encoded = s.wire(s.fresh() |> a.ical_add_todo(updated))
  s.contains_line(encoded, "DESCRIPTION:New details")
  s.contains_line(encoded, "STATUS:COMPLETED")
  s.contains_line(encoded, "PERCENT-COMPLETE:100")
  s.contains_line(encoded, "PRIORITY:1")
  s.contains_line(encoded, "RRULE:FREQ=WEEKLY;COUNT=2")
  s.contains_line(encoded, "CATEGORIES;LANGUAGE=en:work,shared")
  s.contains_line(encoded, "CATEGORIES:finished")
  s.contains_line(encoded, "X-TODO:todo-new")
  s.contains_line(encoded, "X-KEEP:todo-kept")
  s.contains_line(encoded, "DTSTART;VALUE=DATE:20260102")
  s.contains_line(encoded, "DUE;VALUE=DATE:20260103")
  s.contains_line(encoded, "TRIGGER;RELATED=START:-PT10M")
  s.contains_line(encoded, "TRIGGER:-PT5M")
  s.excludes_text(encoded, "DESCRIPTION;LANGUAGE=en:Old details")
  s.excludes_text(encoded, "STATUS;X-OLD")
  s.excludes_text(encoded, "PERCENT-COMPLETE;X-OLD")
  s.excludes_text(encoded, "PRIORITY;X-OLD")
  s.excludes_text(encoded, "RRULE;X-OLD")
  s.excludes_text(encoded, "X-TODO;X-OLD")
  let assert Ok(parsed) = a.ical_parse(encoded)
  let assert [task] = a.ical_todos(parsed)
  assert a.ical_todo_description(task) == Some("New details")
  assert a.ical_todo_status(task) == Some("COMPLETED")
  assert a.ical_todo_percent_complete(task) == Some(100)
  assert a.ical_todo_priority(task) == Some(1)
  assert a.ical_todo_categories(task) == ["work", "shared", "finished"]
  assert a.ical_todo_rrule(task) == Some(rule)
  assert a.ical_todo_due(task) == Some(s.jan(3, 0))
  assert a.ical_todo_rdates(task) == [s.jan(5, 0), s.jan(6, 0)]
  assert list.map(a.ical_todo_alarms(task), a.ical_alarm_trigger)
    == ["-PT10M", "-PT5M"]
  assert dict.get(a.ical_todo_x_properties(task), "X-KEEP") == Ok("todo-kept")
}

pub fn publishing_journal_preserves_summary_form_and_category_order_test() {
  let assert [journal] = a.ical_journals(s.imported_calendar())
  let updated =
    journal
    |> a.ical_with_journal_description("Published notes")
    |> a.ical_with_journal_status("FINAL")
    |> a.ical_add_journal_category("published")
    |> a.ical_with_journal_x_property("X-JOURNAL", "journal-new")
  let encoded = s.wire(s.fresh() |> a.ical_add_journal(updated))
  s.contains_line(encoded, "DESCRIPTION:Published notes")
  s.contains_line(encoded, "STATUS:FINAL")
  s.contains_line(encoded, "X-JOURNAL:journal-new")
  s.contains_line(encoded, "SUMMARY;LANGUAGE=en:Daily notes")
  s.contains_line(encoded, "DTSTART;VALUE=DATE:20260102")
  s.contains_line(encoded, "CATEGORIES;LANGUAGE=en:notes,team")
  s.contains_line(encoded, "CATEGORIES:published")
  s.contains_line(encoded, "X-KEEP:journal-kept")
  s.excludes_text(encoded, "DESCRIPTION;LANGUAGE")
  s.excludes_text(encoded, "STATUS;X-OLD")
  s.excludes_text(encoded, "X-JOURNAL;X-OLD")
  let assert Ok(parsed) = a.ical_parse(encoded)
  let assert [journal] = a.ical_journals(parsed)
  assert a.ical_journal_description(journal) == Some("Published notes")
  assert a.ical_journal_status(journal) == Some("FINAL")
  assert a.ical_journal_categories(journal) == ["notes", "team", "published"]
  assert a.ical_journal_summary(journal) == Some("Daily notes")
}

pub fn adding_freebusy_availability_keeps_earlier_period_parameters_test() {
  let assert [value] = a.ical_freebusy(s.imported_calendar())
  let updated =
    value
    |> a.ical_with_freebusy_organizer("mailto:new-owner@example.org")
    |> a.ical_add_freebusy_attendee("mailto:charlie@example.org")
    |> a.ical_add_freebusy_period("20260101T160000Z/PT30M")
    |> a.ical_with_freebusy_x_property("X-FREEBUSY", "freebusy-new")
  let encoded = s.wire(s.fresh() |> a.ical_add_freebusy(updated))
  s.contains_line(encoded, "ORGANIZER:mailto:new-owner@example.org")
  s.contains_line(encoded, "ATTENDEE;CN=Alice:mailto:alice@example.org")
  s.contains_line(encoded, "ATTENDEE:mailto:charlie@example.org")
  s.contains_line(
    encoded,
    "FREEBUSY;FBTYPE=BUSY:20260101T100000Z/20260101T110000Z",
  )
  s.contains_line(
    encoded,
    "FREEBUSY;FBTYPE=BUSY-TENTATIVE:20260101T140000Z/PT1H",
  )
  s.contains_line(encoded, "FREEBUSY:20260101T160000Z/PT30M")
  s.contains_line(encoded, "X-FREEBUSY:freebusy-new")
  s.contains_line(encoded, "X-KEEP:freebusy-kept")
  s.excludes_text(encoded, "ORGANIZER;CN")
  s.excludes_text(encoded, "X-FREEBUSY;X-OLD")
  let assert Ok(parsed) = a.ical_parse(encoded)
  let assert [value] = a.ical_freebusy(parsed)
  assert a.ical_freebusy_organizer(value)
    == Some("mailto:new-owner@example.org")
  assert a.ical_freebusy_attendees(value)
    == [
      "mailto:alice@example.org",
      "mailto:bob@example.org",
      "mailto:charlie@example.org",
    ]
  assert a.ical_freebusy_periods(value)
    == [
      "20260101T100000Z/20260101T110000Z",
      "20260101T140000Z/PT1H",
      "20260101T160000Z/PT30M",
    ]
  assert a.ical_freebusy_dtstart(value) == Some(s.jan(1, 9))
  assert a.ical_freebusy_dtend(value) == Some(s.jan(1, 18))
}

pub fn updating_timezone_source_retains_rule_order_and_local_time_forms_test() {
  let assert [zone] = a.ical_timezones(s.imported_calendar())
  let updated =
    zone
    |> a.ical_with_timezone_url("https://example.org/new-zone")
    |> a.ical_with_timezone_x_property("X-TIMEZONE", "zone-new")
  let encoded = s.wire(s.fresh() |> a.ical_add_timezone(updated))
  s.contains_line(encoded, "TZURL:https://example.org/new-zone")
  s.contains_line(encoded, "X-TIMEZONE:zone-new")
  s.contains_line(encoded, "X-KEEP:zone-kept")
  s.contains_line(encoded, "TZNAME;LANGUAGE=en:First standard")
  s.contains_line(encoded, "DTSTART:20260101T020000")
  s.contains_line(encoded, "DTSTART:20260103T020000")
  s.excludes_text(encoded, "TZURL;X-OLD")
  s.excludes_text(encoded, "X-TIMEZONE;X-OLD")
  let assert Ok(parsed) = a.ical_parse(encoded)
  let assert [zone] = a.ical_timezones(parsed)
  assert a.ical_timezone_tzurl(zone) == Some("https://example.org/new-zone")
  assert list.map(a.ical_timezone_standard(zone), fn(rule) { rule.tzname })
    == [Some("First standard"), Some("Second standard")]
  assert list.map(a.ical_timezone_daylight(zone), fn(rule) { rule.tzname })
    == [Some("Summer")]
  assert a.ical_timezone_last_modified(zone) == Some(s.jan(1, 2))
}

pub fn editing_imported_alarm_preserves_trigger_and_appends_attendee_test() {
  let assert [task] = a.ical_todos(s.imported_calendar())
  let assert [alarm] = a.ical_todo_alarms(task)
  let updated =
    alarm
    |> a.ical_with_alarm_summary("New reminder")
    |> a.ical_with_alarm_repeat(3)
    |> a.ical_with_alarm_duration("PT2M")
    |> a.ical_add_alarm_attendee("mailto:charlie@example.org")
    |> a.ical_with_alarm_x_property("X-ALARM", "alarm-new")
  let event =
    a.ical_new_event("reminder", s.jan(1, 3)) |> a.ical_add_alarm(updated)
  let encoded = s.wire(s.fresh() |> a.ical_add_event(event))
  s.contains_line(encoded, "SUMMARY:New reminder")
  s.contains_line(encoded, "REPEAT:3")
  s.contains_line(encoded, "DURATION:PT2M")
  s.contains_line(encoded, "X-ALARM:alarm-new")
  s.contains_line(encoded, "X-KEEP:alarm-kept")
  s.contains_line(encoded, "TRIGGER;RELATED=START:-PT10M")
  s.contains_line(encoded, "DESCRIPTION;LANGUAGE=en:Reminder")
  s.contains_line(encoded, "ATTENDEE;CN=Alice:mailto:alice@example.org")
  s.contains_line(encoded, "ATTENDEE:mailto:charlie@example.org")
  s.excludes_text(encoded, "SUMMARY;LANGUAGE")
  s.excludes_text(encoded, "REPEAT;X-OLD")
  s.excludes_text(encoded, "DURATION;X-OLD")
  s.excludes_text(encoded, "X-ALARM;X-OLD")
  let assert Ok(parsed) = a.ical_parse(encoded)
  let assert [event] = a.ical_events(parsed)
  let assert [alarm] = a.ical_event_alarms(event)
  assert a.ical_alarm_summary(alarm) == Some("New reminder")
  assert a.ical_alarm_repeat(alarm) == Some(3)
  assert a.ical_alarm_duration(alarm) == Some("PT2M")
  assert a.ical_alarm_trigger(alarm) == "-PT10M"
  assert a.ical_alarm_attendees(alarm)
    == [
      "mailto:alice@example.org",
      "mailto:bob@example.org",
      "mailto:charlie@example.org",
    ]
}
