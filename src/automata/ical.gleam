//// RFC 5545 iCalendar parser and emitter built on top of
//// `automata/rrule`. Handles the `VCALENDAR` envelope —
//// `VEVENT` / `VTODO` / `VJOURNAL` / `VFREEBUSY` / `VTIMEZONE` /
//// `VALARM` blocks, §3.1 line folding (CRLF/LF tolerant input,
//// CRLF output, 75-octet UTF-8 boundary on emit), §3.2 quoted
//// parameter values, §3.3.11 TEXT escaping
//// (`\\`, `\,`, `\;`, `\n`/`\N`), and §3.4 content-line layout.
////
//// RRULE values are preserved as `automata/rrule.RawRRule` so
//// callers can pipe them through `rrule.validate` — `InvalidRRule`
//// wraps the syntactic `rrule/parser.ParseError`. Unknown
//// component kinds round-trip through `UnknownComponent` rather
//// than being dropped.

import automata/ical/emitter
import automata/ical/parser as ical_parser
import automata/ical/validator as ical_validator
import automata/rrule/ast as rule_ast
import automata/rrule/parser as rrule_parser
import automata/schedule/ast as schedule_ast
import gleam/dict.{type Dict}
import gleam/option.{type Option}

// ============================================================
// Type re-exports
// ============================================================

pub type Calendar =
  ical_validator.Calendar

pub type Event =
  ical_validator.Event

pub type Todo =
  ical_validator.Todo

pub type Journal =
  ical_validator.Journal

pub type FreeBusy =
  ical_validator.FreeBusy

pub type Timezone =
  ical_validator.Timezone

pub type TimezoneRule =
  ical_validator.TimezoneRule

pub type Alarm =
  ical_validator.Alarm

pub type UnknownComponent =
  ical_validator.UnknownComponent

// ============================================================
// Unified error type
// ============================================================

pub type IcalError {
  UnexpectedEnd(line: Int)
  MismatchedBlock(begin: String, end: String, line: Int)
  MalformedProperty(line: Int, raw: String)
  MalformedParameter(line: Int, raw: String)
  MissingVersion
  MissingProductId
  MissingComponentProperty(component: String, name: String)
  InvalidDateTime(name: String, raw: String)
  InvalidEscape(raw: String)
  InvalidInteger(name: String, raw: String)
  InvalidRRule(raw: String, error: rrule_parser.ParseError)
  DuplicateRRule(component_uid: String)
  EmptyInputError
}

// ============================================================
// Public API
// ============================================================

/// Parse an iCalendar document into a validated `Calendar`. Errors
/// from the lexer, parser, and validator are mapped into the unified
/// `IcalError` type so callers only need one pattern-match.
pub fn parse(input: String) -> Result(Calendar, IcalError) {
  case ical_parser.parse(input) {
    Error(e) -> Error(map_parse_error(e))
    Ok(raw) ->
      case ical_validator.validate(raw) {
        Error(e) -> Error(map_validation_error(e))
        Ok(cal) -> Ok(cal)
      }
  }
}

/// Render a `Calendar` back to the RFC 5545 wire format. Output
/// uses CRLF line terminators and folds at 75 UTF-8 octets.
pub fn encode(cal: Calendar) -> String {
  emitter.encode(cal)
}

fn map_parse_error(e: ical_parser.ParseError) -> IcalError {
  case e {
    ical_parser.UnexpectedEnd(line) -> UnexpectedEnd(line)
    ical_parser.MismatchedBlock(begin, end, line) ->
      MismatchedBlock(begin, end, line)
    ical_parser.MalformedProperty(line, raw) -> MalformedProperty(line, raw)
    ical_parser.MalformedParameter(line, raw) -> MalformedParameter(line, raw)
    ical_parser.EmptyInputError -> EmptyInputError
  }
}

fn map_validation_error(e: ical_validator.ValidationError) -> IcalError {
  case e {
    ical_validator.MissingVersion -> MissingVersion
    ical_validator.MissingProductId -> MissingProductId
    ical_validator.MissingComponentProperty(comp, name) ->
      MissingComponentProperty(comp, name)
    ical_validator.InvalidDateTime(name, raw) -> InvalidDateTime(name, raw)
    ical_validator.InvalidEscape(raw) -> InvalidEscape(raw)
    ical_validator.InvalidInteger(name, raw) -> InvalidInteger(name, raw)
    ical_validator.InvalidRRule(raw, err) -> InvalidRRule(raw, err)
    ical_validator.DuplicateRRule(uid) -> DuplicateRRule(uid)
  }
}

