//// RFC 5545 iCalendar emitter. Renders a validated `Calendar` back
//// to the wire format, applying §3.1 line folding at the 75-octet
//// UTF-8 boundary, §3.3.11 TEXT escaping, and CRLF line endings.

import automata/ical/ast.{type Parameter, type RawComponent, type RawProperty}
import automata/ical/validator as ical_validator
import automata/rrule/ast as rule_ast
import automata/schedule/ast as schedule_ast
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

/// Encode a `Calendar` as an RFC 5545 wire-format string. Each
/// emitted line is at most 75 UTF-8 octets and is terminated by
/// CRLF; lines that would exceed the limit are folded onto a
/// continuation line beginning with a single space.
pub fn encode(cal: ical_validator.Calendar) -> String {
  cal
  |> render_calendar
  |> list.flat_map(fold_line)
  |> list.map(fn(physical) { physical <> "\r\n" })
  |> string.concat
}

// ============================================================
// Calendar
// ============================================================

fn render_calendar(cal: ical_validator.Calendar) -> List(String) {
  let header = [
    "BEGIN:VCALENDAR",
    "VERSION:" <> ical_validator.version(cal),
    "PRODID:" <> escape_text(ical_validator.product_id(cal)),
  ]
  let method_lines = case ical_validator.method(cal) {
    Some(m) -> ["METHOD:" <> escape_text(m)]
    None -> []
  }
  let calscale_lines = case ical_validator.calscale(cal) {
    Some(s) -> ["CALSCALE:" <> escape_text(s)]
    None -> []
  }
  let x_lines = render_x_properties(ical_validator.calendar_x_properties(cal))
  let tz_lines = list.flat_map(ical_validator.timezones(cal), render_timezone)
  let event_lines = list.flat_map(ical_validator.events(cal), render_event)
  let todo_lines = list.flat_map(ical_validator.todos(cal), render_todo)
  let journal_lines =
    list.flat_map(ical_validator.journals(cal), render_journal)
  let freebusy_lines =
    list.flat_map(ical_validator.freebusy(cal), render_freebusy)
  let unknown_lines =
    list.flat_map(
      ical_validator.unknown_components(cal),
      render_unknown_component,
    )

  list.flatten([
    header,
    method_lines,
    calscale_lines,
    x_lines,
    tz_lines,
    event_lines,
    todo_lines,
    journal_lines,
    freebusy_lines,
    unknown_lines,
    ["END:VCALENDAR"],
  ])
}

fn render_x_properties(x_props: dict.Dict(String, String)) -> List(String) {
  x_props
  |> dict.to_list
  |> list.map(fn(pair) {
    let #(name, value) = pair
    name <> ":" <> escape_text(value)
  })
}

// ============================================================
// VEVENT
// ============================================================

