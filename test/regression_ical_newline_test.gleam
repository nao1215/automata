import automata as a
import gleam/list
import gleam/option.{Some}
import gleam/string
import gleeunit/should
import regression_canonical_support as s

fn calendar() -> a.IcalCalendar {
  a.ical_new_calendar(version: "2.0", prod_id: "regression")
}

fn event() -> a.IcalEvent {
  a.ical_new_event(uid: "event", dtstamp: s.raw(2026, 1, 1, 0, 0, 0, 0))
}

fn event_calendar(value: a.IcalEvent) -> a.IcalCalendar {
  a.ical_add_event(calendar(), value)
}

fn first_event(value: a.IcalCalendar) -> a.IcalEvent {
  let assert [event] = a.ical_events(value)
  event
}

pub fn typed_text_newlines_normalize_only_during_encoding_test() {
  list.each(
    [
      #("a\nb", "a\nb", "SUMMARY:a\\nb"),
      #("a\rb", "a\nb", "SUMMARY:a\\nb"),
      #("a\r\nb", "a\nb", "SUMMARY:a\\nb"),
      #("a\\nb", "a\\nb", "SUMMARY:a\\\\nb"),
      #("a\\b,c;d\r\ne", "a\\b,c;d\ne", "SUMMARY:a\\\\b\\,c\\;d\\ne"),
    ],
    fn(row) {
      let value = a.ical_with_summary(event(), row.0)
      a.ical_event_summary(value) |> should.equal(Some(row.0))
      let assert Ok(wire) = event_calendar(value) |> a.ical_encode
      string.split(wire, "\r\n") |> list.contains(row.2) |> should.be_true
      let assert Ok(parsed) = a.ical_parse(wire)
      parsed |> first_event |> a.ical_event_summary |> should.equal(Some(row.1))
      a.ical_event_summary(value) |> should.equal(Some(row.0))
    },
  )
}

pub fn event_description_location_categories_and_alarm_keep_canonical_text_test() {
  let alarm =
    a.ical_new_alarm(action: "DISPLAY", trigger: "-PT5M")
    |> a.ical_with_alarm_description("alarm\r\ntext")
  let value =
    event()
    |> a.ical_with_description("description\rtext")
    |> a.ical_with_location("location\r\ntext")
    |> a.ical_add_category("category\rtext")
    |> a.ical_add_alarm(alarm)
  let assert Ok(wire) = event_calendar(value) |> a.ical_encode
  let assert Ok(parsed) = a.ical_parse(wire)
  let value = first_event(parsed)
  a.ical_event_description(value) |> should.equal(Some("description\ntext"))
  a.ical_event_location(value) |> should.equal(Some("location\ntext"))
  a.ical_event_categories(value) |> should.equal(["category\ntext"])
  let assert [alarm] = a.ical_event_alarms(value)
  a.ical_alarm_description(alarm) |> should.equal(Some("alarm\ntext"))
}

pub fn non_text_uid_uri_status_and_trigger_reject_physical_newlines_test() {
  let alarm = a.ical_new_alarm(action: "DISPLAY", trigger: "-PT5M\nother")
  list.each(
    [
      #(
        a.ical_new_event(
          uid: "event\r\nSUMMARY:injected",
          dtstamp: s.raw(2026, 1, 1, 0, 0, 0, 0),
        ),
        "UID:event\r\nSUMMARY:injected",
      ),
      #(
        a.ical_with_url(event(), "https://example.test/\nother"),
        "URL:https://example.test/\nother",
      ),
      #(
        a.ical_with_status(event(), "CONFIRMED\rother"),
        "STATUS:CONFIRMED\rother",
      ),
      #(a.ical_add_alarm(event(), alarm), "TRIGGER:-PT5M\nother"),
    ],
    fn(row) {
      event_calendar(row.0)
      |> a.ical_encode
      |> should.equal(Error(a.IcalPhysicalNewline(row.1)))
    },
  )
}

pub fn unknown_raw_property_name_and_value_reject_physical_newlines_test() {
  list.each(
    [
      #("X-VALUE", "a\nb", "X-VALUE:a\nb"),
      #("X-\rNAME", "value", "X-\rNAME:value"),
    ],
    fn(row) {
      let property = a.IcalRawProperty(row.0, [], row.1, 1)
      let unknown = a.IcalUnknownComponent("X-COMPONENT", [property], [])
      a.ical_add_unknown_component(calendar(), unknown)
      |> a.ical_encode
      |> should.equal(Error(a.IcalPhysicalNewline(row.2)))
    },
  )
}

pub fn component_begin_line_rejects_physical_newline_test() {
  let unknown = a.IcalUnknownComponent("X-ONE\nBEGIN:X-TWO", [], [])
  a.ical_add_unknown_component(calendar(), unknown)
  |> a.ical_encode
  |> should.equal(Error(a.IcalPhysicalNewline("BEGIN:X-ONE\nBEGIN:X-TWO")))
}

pub fn raw_parameter_name_and_value_reject_physical_newlines_test() {
  list.each(
    [
      #(a.IcalParameter("X-\nNAME", "value"), "X-VALUE;X-\nNAME=value:clean"),
      #(a.IcalParameter("X-NAME", "a\rb"), "X-VALUE;X-NAME=a\rb:clean"),
    ],
    fn(row) {
      let property = a.IcalRawProperty("X-VALUE", [row.0], "clean", 1)
      let unknown = a.IcalUnknownComponent("X-COMPONENT", [property], [])
      a.ical_add_unknown_component(calendar(), unknown)
      |> a.ical_encode
      |> should.equal(Error(a.IcalPhysicalNewline(row.1)))
    },
  )
}

pub fn parsed_raw_text_is_not_escaped_a_second_time_test() {
  let source =
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:one\\,two\r\nX-CUSTOM:a\\nb\r\nEND:VCALENDAR\r\n"
  let assert Ok(parsed) = a.ical_parse(source)
  let assert Ok(wire) = a.ical_encode(parsed)
  let lines = string.split(wire, "\r\n")
  list.contains(lines, "PRODID:one\\,two") |> should.be_true
  list.contains(lines, "X-CUSTOM:a\\nb") |> should.be_true
}

pub fn tolerant_input_line_endings_remain_accepted_test() {
  let lines = [
    "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:regression", "BEGIN:VEVENT",
    "UID:event", "DTSTAMP:20260101T000000Z", "SUMMARY:text", "END:VEVENT",
    "END:VCALENDAR",
  ]
  list.each(["\r\n", "\n", "\r"], fn(separator) {
    let assert Ok(parsed) = a.ical_parse(string.join(lines, separator))
    parsed |> first_event |> a.ical_event_summary |> should.equal(Some("text"))
  })
}
