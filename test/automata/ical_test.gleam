import automata/ical
import automata/ical/emitter
import automata/ical/parser as ical_parser
import automata/ical/validator as ical_validator
import automata/rrule
import automata/schedule/ast as schedule_ast
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

// ============================================================
// Fixtures
// ============================================================

const minimal_ics =
  "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//EN\r\nBEGIN:VEVENT\r\nUID:abc@test\r\nDTSTAMP:20260511T000000Z\r\nDTSTART:20260511T130000\r\nSUMMARY:Coffee\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

const recurrence_ics =
  "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//recurrence//EN\r\nBEGIN:VEVENT\r\nUID:rec@test\r\nDTSTAMP:20260101T000000Z\r\nDTSTART:20260105T090000\r\nSUMMARY:Standup\r\nRRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=10\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

const alarm_ics =
  "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//alarm//EN\r\nBEGIN:VEVENT\r\nUID:alm@test\r\nDTSTAMP:20260301T000000Z\r\nDTSTART:20260301T140000\r\nSUMMARY:Dentist\r\nBEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT15M\r\nDESCRIPTION:Reminder\r\nEND:VALARM\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

const todo_ics =
  "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//todo//EN\r\nBEGIN:VTODO\r\nUID:todo1@test\r\nDTSTAMP:20260401T000000Z\r\nDUE:20260415T170000\r\nSUMMARY:File taxes\r\nSTATUS:NEEDS-ACTION\r\nPRIORITY:1\r\nPERCENT-COMPLETE:25\r\nEND:VTODO\r\nEND:VCALENDAR\r\n"

const apple_export_ics =
  "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Apple Inc.//macOS 14.0//EN\nCALSCALE:GREGORIAN\nBEGIN:VEVENT\nUID:apple-event-1@icloud\nDTSTAMP:20260201T120000Z\nDTSTART:20260210T090000\nDTEND:20260210T100000\nSUMMARY:Team sync\nX-APPLE-CALENDAR-COLOR:#FF2968\nEND:VEVENT\nEND:VCALENDAR\n"

const google_export_ics =
  "BEGIN:VCALENDAR\r\nPRODID:-//Google Inc//Google Calendar 70.9054//EN\r\nVERSION:2.0\r\nCALSCALE:GREGORIAN\r\nMETHOD:PUBLISH\r\nBEGIN:VTIMEZONE\r\nTZID:Asia/Tokyo\r\nBEGIN:STANDARD\r\nDTSTART:19700101T000000\r\nTZOFFSETFROM:+0900\r\nTZOFFSETTO:+0900\r\nTZNAME:JST\r\nEND:STANDARD\r\nEND:VTIMEZONE\r\nBEGIN:VEVENT\r\nDTSTART;TZID=Asia/Tokyo:20260620T100000\r\nDTEND;TZID=Asia/Tokyo:20260620T110000\r\nRRULE:FREQ=WEEKLY;BYDAY=MO\r\nDTSTAMP:20260601T000000Z\r\nUID:google-event-1@google.com\r\nATTENDEE:mailto:alice@example.com\r\nSUMMARY:Weekly review\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

const outlook_export_ics =
  "BEGIN:VCALENDAR\r\nMETHOD:PUBLISH\r\nPRODID:Microsoft Exchange Server 2010\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:outlook-event-1@outlook\r\nDTSTAMP:20260315T080000Z\r\nDTSTART:20260320T130000Z\r\nDTEND:20260320T140000Z\r\nSUMMARY:Quarterly planning\r\nORGANIZER:mailto:boss@example.com\r\nSEQUENCE:2\r\nTRANSP:OPAQUE\r\nSTATUS:CONFIRMED\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

const nextcloud_export_ics =
  "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//IDN nextcloud.com//Calendar app 4.0.0//EN\r\nBEGIN:VEVENT\r\nCREATED:20260101T100000Z\r\nDTSTAMP:20260105T120000Z\r\nLAST-MODIFIED:20260105T120000Z\r\nUID:nextcloud-event-1@nextcloud\r\nSUMMARY:Lunch with team\r\nDTSTART:20260110T120000\r\nDTEND:20260110T130000\r\nLOCATION:Cafeteria\r\nDESCRIPTION:Monthly catch-up\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

// ============================================================
// Original smoke test (preserved)
// ============================================================

pub fn parse_and_validate_minimal_test() {
  let assert Ok(raw) = ical_parser.parse(minimal_ics)
  let assert Ok(cal) = ical_validator.validate(raw)

  ical_validator.version(cal) |> should.equal("2.0")
  ical_validator.product_id(cal) |> should.equal("-//test//EN")

  let assert [event] = ical_validator.events(cal)
  ical_validator.event_uid(event) |> should.equal("abc@test")
  ical_validator.event_summary(event) |> should.equal(Some("Coffee"))
}

// ============================================================
// Parsing correctness
// ============================================================

pub fn parse_empty_input_returns_error_test() {
  ical.parse("") |> should.equal(Error(ical.EmptyInputError))
}

pub fn parse_minimal_calendar_test() {
  let assert Ok(cal) = ical.parse(minimal_ics)
  ical.version(cal) |> should.equal("2.0")
  ical.product_id(cal) |> should.equal("-//test//EN")
  ical.events(cal) |> list.length |> should.equal(1)
}

pub fn parse_missing_version_test() {
  let ics =
    "BEGIN:VCALENDAR\r\nPRODID:-//x//EN\r\nBEGIN:VEVENT\r\nUID:u\r\nDTSTAMP:20260101T000000Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
  ical.parse(ics) |> should.equal(Error(ical.MissingVersion))
}

pub fn parse_missing_prodid_test() {
  let ics =
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:u\r\nDTSTAMP:20260101T000000Z\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
  ical.parse(ics) |> should.equal(Error(ical.MissingProductId))
}