fn render_event(event: ical_validator.Event) -> List(String) {
  let header = [
    "BEGIN:VEVENT",
    "UID:" <> ical_validator.event_uid(event),
    "DTSTAMP:" <> render_datetime(ical_validator.event_dtstamp(event)),
  ]
  let dtstart_lines =
    render_dt_with_tzid(
      "DTSTART",
      ical_validator.event_dtstart(event),
      ical_validator.event_dtstart_tzid(event),
    )
  let dtend_lines =
    render_dt_with_tzid(
      "DTEND",
      ical_validator.event_dtend(event),
      ical_validator.event_dtend_tzid(event),
    )
  let duration_lines = case ical_validator.event_duration(event) {
    Some(d) -> ["DURATION:" <> d]
    None -> []
  }
  let summary_lines =
    render_text_opt("SUMMARY", ical_validator.event_summary(event))
  let description_lines =
    render_text_opt("DESCRIPTION", ical_validator.event_description(event))
  let location_lines =
    render_text_opt("LOCATION", ical_validator.event_location(event))
  let status_lines = case ical_validator.event_status(event) {
    Some(v) -> ["STATUS:" <> v]
    None -> []
  }
  let organizer_lines = case ical_validator.event_organizer(event) {
    Some(v) -> ["ORGANIZER:" <> v]
    None -> []
  }
  let attendee_lines =
    list.map(ical_validator.event_attendees(event), fn(a) { "ATTENDEE:" <> a })
  let categories_lines =
    render_categories(ical_validator.event_categories(event))
  let url_lines = case ical_validator.event_url(event) {
    Some(v) -> ["URL:" <> v]
    None -> []
  }
  let created_lines = case ical_validator.event_created(event) {
    Some(dt) -> ["CREATED:" <> render_datetime(dt)]
    None -> []
  }
  let last_mod_lines = case ical_validator.event_last_modified(event) {
    Some(dt) -> ["LAST-MODIFIED:" <> render_datetime(dt)]
    None -> []
  }
  let sequence_lines = case ical_validator.event_sequence(event) {
    0 -> []
    n -> ["SEQUENCE:" <> int.to_string(n)]
  }
  let transp_lines = case ical_validator.event_transparency(event) {
    Some(v) -> ["TRANSP:" <> v]
    None -> []
  }
  let rrule_lines = case ical_validator.event_rrule(event) {
    Some(raw) -> ["RRULE:" <> render_raw_rrule(raw)]
    None -> []
  }
  let rdate_lines = render_dt_list("RDATE", ical_validator.event_rdates(event))
  let exdate_lines =
    render_dt_list("EXDATE", ical_validator.event_exdates(event))
  let alarm_lines =
    list.flat_map(ical_validator.event_alarms(event), render_alarm)
  let x_lines = render_x_properties(ical_validator.event_x_properties(event))

  list.flatten([
    header,
    dtstart_lines,
    dtend_lines,
    duration_lines,
    summary_lines,
    description_lines,
    location_lines,
    status_lines,
    organizer_lines,
    attendee_lines,
    categories_lines,
    url_lines,
    created_lines,
    last_mod_lines,
    sequence_lines,
    transp_lines,
    rrule_lines,
    rdate_lines,
    exdate_lines,
    alarm_lines,
    x_lines,
    ["END:VEVENT"],
  ])
}

// ============================================================
// VTODO
// ============================================================

fn render_todo(t: ical_validator.Todo) -> List(String) {
  let header = [
    "BEGIN:VTODO",
    "UID:" <> ical_validator.todo_uid(t),
    "DTSTAMP:" <> render_datetime(ical_validator.todo_dtstamp(t)),
  ]
  let dtstart_lines = case ical_validator.todo_dtstart(t) {
    Some(dt) -> ["DTSTART:" <> render_datetime(dt)]
    None -> []
  }
  let due_lines = case ical_validator.todo_due(t) {
    Some(dt) -> ["DUE:" <> render_datetime(dt)]
    None -> []
  }
  let completed_lines = case ical_validator.todo_completed(t) {
    Some(dt) -> ["COMPLETED:" <> render_datetime(dt)]
    None -> []
  }
  let summary_lines = render_text_opt("SUMMARY", ical_validator.todo_summary(t))
  let description_lines =
    render_text_opt("DESCRIPTION", ical_validator.todo_description(t))
  let status_lines = case ical_validator.todo_status(t) {
    Some(v) -> ["STATUS:" <> v]
    None -> []
  }
  let percent_lines = case ical_validator.todo_percent_complete(t) {
    Some(n) -> ["PERCENT-COMPLETE:" <> int.to_string(n)]
    None -> []
  }
  let priority_lines = case ical_validator.todo_priority(t) {
    Some(n) -> ["PRIORITY:" <> int.to_string(n)]
    None -> []
  }
  let categories_lines = render_categories(ical_validator.todo_categories(t))
  let rrule_lines = case ical_validator.todo_rrule(t) {
    Some(raw) -> ["RRULE:" <> render_raw_rrule(raw)]
    None -> []
  }
  let rdate_lines = render_dt_list("RDATE", ical_validator.todo_rdates(t))
  let exdate_lines = render_dt_list("EXDATE", ical_validator.todo_exdates(t))
  let alarm_lines = list.flat_map(ical_validator.todo_alarms(t), render_alarm)
  let x_lines = render_x_properties(ical_validator.todo_x_properties(t))

  list.flatten([
    header,
    dtstart_lines,
    due_lines,
    completed_lines,
    summary_lines,
    description_lines,
    status_lines,
    percent_lines,
    priority_lines,
    categories_lines,
    rrule_lines,
    rdate_lines,
    exdate_lines,
    alarm_lines,
    x_lines,
    ["END:VTODO"],
  ])
}