// ============================================================
// Calendar accessors
// ============================================================

pub fn version(cal: Calendar) -> String {
  ical_validator.version(cal)
}

pub fn product_id(cal: Calendar) -> String {
  ical_validator.product_id(cal)
}

pub fn method(cal: Calendar) -> Option(String) {
  ical_validator.method(cal)
}

pub fn calscale(cal: Calendar) -> Option(String) {
  ical_validator.calscale(cal)
}

pub fn events(cal: Calendar) -> List(Event) {
  ical_validator.events(cal)
}

pub fn todos(cal: Calendar) -> List(Todo) {
  ical_validator.todos(cal)
}

pub fn journals(cal: Calendar) -> List(Journal) {
  ical_validator.journals(cal)
}

pub fn freebusy(cal: Calendar) -> List(FreeBusy) {
  ical_validator.freebusy(cal)
}

pub fn timezones(cal: Calendar) -> List(Timezone) {
  ical_validator.timezones(cal)
}

pub fn unknown_components(cal: Calendar) -> List(UnknownComponent) {
  ical_validator.unknown_components(cal)
}

pub fn calendar_x_properties(cal: Calendar) -> Dict(String, String) {
  ical_validator.calendar_x_properties(cal)
}

// ============================================================
// Event accessors
// ============================================================

pub fn event_uid(event: Event) -> String {
  ical_validator.event_uid(event)
}

pub fn event_dtstamp(event: Event) -> schedule_ast.DateTime {
  ical_validator.event_dtstamp(event)
}

pub fn event_dtstart(event: Event) -> Option(schedule_ast.DateTime) {
  ical_validator.event_dtstart(event)
}

pub fn event_dtstart_tzid(event: Event) -> Option(String) {
  ical_validator.event_dtstart_tzid(event)
}

pub fn event_dtend(event: Event) -> Option(schedule_ast.DateTime) {
  ical_validator.event_dtend(event)
}

pub fn event_dtend_tzid(event: Event) -> Option(String) {
  ical_validator.event_dtend_tzid(event)
}

pub fn event_duration(event: Event) -> Option(String) {
  ical_validator.event_duration(event)
}

pub fn event_summary(event: Event) -> Option(String) {
  ical_validator.event_summary(event)
}

pub fn event_description(event: Event) -> Option(String) {
  ical_validator.event_description(event)
}

pub fn event_location(event: Event) -> Option(String) {
  ical_validator.event_location(event)
}

pub fn event_status(event: Event) -> Option(String) {
  ical_validator.event_status(event)
}

pub fn event_organizer(event: Event) -> Option(String) {
  ical_validator.event_organizer(event)
}

pub fn event_attendees(event: Event) -> List(String) {
  ical_validator.event_attendees(event)
}

pub fn event_categories(event: Event) -> List(String) {
  ical_validator.event_categories(event)
}

pub fn event_url(event: Event) -> Option(String) {
  ical_validator.event_url(event)
}

pub fn event_created(event: Event) -> Option(schedule_ast.DateTime) {
  ical_validator.event_created(event)
}

pub fn event_last_modified(event: Event) -> Option(schedule_ast.DateTime) {
  ical_validator.event_last_modified(event)
}

pub fn event_sequence(event: Event) -> Int {
  ical_validator.event_sequence(event)
}

pub fn event_transparency(event: Event) -> Option(String) {
  ical_validator.event_transparency(event)
}

pub fn event_rrule(event: Event) -> Option(rule_ast.RawRRule) {
  ical_validator.event_rrule(event)
}

pub fn event_rdates(event: Event) -> List(schedule_ast.DateTime) {
  ical_validator.event_rdates(event)
}

pub fn event_exdates(event: Event) -> List(schedule_ast.DateTime) {
  ical_validator.event_exdates(event)
}

pub fn event_alarms(event: Event) -> List(Alarm) {
  ical_validator.event_alarms(event)
}

pub fn event_x_properties(event: Event) -> Dict(String, String) {
  ical_validator.event_x_properties(event)
}

// ============================================================
// Todo accessors
// ============================================================

pub fn todo_uid(t: Todo) -> String {
  ical_validator.todo_uid(t)
}

pub fn todo_dtstamp(t: Todo) -> schedule_ast.DateTime {
  ical_validator.todo_dtstamp(t)
}

pub fn todo_dtstart(t: Todo) -> Option(schedule_ast.DateTime) {
  ical_validator.todo_dtstart(t)
}