pub fn parse_unmatched_begin_test() {
  let ics = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//x//EN\r\n"
  case ical.parse(ics) {
    Error(ical.MismatchedBlock(begin: "VCALENDAR", ..)) -> Nil
    other -> {
      other
      |> should.equal(Error(ical.MismatchedBlock("VCALENDAR", "<eof>", 1)))
      Nil
    }
  }
}

pub fn parse_unmatched_end_test() {
  let ics =
    "BEGIN:VEVENT\r\nUID:u\r\nDTSTAMP:20260101T000000Z\r\nEND:VEVENT\r\n"
  case ical.parse(ics) {
    Error(_) -> Nil
    Ok(_) -> should.fail()
  }
}

pub fn parse_nested_valarm_test() {
  let assert Ok(cal) = ical.parse(alarm_ics)
  let assert [event] = ical.events(cal)
  let assert [alarm] = ical.event_alarms(event)
  ical.alarm_action(alarm) |> should.equal("DISPLAY")
  ical.alarm_trigger(alarm) |> should.equal("-PT15M")
  ical.alarm_description(alarm) |> should.equal(Some("Reminder"))
}

pub fn parse_unknown_component_preserved_test() {
  let ics =
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//x//EN\r\nBEGIN:X-CUSTOM\r\nX-FIELD:hello\r\nEND:X-CUSTOM\r\nEND:VCALENDAR\r\n"
  let assert Ok(cal) = ical.parse(ics)
  let assert [unknown] = ical.unknown_components(cal)
  let ical_validator.UnknownComponent(kind: kind, ..) = unknown
  kind |> should.equal("X-CUSTOM")
}

pub fn parse_case_insensitive_property_names_test() {
  let ics =
    "begin:vcalendar\r\nversion:2.0\r\nprodid:-//x//EN\r\nbegin:vevent\r\nuid:u@x\r\ndtstamp:20260101T000000Z\r\nsummary:Hi\r\nend:vevent\r\nend:vcalendar\r\n"
  let assert Ok(cal) = ical.parse(ics)
  let assert [event] = ical.events(cal)
  ical.event_summary(event) |> should.equal(Some("Hi"))
}

pub fn parse_case_insensitive_parameter_names_test() {
  let ics =
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//x//EN\r\nBEGIN:VEVENT\r\nUID:u@x\r\nDTSTAMP:20260101T000000Z\r\ndtstart;tzid=Asia/Tokyo:20260101T090000\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
  let assert Ok(cal) = ical.parse(ics)
  let assert [event] = ical.events(cal)
  ical.event_dtstart_tzid(event) |> should.equal(Some("Asia/Tokyo"))
}

pub fn parse_quoted_parameter_value_with_comma_test() {
  let ics =
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//x//EN\r\nBEGIN:VEVENT\r\nUID:u@x\r\nDTSTAMP:20260101T000000Z\r\nDTSTART;TZID=\"Asia/Tokyo,Standard\":20260101T090000\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
  let assert Ok(cal) = ical.parse(ics)
  let assert [event] = ical.events(cal)
  ical.event_dtstart_tzid(event) |> should.equal(Some("Asia/Tokyo,Standard"))
}

pub fn parse_long_folded_summary_test() {
  let line1 = "SUMMARY:This is a very long summary that spans"
  let line2 = " across multiple physical lines via the §3.1 fold mechanism"
  let ics =
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//x//EN\r\nBEGIN:VEVENT\r\nUID:u@x\r\nDTSTAMP:20260101T000000Z\r\n"
    <> line1
    <> "\r\n"
    <> line2
    <> "\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
  let assert Ok(cal) = ical.parse(ics)
  let assert [event] = ical.events(cal)
  case ical.event_summary(event) {
    Some(s) -> {
      string.contains(s, "very long summary") |> should.equal(True)
      string.contains(s, "fold mechanism") |> should.equal(True)
    }
    None -> should.fail()
  }
}

pub fn parse_lf_only_line_endings_test() {
  let lf_input = string.replace(minimal_ics, "\r\n", "\n")
  let assert Ok(cal) = ical.parse(lf_input)
  ical.version(cal) |> should.equal("2.0")
}

pub fn parse_bom_tolerated_test() {
  let bom_input = "\u{FEFF}" <> minimal_ics
  let assert Ok(cal) = ical.parse(bom_input)
  ical.version(cal) |> should.equal("2.0")
}

// ============================================================
// Escape handling
// ============================================================

pub fn escape_backslash_test() {
  let ics =
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//x//EN\r\nBEGIN:VEVENT\r\nUID:u\r\nDTSTAMP:20260101T000000Z\r\nSUMMARY:back\\\\slash\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
  let assert Ok(cal) = ical.parse(ics)
  let assert [event] = ical.events(cal)
  ical.event_summary(event) |> should.equal(Some("back\\slash"))
}

pub fn escape_comma_test() {
  let ics =
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//x//EN\r\nBEGIN:VEVENT\r\nUID:u\r\nDTSTAMP:20260101T000000Z\r\nSUMMARY:a\\,b\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
  let assert Ok(cal) = ical.parse(ics)
  let assert [event] = ical.events(cal)
  ical.event_summary(event) |> should.equal(Some("a,b"))
}

pub fn escape_semicolon_test() {
  let ics =
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//x//EN\r\nBEGIN:VEVENT\r\nUID:u\r\nDTSTAMP:20260101T000000Z\r\nSUMMARY:a\\;b\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
  let assert Ok(cal) = ical.parse(ics)
  let assert [event] = ical.events(cal)
  ical.event_summary(event) |> should.equal(Some("a;b"))
}

pub fn escape_newline_lower_test() {
  let ics =
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//x//EN\r\nBEGIN:VEVENT\r\nUID:u\r\nDTSTAMP:20260101T000000Z\r\nSUMMARY:a\\nb\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
  let assert Ok(cal) = ical.parse(ics)
  let assert [event] = ical.events(cal)
  ical.event_summary(event) |> should.equal(Some("a\nb"))
}

