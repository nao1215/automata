import automata as a
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import regression_surface_support as s

pub fn imported_events_keep_order_dates_recurrence_and_parameters_test() {
  let calendar = s.imported_calendar()
  assert a.ical_calscale(calendar) == Some("GREGORIAN")
  assert dict.get(a.ical_calendar_x_properties(calendar), "X-CALENDAR")
    == Ok("original")
  let assert [first, second] = a.ical_events(calendar)
  assert list.map([first, second], a.ical_event_uid) == ["event-1", "event-2"]
  assert a.ical_event_dtend(first) == Some(s.jan(1, 10))
  assert a.ical_event_dtend_tzid(first) == Some("Europe/Paris")
  assert a.ical_event_duration(second) == Some("PT1H")
  assert a.ical_event_status(first) == Some("TENTATIVE")
  assert a.ical_event_organizer(first) == Some("mailto:owner@example.org")
  assert a.ical_event_attendees(first)
    == ["mailto:alice@example.org", "mailto:bob@example.org"]
  assert a.ical_event_created(first) == Some(s.jan(1, 1))
  assert a.ical_event_last_modified(first) == Some(s.jan(1, 2))
  assert a.ical_event_sequence(first) == 1
  assert a.ical_event_transparency(first) == Some("OPAQUE")
  assert a.ical_event_rdates(first) == [s.jan(3, 0), s.jan(4, 0)]
  assert a.ical_event_exdates(first) == [s.jan(2, 9)]
  assert dict.get(a.ical_event_x_properties(first), "X-EVENT") == Ok("kept")
  let encoded = s.wire(calendar)
  s.contains_line(encoded, "DTEND;TZID=Europe/Paris;X-WALL=end:20260101T100000")
  s.contains_line(encoded, "ATTENDEE;CN=Alice:mailto:alice@example.org")
  s.contains_line(encoded, "EXDATE;TZID=Europe/Paris:20260102T090000")
  s.contains_line(encoded, "RDATE;VALUE=DATE:20260103,20260104")
}

pub fn imported_todo_and_alarm_keep_ordered_values_and_forms_test() {
  let calendar = s.imported_calendar()
  let assert [task] = a.ical_todos(calendar)
  assert a.ical_todo_dtstamp(task) == s.jan(1, 3)
  assert a.ical_todo_dtstart(task) == Some(s.jan(2, 0))
  assert a.ical_todo_due(task) == Some(s.jan(3, 0))
  assert a.ical_todo_completed(task) == Some(s.jan(4, 12))
  assert a.ical_todo_description(task) == Some("Old details")
  assert a.ical_todo_status(task) == Some("IN-PROCESS")
  assert a.ical_todo_percent_complete(task) == Some(25)
  assert a.ical_todo_categories(task) == ["work", "shared"]
  assert a.ical_todo_rrule(task)
    == Some(
      a.RawRRule([a.RawRulePart("FREQ", "DAILY"), a.RawRulePart("COUNT", "3")]),
    )
  assert a.ical_todo_rdates(task) == [s.jan(5, 0), s.jan(6, 0)]
  assert a.ical_todo_exdates(task) == [s.jan(7, 0)]
  assert dict.get(a.ical_todo_x_properties(task), "X-TODO") == Ok("todo-old")
  let assert [alarm] = a.ical_todo_alarms(task)
  assert a.ical_alarm_summary(alarm) == Some("Old reminder")
  assert a.ical_alarm_repeat(alarm) == Some(2)
  assert a.ical_alarm_duration(alarm) == Some("PT5M")
  assert a.ical_alarm_attendees(alarm)
    == ["mailto:alice@example.org", "mailto:bob@example.org"]
  assert dict.get(a.ical_alarm_x_properties(alarm), "X-ALARM")
    == Ok("alarm-old")
  let encoded = s.wire(calendar)
  s.contains_line(encoded, "DUE;VALUE=DATE:20260103")
  s.contains_line(encoded, "TRIGGER;RELATED=START:-PT10M")
  s.contains_line(encoded, "SUMMARY;LANGUAGE=en:Old reminder")
}

pub fn imported_journal_exposes_text_dates_and_categories_test() {
  let assert [journal] = a.ical_journals(s.imported_calendar())
  assert a.ical_journal_uid(journal) == "journal-1"
  assert a.ical_journal_dtstamp(journal) == s.jan(1, 3)
  assert a.ical_journal_dtstart(journal) == Some(s.jan(2, 0))
  assert a.ical_journal_summary(journal) == Some("Daily notes")
  assert a.ical_journal_description(journal) == Some("Original journal")
  assert a.ical_journal_status(journal) == Some("DRAFT")
  assert a.ical_journal_categories(journal) == ["notes", "team"]
  assert dict.get(a.ical_journal_x_properties(journal), "X-JOURNAL")
    == Ok("journal-old")
}

pub fn imported_freebusy_keeps_attendee_and_period_order_test() {
  let assert [value] = a.ical_freebusy(s.imported_calendar())
  assert a.ical_freebusy_uid(value) == "freebusy-1"
  assert a.ical_freebusy_dtstamp(value) == s.jan(1, 3)
  assert a.ical_freebusy_dtstart(value) == Some(s.jan(1, 9))
  assert a.ical_freebusy_dtend(value) == Some(s.jan(1, 18))
  assert a.ical_freebusy_organizer(value) == Some("mailto:owner@example.org")
  assert a.ical_freebusy_attendees(value)
    == ["mailto:alice@example.org", "mailto:bob@example.org"]
  assert a.ical_freebusy_periods(value)
    == ["20260101T100000Z/20260101T110000Z", "20260101T140000Z/PT1H"]
  assert dict.get(a.ical_freebusy_x_properties(value), "X-FREEBUSY")
    == Ok("freebusy-old")
}

pub fn imported_timezone_keeps_each_standard_and_daylight_rule_test() {
  let assert [zone] = a.ical_timezones(s.imported_calendar())
  assert a.ical_timezone_tzid(zone) == "Test/Office"
  assert a.ical_timezone_last_modified(zone) == Some(s.jan(1, 2))
  assert a.ical_timezone_tzurl(zone) == Some("https://example.org/old-zone")
  assert a.ical_timezone_standard(zone)
    == [
      a.IcalTimezoneRule(
        s.jan(1, 2),
        "+0200",
        "+0100",
        Some(
          a.RawRRule([
            a.RawRulePart("FREQ", "YEARLY"),
            a.RawRulePart("BYMONTH", "10"),
            a.RawRulePart("BYDAY", "-1SU"),
          ]),
        ),
        Some("First standard"),
      ),
      a.IcalTimezoneRule(
        s.jan(2, 2),
        "+0300",
        "+0100",
        None,
        Some("Second standard"),
      ),
    ]
  assert a.ical_timezone_daylight(zone)
    == [a.IcalTimezoneRule(s.jan(3, 2), "+0100", "+0200", None, Some("Summer"))]
  assert dict.get(a.ical_timezone_x_properties(zone), "X-TIMEZONE")
    == Ok("zone-old")
  let encoded = s.wire(s.fresh() |> a.ical_add_timezone(zone))
  s.contains_line(encoded, "DTSTART:20260101T020000")
  s.contains_line(encoded, "TZNAME;LANGUAGE=en:First standard")
}