pub fn todo_due(t: Todo) -> Option(schedule_ast.DateTime) {
  ical_validator.todo_due(t)
}

pub fn todo_completed(t: Todo) -> Option(schedule_ast.DateTime) {
  ical_validator.todo_completed(t)
}

pub fn todo_summary(t: Todo) -> Option(String) {
  ical_validator.todo_summary(t)
}

pub fn todo_description(t: Todo) -> Option(String) {
  ical_validator.todo_description(t)
}

pub fn todo_status(t: Todo) -> Option(String) {
  ical_validator.todo_status(t)
}

pub fn todo_percent_complete(t: Todo) -> Option(Int) {
  ical_validator.todo_percent_complete(t)
}

pub fn todo_priority(t: Todo) -> Option(Int) {
  ical_validator.todo_priority(t)
}

pub fn todo_categories(t: Todo) -> List(String) {
  ical_validator.todo_categories(t)
}

pub fn todo_rrule(t: Todo) -> Option(rule_ast.RawRRule) {
  ical_validator.todo_rrule(t)
}

pub fn todo_rdates(t: Todo) -> List(schedule_ast.DateTime) {
  ical_validator.todo_rdates(t)
}

pub fn todo_exdates(t: Todo) -> List(schedule_ast.DateTime) {
  ical_validator.todo_exdates(t)
}

pub fn todo_alarms(t: Todo) -> List(Alarm) {
  ical_validator.todo_alarms(t)
}

pub fn todo_x_properties(t: Todo) -> Dict(String, String) {
  ical_validator.todo_x_properties(t)
}

// ============================================================
// Journal accessors
// ============================================================

pub fn journal_uid(j: Journal) -> String {
  ical_validator.journal_uid(j)
}

pub fn journal_dtstamp(j: Journal) -> schedule_ast.DateTime {
  ical_validator.journal_dtstamp(j)
}

pub fn journal_dtstart(j: Journal) -> Option(schedule_ast.DateTime) {
  ical_validator.journal_dtstart(j)
}

pub fn journal_summary(j: Journal) -> Option(String) {
  ical_validator.journal_summary(j)
}

pub fn journal_description(j: Journal) -> Option(String) {
  ical_validator.journal_description(j)
}

pub fn journal_status(j: Journal) -> Option(String) {
  ical_validator.journal_status(j)
}

pub fn journal_categories(j: Journal) -> List(String) {
  ical_validator.journal_categories(j)
}

pub fn journal_x_properties(j: Journal) -> Dict(String, String) {
  ical_validator.journal_x_properties(j)
}

// ============================================================
// FreeBusy accessors
// ============================================================

pub fn freebusy_uid(fb: FreeBusy) -> String {
  ical_validator.freebusy_uid(fb)
}

pub fn freebusy_dtstamp(fb: FreeBusy) -> schedule_ast.DateTime {
  ical_validator.freebusy_dtstamp(fb)
}

pub fn freebusy_dtstart(fb: FreeBusy) -> Option(schedule_ast.DateTime) {
  ical_validator.freebusy_dtstart(fb)
}

pub fn freebusy_dtend(fb: FreeBusy) -> Option(schedule_ast.DateTime) {
  ical_validator.freebusy_dtend(fb)
}

pub fn freebusy_organizer(fb: FreeBusy) -> Option(String) {
  ical_validator.freebusy_organizer(fb)
}

pub fn freebusy_attendees(fb: FreeBusy) -> List(String) {
  ical_validator.freebusy_attendees(fb)
}

pub fn freebusy_periods(fb: FreeBusy) -> List(String) {
  ical_validator.freebusy_periods(fb)
}

pub fn freebusy_x_properties(fb: FreeBusy) -> Dict(String, String) {
  ical_validator.freebusy_x_properties(fb)
}

// ============================================================
// Timezone accessors
// ============================================================

pub fn timezone_tzid(tz: Timezone) -> String {
  ical_validator.timezone_tzid(tz)
}

pub fn timezone_last_modified(tz: Timezone) -> Option(schedule_ast.DateTime) {
  ical_validator.timezone_last_modified(tz)
}

pub fn timezone_tzurl(tz: Timezone) -> Option(String) {
  ical_validator.timezone_tzurl(tz)
}

pub fn timezone_standard(tz: Timezone) -> List(TimezoneRule) {
  ical_validator.timezone_standard(tz)
}