pub fn escape_newline_upper_test() {
  let ics =
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//x//EN\r\nBEGIN:VEVENT\r\nUID:u\r\nDTSTAMP:20260101T000000Z\r\nSUMMARY:a\\Nb\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
  let assert Ok(cal) = ical.parse(ics)
  let assert [event] = ical.events(cal)
  ical.event_summary(event) |> should.equal(Some("a\nb"))
}

pub fn escape_applied_to_location_test() {
  let ics =
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//x//EN\r\nBEGIN:VEVENT\r\nUID:u\r\nDTSTAMP:20260101T000000Z\r\nLOCATION:Tokyo\\, Japan\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
  let assert Ok(cal) = ical.parse(ics)
  let assert [event] = ical.events(cal)
  ical.event_location(event) |> should.equal(Some("Tokyo, Japan"))
}

pub fn escape_not_applied_to_uri_test() {
  // URLs contain ; in some cases; we don't unescape URL.
  let ics =
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//x//EN\r\nBEGIN:VEVENT\r\nUID:u\r\nDTSTAMP:20260101T000000Z\r\nURL:https://example.com/path\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
  let assert Ok(cal) = ical.parse(ics)
  let assert [event] = ical.events(cal)
  ical.event_url(event) |> should.equal(Some("https://example.com/path"))
}

// ============================================================
// RRULE composition
// ============================================================

pub fn rrule_returned_as_raw_test() {
  let assert Ok(cal) = ical.parse(recurrence_ics)
  let assert [event] = ical.events(cal)
  case ical.event_rrule(event) {
    Some(_raw) -> Nil
    None -> should.fail()
  }
}

pub fn rrule_pipes_to_validator_test() {
  let assert Ok(cal) = ical.parse(recurrence_ics)
  let assert [event] = ical.events(cal)
  let assert Some(raw) = ical.event_rrule(event)
  case rrule.validate(raw: raw) {
    Ok(_spec) -> Nil
    Error(_) -> should.fail()
  }
}

pub fn rrule_duplicate_rejected_test() {
  let ics =
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//x//EN\r\nBEGIN:VEVENT\r\nUID:dup@x\r\nDTSTAMP:20260101T000000Z\r\nRRULE:FREQ=DAILY\r\nRRULE:FREQ=WEEKLY\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
  case ical.parse(ics) {
    Error(ical.DuplicateRRule(component_uid: "dup@x")) -> Nil
    other -> {
      other
      |> should.equal(Error(ical.DuplicateRRule(component_uid: "dup@x")))
      Nil
    }
  }
}

// ============================================================
// Round-trip stability
// ============================================================

fn round_trip_preserves_event_count(input: String) -> Nil {
  let assert Ok(cal1) = ical.parse(input)
  let encoded = ical.encode(cal1)
  let assert Ok(cal2) = ical.parse(encoded)
  list.length(ical.events(cal1))
  |> should.equal(list.length(ical.events(cal2)))
}

pub fn round_trip_minimal_test() {
  round_trip_preserves_event_count(minimal_ics)
}

pub fn round_trip_recurrence_test() {
  let assert Ok(cal1) = ical.parse(recurrence_ics)
  let encoded = ical.encode(cal1)
  let assert Ok(cal2) = ical.parse(encoded)
  let assert [e1] = ical.events(cal1)
  let assert [e2] = ical.events(cal2)
  ical.event_rrule(e1) |> should.equal(ical.event_rrule(e2))
}

pub fn round_trip_todo_test() {
  let assert Ok(cal1) = ical.parse(todo_ics)
  let encoded = ical.encode(cal1)
  let assert Ok(cal2) = ical.parse(encoded)
  let assert [t1] = ical.todos(cal1)
  let assert [t2] = ical.todos(cal2)
  ical.todo_uid(t1) |> should.equal(ical.todo_uid(t2))
  ical.todo_summary(t1) |> should.equal(ical.todo_summary(t2))
  ical.todo_priority(t1) |> should.equal(ical.todo_priority(t2))
}

pub fn round_trip_alarm_test() {
  let assert Ok(cal1) = ical.parse(alarm_ics)
  let encoded = ical.encode(cal1)
  let assert Ok(cal2) = ical.parse(encoded)
  let assert [e1] = ical.events(cal1)
  let assert [e2] = ical.events(cal2)
  let assert [a1] = ical.event_alarms(e1)
  let assert [a2] = ical.event_alarms(e2)
  ical.alarm_action(a1) |> should.equal(ical.alarm_action(a2))
  ical.alarm_trigger(a1) |> should.equal(ical.alarm_trigger(a2))
}

pub fn round_trip_google_test() {
  let assert Ok(cal1) = ical.parse(google_export_ics)
  let encoded = ical.encode(cal1)
  let assert Ok(cal2) = ical.parse(encoded)
  list.length(ical.events(cal1))
  |> should.equal(list.length(ical.events(cal2)))
  list.length(ical.timezones(cal1))
  |> should.equal(list.length(ical.timezones(cal2)))
}

pub fn round_trip_apple_test() {
  round_trip_preserves_event_count(apple_export_ics)
}

pub fn round_trip_outlook_test() {
  let assert Ok(cal1) = ical.parse(outlook_export_ics)
  let encoded = ical.encode(cal1)
  let assert Ok(cal2) = ical.parse(encoded)
  ical.method(cal1) |> should.equal(ical.method(cal2))
}

pub fn round_trip_nextcloud_test() {
  round_trip_preserves_event_count(nextcloud_export_ics)
}

// ============================================================
// Emit format compliance
// ============================================================

pub fn emit_no_line_exceeds_75_octets_test() {
  let long_summary = string.repeat("a", 200)
  let assert Ok(start_dt) =
    schedule_ast.try_datetime(
      year: 2026,
      month: 5,
      day: 11,
      hour: 9,
      minute: 0,
      second: 0,
    )
  let cal =
    ical.new_calendar(version: "2.0", prod_id: "-//x//EN")
    |> ical.add_event(
      ical.new_event(uid: "long@x", dtstamp: start_dt)
      |> ical.with_summary(long_summary),
    )
  let encoded = ical.encode(cal)
  let lines = string.split(encoded, "\r\n")
  list.each(lines, fn(line) {
    // 75 octet limit is on the raw bytes pre-CRLF; ASCII char count == bytes
    case string.byte_size(line) > 75 {
      True -> should.fail()
      False -> Nil
    }
  })
}

