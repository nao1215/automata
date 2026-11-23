import automata as a
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should
import regression_canonical_support as s

fn stamp() -> a.DateTime {
  s.raw(2026, 1, 1, 0, 0, 0, 0)
}

fn bad() -> a.DateTime {
  s.raw(2026, 1, 1, 0, 0, 0, 1)
}

fn calendar() -> a.IcalCalendar {
  a.ical_new_calendar(version: "2.0", prod_id: "regression")
}

fn event_calendar(event: a.IcalEvent) -> a.IcalCalendar {
  a.ical_add_event(calendar(), event)
}

fn reject_nanos(cal: a.IcalCalendar, property: String) -> Nil {
  a.ical_encode(cal)
  |> should.equal(
    Error(a.IcalInvalidDateValue(property, bad(), a.InvalidTime(0, 0, 0, 1))),
  )
}

pub fn event_all_date_fields_reject_nanoseconds_test() {
  let event = a.ical_new_event(uid: "event", dtstamp: stamp())
  list.each(
    [
      #("DTSTAMP", a.ical_new_event(uid: "event", dtstamp: bad())),
      #("DTSTART", a.ical_with_dtstart(event, bad())),
      #("DTEND", a.ical_with_dtend(event, bad())),
      #("CREATED", a.ical_with_created(event, bad())),
      #("LAST-MODIFIED", a.ical_with_last_modified(event, bad())),
      #("RDATE", a.ical_add_rdate(event, bad())),
      #("EXDATE", a.ical_add_exdate(event, bad())),
    ],
    fn(row) { reject_nanos(event_calendar(row.1), row.0) },
  )
}

pub fn todo_all_date_fields_reject_nanoseconds_test() {
  let item = a.ical_new_todo(uid: "todo", dtstamp: stamp())
  list.each(
    [
      #("DTSTAMP", a.ical_new_todo(uid: "todo", dtstamp: bad())),
      #("DTSTART", a.ical_with_todo_dtstart(item, bad())),
      #("DUE", a.ical_with_todo_due(item, bad())),
      #("COMPLETED", a.ical_with_todo_completed(item, bad())),
      #("RDATE", a.ical_add_todo_rdate(item, bad())),
      #("EXDATE", a.ical_add_todo_exdate(item, bad())),
    ],
    fn(row) { reject_nanos(a.ical_add_todo(calendar(), row.1), row.0) },
  )
}

pub fn journal_date_fields_reject_nanoseconds_test() {
  let journal = a.ical_new_journal(uid: "journal", dtstamp: stamp())
  reject_nanos(
    a.ical_add_journal(
      calendar(),
      a.ical_new_journal(uid: "journal", dtstamp: bad()),
    ),
    "DTSTAMP",
  )
  reject_nanos(
    a.ical_add_journal(calendar(), a.ical_with_journal_dtstart(journal, bad())),
    "DTSTART",
  )
}

pub fn freebusy_all_date_fields_reject_nanoseconds_test() {
  let freebusy = a.ical_new_freebusy(uid: "freebusy", dtstamp: stamp())
  list.each(
    [
      #("DTSTAMP", a.ical_new_freebusy(uid: "freebusy", dtstamp: bad())),
      #("DTSTART", a.ical_with_freebusy_dtstart(freebusy, bad())),
      #("DTEND", a.ical_with_freebusy_dtend(freebusy, bad())),
    ],
    fn(row) { reject_nanos(a.ical_add_freebusy(calendar(), row.1), row.0) },
  )
}

pub fn timezone_all_date_fields_reject_nanoseconds_test() {
  let zone = a.ical_new_timezone(tzid: "Test/Zone")
  let rule = a.IcalTimezoneRule(bad(), "+0000", "+0100", None, None)
  list.each(
    [
      #("LAST-MODIFIED", a.ical_with_timezone_last_modified(zone, bad())),
      #("DTSTART", a.ical_add_timezone_standard(zone, rule)),
      #("DTSTART", a.ical_add_timezone_daylight(zone, rule)),
    ],
    fn(row) { reject_nanos(a.ical_add_timezone(calendar(), row.1), row.0) },
  )
}

