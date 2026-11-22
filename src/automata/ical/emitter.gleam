//// RFC 5545 iCalendar emitter. Renders a validated `Calendar` back
//// to the wire format, applying §3.1 line folding at the 75-octet
//// UTF-8 boundary, §3.3.11 TEXT escaping, and CRLF line endings.

import automata/ical/ast.{type Parameter, type RawComponent, type RawProperty}
import automata/ical/validator as ical_validator
import automata/internal/digits
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
  let forms = ical_validator.event_forms(event)
  let header = [
    "BEGIN:VEVENT",
    "UID:" <> ical_validator.event_uid(event),
    "DTSTAMP:" <> render_datetime_utc(ical_validator.event_dtstamp(event)),
  ]
  let dtstart_lines =
    render_dt_opt(
      forms,
      "DTSTART",
      ical_validator.event_dtstart(event),
      ical_validator.event_dtstart_tzid(event),
    )
  let dtend_lines =
    render_dt_opt(
      forms,
      "DTEND",
      ical_validator.event_dtend(event),
      ical_validator.event_dtend_tzid(event),
    )
  let duration_lines =
    render_opt(forms, "DURATION", ical_validator.event_duration(event))
  let summary_lines =
    render_text_opt(forms, "SUMMARY", ical_validator.event_summary(event))
  let description_lines =
    render_text_opt(
      forms,
      "DESCRIPTION",
      ical_validator.event_description(event),
    )
  let location_lines =
    render_text_opt(forms, "LOCATION", ical_validator.event_location(event))
  let status_lines =
    render_opt(forms, "STATUS", ical_validator.event_status(event))
  let organizer_lines =
    render_opt(forms, "ORGANIZER", ical_validator.event_organizer(event))
  let attendee_lines =
    render_lines(forms, "ATTENDEE", ical_validator.event_attendees(event))
  let categories_lines =
    render_categories(forms, ical_validator.event_categories(event))
  let url_lines = render_opt(forms, "URL", ical_validator.event_url(event))
  let created_lines = case ical_validator.event_created(event) {
    Some(dt) -> ["CREATED:" <> render_datetime_utc(dt)]
    None -> []
  }
  let last_mod_lines = case ical_validator.event_last_modified(event) {
    Some(dt) -> ["LAST-MODIFIED:" <> render_datetime_utc(dt)]
    None -> []
  }
  let sequence_lines = case ical_validator.event_sequence(event) {
    0 -> []
    n -> ["SEQUENCE:" <> int.to_string(n)]
  }
  let transp_lines =
    render_opt(forms, "TRANSP", ical_validator.event_transparency(event))
  let rrule_lines = case ical_validator.event_rrule(event) {
    Some(raw) -> ["RRULE:" <> render_raw_rrule(raw)]
    None -> []
  }
  let rdate_lines =
    render_dt_list(forms, "RDATE", ical_validator.event_rdates(event))
  let exdate_lines =
    render_dt_list(forms, "EXDATE", ical_validator.event_exdates(event))
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
  let forms = ical_validator.todo_forms(t)
  let header = [
    "BEGIN:VTODO",
    "UID:" <> ical_validator.todo_uid(t),
    "DTSTAMP:" <> render_datetime_utc(ical_validator.todo_dtstamp(t)),
  ]
  let dtstart_lines =
    render_dt_opt(forms, "DTSTART", ical_validator.todo_dtstart(t), None)
  let due_lines = render_dt_opt(forms, "DUE", ical_validator.todo_due(t), None)
  let completed_lines = case ical_validator.todo_completed(t) {
    Some(dt) -> ["COMPLETED:" <> render_datetime_utc(dt)]
    None -> []
  }
  let summary_lines =
    render_text_opt(forms, "SUMMARY", ical_validator.todo_summary(t))
  let description_lines =
    render_text_opt(forms, "DESCRIPTION", ical_validator.todo_description(t))
  let status_lines = render_opt(forms, "STATUS", ical_validator.todo_status(t))
  let percent_lines = case ical_validator.todo_percent_complete(t) {
    Some(n) -> ["PERCENT-COMPLETE:" <> int.to_string(n)]
    None -> []
  }
  let priority_lines = case ical_validator.todo_priority(t) {
    Some(n) -> ["PRIORITY:" <> int.to_string(n)]
    None -> []
  }
  let categories_lines =
    render_categories(forms, ical_validator.todo_categories(t))
  let rrule_lines = case ical_validator.todo_rrule(t) {
    Some(raw) -> ["RRULE:" <> render_raw_rrule(raw)]
    None -> []
  }
  let rdate_lines =
    render_dt_list(forms, "RDATE", ical_validator.todo_rdates(t))
  let exdate_lines =
    render_dt_list(forms, "EXDATE", ical_validator.todo_exdates(t))
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
  let forms = ical_validator.journal_forms(j)
  let header = [
    "BEGIN:VJOURNAL",
    "UID:" <> ical_validator.journal_uid(j),
    "DTSTAMP:" <> render_datetime_utc(ical_validator.journal_dtstamp(j)),
  ]
  let dtstart_lines =
    render_dt_opt(forms, "DTSTART", ical_validator.journal_dtstart(j), None)
  let summary_lines =
    render_text_opt(forms, "SUMMARY", ical_validator.journal_summary(j))
  let description_lines =
    render_text_opt(forms, "DESCRIPTION", ical_validator.journal_description(j))
  let status_lines =
    render_opt(forms, "STATUS", ical_validator.journal_status(j))
  let categories_lines =
    render_categories(forms, ical_validator.journal_categories(j))
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
  let forms = ical_validator.freebusy_forms(fb)
  let header = [
    "BEGIN:VFREEBUSY",
    "UID:" <> ical_validator.freebusy_uid(fb),
    "DTSTAMP:" <> render_datetime_utc(ical_validator.freebusy_dtstamp(fb)),
  ]
  let dtstart_lines =
    render_dt_opt(forms, "DTSTART", ical_validator.freebusy_dtstart(fb), None)
  let dtend_lines =
    render_dt_opt(forms, "DTEND", ical_validator.freebusy_dtend(fb), None)
  let organizer_lines =
    render_opt(forms, "ORGANIZER", ical_validator.freebusy_organizer(fb))
  let attendee_lines =
    render_lines(forms, "ATTENDEE", ical_validator.freebusy_attendees(fb))
  let period_lines =
    render_lines(forms, "FREEBUSY", ical_validator.freebusy_periods(fb))
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
    Some(dt) -> ["LAST-MODIFIED:" <> render_datetime_utc(dt)]
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
  let forms = ical_validator.alarm_forms(alarm)
  let header = [
    "BEGIN:VALARM",
    property(forms, "ACTION", ical_validator.alarm_action(alarm)),
    property(forms, "TRIGGER", ical_validator.alarm_trigger(alarm)),
  ]
  let description_lines =
    render_text_opt(
      forms,
      "DESCRIPTION",
      ical_validator.alarm_description(alarm),
    )
  let summary_lines =
    render_text_opt(forms, "SUMMARY", ical_validator.alarm_summary(alarm))
  let repeat_lines = case ical_validator.alarm_repeat(alarm) {
    Some(n) -> ["REPEAT:" <> int.to_string(n)]
    None -> []
  }
  let duration_lines =
    render_opt(forms, "DURATION", ical_validator.alarm_duration(alarm))
  let attendee_lines =
    render_lines(forms, "ATTENDEE", ical_validator.alarm_attendees(alarm))
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