pub fn emit_uses_crlf_test() {
  let assert Ok(cal) = ical.parse(minimal_ics)
  let encoded = ical.encode(cal)
  string.contains(encoded, "\r\n") |> should.equal(True)
}

pub fn emit_escapes_text_specials_test() {
  let assert Ok(start_dt) =
    schedule_ast.try_datetime(
      year: 2026,
      month: 5,
      day: 11,
      hour: 9,
      minute: 0,
      second: 0,
    )
  let cal =
    ical.new_calendar(version: "2.0", prod_id: "-//x//EN")
    |> ical.add_event(
      ical.new_event(uid: "esc@x", dtstamp: start_dt)
      |> ical.with_summary("a,b;c\nd"),
    )
  let encoded = ical.encode(cal)
  string.contains(encoded, "a\\,b\\;c\\nd") |> should.equal(True)
}

// ============================================================
// Real-world fixture parsing
// ============================================================

pub fn fixture_minimal_parses_test() {
  case ical.parse(minimal_ics) {
    Ok(_) -> Nil
    Error(_) -> should.fail()
  }
}

pub fn fixture_recurrence_parses_test() {
  case ical.parse(recurrence_ics) {
    Ok(_) -> Nil
    Error(_) -> should.fail()
  }
}

pub fn fixture_todo_parses_test() {
  case ical.parse(todo_ics) {
    Ok(_) -> Nil
    Error(_) -> should.fail()
  }
}

pub fn fixture_alarm_parses_test() {
  case ical.parse(alarm_ics) {
    Ok(_) -> Nil
    Error(_) -> should.fail()
  }
}

pub fn fixture_google_parses_test() {
  case ical.parse(google_export_ics) {
    Ok(_) -> Nil
    Error(_) -> should.fail()
  }
}

pub fn fixture_apple_parses_test() {
  case ical.parse(apple_export_ics) {
    Ok(_) -> Nil
    Error(_) -> should.fail()
  }
}

pub fn fixture_outlook_parses_test() {
  case ical.parse(outlook_export_ics) {
    Ok(_) -> Nil
    Error(_) -> should.fail()
  }
}

pub fn fixture_nextcloud_parses_test() {
  case ical.parse(nextcloud_export_ics) {
    Ok(_) -> Nil
    Error(_) -> should.fail()
  }
}

// ============================================================
// Error reporting
// ============================================================

pub fn error_carries_line_number_test() {
  // Malformed property: missing colon (and not BEGIN/END marker) on line 3.
  let ics = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nNOCOLONHERE\r\nEND:VCALENDAR\r\n"
  case ical.parse(ics) {
    Error(ical.MalformedProperty(line: ln, ..)) -> {
      ln |> should.equal(3)
    }
    other -> {
      other
      |> should.equal(Error(ical.MalformedProperty(3, "NOCOLONHERE")))
      Nil
    }
  }
}

pub fn error_carries_raw_text_test() {
  let ics =
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//x//EN\r\nBEGIN:VEVENT\r\nUID:u\r\nDTSTAMP:not-a-date\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
  case ical.parse(ics) {
    Error(ical.InvalidDateTime(name: "DTSTAMP", raw: "not-a-date")) -> Nil
    other -> {
      other
      |> should.equal(Error(ical.InvalidDateTime("DTSTAMP", "not-a-date")))
      Nil
    }
  }
}

// ============================================================
// Internal helpers (emitter)
// ============================================================

pub fn fold_line_short_returns_single_test() {
  emitter.fold_line("hello") |> should.equal(["hello"])
}

pub fn fold_line_long_folds_test() {
  let long = string.repeat("a", 200)
  let folded = emitter.fold_line(long)
  list.length(folded) |> { fn(n) { n > 1 } } |> should.equal(True)
  list.each(folded, fn(line) {
    case string.byte_size(line) > 75 {
      True -> should.fail()
      False -> Nil
    }
  })
}

pub fn escape_text_round_trip_test() {
  let s = "comma,semi;back\\nl\nnormal"
  let escaped = emitter.escape_text(s)
  // We can't directly call validator.unescape_text but we can verify the
  // escaped string parses back through a round trip via SUMMARY.
  let assert Ok(start_dt) =
    schedule_ast.try_datetime(
      year: 2026,
      month: 5,
      day: 11,
      hour: 9,
      minute: 0,
      second: 0,
    )
  let cal =
    ical.new_calendar(version: "2.0", prod_id: "-//x//EN")
    |> ical.add_event(
      ical.new_event(uid: "esc@x", dtstamp: start_dt)
      |> ical.with_summary(s),
    )
  let encoded = ical.encode(cal)
  string.contains(encoded, escaped) |> should.equal(True)
  let assert Ok(cal2) = ical.parse(encoded)
  let assert [e2] = ical.events(cal2)
  ical.event_summary(e2) |> should.equal(Some(s))
}

// ============================================================
// UTC marker preservation (RFC 5545 §3.3.5 FORM #2)
// ============================================================

const utc_event_ics =
  "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//EN\r\nBEGIN:VEVENT\r\nUID:utc@test\r\nDTSTAMP:20240101T120000Z\r\nDTSTART:20240615T090000Z\r\nDTEND:20240615T100000Z\r\nSUMMARY:Meeting\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

pub fn encode_preserves_z_marker_on_dtstamp_test() {
  let body = utc_event_ics
  let assert Ok(cal) = ical.parse(body)
  let encoded = ical.encode(cal)
  // Every emitted DATE-TIME line should keep its Z suffix.
  string.contains(encoded, "DTSTAMP:20240101T120000Z") |> should.equal(True)
  string.contains(encoded, "DTSTART:20240615T090000Z") |> should.equal(True)
  string.contains(encoded, "DTEND:20240615T100000Z") |> should.equal(True)
}