pub fn encode_rejects_invalid_calendar_day_and_time_test() {
  let invalid_day = s.raw(2026, 2, 30, 0, 0, 0, 0)
  a.ical_new_event(uid: "event", dtstamp: invalid_day)
  |> event_calendar
  |> a.ical_encode
  |> should.equal(
    Error(a.IcalInvalidDateValue(
      "DTSTAMP",
      invalid_day,
      a.InvalidDate(2026, 2, 30),
    )),
  )
  list.each([#(24, 0, 0), #(0, 60, 0), #(0, 0, 60)], fn(row) {
    let value = s.raw(2026, 1, 1, row.0, row.1, row.2, 0)
    a.ical_new_event(uid: "event", dtstamp: value)
    |> event_calendar
    |> a.ical_encode
    |> should.equal(
      Error(a.IcalInvalidDateValue(
        "DTSTAMP",
        value,
        a.InvalidTime(row.0, row.1, row.2, 0),
      )),
    )
  })
}

pub fn wire_year_boundaries_keep_negative_and_zero_years_test() {
  list.each(
    [#(-999, "-999"), #(-1, "-001"), #(0, "0000"), #(9999, "9999")],
    fn(row) {
      let value = s.raw(row.0, 1, 1, 0, 0, 0, 0)
      let assert Ok(wire) =
        a.ical_new_event(uid: "event", dtstamp: value)
        |> event_calendar
        |> a.ical_encode
      string.split(wire, "\r\n")
      |> list.contains("DTSTAMP:" <> row.1 <> "0101T000000Z")
      |> should.be_true
      let assert Ok(parsed) = a.ical_parse(wire)
      let assert [event] = a.ical_events(parsed)
      a.ical_event_dtstamp(event) |> should.equal(value)
    },
  )
}

pub fn wire_rejects_civil_years_outside_its_four_character_range_test() {
  list.each([-1000, 10_000], fn(year) {
    let value = s.raw(year, 1, 1, 0, 0, 0, 0)
    let assert Ok(_) = a.datetime_validate(value)
    a.ical_new_event(uid: "event", dtstamp: value)
    |> event_calendar
    |> a.ical_encode
    |> should.equal(Error(a.IcalYearNotRepresentable("DTSTAMP", year)))
  })
}

pub fn parsed_signed_years_have_reparseable_canonical_spelling_test() {
  list.each(
    [#("-001", "-001", -1), #("+001", "0001", 1), #("-000", "0000", 0)],
    fn(row) {
      let source =
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:regression\r\nBEGIN:VEVENT\r\nUID:event\r\nDTSTAMP:"
        <> row.0
        <> "0101T000000Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
      let assert Ok(parsed) = a.ical_parse(source)
      let assert Ok(wire) = a.ical_encode(parsed)
      string.split(wire, "\r\n")
      |> list.contains("DTSTAMP:" <> row.1 <> "0101T000000Z")
      |> should.be_true
      let assert Ok(reparsed) = a.ical_parse(wire)
      let assert [event] = a.ical_events(reparsed)
      a.ical_event_dtstamp(event)
      |> should.equal(s.raw(row.2, 1, 1, 0, 0, 0, 0))
    },
  )
}

pub fn invalid_date_precedes_unrepresentable_wire_year_test() {
  let value = s.raw(10_000, 2, 30, 0, 0, 0, 0)
  a.ical_new_event(uid: "event", dtstamp: value)
  |> event_calendar
  |> a.ical_encode
  |> should.equal(
    Error(a.IcalInvalidDateValue("DTSTAMP", value, a.InvalidDate(10_000, 2, 30))),
  )
}

pub fn earlier_uid_newline_precedes_later_invalid_date_test() {
  a.ical_new_event(uid: "event\nother", dtstamp: bad())
  |> event_calendar
  |> a.ical_encode
  |> should.equal(Error(a.IcalPhysicalNewline("UID:event\nother")))
}

pub fn earlier_date_error_precedes_later_url_newline_test() {
  a.ical_new_event(uid: "event", dtstamp: bad())
  |> a.ical_with_url("https://example.test/\nother")
  |> event_calendar
  |> a.ical_encode
  |> should.equal(
    Error(a.IcalInvalidDateValue("DTSTAMP", bad(), a.InvalidTime(0, 0, 0, 1))),
  )
}