// ============================================================
// VJOURNAL
// ============================================================

fn render_journal(j: ical_validator.Journal) -> List(String) {
  let header = [
    "BEGIN:VJOURNAL",
    "UID:" <> ical_validator.journal_uid(j),
    "DTSTAMP:" <> render_datetime(ical_validator.journal_dtstamp(j)),
  ]
  let dtstart_lines = case ical_validator.journal_dtstart(j) {
    Some(dt) -> ["DTSTART:" <> render_datetime(dt)]
    None -> []
  }
  let summary_lines =
    render_text_opt("SUMMARY", ical_validator.journal_summary(j))
  let description_lines =
    render_text_opt("DESCRIPTION", ical_validator.journal_description(j))
  let status_lines = case ical_validator.journal_status(j) {
    Some(v) -> ["STATUS:" <> v]
    None -> []
  }
  let categories_lines = render_categories(ical_validator.journal_categories(j))
  let x_lines = render_x_properties(ical_validator.journal_x_properties(j))

  list.flatten([
    header,
    dtstart_lines,
    summary_lines,
    description_lines,
    status_lines,
    categories_lines,
    x_lines,
    ["END:VJOURNAL"],
  ])
}

// ============================================================
// VFREEBUSY
// ============================================================

fn render_freebusy(fb: ical_validator.FreeBusy) -> List(String) {
  let header = [
    "BEGIN:VFREEBUSY",
    "UID:" <> ical_validator.freebusy_uid(fb),
    "DTSTAMP:" <> render_datetime(ical_validator.freebusy_dtstamp(fb)),
  ]
  let dtstart_lines = case ical_validator.freebusy_dtstart(fb) {
    Some(dt) -> ["DTSTART:" <> render_datetime(dt)]
    None -> []
  }
  let dtend_lines = case ical_validator.freebusy_dtend(fb) {
    Some(dt) -> ["DTEND:" <> render_datetime(dt)]
    None -> []
  }
  let organizer_lines = case ical_validator.freebusy_organizer(fb) {
    Some(v) -> ["ORGANIZER:" <> v]
    None -> []
  }
  let attendee_lines =
    list.map(ical_validator.freebusy_attendees(fb), fn(a) { "ATTENDEE:" <> a })
  let period_lines =
    list.map(ical_validator.freebusy_periods(fb), fn(p) { "FREEBUSY:" <> p })
  let x_lines = render_x_properties(ical_validator.freebusy_x_properties(fb))

  list.flatten([
    header,
    dtstart_lines,
    dtend_lines,
    organizer_lines,
    attendee_lines,
    period_lines,
    x_lines,
    ["END:VFREEBUSY"],
  ])
}

// ============================================================
// VTIMEZONE
// ============================================================

fn render_timezone(tz: ical_validator.Timezone) -> List(String) {
  let header = ["BEGIN:VTIMEZONE", "TZID:" <> ical_validator.timezone_tzid(tz)]
  let last_mod_lines = case ical_validator.timezone_last_modified(tz) {
    Some(dt) -> ["LAST-MODIFIED:" <> render_datetime(dt)]
    None -> []
  }
  let tzurl_lines = case ical_validator.timezone_tzurl(tz) {
    Some(v) -> ["TZURL:" <> v]
    None -> []
  }
  let standard_lines =
    list.flat_map(ical_validator.timezone_standard(tz), fn(rule) {
      render_timezone_rule("STANDARD", rule)
    })
  let daylight_lines =
    list.flat_map(ical_validator.timezone_daylight(tz), fn(rule) {
      render_timezone_rule("DAYLIGHT", rule)
    })
  let x_lines = render_x_properties(ical_validator.timezone_x_properties(tz))

  list.flatten([
    header,
    last_mod_lines,
    tzurl_lines,
    standard_lines,
    daylight_lines,
    x_lines,
    ["END:VTIMEZONE"],
  ])
}