pub fn encode_keeps_no_z_under_tzid_test() {
  // When DTSTART carries TZID, the value is FORM #3 (local time anchored
  // to a named zone) and MUST NOT have a Z suffix.
  let assert Ok(cal) = ical.parse(google_export_ics)
  let encoded = ical.encode(cal)
  // Should emit DTSTART;TZID=Asia/Tokyo:20260620T100000 (no Z)
  string.contains(encoded, "DTSTART;TZID=Asia/Tokyo:20260620T100000")
  |> should.equal(True)
  // ... but DTSTAMP (which has no TZID) should keep its Z
  string.contains(encoded, "DTSTAMP:20260601T000000Z") |> should.equal(True)
}

pub fn encode_preserves_z_on_created_and_last_modified_test() {
  let assert Ok(cal) = ical.parse(nextcloud_export_ics)
  let encoded = ical.encode(cal)
  string.contains(encoded, "CREATED:20260101T100000Z") |> should.equal(True)
  string.contains(encoded, "LAST-MODIFIED:20260105T120000Z")
  |> should.equal(True)
}

// ============================================================
// Component order
// ============================================================

fn stamp() -> schedule_ast.DateTime {
  schedule_ast.datetime(2026, 5, 11, 9, 0, 0)
}

pub fn add_component_keeps_insertion_order_test() {
  let cal =
    ical.new_calendar(version: "2.0", prod_id: "-//x//EN")
    |> ical.add_event(ical.new_event(uid: "e1", dtstamp: stamp()))
    |> ical.add_todo(ical.new_todo(uid: "t1", dtstamp: stamp()))
    |> ical.add_event(ical.new_event(uid: "e2", dtstamp: stamp()))
    |> ical.add_todo(ical.new_todo(uid: "t2", dtstamp: stamp()))
    |> ical.add_event(ical.new_event(uid: "e3", dtstamp: stamp()))

  list.map(ical.events(cal), ical.event_uid)
  |> should.equal(["e1", "e2", "e3"])
  list.map(ical.todos(cal), ical.todo_uid) |> should.equal(["t1", "t2"])

  let assert Ok(decoded) = ical.parse(ical.encode(cal))
  list.map(ical.events(decoded), ical.event_uid)
  |> should.equal(["e1", "e2", "e3"])
  decoded |> should.equal(cal)
}

pub fn add_many_events_keeps_order_test() {
  let cal =
    list.fold(
      list.repeat(Nil, 3000),
      #(ical.new_calendar(version: "2.0", prod_id: "-//x//EN"), 0),
      fn(acc, _) {
        let #(cal, n) = acc
        #(
          ical.add_event(
            cal,
            ical.new_event(uid: "e" <> int.to_string(n), dtstamp: stamp()),
          ),
          n + 1,
        )
      },
    ).0
  let uids = list.map(ical.events(cal), ical.event_uid)
  list.length(uids) |> should.equal(3000)
  list.first(uids) |> should.equal(Ok("e0"))
  list.last(uids) |> should.equal(Ok("e2999"))
}

// ============================================================
// Round trip of value forms and parameters
// ============================================================

fn wrap_event(lines: List(String)) -> String {
  string.join(
    list.flatten([
      [
        "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//x//EN", "BEGIN:VEVENT",
        "UID:u@x", "DTSTAMP:20260101T000000Z",
      ],
      lines,
      ["END:VEVENT", "END:VCALENDAR", ""],
    ]),
    "\r\n",
  )
}

fn encoded_lines(input: String) -> List(String) {
  let assert Ok(cal) = ical.parse(input)
  string.split(ical.encode(cal), "\r\n")
}

pub fn encode_keeps_floating_datetime_test() {
  // DTSTART without Z is floating local time; adding Z would move it
  // to UTC.
  let lines = encoded_lines(minimal_ics)
  list.contains(lines, "DTSTART:20260511T130000") |> should.equal(True)
  list.contains(lines, "DTSTART:20260511T130000Z") |> should.equal(False)
}

pub fn encode_keeps_utc_datetime_test() {
  encoded_lines(outlook_export_ics)
  |> list.contains("DTSTART:20260320T130000Z")
  |> should.equal(True)
}

pub fn encode_keeps_date_value_test() {
  let lines =
    encoded_lines(
      wrap_event(["DTSTART;VALUE=DATE:20260101", "DTEND;VALUE=DATE:20260102"]),
    )
  list.contains(lines, "DTSTART;VALUE=DATE:20260101") |> should.equal(True)
  list.contains(lines, "DTEND;VALUE=DATE:20260102") |> should.equal(True)
}

pub fn encode_keeps_date_list_test() {
  encoded_lines(
    wrap_event([
      "DTSTART;VALUE=DATE:20260101", "RDATE;VALUE=DATE:20260105,20260106",
      "EXDATE;VALUE=DATE:20260108",
    ]),
  )
  |> list.filter(fn(line) {
    string.starts_with(line, "RDATE") || string.starts_with(line, "EXDATE")
  })
  |> should.equal([
    "RDATE;VALUE=DATE:20260105,20260106", "EXDATE;VALUE=DATE:20260108",
  ])
}

pub fn encode_keeps_property_parameters_test() {
  let lines =
    encoded_lines(
      wrap_event([
        "DTSTART:20260511T130000Z", "ORGANIZER;CN=\"Doe, John: Jr\":mailto:j@x",
        "SUMMARY;LANGUAGE=de:Kaffee",
      ]),
    )
  list.contains(lines, "ORGANIZER;CN=\"Doe, John: Jr\":mailto:j@x")
  |> should.equal(True)
  list.contains(lines, "SUMMARY;LANGUAGE=de:Kaffee") |> should.equal(True)
}