pub fn timezone_daylight(tz: Timezone) -> List(TimezoneRule) {
  ical_validator.timezone_daylight(tz)
}

pub fn timezone_x_properties(tz: Timezone) -> Dict(String, String) {
  ical_validator.timezone_x_properties(tz)
}

// ============================================================
// Alarm accessors
// ============================================================

pub fn alarm_action(a: Alarm) -> String {
  ical_validator.alarm_action(a)
}

pub fn alarm_trigger(a: Alarm) -> String {
  ical_validator.alarm_trigger(a)
}

pub fn alarm_description(a: Alarm) -> Option(String) {
  ical_validator.alarm_description(a)
}

pub fn alarm_summary(a: Alarm) -> Option(String) {
  ical_validator.alarm_summary(a)
}

pub fn alarm_repeat(a: Alarm) -> Option(Int) {
  ical_validator.alarm_repeat(a)
}

pub fn alarm_duration(a: Alarm) -> Option(String) {
  ical_validator.alarm_duration(a)
}

pub fn alarm_attendees(a: Alarm) -> List(String) {
  ical_validator.alarm_attendees(a)
}

pub fn alarm_x_properties(a: Alarm) -> Dict(String, String) {
  ical_validator.alarm_x_properties(a)
}

// ============================================================
// Builders: Calendar
// ============================================================

pub fn new_calendar(
  version version: String,
  prod_id prod_id: String,
) -> Calendar {
  ical_validator.new_calendar(version: version, prod_id: prod_id)
}

pub fn with_method(cal: Calendar, method: String) -> Calendar {
  ical_validator.with_method(cal, method)
}

pub fn with_calscale(cal: Calendar, scale: String) -> Calendar {
  ical_validator.with_calscale(cal, scale)
}

pub fn add_event(cal: Calendar, event: Event) -> Calendar {
  ical_validator.add_event(cal, event)
}

pub fn add_todo(cal: Calendar, t: Todo) -> Calendar {
  ical_validator.add_todo(cal, t)
}

pub fn add_journal(cal: Calendar, j: Journal) -> Calendar {
  ical_validator.add_journal(cal, j)
}

pub fn add_freebusy(cal: Calendar, fb: FreeBusy) -> Calendar {
  ical_validator.add_freebusy(cal, fb)
}

pub fn add_timezone(cal: Calendar, tz: Timezone) -> Calendar {
  ical_validator.add_timezone(cal, tz)
}

pub fn add_unknown_component(
  cal: Calendar,
  component: UnknownComponent,
) -> Calendar {
  ical_validator.add_unknown_component(cal, component)
}

pub fn with_calendar_x_property(
  cal: Calendar,
  name: String,
  value: String,
) -> Calendar {
  ical_validator.with_calendar_x_property(cal, name, value)
}

// ============================================================
// Builders: Event
// ============================================================

pub fn new_event(
  uid uid: String,
  dtstamp dtstamp: schedule_ast.DateTime,
) -> Event {
  ical_validator.new_event(uid: uid, dtstamp: dtstamp)
}

pub fn with_dtstart(event: Event, dt: schedule_ast.DateTime) -> Event {
  ical_validator.with_dtstart(event, dt)
}

pub fn with_dtstart_tzid(event: Event, tzid: String) -> Event {
  ical_validator.with_dtstart_tzid(event, tzid)
}

pub fn with_dtend(event: Event, dt: schedule_ast.DateTime) -> Event {
  ical_validator.with_dtend(event, dt)
}

pub fn with_dtend_tzid(event: Event, tzid: String) -> Event {
  ical_validator.with_dtend_tzid(event, tzid)
}

pub fn with_duration(event: Event, value: String) -> Event {
  ical_validator.with_duration(event, value)
}

pub fn with_summary(event: Event, value: String) -> Event {
  ical_validator.with_summary(event, value)
}

pub fn with_description(event: Event, value: String) -> Event {
  ical_validator.with_description(event, value)
}

pub fn with_location(event: Event, value: String) -> Event {
  ical_validator.with_location(event, value)
}

pub fn with_status(event: Event, value: String) -> Event {
  ical_validator.with_status(event, value)
}

pub fn with_organizer(event: Event, value: String) -> Event {
  ical_validator.with_organizer(event, value)
}

pub fn add_attendee(event: Event, value: String) -> Event {
  ical_validator.add_attendee(event, value)
}

pub fn add_category(event: Event, value: String) -> Event {
  ical_validator.add_category(event, value)
}

pub fn with_url(event: Event, value: String) -> Event {
  ical_validator.with_url(event, value)
}