fn render_timezone_rule(
  kind: String,
  rule: ical_validator.TimezoneRule,
) -> List(String) {
  let ical_validator.TimezoneRule(
    dtstart: dtstart,
    tzoffsetfrom: from,
    tzoffsetto: to,
    rrule: rrule_opt,
    tzname: tzname_opt,
  ) = rule
  let header = [
    "BEGIN:" <> kind,
    "DTSTART:" <> render_datetime(dtstart),
    "TZOFFSETFROM:" <> from,
    "TZOFFSETTO:" <> to,
  ]
  let rrule_lines = case rrule_opt {
    Some(raw) -> ["RRULE:" <> render_raw_rrule(raw)]
    None -> []
  }
  let tzname_lines = case tzname_opt {
    Some(name) -> ["TZNAME:" <> escape_text(name)]
    None -> []
  }
  list.flatten([header, rrule_lines, tzname_lines, ["END:" <> kind]])
}

// ============================================================
// VALARM
// ============================================================

fn render_alarm(alarm: ical_validator.Alarm) -> List(String) {
  let header = [
    "BEGIN:VALARM",
    "ACTION:" <> ical_validator.alarm_action(alarm),
    "TRIGGER:" <> ical_validator.alarm_trigger(alarm),
  ]
  let description_lines =
    render_text_opt("DESCRIPTION", ical_validator.alarm_description(alarm))
  let summary_lines =
    render_text_opt("SUMMARY", ical_validator.alarm_summary(alarm))
  let repeat_lines = case ical_validator.alarm_repeat(alarm) {
    Some(n) -> ["REPEAT:" <> int.to_string(n)]
    None -> []
  }
  let duration_lines = case ical_validator.alarm_duration(alarm) {
    Some(v) -> ["DURATION:" <> v]
    None -> []
  }
  let attendee_lines =
    list.map(ical_validator.alarm_attendees(alarm), fn(a) { "ATTENDEE:" <> a })
  let x_lines = render_x_properties(ical_validator.alarm_x_properties(alarm))

  list.flatten([
    header,
    description_lines,
    summary_lines,
    repeat_lines,
    duration_lines,
    attendee_lines,
    x_lines,
    ["END:VALARM"],
  ])
}

// ============================================================
// Unknown components (raw passthrough)
// ============================================================

fn render_unknown_component(uc: ical_validator.UnknownComponent) -> List(String) {
  let ical_validator.UnknownComponent(
    kind: kind,
    properties: props,
    children: children,
  ) = uc
  let prop_lines = list.map(props, render_raw_property)
  let child_lines = list.flat_map(children, render_raw_component)
  list.flatten([["BEGIN:" <> kind], prop_lines, child_lines, ["END:" <> kind]])
}

fn render_raw_component(comp: RawComponent) -> List(String) {
  let ast.RawComponent(kind: kind, properties: props, children: children, ..) =
    comp
  let prop_lines = list.map(props, render_raw_property)
  let child_lines = list.flat_map(children, render_raw_component)
  list.flatten([["BEGIN:" <> kind], prop_lines, child_lines, ["END:" <> kind]])
}

fn render_raw_property(prop: RawProperty) -> String {
  let ast.RawProperty(name: name, parameters: params, raw_value: value, ..) =
    prop
  let param_part = case params {
    [] -> ""
    _ ->
      ";"
      <> {
        params
        |> list.map(render_parameter)
        |> string.join(";")
      }
  }
  name <> param_part <> ":" <> value
}

fn render_parameter(p: Parameter) -> String {
  let ast.Parameter(name: name, value: value) = p
  name <> "=" <> quote_param_if_needed(value)
}

fn quote_param_if_needed(value: String) -> String {
  case
    string.contains(value, ":")
    || string.contains(value, ";")
    || string.contains(value, ",")
  {
    True -> "\"" <> value <> "\""
    False -> value
  }
}

// ============================================================
// Property value helpers
// ============================================================

fn render_text_opt(name: String, value: Option(String)) -> List(String) {
  case value {
    Some(v) -> [name <> ":" <> escape_text(v)]
    None -> []
  }
}

fn render_dt_with_tzid(
  name: String,
  dt_opt: Option(schedule_ast.DateTime),
  tzid_opt: Option(String),
) -> List(String) {
  case dt_opt {
    None -> []
    Some(dt) ->
      case tzid_opt {
        Some(tzid) -> [name <> ";TZID=" <> tzid <> ":" <> render_datetime(dt)]
        None -> [name <> ":" <> render_datetime(dt)]
      }
  }
}