pub fn encode_keeps_todo_tzid_test() {
  let input =
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//x//EN\r\nBEGIN:VTODO\r\nUID:t@x\r\nDTSTAMP:20260101T000000Z\r\nDUE;TZID=Asia/Tokyo:20260415T170000\r\nEND:VTODO\r\nEND:VCALENDAR\r\n"
  encoded_lines(input)
  |> list.contains("DUE;TZID=Asia/Tokyo:20260415T170000")
  |> should.equal(True)
}

pub fn encode_keeps_alarm_trigger_parameters_test() {
  encoded_lines(
    wrap_event([
      "BEGIN:VALARM", "ACTION:DISPLAY", "TRIGGER;RELATED=END:-PT5M",
      "DESCRIPTION:Soon", "END:VALARM",
    ]),
  )
  |> list.contains("TRIGGER;RELATED=END:-PT5M")
  |> should.equal(True)
}

pub fn setter_replaces_parsed_value_form_test() {
  // A new value from a setter has no form of its own, so it is written
  // as UTC like any built value.
  let assert Ok(cal) = ical.parse(wrap_event(["DTSTART;VALUE=DATE:20260101"]))
  let assert [event] = ical.events(cal)
  let moved =
    ical.with_dtstart(event, schedule_ast.datetime(2026, 1, 2, 9, 0, 0))
  let out =
    ical.new_calendar(version: "2.0", prod_id: "-//x//EN")
    |> ical.add_event(moved)
    |> ical.encode
  string.contains(out, "DTSTART:20260102T090000Z\r\n") |> should.equal(True)
}

pub fn duplicate_single_valued_property_keeps_first_test() {
  // RFC 5545 allows DTSTART once; a second one is ignored, both in the
  // model and in the encoded output.
  let input =
    wrap_event(["DTSTART:20260511T130000", "DTSTART:20270101T000000Z"])
  let assert Ok(cal) = ical.parse(input)
  let assert [event] = ical.events(cal)
  ical.event_dtstart(event)
  |> should.equal(Some(schedule_ast.datetime(2026, 5, 11, 13, 0, 0)))
  encoded_lines(input)
  |> list.filter(fn(line) { string.starts_with(line, "DTSTART") })
  |> should.equal(["DTSTART:20260511T130000"])
}

fn encode_events(events: List(ical.Event)) -> List(String) {
  list.fold(
    events,
    ical.new_calendar(version: "2.0", prod_id: "-//x//EN"),
    ical.add_event,
  )
  |> ical.encode
  |> string.split("\r\n")
}

fn starting_with(lines: List(String), prefix: String) -> List(String) {
  list.filter(lines, string.starts_with(_, prefix))
}

pub fn added_rdate_is_written_as_utc_test() {
  // The parsed RDATE line is a DATE; a value added later is a UTC
  // DATE-TIME and must not take the parsed line's form.
  let assert Ok(cal) =
    ical.parse(
      wrap_event([
        "DTSTART;VALUE=DATE:20260101", "RDATE;VALUE=DATE:20260105",
        "EXDATE;TZID=Asia/Tokyo:20260108T090000",
      ]),
    )
  let assert [event] = ical.events(cal)
  let lines =
    event
    |> ical.add_rdate(schedule_ast.datetime(2026, 1, 7, 9, 0, 0))
    |> ical.add_exdate(schedule_ast.datetime(2026, 1, 9, 9, 0, 0))
    |> list.wrap
    |> encode_events
  starting_with(lines, "RDATE")
  |> should.equal(["RDATE;VALUE=DATE:20260105", "RDATE:20260107T090000Z"])
  starting_with(lines, "EXDATE")
  |> should.equal([
    "EXDATE;TZID=Asia/Tokyo:20260108T090000", "EXDATE:20260109T090000Z",
  ])
}

pub fn added_todo_rdate_is_written_as_utc_test() {
  let input =
    "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//x//EN\r\nBEGIN:VTODO\r\nUID:t@x\r\nDTSTAMP:20260101T000000Z\r\nRDATE;VALUE=DATE:20260105\r\nEXDATE;VALUE=DATE:20260106\r\nEND:VTODO\r\nEND:VCALENDAR\r\n"
  let assert Ok(cal) = ical.parse(input)
  let assert [t] = ical.todos(cal)
  let updated =
    t
    |> ical.add_todo_rdate(schedule_ast.datetime(2026, 1, 7, 9, 0, 0))
    |> ical.add_todo_exdate(schedule_ast.datetime(2026, 1, 8, 9, 0, 0))
  let lines =
    ical.new_calendar(version: "2.0", prod_id: "-//x//EN")
    |> ical.add_todo(updated)
    |> ical.encode
    |> string.split("\r\n")
  starting_with(lines, "RDATE")
  |> should.equal(["RDATE;VALUE=DATE:20260105", "RDATE:20260107T090000Z"])
  starting_with(lines, "EXDATE")
  |> should.equal(["EXDATE;VALUE=DATE:20260106", "EXDATE:20260108T090000Z"])
}

pub fn date_list_lines_keep_their_own_forms_test() {
  let lines =
    encoded_lines(
      wrap_event([
        "DTSTART:20260101T090000Z", "RDATE;VALUE=DATE:20260105,20260106",
        "RDATE;TZID=Asia/Tokyo:20260107T090000", "RDATE:20260108T090000Z",
      ]),
    )
  starting_with(lines, "RDATE")
  |> should.equal([
    "RDATE;VALUE=DATE:20260105,20260106",
    "RDATE;TZID=Asia/Tokyo:20260107T090000", "RDATE:20260108T090000Z",
  ])
}

pub fn date_without_value_parameter_stays_a_date_test() {
  // An 8-digit value is a DATE even without VALUE=DATE.
  let lines = encoded_lines(wrap_event(["DTSTART:20250101"]))
  starting_with(lines, "DTSTART") |> should.equal(["DTSTART:20250101"])
}

