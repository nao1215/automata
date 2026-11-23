import automata as a
import gleam/list
import gleam/option.{Some}
import gleeunit/should

fn feed(properties: String) -> String {
  "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//regression//EN\r\nBEGIN:VEVENT\r\nUID:bom\r\nDTSTAMP:20260101T000000Z\r\n"
  <> properties
  <> "END:VEVENT\r\nEND:VCALENDAR\r\n"
}

pub fn summary_embedded_bom_survives_with_and_without_document_bom_test() {
  list.each(["", "\u{FEFF}"], fn(prefix) {
    let assert Ok(cal) =
      a.ical_parse(prefix <> feed("SUMMARY:before\u{FEFF}after\r\n"))
    let assert [event] = a.ical_events(cal)
    a.ical_event_summary(event) |> should.equal(Some("before\u{FEFF}after"))
  })
}

pub fn summary_edge_boms_are_not_trimmed_test() {
  let assert Ok(cal) =
    a.ical_parse("\u{FEFF}" <> feed("SUMMARY:\u{FEFF}middle\u{FEFF}\r\n"))
  let assert [event] = a.ical_events(cal)
  a.ical_event_summary(event) |> should.equal(Some("\u{FEFF}middle\u{FEFF}"))
}

pub fn embedded_bom_survives_encode_and_second_parse_test() {
  let assert Ok(cal) =
    a.ical_parse("\u{FEFF}" <> feed("SUMMARY:before\u{FEFF}after\r\n"))
  let assert Ok(encoded) = a.ical_encode(cal)
  let assert Ok(reparsed) = a.ical_parse(encoded)
  let assert [event] = a.ical_events(reparsed)
  a.ical_event_summary(event) |> should.equal(Some("before\u{FEFF}after"))
}

pub fn attendee_parameter_bom_survives_both_parses_test() {
  let text = "\u{FEFF}" <> feed("ATTENDEE;CN=person\u{FEFF}name:mailto:a@b\r\n")
  assert_parameter(text)
  let assert Ok(cal) = a.ical_parse(text)
  let assert Ok(encoded) = a.ical_encode(cal)
  assert_parameter(encoded)
}

fn assert_parameter(text: String) {
  let assert Ok(raw) = a.ical_parse_raw(text)
  let assert [event] = raw.components
  let assert [attendee] =
    list.filter(event.properties, fn(p) { p.name == "ATTENDEE" })
  let assert [parameter] = attendee.parameters
  #(parameter.name, parameter.value, attendee.raw_value)
  |> should.equal(#("CN", "person\u{FEFF}name", "mailto:a@b"))
}

pub fn unknown_nested_values_keep_their_boms_test() {
  let text =
    "\u{FEFF}BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//regression//EN\r\nBEGIN:X-CUSTOM\r\nX-PROP:outer\u{FEFF}value\r\nBEGIN:X-CHILD\r\nX-PROP:inner\u{FEFF}value\r\nEND:X-CHILD\r\nEND:X-CUSTOM\r\nEND:VCALENDAR\r\n"
  let assert Ok(cal) = a.ical_parse(text)
  assert_unknown(cal)
  let assert Ok(encoded) = a.ical_encode(cal)
  let assert Ok(reparsed) = a.ical_parse(encoded)
  assert_unknown(reparsed)
}

fn assert_unknown(cal: a.IcalCalendar) {
  let assert [unknown] = a.ical_unknown_components(cal)
  let assert [outer] = unknown.properties
  let assert [child] = unknown.children
  let assert [inner] = child.properties
  #(
    unknown.kind,
    outer.name,
    outer.raw_value,
    child.kind,
    inner.name,
    inner.raw_value,
  )
  |> should.equal(#(
    "X-CUSTOM",
    "X-PROP",
    "outer\u{FEFF}value",
    "X-CHILD",
    "X-PROP",
    "inner\u{FEFF}value",
  ))
  child.children |> should.equal([])
}