pub fn with_created(event: Event, dt: schedule_ast.DateTime) -> Event {
  ical_validator.with_created(event, dt)
}

pub fn with_last_modified(event: Event, dt: schedule_ast.DateTime) -> Event {
  ical_validator.with_last_modified(event, dt)
}

pub fn with_sequence(event: Event, value: Int) -> Event {
  ical_validator.with_sequence(event, value)
}

pub fn with_transparency(event: Event, value: String) -> Event {
  ical_validator.with_transparency(event, value)
}

pub fn with_rrule(event: Event, rule: rule_ast.RawRRule) -> Event {
  ical_validator.with_rrule(event, rule)
}

pub fn add_rdate(event: Event, dt: schedule_ast.DateTime) -> Event {
  ical_validator.add_rdate(event, dt)
}

pub fn add_exdate(event: Event, dt: schedule_ast.DateTime) -> Event {
  ical_validator.add_exdate(event, dt)
}

pub fn add_alarm(event: Event, alarm: Alarm) -> Event {
  ical_validator.add_alarm(event, alarm)
}

pub fn with_event_x_property(event: Event, name: String, value: String) -> Event {
  ical_validator.with_event_x_property(event, name, value)
}

// ============================================================
// Builders: Todo
// ============================================================

pub fn new_todo(uid uid: String, dtstamp dtstamp: schedule_ast.DateTime) -> Todo {
  ical_validator.new_todo(uid: uid, dtstamp: dtstamp)
}

pub fn with_todo_dtstart(t: Todo, dt: schedule_ast.DateTime) -> Todo {
  ical_validator.with_todo_dtstart(t, dt)
}

pub fn with_todo_due(t: Todo, dt: schedule_ast.DateTime) -> Todo {
  ical_validator.with_todo_due(t, dt)
}

pub fn with_todo_completed(t: Todo, dt: schedule_ast.DateTime) -> Todo {
  ical_validator.with_todo_completed(t, dt)
}

pub fn with_todo_summary(t: Todo, value: String) -> Todo {
  ical_validator.with_todo_summary(t, value)
}

pub fn with_todo_description(t: Todo, value: String) -> Todo {
  ical_validator.with_todo_description(t, value)
}

pub fn with_todo_status(t: Todo, value: String) -> Todo {
  ical_validator.with_todo_status(t, value)
}

pub fn with_todo_percent_complete(t: Todo, value: Int) -> Todo {
  ical_validator.with_todo_percent_complete(t, value)
}

pub fn with_todo_priority(t: Todo, value: Int) -> Todo {
  ical_validator.with_todo_priority(t, value)
}

pub fn add_todo_category(t: Todo, value: String) -> Todo {
  ical_validator.add_todo_category(t, value)
}

pub fn with_todo_rrule(t: Todo, rule: rule_ast.RawRRule) -> Todo {
  ical_validator.with_todo_rrule(t, rule)
}

pub fn add_todo_rdate(t: Todo, dt: schedule_ast.DateTime) -> Todo {
  ical_validator.add_todo_rdate(t, dt)
}

pub fn add_todo_exdate(t: Todo, dt: schedule_ast.DateTime) -> Todo {
  ical_validator.add_todo_exdate(t, dt)
}

pub fn add_todo_alarm(t: Todo, alarm: Alarm) -> Todo {
  ical_validator.add_todo_alarm(t, alarm)
}

pub fn with_todo_x_property(t: Todo, name: String, value: String) -> Todo {
  ical_validator.with_todo_x_property(t, name, value)
}

// ============================================================
// Builders: Journal
// ============================================================

pub fn new_journal(
  uid uid: String,
  dtstamp dtstamp: schedule_ast.DateTime,
) -> Journal {
  ical_validator.new_journal(uid: uid, dtstamp: dtstamp)
}

pub fn with_journal_dtstart(j: Journal, dt: schedule_ast.DateTime) -> Journal {
  ical_validator.with_journal_dtstart(j, dt)
}

pub fn with_journal_summary(j: Journal, value: String) -> Journal {
  ical_validator.with_journal_summary(j, value)
}

pub fn with_journal_description(j: Journal, value: String) -> Journal {
  ical_validator.with_journal_description(j, value)
}

pub fn with_journal_status(j: Journal, value: String) -> Journal {
  ical_validator.with_journal_status(j, value)
}

pub fn add_journal_category(j: Journal, value: String) -> Journal {
  ical_validator.add_journal_category(j, value)
}