pub fn moving_date_dtstart_also_resets_dtend_test() {
  // DTSTART and DTEND must have the same value type, so replacing a DATE
  // DTSTART with a DATE-TIME also writes DTEND as a DATE-TIME.
  let assert Ok(cal) =
    ical.parse(
      wrap_event(["DTSTART;VALUE=DATE:20260101", "DTEND;VALUE=DATE:20260102"]),
    )
  let assert [event] = ical.events(cal)
  let lines =
    event
    |> ical.with_dtstart(schedule_ast.datetime(2026, 1, 1, 9, 0, 0))
    |> list.wrap
    |> encode_events
  starting_with(lines, "DTSTART") |> should.equal(["DTSTART:20260101T090000Z"])
  starting_with(lines, "DTEND") |> should.equal(["DTEND:20260102T000000Z"])
}

fn wrap_component(kind: String, lines: List(String)) -> String {
  wrap_event(lines)
  |> string.replace("VEVENT", kind)
}

pub fn repeated_properties_keep_parameters_per_value_test() {
  let attendees = [
    "ATTENDEE;CN=Alice;PARTSTAT=ACCEPTED:mailto:a@x",
    "ATTENDEE;CN=Bob;PARTSTAT=DECLINED:mailto:b@x",
    "ATTENDEE:mailto:c@x",
  ]
  ["VEVENT", "VFREEBUSY", "VALARM"]
  |> list.each(fn(kind) {
    let lines = list.append(["ACTION:EMAIL", "TRIGGER:-PT5M"], attendees)
    let input = case kind {
      "VALARM" ->
        wrap_event(list.append(["BEGIN:VALARM", ..lines], ["END:VALARM"]))
      _ -> wrap_component(kind, lines)
    }
    encoded_lines(input)
    |> starting_with("ATTENDEE")
    |> should.equal(attendees)
  })
}

pub fn freebusy_lines_keep_their_busy_types_test() {
  let periods = [
    "FREEBUSY;FBTYPE=FREE:20260101T090000Z/20260101T100000Z",
    "FREEBUSY;FBTYPE=BUSY-TENTATIVE:20260102T090000Z/PT1H",
    "FREEBUSY:20260103T090000Z/PT1H",
  ]
  wrap_component("VFREEBUSY", periods)
  |> encoded_lines
  |> starting_with("FREEBUSY")
  |> should.equal(periods)
}

pub fn category_lines_keep_their_languages_test() {
  let categories = [
    "CATEGORIES;LANGUAGE=en:Work,Home\\, office",
    "CATEGORIES;LANGUAGE=de:Arbeit",
    "CATEGORIES:Travel",
  ]
  ["VEVENT", "VTODO", "VJOURNAL"]
  |> list.each(fn(kind) {
    wrap_component(kind, categories)
    |> encoded_lines
    |> starting_with("CATEGORIES")
    |> should.equal(categories)
  })
}

pub fn appended_properties_do_not_inherit_parsed_parameters_test() {
  let assert Ok(cal) =
    ical.parse(
      wrap_event([
        "ATTENDEE;CN=Alice:mailto:a@x", "CATEGORIES;LANGUAGE=de:Arbeit",
      ]),
    )
  let assert [event] = ical.events(cal)
  let lines =
    event
    |> ical.add_attendee("mailto:b@x")
    |> ical.add_category("Work")
    |> list.wrap
    |> encode_events
  starting_with(lines, "ATTENDEE")
  |> should.equal(["ATTENDEE;CN=Alice:mailto:a@x", "ATTENDEE:mailto:b@x"])
  starting_with(lines, "CATEGORIES")
  |> should.equal(["CATEGORIES;LANGUAGE=de:Arbeit", "CATEGORIES:Work"])
}

pub fn event_setters_clear_replaced_property_parameters_test() {
  let assert Ok(cal) =
    ical.parse(
      wrap_event([
        "SUMMARY;LANGUAGE=de:Alt", "DESCRIPTION;LANGUAGE=de:Alt",
        "LOCATION;ALTREP=\"cid:old\":Alt", "URL;X-LABEL=old:https://old",
        "DURATION;X-LABEL=old:PT1H", "STATUS;X-LABEL=old:TENTATIVE",
        "TRANSP;X-LABEL=old:OPAQUE",
      ]),
    )
  let assert [event] = ical.events(cal)
  let lines =
    event
    |> ical.with_summary("New")
    |> ical.with_description("New")
    |> ical.with_location("New")
    |> ical.with_url("https://new")
    |> ical.with_duration("PT2H")
    |> ical.with_status("CONFIRMED")
    |> ical.with_transparency("TRANSPARENT")
    |> list.wrap
    |> encode_events
  [
    "SUMMARY:New",
    "DESCRIPTION:New",
    "LOCATION:New",
    "URL:https://new",
    "DURATION:PT2H",
    "STATUS:CONFIRMED",
    "TRANSP:TRANSPARENT",
  ]
  |> list.each(fn(expected) { list.contains(lines, expected) |> should.be_true })
}

pub fn other_component_setters_clear_replaced_parameters_test() {
  let input =
    string.concat([
      "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//x//EN\r\n",
      "BEGIN:VTODO\r\nUID:t\r\nDTSTAMP:20260101T000000Z\r\nSUMMARY;LANGUAGE=de:Alt\r\nEND:VTODO\r\n",
      "BEGIN:VJOURNAL\r\nUID:j\r\nDTSTAMP:20260101T000000Z\r\nSUMMARY;LANGUAGE=de:Alt\r\nEND:VJOURNAL\r\n",
      "BEGIN:VEVENT\r\nUID:e\r\nDTSTAMP:20260101T000000Z\r\nBEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT5M\r\nDESCRIPTION;LANGUAGE=de:Alt\r\nEND:VALARM\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n",
    ])
  let assert Ok(cal) = ical.parse(input)
  let assert [task] = ical.todos(cal)
  let assert [journal] = ical.journals(cal)
  let assert [event] = ical.events(cal)
  let assert [alarm] = ical.event_alarms(event)
  let lines =
    ical.new_calendar("2.0", "-//x//EN")
    |> ical.add_todo(ical.with_todo_summary(task, "New"))
    |> ical.add_journal(ical.with_journal_summary(journal, "New"))
    |> ical.add_event(
      ical.new_event("new", stamp())
      |> ical.add_alarm(ical.with_alarm_description(alarm, "New")),
    )
    |> ical.encode
    |> string.split("\r\n")
  starting_with(lines, "SUMMARY")
  |> should.equal(["SUMMARY:New", "SUMMARY:New"])
  starting_with(lines, "DESCRIPTION") |> should.equal(["DESCRIPTION:New"])
}