fn render_dt_list(
  name: String,
  values: List(schedule_ast.DateTime),
) -> List(String) {
  case values {
    [] -> []
    _ -> {
      let joined =
        values
        |> list.map(render_datetime)
        |> string.join(",")
      [name <> ":" <> joined]
    }
  }
}

fn render_categories(categories: List(String)) -> List(String) {
  case categories {
    [] -> []
    _ -> {
      let joined =
        categories
        |> list.map(escape_text)
        |> string.join(",")
      ["CATEGORIES:" <> joined]
    }
  }
}

// ============================================================
// RRULE serialisation
// ============================================================

fn render_raw_rrule(raw: rule_ast.RawRRule) -> String {
  let rule_ast.RawRRule(parts: parts) = raw
  parts
  |> list.map(fn(p) {
    let rule_ast.RawRulePart(name: name, value: value) = p
    name <> "=" <> value
  })
  |> string.join(";")
}

// ============================================================
// DateTime rendering
// ============================================================

/// Render a `DateTime` as the RFC 5545 form: `YYYYMMDDTHHMMSS` (15
/// characters). Trailing `Z` for UTC isn't appended here — the
/// caller carries that information out-of-band via `dtstart_tzid` or
/// by writing the property without a `TZID` parameter.
fn render_datetime(dt: schedule_ast.DateTime) -> String {
  let schedule_ast.DateTime(date: date, time: time) = dt
  let schedule_ast.Date(year: y, month: mo, day: d) = date
  let schedule_ast.Time(hour: h, minute: mi, second: s) = time
  pad4(y) <> pad2(mo) <> pad2(d) <> "T" <> pad2(h) <> pad2(mi) <> pad2(s)
}

fn pad2(n: Int) -> String {
  case n < 10 {
    True -> "0" <> int.to_string(n)
    False -> int.to_string(n)
  }
}

fn pad4(n: Int) -> String {
  case n {
    _ if n < 10 -> "000" <> int.to_string(n)
    _ if n < 100 -> "00" <> int.to_string(n)
    _ if n < 1000 -> "0" <> int.to_string(n)
    _ -> int.to_string(n)
  }
}

// ============================================================
// Text escape
// ============================================================

/// Escape a TEXT property value per RFC 5545 §3.3.11.
pub fn escape_text(s: String) -> String {
  s
  |> string.replace("\\", "\\\\")
  |> string.replace("\n", "\\n")
  |> string.replace(",", "\\,")
  |> string.replace(";", "\\;")
}

// ============================================================
// Line folding (RFC 5545 §3.1)
// ============================================================

/// Fold a single logical line into one or more physical lines, each
/// at most 75 UTF-8 octets, with continuation lines prefixed by a
/// single space. The returned list never contains CRLF — callers
/// glue lines together themselves.
pub fn fold_line(line: String) -> List(String) {
  let codepoints = string.to_utf_codepoints(line)
  fold_loop(codepoints, [], 0, [], False)
}

fn fold_loop(
  codepoints: List(UtfCodepoint),
  current: List(UtfCodepoint),
  current_bytes: Int,
  acc: List(String),
  is_continuation: Bool,
) -> List(String) {
  case codepoints {
    [] -> {
      let final_line = build_line(current, is_continuation)
      list.reverse([final_line, ..acc])
    }
    [cp, ..rest] -> {
      let cp_bytes = utf8_byte_length(cp)
      let limit = case is_continuation {
        True -> 74
        False -> 75
      }
      case current_bytes + cp_bytes > limit {
        True -> {
          let finished = build_line(current, is_continuation)
          fold_loop(rest, [cp], cp_bytes, [finished, ..acc], True)
        }
        False ->
          fold_loop(
            rest,
            [cp, ..current],
            current_bytes + cp_bytes,
            acc,
            is_continuation,
          )
      }
    }
  }
}

fn build_line(current: List(UtfCodepoint), is_continuation: Bool) -> String {
  let body = string.from_utf_codepoints(list.reverse(current))
  case is_continuation {
    True -> " " <> body
    False -> body
  }
}

fn utf8_byte_length(cp: UtfCodepoint) -> Int {
  let n = string.utf_codepoint_to_int(cp)
  case n {
    _ if n < 0x80 -> 1
    _ if n < 0x800 -> 2
    _ if n < 0x10000 -> 3
    _ -> 4
  }
}