pub fn with_journal_x_property(
  j: Journal,
  name: String,
  value: String,
) -> Journal {
  ical_validator.with_journal_x_property(j, name, value)
}

// ============================================================
// Builders: FreeBusy
// ============================================================

pub fn new_freebusy(
  uid uid: String,
  dtstamp dtstamp: schedule_ast.DateTime,
) -> FreeBusy {
  ical_validator.new_freebusy(uid: uid, dtstamp: dtstamp)
}

pub fn with_freebusy_dtstart(
  fb: FreeBusy,
  dt: schedule_ast.DateTime,
) -> FreeBusy {
  ical_validator.with_freebusy_dtstart(fb, dt)
}

pub fn with_freebusy_dtend(fb: FreeBusy, dt: schedule_ast.DateTime) -> FreeBusy {
  ical_validator.with_freebusy_dtend(fb, dt)
}

pub fn with_freebusy_organizer(fb: FreeBusy, value: String) -> FreeBusy {
  ical_validator.with_freebusy_organizer(fb, value)
}

pub fn add_freebusy_attendee(fb: FreeBusy, value: String) -> FreeBusy {
  ical_validator.add_freebusy_attendee(fb, value)
}

pub fn add_freebusy_period(fb: FreeBusy, value: String) -> FreeBusy {
  ical_validator.add_freebusy_period(fb, value)
}

pub fn with_freebusy_x_property(
  fb: FreeBusy,
  name: String,
  value: String,
) -> FreeBusy {
  ical_validator.with_freebusy_x_property(fb, name, value)
}

// ============================================================
// Builders: Timezone
// ============================================================

pub fn new_timezone(tzid tzid: String) -> Timezone {
  ical_validator.new_timezone(tzid: tzid)
}

pub fn with_timezone_last_modified(
  tz: Timezone,
  dt: schedule_ast.DateTime,
) -> Timezone {
  ical_validator.with_timezone_last_modified(tz, dt)
}

pub fn with_timezone_url(tz: Timezone, value: String) -> Timezone {
  ical_validator.with_timezone_url(tz, value)
}

pub fn add_timezone_standard(tz: Timezone, rule: TimezoneRule) -> Timezone {
  ical_validator.add_timezone_standard(tz, rule)
}

pub fn add_timezone_daylight(tz: Timezone, rule: TimezoneRule) -> Timezone {
  ical_validator.add_timezone_daylight(tz, rule)
}

pub fn with_timezone_x_property(
  tz: Timezone,
  name: String,
  value: String,
) -> Timezone {
  ical_validator.with_timezone_x_property(tz, name, value)
}

pub fn new_timezone_rule(
  dtstart dtstart: schedule_ast.DateTime,
  offset_from offset_from: String,
  offset_to offset_to: String,
) -> TimezoneRule {
  ical_validator.new_timezone_rule(
    dtstart: dtstart,
    offset_from: offset_from,
    offset_to: offset_to,
  )
}

pub fn with_timezone_rule_rrule(
  rule: TimezoneRule,
  value: rule_ast.RawRRule,
) -> TimezoneRule {
  ical_validator.with_timezone_rule_rrule(rule, value)
}

pub fn with_timezone_rule_name(
  rule: TimezoneRule,
  value: String,
) -> TimezoneRule {
  ical_validator.with_timezone_rule_name(rule, value)
}

// ============================================================
// Builders: Alarm
// ============================================================

pub fn new_alarm(action action: String, trigger trigger: String) -> Alarm {
  ical_validator.new_alarm(action: action, trigger: trigger)
}

pub fn with_alarm_description(alarm: Alarm, value: String) -> Alarm {
  ical_validator.with_alarm_description(alarm, value)
}

pub fn with_alarm_summary(alarm: Alarm, value: String) -> Alarm {
  ical_validator.with_alarm_summary(alarm, value)
}

pub fn with_alarm_repeat(alarm: Alarm, value: Int) -> Alarm {
  ical_validator.with_alarm_repeat(alarm, value)
}

pub fn with_alarm_duration(alarm: Alarm, value: String) -> Alarm {
  ical_validator.with_alarm_duration(alarm, value)
}

pub fn add_alarm_attendee(alarm: Alarm, value: String) -> Alarm {
  ical_validator.add_alarm_attendee(alarm, value)
}

pub fn with_alarm_x_property(alarm: Alarm, name: String, value: String) -> Alarm {
  ical_validator.with_alarm_x_property(alarm, name, value)
}