pub fn exdate_lines_keep_their_own_forms_on_events_and_todos_test() {
  let dates = [
    "EXDATE:20260101T090000Z", "EXDATE;TZID=Asia/Tokyo:20260102T090000",
    "EXDATE;VALUE=DATE:20260103,20260104", "EXDATE:20260105T090000",
  ]
  ["VEVENT", "VTODO"]
  |> list.each(fn(kind) {
    encoded_lines(wrap_component(kind, dates))
    |> starting_with("EXDATE")
    |> should.equal(dates)
  })
}

pub fn categories_distinguish_escaped_backslashes_from_escaped_commas_test() {
  let input = wrap_event(["CATEGORIES:Path\\\\,Next,Home\\, office"])
  let assert Ok(cal) = ical.parse(input)
  let assert [event] = ical.events(cal)
  ical.event_categories(event)
  |> should.equal(["Path\\", "Next", "Home, office"])
  encoded_lines(input)
  |> starting_with("CATEGORIES")
  |> should.equal(["CATEGORIES:Path\\\\,Next,Home\\, office"])
}

pub fn scalar_property_parameters_survive_encoding_test() {
  let props = [
    "CREATED;X-SOURCE=one:20260101T000000Z",
    "LAST-MODIFIED;X-SOURCE=two:20260102T000000Z",
    "SEQUENCE;X-SOURCE=three:0",
    "RRULE;X-SOURCE=four:FREQ=DAILY",
  ]
  let lines = encoded_lines(wrap_event(props))
  props |> list.each(fn(prop) { list.contains(lines, prop) |> should.be_true })
}

pub fn extension_properties_keep_raw_values_and_last_parameters_test() {
  let props = [
    "X-TEXT;LANGUAGE=en:Hello\\, world\\nAgain",
    "X-LINK;VALUE=URI:https://x/a,b;c",
    "X-REPEATED;LANGUAGE=en:old",
    "X-REPEATED;LANGUAGE=de:neu",
  ]
  ["VEVENT", "VTODO", "VJOURNAL", "VFREEBUSY"]
  |> list.each(fn(kind) {
    let input = wrap_component(kind, props)
    let lines = encoded_lines(input)
    starting_with(lines, "X-")
    |> list.sort(string.compare)
    |> should.equal([
      "X-LINK;VALUE=URI:https://x/a,b;c",
      "X-REPEATED;LANGUAGE=de:neu",
      "X-TEXT;LANGUAGE=en:Hello\\, world\\nAgain",
    ])
    encoded_lines(string.join(lines, "\r\n")) |> should.equal(lines)
  })
}

pub fn calendar_and_timezone_keep_text_escaping_and_parameters_test() {
  let props = [
    "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Example\\, Inc//EN",
    "X-TEXT;LANGUAGE=de:eins\\, zwei", "BEGIN:VTIMEZONE", "TZID:Example",
    "BEGIN:STANDARD", "DTSTART:20260101T020000", "TZOFFSETFROM:+0100",
    "TZOFFSETTO:+0100", "TZNAME;LANGUAGE=de:Zeit\\, Name", "END:STANDARD",
    "BEGIN:DAYLIGHT", "DTSTART:20260601T020000", "TZOFFSETFROM:+0100",
    "TZOFFSETTO:+0200", "TZNAME;LANGUAGE=en:Summer", "END:DAYLIGHT",
    "END:VTIMEZONE", "END:VCALENDAR", "",
  ]
  let input = string.join(props, "\r\n")
  encoded_lines(input) |> should.equal(props)
}

pub fn replacing_extension_property_clears_parameters_and_escapes_text_test() {
  let assert Ok(cal) = ical.parse(wrap_event(["X-NAME;LANGUAGE=de:Alt"]))
  let assert [event] = ical.events(cal)
  let lines =
    event
    |> ical.with_event_x_property("X-NAME", "New, text")
    |> list.wrap
    |> encode_events
  starting_with(lines, "X-NAME") |> should.equal(["X-NAME:New\\, text"])
}

pub fn parameter_lists_keep_quoted_value_boundaries_test() {
  // The first line has three values; the second has one comma-containing
  // value. Quoting the entire first list would change its meaning.
  let props = [
    "X-LIST;X-OPTIONS=one,\"two,three\",four:value",
    "X-SINGLE;X-OPTIONS=\"one,two\":value",
    "ATTENDEE;MEMBER=\"mailto:a@x\",\"mailto:b@x\":mailto:c@x",
  ]
  ["VEVENT", "X-CUSTOM"]
  |> list.each(fn(kind) {
    let lines = encoded_lines(wrap_component(kind, props))
    props
    |> list.each(fn(prop) { list.contains(lines, prop) |> should.be_true })
    encoded_lines(string.join(lines, "\r\n")) |> should.equal(lines)
  })
}

pub fn parsed_timezone_rule_keeps_an_explicit_utc_marker_test() {
  // Even when accepting a non-local DTSTART in a timezone rule, encoding
  // must not silently reinterpret the retained value as local time.
  let input =
    string.join(
      [
        "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//x//EN", "BEGIN:VTIMEZONE",
        "TZID:Example", "BEGIN:STANDARD", "DTSTART:20260101T020000Z",
        "TZOFFSETFROM:+0100", "TZOFFSETTO:+0100", "END:STANDARD",
        "END:VTIMEZONE", "END:VCALENDAR", "",
      ],
      "\r\n",
    )
  encoded_lines(input)
  |> starting_with("DTSTART")
  |> should.equal(["DTSTART:20260101T020000Z"])
}
