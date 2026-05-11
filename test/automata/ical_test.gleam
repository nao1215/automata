import automata/ical
import automata/ical/emitter
import automata/ical/parser as ical_parser
import automata/ical/validator as ical_validator
import automata/rrule
import automata/schedule/ast as schedule_ast
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should

// ============================================================
// Fixtures
// ============================================================

const minimal_ics = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//EN\r\nBEGIN:VEVENT\r\nUID:abc@test\r\nDTSTAMP:20260511T000000Z\r\nDTSTART:20260511T130000\r\nSUMMARY:Coffee\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

const recurrence_ics = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//recurrence//EN\r\nBEGIN:VEVENT\r\nUID:rec@test\r\nDTSTAMP:20260101T000000Z\r\nDTSTART:20260105T090000\r\nSUMMARY:Standup\r\nRRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR;COUNT=10\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

const alarm_ics = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//alarm//EN\r\nBEGIN:VEVENT\r\nUID:alm@test\r\nDTSTAMP:20260301T000000Z\r\nDTSTART:20260301T140000\r\nSUMMARY:Dentist\r\nBEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT15M\r\nDESCRIPTION:Reminder\r\nEND:VALARM\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

const todo_ics = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//test//todo//EN\r\nBEGIN:VTODO\r\nUID:todo1@test\r\nDTSTAMP:20260401T000000Z\r\nDUE:20260415T170000\r\nSUMMARY:File taxes\r\nSTATUS:NEEDS-ACTION\r\nPRIORITY:1\r\nPERCENT-COMPLETE:25\r\nEND:VTODO\r\nEND:VCALENDAR\r\n"

const apple_export_ics = "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Apple Inc.//macOS 14.0//EN\nCALSCALE:GREGORIAN\nBEGIN:VEVENT\nUID:apple-event-1@icloud\nDTSTAMP:20260201T120000Z\nDTSTART:20260210T090000\nDTEND:20260210T100000\nSUMMARY:Team sync\nX-APPLE-CALENDAR-COLOR:#FF2968\nEND:VEVENT\nEND:VCALENDAR\n"

const google_export_ics = "BEGIN:VCALENDAR\r\nPRODID:-//Google Inc//Google Calendar 70.9054//EN\r\nVERSION:2.0\r\nCALSCALE:GREGORIAN\r\nMETHOD:PUBLISH\r\nBEGIN:VTIMEZONE\r\nTZID:Asia/Tokyo\r\nBEGIN:STANDARD\r\nDTSTART:19700101T000000\r\nTZOFFSETFROM:+0900\r\nTZOFFSETTO:+0900\r\nTZNAME:JST\r\nEND:STANDARD\r\nEND:VTIMEZONE\r\nBEGIN:VEVENT\r\nDTSTART;TZID=Asia/Tokyo:20260620T100000\r\nDTEND;TZID=Asia/Tokyo:20260620T110000\r\nRRULE:FREQ=WEEKLY;BYDAY=MO\r\nDTSTAMP:20260601T000000Z\r\nUID:google-event-1@google.com\r\nATTENDEE:mailto:alice@example.com\r\nSUMMARY:Weekly review\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

const outlook_export_ics = "BEGIN:VCALENDAR\r\nMETHOD:PUBLISH\r\nPRODID:Microsoft Exchange Server 2010\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:outlook-event-1@outlook\r\nDTSTAMP:20260315T080000Z\r\nDTSTART:20260320T130000Z\r\nDTEND:20260320T140000Z\r\nSUMMARY:Quarterly planning\r\nORGANIZER:mailto:boss@example.com\r\nSEQUENCE:2\r\nTRANSP:OPAQUE\r\nSTATUS:CONFIRMED\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

const nextcloud_export_ics = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//IDN nextcloud.com//Calendar app 4.0.0//EN\r\nBEGIN:VEVENT\r\nCREATED:20260101T100000Z\r\nDTSTAMP:20260105T120000Z\r\nLAST-MODIFIED:20260105T120000Z\r\nUID:nextcloud-event-1@nextcloud\r\nSUMMARY:Lunch with team\r\nDTSTART:20260110T120000\r\nDTEND:20260110T130000\r\nLOCATION:Cafeteria\r\nDESCRIPTION:Monthly catch-up\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"

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