fn render_unknown_component(
  uc: ical_validator.UnknownComponent,
) -> List(String) {
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

type Forms =
  dict.Dict(String, List(ical_validator.PropertyForm))

fn forms_for(forms: Forms, name: String) -> List(ical_validator.PropertyForm) {
  case dict.get(forms, name) {
    Ok(list) -> list
    Error(_) -> []
  }
}

fn form_of(forms: Forms, name: String) -> ical_validator.PropertyForm {
  case forms_for(forms, name) {
    [form, ..] -> form
    [] -> default_form()
  }
}

fn default_form() -> ical_validator.PropertyForm {
  ical_validator.PropertyForm(parameters: [], utc: True, date_only: False)
}

/// `NAME;PARAM=...:value`, with the parameters the property was parsed
/// with.
fn property(forms: Forms, name: String, value: String) -> String {
  name <> render_parameters(form_of(forms, name).parameters) <> ":" <> value
}

fn render_parameters(params: List(Parameter)) -> String {
  params
  |> list.map(fn(p) { ";" <> render_parameter(p) })
  |> string.concat
}

fn render_opt(
  forms: Forms,
  name: String,
  value: Option(String),
) -> List(String) {
  case value {
    Some(v) -> [property(forms, name, v)]
    None -> []
  }
}

fn render_text_opt(
  forms: Forms,
  name: String,
  value: Option(String),
) -> List(String) {
  render_opt(forms, name, option.map(value, escape_text))
}

fn render_dt_opt(
  forms: Forms,
  name: String,
  dt_opt: Option(schedule_ast.DateTime),
  tzid_opt: Option(String),
) -> List(String) {
  case dt_opt {
    None -> []
    Some(dt) -> [render_dt_values(form_of(forms, name), name, [dt], tzid_opt)]
  }
}

/// One line per run of consecutive values that share a form, so each
/// parsed line comes back with its own parameters.
fn render_dt_list(
  forms: Forms,
  name: String,
  values: List(schedule_ast.DateTime),
) -> List(String) {
  pair_forms(values, forms_for(forms, name), [])
  |> group_by_form([])
  |> list.map(fn(group) {
    let #(form, dts) = group
    render_dt_values(form, name, dts, None)
  })
}

fn pair_forms(
  values: List(a),
  forms: List(ical_validator.PropertyForm),
  acc: List(#(ical_validator.PropertyForm, a)),
) -> List(#(ical_validator.PropertyForm, a)) {
  case values, forms {
    [], _ -> list.reverse(acc)
    [value, ..rest], [form, ..forms] ->
      pair_forms(rest, forms, [#(form, value), ..acc])
    [value, ..rest], [] ->
      pair_forms(rest, [], [#(default_form(), value), ..acc])
  }
}

fn group_by_form(
  pairs: List(#(ical_validator.PropertyForm, a)),
  acc: List(#(ical_validator.PropertyForm, List(a))),
) -> List(#(ical_validator.PropertyForm, List(a))) {
  case pairs, acc {
    [], _ ->
      list.reverse(
        list.map(acc, fn(group) { #(group.0, list.reverse(group.1)) }),
      )
    [#(form, value), ..rest], [#(current, values), ..done] if form == current ->
      group_by_form(rest, [#(current, [value, ..values]), ..done])
    [#(form, value), ..rest], _ ->
      group_by_form(rest, [#(form, [value]), ..acc])
  }
}

/// Write date values in the form they were parsed in: `VALUE=DATE` or
/// a value without a time part as a DATE, a `TZID` or a value without
/// `Z` as local time, anything else as UTC. A `tzid` from the model
/// replaces the parsed `TZID`.
fn render_dt_values(
  form: ical_validator.PropertyForm,
  name: String,
  values: List(schedule_ast.DateTime),
  tzid_opt: Option(String),
) -> String {
  let params = case tzid_opt {
    None -> form.parameters
    Some(tzid) -> [
      ast.Parameter(name: "TZID", value: tzid),
      ..list.filter(form.parameters, fn(p) { !parameter_is(p, "TZID") })
    ]
  }
  let is_date =
    form.date_only
    || list.any(params, fn(p) {
      parameter_is(p, "VALUE") && string.uppercase(p.value) == "DATE"
    })
  let is_local = !form.utc || list.any(params, parameter_is(_, "TZID"))
  let render = case is_date, is_local {
    True, _ -> render_date
    False, True -> render_datetime
    False, False -> render_datetime_utc
  }
  name
  <> render_parameters(params)
  <> ":"
  <> string.join(list.map(values, render), ",")
}

fn parameter_is(p: Parameter, name: String) -> Bool {
  string.uppercase(p.name) == name
}

fn render_lines(
  forms: Forms,
  name: String,
  values: List(String),
) -> List(String) {
  pair_forms(values, forms_for(forms, name), [])
  |> list.map(fn(pair) {
    name <> render_parameters(pair.0.parameters) <> ":" <> pair.1
  })
}

fn render_categories(forms: Forms, categories: List(String)) -> List(String) {
  pair_forms(categories, forms_for(forms, "CATEGORIES"), [])
  |> group_by_form([])
  |> list.map(fn(group) {
    "CATEGORIES"
    <> render_parameters(group.0.parameters)
    <> ":"
    <> string.join(list.map(group.1, escape_text), ",")
  })
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

/// Render a `DateTime` as the RFC 5545 floating / TZID-anchored form:
/// `YYYYMMDDTHHMMSS` (15 characters), no trailing `Z`. Use this only
/// for properties that carry a `TZID` parameter or that are emitted
/// inside `VTIMEZONE` (where DTSTART is local-clock by spec). All other
/// DATE-TIME emissions should go through [`render_datetime_utc`](#render_datetime_utc).
fn render_date(dt: schedule_ast.DateTime) -> String {
  let schedule_ast.Date(year: y, month: mo, day: d) = dt.date
  digits.pad4(y) <> digits.pad2(mo) <> digits.pad2(d)
}

fn render_datetime(dt: schedule_ast.DateTime) -> String {
  let schedule_ast.DateTime(date: date, time: time) = dt
  let schedule_ast.Date(year: y, month: mo, day: d) = date
  let schedule_ast.Time(hour: h, minute: mi, second: s) = time
  digits.pad4(y)
  <> digits.pad2(mo)
  <> digits.pad2(d)
  <> "T"
  <> digits.pad2(h)
  <> digits.pad2(mi)
  <> digits.pad2(s)
}

/// Render a `DateTime` as the RFC 5545 UTC form (`FORM #2`): `YYYYMMDDTHHMMSSZ`
/// (16 characters). Required for properties that the RFC mandates as UTC
/// (DTSTAMP, CREATED, LAST-MODIFIED, COMPLETED) and used as the default for
/// DATE-TIME properties emitted without a `TZID` parameter (round-trip
/// preserves the UTC marker that the parser strips).
fn render_datetime_utc(dt: schedule_ast.DateTime) -> String {
  render_datetime(dt) <> "Z"
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
