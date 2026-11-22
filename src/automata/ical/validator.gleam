import automata/ical/ast.{
  type Parameter, type RawCalendar, type RawComponent, type RawProperty,
  Parameter, RawCalendar, RawComponent, RawProperty,
}
import automata/rrule
import automata/rrule/ast as rule_ast
import automata/rrule/parser as rrule_parser
import automata/schedule/ast as schedule_ast
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string

// ============================================================
// ValidationError
// ============================================================

pub type ValidationError {
  MissingVersion
  MissingProductId
  MissingComponentProperty(component: String, name: String)
  InvalidDateTime(name: String, raw: String)
  InvalidEscape(raw: String)
  InvalidInteger(name: String, raw: String)
  InvalidRRule(raw: String, error: rrule_parser.ParseError)
  DuplicateRRule(component_uid: String)
}

// ============================================================
// Opaque types
// ============================================================

pub opaque type Calendar {
  Calendar(
    version: String,
    product_id: String,
    method: Option(String),
    calscale: Option(String),
    // Components are kept newest first so that `add_*` is O(1); the
    // accessors reverse them back into document order.
    events_rev: List(Event),
    todos_rev: List(Todo),
    journals_rev: List(Journal),
    freebusy_rev: List(FreeBusy),
    timezones_rev: List(Timezone),
    unknown_components_rev: List(UnknownComponent),
    x_properties: Dict(String, String),
  )
}

pub opaque type Event {
  Event(
    uid: String,
    dtstamp: schedule_ast.DateTime,
    dtstart: Option(schedule_ast.DateTime),
    dtstart_tzid: Option(String),
    dtend: Option(schedule_ast.DateTime),
    dtend_tzid: Option(String),
    duration: Option(String),
    summary: Option(String),
    description: Option(String),
    location: Option(String),
    status: Option(String),
    organizer: Option(String),
    attendees: List(String),
    categories: List(String),
    url: Option(String),
    created: Option(schedule_ast.DateTime),
    last_modified: Option(schedule_ast.DateTime),
    sequence: Int,
    transparency: Option(String),
    rrule: Option(rule_ast.RawRRule),
    rdates: List(schedule_ast.DateTime),
    exdates: List(schedule_ast.DateTime),
    alarms: List(Alarm),
    x_properties: Dict(String, String),
    forms: Dict(String, List(PropertyForm)),
  )
}

pub opaque type Todo {
  Todo(
    uid: String,
    dtstamp: schedule_ast.DateTime,
    dtstart: Option(schedule_ast.DateTime),
    due: Option(schedule_ast.DateTime),
    completed: Option(schedule_ast.DateTime),
    summary: Option(String),
    description: Option(String),
    status: Option(String),
    percent_complete: Option(Int),
    priority: Option(Int),
    categories: List(String),
    rrule: Option(rule_ast.RawRRule),
    rdates: List(schedule_ast.DateTime),
    exdates: List(schedule_ast.DateTime),
    alarms: List(Alarm),
    x_properties: Dict(String, String),
    forms: Dict(String, List(PropertyForm)),
  )
}

pub opaque type Journal {
  Journal(
    uid: String,
    dtstamp: schedule_ast.DateTime,
    dtstart: Option(schedule_ast.DateTime),
    summary: Option(String),
    description: Option(String),
    status: Option(String),
    categories: List(String),
    x_properties: Dict(String, String),
    forms: Dict(String, List(PropertyForm)),
  )
}

pub opaque type FreeBusy {
  FreeBusy(
    uid: String,
    dtstamp: schedule_ast.DateTime,
    dtstart: Option(schedule_ast.DateTime),
    dtend: Option(schedule_ast.DateTime),
    organizer: Option(String),
    attendees: List(String),
    freebusy_periods: List(String),
    x_properties: Dict(String, String),
    forms: Dict(String, List(PropertyForm)),
  )
}

pub opaque type Timezone {
  Timezone(
    tzid: String,
    last_modified: Option(schedule_ast.DateTime),
    tzurl: Option(String),
    standard: List(TimezoneRule),
    daylight: List(TimezoneRule),
    x_properties: Dict(String, String),
  )
}

pub type TimezoneRule {
  TimezoneRule(
    dtstart: schedule_ast.DateTime,
    tzoffsetfrom: String,
    tzoffsetto: String,
    rrule: Option(rule_ast.RawRRule),
    tzname: Option(String),
  )
}

pub opaque type Alarm {
  Alarm(
    action: String,
    trigger: String,
    description: Option(String),
    summary: Option(String),
    repeat: Option(Int),
    duration: Option(String),
    attendees: List(String),
    x_properties: Dict(String, String),
    forms: Dict(String, List(PropertyForm)),
  )
}

/// How a property was written in parsed text: its parameters (such as
/// `VALUE=DATE`, `TZID` or `CN`), whether a date value ended in `Z`,
/// and whether it had no time part. The emitter uses it to write the
/// property back in the same form. A component keeps one form for a
/// single-valued property and one per value, in order, for repeated
/// properties. Only parsed properties that carry parameters, and date
/// properties written without `Z`, have forms; built values are
/// written as UTC DATE-TIME without parameters.
@internal
pub type PropertyForm {
  PropertyForm(parameters: List(Parameter), utc: Bool, date_only: Bool)
}

const utc_form = PropertyForm(parameters: [], utc: True, date_only: False)

pub type UnknownComponent {
  UnknownComponent(
    kind: String,
    properties: List(RawProperty),
    children: List(RawComponent),
  )
}

// ============================================================
// Public entry point
// ============================================================

pub fn validate(raw: RawCalendar) -> Result(Calendar, ValidationError) {
  let RawCalendar(properties: properties, components: components) = raw
  case find_value(properties, "VERSION") {
    None -> Error(MissingVersion)
    Some(version_raw) ->
      case find_value(properties, "PRODID") {
        None -> Error(MissingProductId)
        Some(prod_raw) -> {
          let method = find_value(properties, "METHOD")
          let calscale = find_value(properties, "CALSCALE")
          let x_props = collect_x_properties(properties)
          case classify_components(components) {
            Error(err) -> Error(err)
            Ok(buckets) -> {
              let ComponentBuckets(
                events: events,
                todos: todos,
                journals: journals,
                freebusy: freebusy,
                timezones: timezones,
                unknowns: unknowns,
              ) = buckets
              Ok(Calendar(
                version: version_raw,
                product_id: prod_raw,
                method: method,
                calscale: calscale,
                events_rev: events,
                todos_rev: todos,
                journals_rev: journals,
                freebusy_rev: freebusy,
                timezones_rev: timezones,
                unknown_components_rev: unknowns,
                x_properties: x_props,
              ))
            }
          }
        }
      }
  }
}

// ============================================================
// Component classification
// ============================================================

type ComponentBuckets {
  ComponentBuckets(
    events: List(Event),
    todos: List(Todo),
    journals: List(Journal),
    freebusy: List(FreeBusy),
    timezones: List(Timezone),
    unknowns: List(UnknownComponent),
  )
}

fn empty_buckets() -> ComponentBuckets {
  ComponentBuckets(
    events: [],
    todos: [],
    journals: [],
    freebusy: [],
    timezones: [],
    unknowns: [],
  )
}

fn classify_components(
  components: List(RawComponent),
) -> Result(ComponentBuckets, ValidationError) {
  // The buckets come out newest first, which is how `Calendar` stores
  // its components.
  do_classify(components, empty_buckets())
}

fn do_classify(
  components: List(RawComponent),
  acc: ComponentBuckets,
) -> Result(ComponentBuckets, ValidationError) {
  case components {
    [] -> Ok(acc)
    [first, ..rest] -> {
      let RawComponent(kind: kind, ..) = first
      case kind {
        "VEVENT" ->
          case validate_event(first) {
            Error(err) -> Error(err)
            Ok(event) ->
              do_classify(
                rest,
                ComponentBuckets(..acc, events: [event, ..acc.events]),
              )
          }
        "VTODO" ->
          case validate_todo(first) {
            Error(err) -> Error(err)
            Ok(todo_item) ->
              do_classify(
                rest,
                ComponentBuckets(..acc, todos: [todo_item, ..acc.todos]),
              )
          }
        "VJOURNAL" ->
          case validate_journal(first) {
            Error(err) -> Error(err)
            Ok(j) ->
              do_classify(
                rest,
                ComponentBuckets(..acc, journals: [j, ..acc.journals]),
              )
          }
        "VFREEBUSY" ->
          case validate_freebusy(first) {
            Error(err) -> Error(err)
            Ok(fb) ->
              do_classify(
                rest,
                ComponentBuckets(..acc, freebusy: [fb, ..acc.freebusy]),
              )
          }
        "VTIMEZONE" ->
          case validate_timezone(first) {
            Error(err) -> Error(err)
            Ok(tz) ->
              do_classify(
                rest,
                ComponentBuckets(..acc, timezones: [tz, ..acc.timezones]),
              )
          }
        _ -> {
          let RawComponent(properties: props, children: children, ..) = first
          let unknown =
            UnknownComponent(kind: kind, properties: props, children: children)
          do_classify(
            rest,
            ComponentBuckets(..acc, unknowns: [unknown, ..acc.unknowns]),
          )
        }
      }
    }
  }
}

// ============================================================
// VEVENT
// ============================================================

fn validate_event(comp: RawComponent) -> Result(Event, ValidationError) {
  let RawComponent(properties: props, children: children, ..) = comp
  case find_value(props, "UID") {
    None -> Error(MissingComponentProperty(component: "VEVENT", name: "UID"))
    Some(uid) ->
      case find_dt(props, "DTSTAMP") {
        Error(err) -> Error(err)
        Ok(None) ->
          Error(MissingComponentProperty(component: "VEVENT", name: "DTSTAMP"))
        Ok(Some(dtstamp)) -> build_event_body(uid, dtstamp, props, children)
      }
  }
}

fn build_event_body(
  uid: String,
  dtstamp: schedule_ast.DateTime,
  props: List(RawProperty),
  children: List(RawComponent),
) -> Result(Event, ValidationError) {
  case find_dt(props, "DTSTART") {
    Error(err) -> Error(err)
    Ok(dtstart) -> {
      let dtstart_tzid = find_tzid(props, "DTSTART")
      case find_dt(props, "DTEND") {
        Error(err) -> Error(err)
        Ok(dtend) -> {
          let dtend_tzid = find_tzid(props, "DTEND")
          build_event_optional(
            uid,
            dtstamp,
            dtstart,
            dtstart_tzid,
            dtend,
            dtend_tzid,
            props,
            children,
          )
        }
      }
    }
  }
}

fn build_event_optional(
  uid: String,
  dtstamp: schedule_ast.DateTime,
  dtstart: Option(schedule_ast.DateTime),
  dtstart_tzid: Option(String),
  dtend: Option(schedule_ast.DateTime),
  dtend_tzid: Option(String),
  props: List(RawProperty),
  children: List(RawComponent),
) -> Result(Event, ValidationError) {
  case opt_unescape(find_value(props, "SUMMARY")) {
    Error(err) -> Error(err)
    Ok(summary) ->
      case opt_unescape(find_value(props, "DESCRIPTION")) {
        Error(err) -> Error(err)
        Ok(description) ->
          case opt_unescape(find_value(props, "LOCATION")) {
            Error(err) -> Error(err)
            Ok(location) ->
              build_event_rest(
                uid,
                dtstamp,
                dtstart,
                dtstart_tzid,
                dtend,
                dtend_tzid,
                summary,
                description,
                location,
                props,
                children,
              )
          }
      }
  }
}

fn build_event_rest(
  uid: String,
  dtstamp: schedule_ast.DateTime,
  dtstart: Option(schedule_ast.DateTime),
  dtstart_tzid: Option(String),
  dtend: Option(schedule_ast.DateTime),
  dtend_tzid: Option(String),
  summary: Option(String),
  description: Option(String),
  location: Option(String),
  props: List(RawProperty),
  children: List(RawComponent),
) -> Result(Event, ValidationError) {
  case categories_of(props) {
    Error(err) -> Error(err)
    Ok(categories) ->
      case parse_sequence(props) {
        Error(err) -> Error(err)
        Ok(sequence) ->
          case find_dt(props, "CREATED") {
            Error(err) -> Error(err)
            Ok(created) ->
              case find_dt(props, "LAST-MODIFIED") {
                Error(err) -> Error(err)
                Ok(last_modified) ->
                  case parse_event_rrule(uid, props) {
                    Error(err) -> Error(err)
                    Ok(rrule_value) ->
                      case parse_datetime_list_prop(props, "RDATE") {
                        Error(err) -> Error(err)
                        Ok(rdates) ->
                          case parse_datetime_list_prop(props, "EXDATE") {
                            Error(err) -> Error(err)
                            Ok(exdates) ->
                              finalize_event(
                                uid,
                                dtstamp,
                                dtstart,
                                dtstart_tzid,
                                dtend,
                                dtend_tzid,
                                summary,
                                description,
                                location,
                                categories,
                                sequence,
                                created,
                                last_modified,
                                rrule_value,
                                rdates,
                                exdates,
                                props,
                                children,
                              )
                          }
                      }
                  }
              }
          }
      }
  }
}

fn finalize_event(
  uid: String,
  dtstamp: schedule_ast.DateTime,
  dtstart: Option(schedule_ast.DateTime),
  dtstart_tzid: Option(String),
  dtend: Option(schedule_ast.DateTime),
  dtend_tzid: Option(String),
  summary: Option(String),
  description: Option(String),
  location: Option(String),
  categories: List(String),
  sequence: Int,
  created: Option(schedule_ast.DateTime),
  last_modified: Option(schedule_ast.DateTime),
  rrule_value: Option(rule_ast.RawRRule),
  rdates: List(schedule_ast.DateTime),
  exdates: List(schedule_ast.DateTime),
  props: List(RawProperty),
  children: List(RawComponent),
) -> Result(Event, ValidationError) {
  case collect_alarms(children) {
    Error(err) -> Error(err)
    Ok(alarms) -> {
      let duration = find_value(props, "DURATION")
      let status = find_value(props, "STATUS")
      let organizer = find_value(props, "ORGANIZER")
      let url = find_value(props, "URL")
      let transparency = find_value(props, "TRANSP")
      let attendees = collect_values(props, "ATTENDEE")
      let x_props = collect_x_properties(props)
      Ok(Event(
        uid: uid,
        dtstamp: dtstamp,
        dtstart: dtstart,
        dtstart_tzid: dtstart_tzid,
        dtend: dtend,
        dtend_tzid: dtend_tzid,
        duration: duration,
        summary: summary,
        description: description,
        location: location,
        status: status,
        organizer: organizer,
        attendees: attendees,
        categories: categories,
        url: url,
        created: created,
        last_modified: last_modified,
        sequence: sequence,
        transparency: transparency,
        rrule: rrule_value,
        rdates: rdates,
        exdates: exdates,
        alarms: alarms,
        x_properties: x_props,
        forms: forms_of(props),
      ))
    }
  }
}

fn parse_sequence(props: List(RawProperty)) -> Result(Int, ValidationError) {
  case find_value(props, "SEQUENCE") {
    None -> Ok(0)
    Some(raw) ->
      case int.parse(raw) {
        Ok(v) -> Ok(v)
        Error(_) -> Error(InvalidInteger(name: "SEQUENCE", raw: raw))
      }
  }
}

fn parse_event_rrule(
  uid: String,
  props: List(RawProperty),
) -> Result(Option(rule_ast.RawRRule), ValidationError) {
  case collect_values(props, "RRULE") {
    [] -> Ok(None)
    [single] ->
      case rrule.parse(single) {
        Ok(parsed) -> Ok(Some(parsed))
        Error(err) -> Error(InvalidRRule(raw: single, error: err))
      }
    [_, _, ..] -> Error(DuplicateRRule(component_uid: uid))
  }
}

// ============================================================
// VTODO
// ============================================================

fn validate_todo(comp: RawComponent) -> Result(Todo, ValidationError) {
  let RawComponent(properties: props, children: children, ..) = comp
  case find_value(props, "UID") {
    None -> Error(MissingComponentProperty(component: "VTODO", name: "UID"))
    Some(uid) ->
      case find_dt(props, "DTSTAMP") {
        Error(err) -> Error(err)
        Ok(None) ->
          Error(MissingComponentProperty(component: "VTODO", name: "DTSTAMP"))
        Ok(Some(dtstamp)) -> build_todo_body(uid, dtstamp, props, children)
      }
  }
}

fn build_todo_body(
  uid: String,
  dtstamp: schedule_ast.DateTime,
  props: List(RawProperty),
  children: List(RawComponent),
) -> Result(Todo, ValidationError) {
  case find_dt(props, "DTSTART") {
    Error(err) -> Error(err)
    Ok(dtstart) ->
      case find_dt(props, "DUE") {
        Error(err) -> Error(err)
        Ok(due) ->
          case find_dt(props, "COMPLETED") {
            Error(err) -> Error(err)
            Ok(completed) ->
              build_todo_optionals(
                uid,
                dtstamp,
                dtstart,
                due,
                completed,
                props,
                children,
              )
          }
      }
  }
}

fn build_todo_optionals(
  uid: String,
  dtstamp: schedule_ast.DateTime,
  dtstart: Option(schedule_ast.DateTime),
  due: Option(schedule_ast.DateTime),
  completed: Option(schedule_ast.DateTime),
  props: List(RawProperty),
  children: List(RawComponent),
) -> Result(Todo, ValidationError) {
  case opt_unescape(find_value(props, "SUMMARY")) {
    Error(err) -> Error(err)
    Ok(summary) ->
      case opt_unescape(find_value(props, "DESCRIPTION")) {
        Error(err) -> Error(err)
        Ok(description) ->
          case categories_of(props) {
            Error(err) -> Error(err)
            Ok(categories) ->
              build_todo_numbers(
                uid,
                dtstamp,
                dtstart,
                due,
                completed,
                summary,
                description,
                categories,
                props,
                children,
              )
          }
      }
  }
}

fn build_todo_numbers(
  uid: String,
  dtstamp: schedule_ast.DateTime,
  dtstart: Option(schedule_ast.DateTime),
  due: Option(schedule_ast.DateTime),
  completed: Option(schedule_ast.DateTime),
  summary: Option(String),
  description: Option(String),
  categories: List(String),
  props: List(RawProperty),
  children: List(RawComponent),
) -> Result(Todo, ValidationError) {
  case parse_optional_int(props, "PERCENT-COMPLETE") {
    Error(err) -> Error(err)
    Ok(percent_complete) ->
      case parse_optional_int(props, "PRIORITY") {
        Error(err) -> Error(err)
        Ok(priority) ->
          case parse_event_rrule(uid, props) {
            Error(err) -> Error(err)
            Ok(rrule_value) ->
              case parse_datetime_list_prop(props, "RDATE") {
                Error(err) -> Error(err)
                Ok(rdates) ->
                  case parse_datetime_list_prop(props, "EXDATE") {
                    Error(err) -> Error(err)
                    Ok(exdates) ->
                      finalize_todo(
                        uid,
                        dtstamp,
                        dtstart,
                        due,
                        completed,
                        summary,
                        description,
                        categories,
                        percent_complete,
                        priority,
                        rrule_value,
                        rdates,
                        exdates,
                        props,
                        children,
                      )
                  }
              }
          }
      }
  }
}

fn finalize_todo(
  uid: String,
  dtstamp: schedule_ast.DateTime,
  dtstart: Option(schedule_ast.DateTime),
  due: Option(schedule_ast.DateTime),
  completed: Option(schedule_ast.DateTime),
  summary: Option(String),
  description: Option(String),
  categories: List(String),
  percent_complete: Option(Int),
  priority: Option(Int),
  rrule_value: Option(rule_ast.RawRRule),
  rdates: List(schedule_ast.DateTime),
  exdates: List(schedule_ast.DateTime),
  props: List(RawProperty),
  children: List(RawComponent),
) -> Result(Todo, ValidationError) {
  case collect_alarms(children) {
    Error(err) -> Error(err)
    Ok(alarms) -> {
      let status = find_value(props, "STATUS")
      let x_props = collect_x_properties(props)
      Ok(Todo(
        uid: uid,
        dtstamp: dtstamp,
        dtstart: dtstart,
        due: due,
        completed: completed,
        summary: summary,
        description: description,
        status: status,
        percent_complete: percent_complete,
        priority: priority,
        categories: categories,
        rrule: rrule_value,
        rdates: rdates,
        exdates: exdates,
        alarms: alarms,
        x_properties: x_props,
        forms: forms_of(props),
      ))
    }
  }
}

fn parse_optional_int(
  props: List(RawProperty),
  name: String,
) -> Result(Option(Int), ValidationError) {
  case find_value(props, name) {
    None -> Ok(None)
    Some(raw) ->
      case int.parse(raw) {
        Ok(v) -> Ok(Some(v))
        Error(_) -> Error(InvalidInteger(name: name, raw: raw))
      }
  }
}

// ============================================================
// VJOURNAL
// ============================================================

fn validate_journal(comp: RawComponent) -> Result(Journal, ValidationError) {
  let RawComponent(properties: props, ..) = comp
  case find_value(props, "UID") {
    None -> Error(MissingComponentProperty(component: "VJOURNAL", name: "UID"))
    Some(uid) ->
      case find_dt(props, "DTSTAMP") {
        Error(err) -> Error(err)
        Ok(None) ->
          Error(MissingComponentProperty(component: "VJOURNAL", name: "DTSTAMP"))
        Ok(Some(dtstamp)) -> build_journal_body(uid, dtstamp, props)
      }
  }
}

fn build_journal_body(
  uid: String,
  dtstamp: schedule_ast.DateTime,
  props: List(RawProperty),
) -> Result(Journal, ValidationError) {
  case find_dt(props, "DTSTART") {
    Error(err) -> Error(err)
    Ok(dtstart) ->
      case opt_unescape(find_value(props, "SUMMARY")) {
        Error(err) -> Error(err)
        Ok(summary) ->
          case opt_unescape(find_value(props, "DESCRIPTION")) {
            Error(err) -> Error(err)
            Ok(description) ->
              case categories_of(props) {
                Error(err) -> Error(err)
                Ok(categories) -> {
                  let status = find_value(props, "STATUS")
                  let x_props = collect_x_properties(props)
                  Ok(Journal(
                    uid: uid,
                    dtstamp: dtstamp,
                    dtstart: dtstart,
                    summary: summary,
                    description: description,
                    status: status,
                    categories: categories,
                    x_properties: x_props,
                    forms: forms_of(props),
                  ))
                }
              }
          }
      }
  }
}

// ============================================================
// VFREEBUSY
// ============================================================

fn validate_freebusy(comp: RawComponent) -> Result(FreeBusy, ValidationError) {
  let RawComponent(properties: props, ..) = comp
  case find_value(props, "UID") {
    None -> Error(MissingComponentProperty(component: "VFREEBUSY", name: "UID"))
    Some(uid) ->
      case find_dt(props, "DTSTAMP") {
        Error(err) -> Error(err)
        Ok(None) ->
          Error(MissingComponentProperty(
            component: "VFREEBUSY",
            name: "DTSTAMP",
          ))
        Ok(Some(dtstamp)) -> build_freebusy_body(uid, dtstamp, props)
      }
  }
}

fn build_freebusy_body(
  uid: String,
  dtstamp: schedule_ast.DateTime,
  props: List(RawProperty),
) -> Result(FreeBusy, ValidationError) {
  case find_dt(props, "DTSTART") {
    Error(err) -> Error(err)
    Ok(dtstart) ->
      case find_dt(props, "DTEND") {
        Error(err) -> Error(err)
        Ok(dtend) -> {
          let organizer = find_value(props, "ORGANIZER")
          let attendees = collect_values(props, "ATTENDEE")
          let periods = collect_values(props, "FREEBUSY")
          let x_props = collect_x_properties(props)
          Ok(FreeBusy(
            uid: uid,
            dtstamp: dtstamp,
            dtstart: dtstart,
            dtend: dtend,
            organizer: organizer,
            attendees: attendees,
            freebusy_periods: periods,
            x_properties: x_props,
            forms: forms_of(props),
          ))
        }
      }
  }
}

// ============================================================
// VTIMEZONE
// ============================================================

fn validate_timezone(comp: RawComponent) -> Result(Timezone, ValidationError) {
  let RawComponent(properties: props, children: children, ..) = comp
  case find_value(props, "TZID") {
    None ->
      Error(MissingComponentProperty(component: "VTIMEZONE", name: "TZID"))
    Some(tzid) ->
      case find_dt(props, "LAST-MODIFIED") {
        Error(err) -> Error(err)
        Ok(last_modified) -> {
          let tzurl = find_value(props, "TZURL")
          case classify_timezone_children(children) {
            Error(err) -> Error(err)
            Ok(#(standard, daylight)) -> {
              let x_props = collect_x_properties(props)
              Ok(Timezone(
                tzid: tzid,
                last_modified: last_modified,
                tzurl: tzurl,
                standard: standard,
                daylight: daylight,
                x_properties: x_props,
              ))
            }
          }
        }
      }
  }
}

fn classify_timezone_children(
  children: List(RawComponent),
) -> Result(#(List(TimezoneRule), List(TimezoneRule)), ValidationError) {
  case do_classify_tz_children(children, [], []) {
    Error(err) -> Error(err)
    Ok(#(s, d)) -> Ok(#(list.reverse(s), list.reverse(d)))
  }
}

fn do_classify_tz_children(
  children: List(RawComponent),
  acc_std: List(TimezoneRule),
  acc_dst: List(TimezoneRule),
) -> Result(#(List(TimezoneRule), List(TimezoneRule)), ValidationError) {
  case children {
    [] -> Ok(#(acc_std, acc_dst))
    [first, ..rest] -> {
      let RawComponent(kind: kind, ..) = first
      case kind {
        "STANDARD" ->
          case validate_tz_rule(first) {
            Error(err) -> Error(err)
            Ok(rule) ->
              do_classify_tz_children(rest, [rule, ..acc_std], acc_dst)
          }
        "DAYLIGHT" ->
          case validate_tz_rule(first) {
            Error(err) -> Error(err)
            Ok(rule) ->
              do_classify_tz_children(rest, acc_std, [rule, ..acc_dst])
          }
        _ -> do_classify_tz_children(rest, acc_std, acc_dst)
      }
    }
  }
}

fn validate_tz_rule(
  comp: RawComponent,
) -> Result(TimezoneRule, ValidationError) {
  let RawComponent(properties: props, kind: kind, ..) = comp
  case find_dt(props, "DTSTART") {
    Error(err) -> Error(err)
    Ok(None) ->
      Error(MissingComponentProperty(component: kind, name: "DTSTART"))
    Ok(Some(dtstart)) ->
      case find_value(props, "TZOFFSETFROM") {
        None ->
          Error(MissingComponentProperty(component: kind, name: "TZOFFSETFROM"))
        Some(from) ->
          case find_value(props, "TZOFFSETTO") {
            None ->
              Error(MissingComponentProperty(
                component: kind,
                name: "TZOFFSETTO",
              ))
            Some(to) ->
              case parse_event_rrule(kind, props) {
                Error(err) -> Error(err)
                Ok(rrule_value) -> {
                  let tzname = find_value(props, "TZNAME")
                  Ok(TimezoneRule(
                    dtstart: dtstart,
                    tzoffsetfrom: from,
                    tzoffsetto: to,
                    rrule: rrule_value,
                    tzname: tzname,
                  ))
                }
              }
          }
      }
  }
}

// ============================================================
// VALARM
// ============================================================

fn collect_alarms(
  children: List(RawComponent),
) -> Result(List(Alarm), ValidationError) {
  case do_collect_alarms(children, []) {
    Error(err) -> Error(err)
    Ok(alarms) -> Ok(list.reverse(alarms))
  }
}

fn do_collect_alarms(
  children: List(RawComponent),
  acc: List(Alarm),
) -> Result(List(Alarm), ValidationError) {
  case children {
    [] -> Ok(acc)
    [first, ..rest] -> {
      let RawComponent(kind: kind, ..) = first
      case kind {
        "VALARM" ->
          case validate_alarm(first) {
            Error(err) -> Error(err)
            Ok(alarm) -> do_collect_alarms(rest, [alarm, ..acc])
          }
        _ -> do_collect_alarms(rest, acc)
      }
    }
  }
}

fn validate_alarm(comp: RawComponent) -> Result(Alarm, ValidationError) {
  let RawComponent(properties: props, ..) = comp
  case find_value(props, "ACTION") {
    None -> Error(MissingComponentProperty(component: "VALARM", name: "ACTION"))
    Some(action) ->
      case find_value(props, "TRIGGER") {
        None ->
          Error(MissingComponentProperty(component: "VALARM", name: "TRIGGER"))
        Some(trigger) -> build_alarm_body(action, trigger, props)
      }
  }
}

fn build_alarm_body(
  action: String,
  trigger: String,
  props: List(RawProperty),
) -> Result(Alarm, ValidationError) {
  case opt_unescape(find_value(props, "DESCRIPTION")) {
    Error(err) -> Error(err)
    Ok(description) ->
      case opt_unescape(find_value(props, "SUMMARY")) {
        Error(err) -> Error(err)
        Ok(summary) ->
          case parse_optional_int(props, "REPEAT") {
            Error(err) -> Error(err)
            Ok(repeat) -> {
              let duration = find_value(props, "DURATION")
              let attendees = collect_values(props, "ATTENDEE")
              let x_props = collect_x_properties(props)
              Ok(Alarm(
                action: action,
                trigger: trigger,
                description: description,
                summary: summary,
                repeat: repeat,
                duration: duration,
                attendees: attendees,
                x_properties: x_props,
                forms: forms_of(props),
              ))
            }
          }
      }
  }
}

// ============================================================
// Property helpers
// ============================================================

const date_properties = ["DTSTART", "DTEND", "DUE", "RDATE", "EXDATE"]

const repeated_properties = [
  "RDATE",
  "EXDATE",
  "CATEGORIES",
  "ATTENDEE",
  "FREEBUSY",
]

// The form of the first occurrence of each single-valued property,
// which is the one the model keeps, and the form of every retained
// repeated value in document order.
fn forms_of(props: List(RawProperty)) -> Dict(String, List(PropertyForm)) {
  list.fold(props, dict.new(), fn(acc, prop) {
    let RawProperty(name: name, parameters: params, raw_value: raw, ..) = prop
    case list.contains(repeated_properties, name) {
      True -> {
        let values = case name {
          "RDATE" | "EXDATE" -> string.split(raw, ",")
          "CATEGORIES" ->
            case split_text_list(raw) {
              Ok(values) -> values
              // The component validator has already checked TEXT escapes.
              Error(_) -> []
            }
          _ -> [raw]
        }
        let line = list.map(values, value_form(params, _))
        case dict.get(acc, name) {
          Ok(previous) -> dict.insert(acc, name, prepend_all(line, previous))
          Error(_) -> dict.insert(acc, name, list.reverse(line))
        }
      }
      False ->
        case dict.has_key(acc, name) {
          True -> acc
          False -> dict.insert(acc, name, [value_form(params, raw)])
        }
    }
  })
  |> dict.map_values(fn(name, forms) {
    case list.contains(repeated_properties, name) {
      True -> list.reverse(forms)
      False -> forms
    }
  })
  |> dict.filter(fn(name, forms) {
    list.any(forms, fn(form) {
      form.parameters != []
      || { !form.utc && list.contains(date_properties, name) }
    })
  })
}

fn value_form(params: List(Parameter), raw: String) -> PropertyForm {
  PropertyForm(
    parameters: params,
    utc: string.ends_with(raw, "Z"),
    date_only: !string.contains(raw, "T"),
  )
}

fn is_date_form(forms: Dict(String, List(PropertyForm)), name: String) -> Bool {
  case dict.get(forms, name) {
    Ok([form, ..]) ->
      form.date_only
      || list.any(form.parameters, fn(p) {
        string.uppercase(p.name) == "VALUE"
        && string.uppercase(p.value) == "DATE"
      })
    _ -> False
  }
}

// A setter gives `name` a UTC DATE-TIME. RFC 5545 wants DTSTART and
// DTEND (or DUE) to share a value type, so a DATE `partner` is reset
// to the same UTC DATE-TIME form.
fn replace_date_form(
  forms: Dict(String, List(PropertyForm)),
  name: String,
  partner: String,
) -> Dict(String, List(PropertyForm)) {
  let forms = dict.delete(forms, name)
  case is_date_form(forms, partner) {
    True -> dict.delete(forms, partner)
    False -> forms
  }
}

// An appended value has no parsed parameters. Dates default to UTC.
// Keep a placeholder so subsequent values stay aligned with their forms.
fn append_default_form(
  forms: Dict(String, List(PropertyForm)),
  name: String,
) -> Dict(String, List(PropertyForm)) {
  case dict.get(forms, name) {
    Ok(existing) -> dict.insert(forms, name, list.append(existing, [utc_form]))
    Error(_) -> forms
  }
}

fn find_value(props: List(RawProperty), name: String) -> Option(String) {
  case list.find(props, fn(p) { p.name == name }) {
    Ok(prop) -> Some(prop.raw_value)
    Error(_) -> None
  }
}

fn collect_values(props: List(RawProperty), name: String) -> List(String) {
  list.filter_map(props, fn(p) {
    case p.name == name {
      True -> Ok(p.raw_value)
      False -> Error(Nil)
    }
  })
}

fn find_prop(props: List(RawProperty), name: String) -> Option(RawProperty) {
  case list.find(props, fn(p) { p.name == name }) {
    Ok(prop) -> Some(prop)
    Error(_) -> None
  }
}

fn find_tzid(props: List(RawProperty), name: String) -> Option(String) {
  case find_prop(props, name) {
    None -> None
    Some(RawProperty(parameters: params, ..)) -> find_param(params, "TZID")
  }
}

fn find_param(params: List(Parameter), name: String) -> Option(String) {
  case list.find(params, fn(p) { p.name == name }) {
    Ok(Parameter(value: v, ..)) -> Some(v)
    Error(_) -> None
  }
}

fn find_dt(
  props: List(RawProperty),
  name: String,
) -> Result(Option(schedule_ast.DateTime), ValidationError) {
  case find_value(props, name) {
    None -> Ok(None)
    Some(raw) ->
      case parse_datetime(name, raw) {
        Ok(dt) -> Ok(Some(dt))
        Error(err) -> Error(err)
      }
  }
}

fn collect_x_properties(props: List(RawProperty)) -> Dict(String, String) {
  list.fold(props, dict.new(), fn(acc, p) {
    case string.starts_with(p.name, "X-") {
      True -> dict.insert(acc, p.name, p.raw_value)
      False -> acc
    }
  })
}

fn opt_unescape(
  value: Option(String),
) -> Result(Option(String), ValidationError) {
  case value {
    None -> Ok(None)
    Some(raw) ->
      case unescape_text(raw) {
        Ok(s) -> Ok(Some(s))
        Error(err) -> Error(err)
      }
  }
}

fn categories_of(
  props: List(RawProperty),
) -> Result(List(String), ValidationError) {
  let raws = collect_values(props, "CATEGORIES")
  fold_categories(raws, [])
}

fn fold_categories(
  raws: List(String),
  acc: List(String),
) -> Result(List(String), ValidationError) {
  case raws {
    [] -> Ok(list.reverse(acc))
    [first, ..rest] ->
      case split_text_list(first) {
        Error(err) -> Error(err)
        Ok(parts) -> fold_categories(rest, prepend_all(parts, acc))
      }
  }
}

fn prepend_all(items: List(a), acc: List(a)) -> List(a) {
  case items {
    [] -> acc
    [first, ..rest] -> prepend_all(rest, [first, ..acc])
  }
}

// ============================================================
// Text escape / list splitting
// ============================================================

const sentinel = "\u{0001}"

fn split_text_list(raw: String) -> Result(List(String), ValidationError) {
  let masked = string.replace(raw, "\\,", sentinel)
  let chunks = string.split(masked, ",")
  unescape_chunks(chunks, [])
}

fn unescape_chunks(
  chunks: List(String),
  acc: List(String),
) -> Result(List(String), ValidationError) {
  case chunks {
    [] -> Ok(list.reverse(acc))
    [first, ..rest] -> {
      let restored = string.replace(first, sentinel, "\\,")
      case unescape_text(restored) {
        Error(err) -> Error(err)
        Ok(s) -> unescape_chunks(rest, [s, ..acc])
      }
    }
  }
}

fn unescape_text(raw: String) -> Result(String, ValidationError) {
  do_unescape(string.to_graphemes(raw), raw, [])
}

fn do_unescape(
  graphemes: List(String),
  original: String,
  acc: List(String),
) -> Result(String, ValidationError) {
  case graphemes {
    [] -> Ok(string.concat(list.reverse(acc)))
    ["\\", second, ..rest] ->
      case second {
        "\\" -> do_unescape(rest, original, ["\\", ..acc])
        "," -> do_unescape(rest, original, [",", ..acc])
        ";" -> do_unescape(rest, original, [";", ..acc])
        "n" -> do_unescape(rest, original, ["\n", ..acc])
        "N" -> do_unescape(rest, original, ["\n", ..acc])
        _ -> Error(InvalidEscape(raw: original))
      }
    ["\\"] -> Error(InvalidEscape(raw: original))
    [first, ..rest] -> do_unescape(rest, original, [first, ..acc])
  }
}

// ============================================================
// DateTime parsing (RFC 5545 §3.3.5)
// ============================================================

fn parse_datetime(
  name: String,
  raw: String,
) -> Result(schedule_ast.DateTime, ValidationError) {
  let stripped = case string.ends_with(raw, "Z") {
    True -> string.drop_end(raw, 1)
    False -> raw
  }
  case string.split_once(stripped, "T") {
    Ok(#(date_part, time_part)) ->
      parse_dt_components(name, raw, date_part, time_part)
    Error(_) ->
      case string.length(stripped) == 8 {
        True -> parse_dt_components(name, raw, stripped, "000000")
        False -> Error(InvalidDateTime(name: name, raw: raw))
      }
  }
}

fn parse_dt_components(
  name: String,
  raw: String,
  date_part: String,
  time_part: String,
) -> Result(schedule_ast.DateTime, ValidationError) {
  case string.length(date_part) == 8 && string.length(time_part) == 6 {
    False -> Error(InvalidDateTime(name: name, raw: raw))
    True ->
      case slice_date_time(date_part, time_part) {
        Error(_) -> Error(InvalidDateTime(name: name, raw: raw))
        Ok(#(y, mo, d, h, mi, s)) ->
          case
            schedule_ast.try_datetime(
              year: y,
              month: mo,
              day: d,
              hour: h,
              minute: mi,
              second: s,
            )
          {
            Ok(dt) -> Ok(dt)
            Error(_) -> Error(InvalidDateTime(name: name, raw: raw))
          }
      }
  }
}

fn slice_date_time(
  date_part: String,
  time_part: String,
) -> Result(#(Int, Int, Int, Int, Int, Int), Nil) {
  let year = string.slice(date_part, 0, 4)
  let month = string.slice(date_part, 4, 2)
  let day = string.slice(date_part, 6, 2)
  let hour = string.slice(time_part, 0, 2)
  let minute = string.slice(time_part, 2, 2)
  let second = string.slice(time_part, 4, 2)
  case int.parse(year) {
    Error(_) -> Error(Nil)
    Ok(y) ->
      case int.parse(month) {
        Error(_) -> Error(Nil)
        Ok(mo) ->
          case int.parse(day) {
            Error(_) -> Error(Nil)
            Ok(d) ->
              case int.parse(hour) {
                Error(_) -> Error(Nil)
                Ok(h) ->
                  case int.parse(minute) {
                    Error(_) -> Error(Nil)
                    Ok(mi) ->
                      case int.parse(second) {
                        Error(_) -> Error(Nil)
                        Ok(s) -> Ok(#(y, mo, d, h, mi, s))
                      }
                  }
              }
          }
      }
  }
}

fn parse_datetime_list_prop(
  props: List(RawProperty),
  name: String,
) -> Result(List(schedule_ast.DateTime), ValidationError) {
  let raws = collect_values(props, name)
  fold_dt_lists(name, raws, [])
}

fn fold_dt_lists(
  name: String,
  raws: List(String),
  acc: List(schedule_ast.DateTime),
) -> Result(List(schedule_ast.DateTime), ValidationError) {
  case raws {
    [] -> Ok(list.reverse(acc))
    [first, ..rest] ->
      case parse_datetime_list(name, first) {
        Error(err) -> Error(err)
        Ok(dts) -> fold_dt_lists(name, rest, prepend_all(dts, acc))
      }
  }
}

fn parse_datetime_list(
  name: String,
  raw: String,
) -> Result(List(schedule_ast.DateTime), ValidationError) {
  let parts = string.split(raw, ",")
  do_parse_datetime_list(name, parts, [])
}

fn do_parse_datetime_list(
  name: String,
  parts: List(String),
  acc: List(schedule_ast.DateTime),
) -> Result(List(schedule_ast.DateTime), ValidationError) {
  case parts {
    [] -> Ok(list.reverse(acc))
    [first, ..rest] ->
      case parse_datetime(name, first) {
        Error(err) -> Error(err)
        Ok(dt) -> do_parse_datetime_list(name, rest, [dt, ..acc])
      }
  }
}

// ============================================================
// Calendar accessors
// ============================================================

@internal
pub fn event_forms(event: Event) -> Dict(String, List(PropertyForm)) {
  event.forms
}

@internal
pub fn todo_forms(t: Todo) -> Dict(String, List(PropertyForm)) {
  t.forms
}

@internal
pub fn journal_forms(j: Journal) -> Dict(String, List(PropertyForm)) {
  j.forms
}

@internal
pub fn freebusy_forms(fb: FreeBusy) -> Dict(String, List(PropertyForm)) {
  fb.forms
}

@internal
pub fn alarm_forms(alarm: Alarm) -> Dict(String, List(PropertyForm)) {
  alarm.forms
}

pub fn version(cal: Calendar) -> String {
  cal.version
}

pub fn product_id(cal: Calendar) -> String {
  cal.product_id
}

pub fn method(cal: Calendar) -> Option(String) {
  cal.method
}

pub fn calscale(cal: Calendar) -> Option(String) {
  cal.calscale
}

pub fn events(cal: Calendar) -> List(Event) {
  list.reverse(cal.events_rev)
}

pub fn todos(cal: Calendar) -> List(Todo) {
  list.reverse(cal.todos_rev)
}

pub fn journals(cal: Calendar) -> List(Journal) {
  list.reverse(cal.journals_rev)
}

pub fn freebusy(cal: Calendar) -> List(FreeBusy) {
  list.reverse(cal.freebusy_rev)
}

pub fn timezones(cal: Calendar) -> List(Timezone) {
  list.reverse(cal.timezones_rev)
}

pub fn unknown_components(cal: Calendar) -> List(UnknownComponent) {
  list.reverse(cal.unknown_components_rev)
}

pub fn calendar_x_properties(cal: Calendar) -> Dict(String, String) {
  cal.x_properties
}

// ============================================================
// Event accessors
// ============================================================

pub fn event_uid(event: Event) -> String {
  event.uid
}

pub fn event_dtstamp(event: Event) -> schedule_ast.DateTime {
  event.dtstamp
}

pub fn event_dtstart(event: Event) -> Option(schedule_ast.DateTime) {
  event.dtstart
}

pub fn event_dtstart_tzid(event: Event) -> Option(String) {
  event.dtstart_tzid
}

pub fn event_dtend(event: Event) -> Option(schedule_ast.DateTime) {
  event.dtend
}

pub fn event_dtend_tzid(event: Event) -> Option(String) {
  event.dtend_tzid
}

pub fn event_duration(event: Event) -> Option(String) {
  event.duration
}

pub fn event_summary(event: Event) -> Option(String) {
  event.summary
}

pub fn event_description(event: Event) -> Option(String) {
  event.description
}

pub fn event_location(event: Event) -> Option(String) {
  event.location
}

pub fn event_status(event: Event) -> Option(String) {
  event.status
}

pub fn event_organizer(event: Event) -> Option(String) {
  event.organizer
}

pub fn event_attendees(event: Event) -> List(String) {
  event.attendees
}

pub fn event_categories(event: Event) -> List(String) {
  event.categories
}

pub fn event_url(event: Event) -> Option(String) {
  event.url
}

pub fn event_created(event: Event) -> Option(schedule_ast.DateTime) {
  event.created
}

pub fn event_last_modified(event: Event) -> Option(schedule_ast.DateTime) {
  event.last_modified
}

pub fn event_sequence(event: Event) -> Int {
  event.sequence
}

pub fn event_transparency(event: Event) -> Option(String) {
  event.transparency
}

pub fn event_rrule(event: Event) -> Option(rule_ast.RawRRule) {
  event.rrule
}

pub fn event_rdates(event: Event) -> List(schedule_ast.DateTime) {
  event.rdates
}

pub fn event_exdates(event: Event) -> List(schedule_ast.DateTime) {
  event.exdates
}

pub fn event_alarms(event: Event) -> List(Alarm) {
  event.alarms
}

pub fn event_x_properties(event: Event) -> Dict(String, String) {
  event.x_properties
}

// ============================================================
// Todo accessors
// ============================================================

pub fn todo_uid(t: Todo) -> String {
  t.uid
}

pub fn todo_dtstamp(t: Todo) -> schedule_ast.DateTime {
  t.dtstamp
}

pub fn todo_dtstart(t: Todo) -> Option(schedule_ast.DateTime) {
  t.dtstart
}

pub fn todo_due(t: Todo) -> Option(schedule_ast.DateTime) {
  t.due
}

pub fn todo_completed(t: Todo) -> Option(schedule_ast.DateTime) {
  t.completed
}

pub fn todo_summary(t: Todo) -> Option(String) {
  t.summary
}

pub fn todo_description(t: Todo) -> Option(String) {
  t.description
}

pub fn todo_status(t: Todo) -> Option(String) {
  t.status
}

pub fn todo_percent_complete(t: Todo) -> Option(Int) {
  t.percent_complete
}

pub fn todo_priority(t: Todo) -> Option(Int) {
  t.priority
}

pub fn todo_categories(t: Todo) -> List(String) {
  t.categories
}

pub fn todo_rrule(t: Todo) -> Option(rule_ast.RawRRule) {
  t.rrule
}

pub fn todo_rdates(t: Todo) -> List(schedule_ast.DateTime) {
  t.rdates
}

pub fn todo_exdates(t: Todo) -> List(schedule_ast.DateTime) {
  t.exdates
}

pub fn todo_alarms(t: Todo) -> List(Alarm) {
  t.alarms
}

pub fn todo_x_properties(t: Todo) -> Dict(String, String) {
  t.x_properties
}

// ============================================================
// Journal accessors
// ============================================================

pub fn journal_uid(j: Journal) -> String {
  j.uid
}

pub fn journal_dtstamp(j: Journal) -> schedule_ast.DateTime {
  j.dtstamp
}

pub fn journal_dtstart(j: Journal) -> Option(schedule_ast.DateTime) {
  j.dtstart
}

pub fn journal_summary(j: Journal) -> Option(String) {
  j.summary
}

pub fn journal_description(j: Journal) -> Option(String) {
  j.description
}

pub fn journal_status(j: Journal) -> Option(String) {
  j.status
}

pub fn journal_categories(j: Journal) -> List(String) {
  j.categories
}

pub fn journal_x_properties(j: Journal) -> Dict(String, String) {
  j.x_properties
}

// ============================================================
// FreeBusy accessors
// ============================================================

pub fn freebusy_uid(fb: FreeBusy) -> String {
  fb.uid
}

pub fn freebusy_dtstamp(fb: FreeBusy) -> schedule_ast.DateTime {
  fb.dtstamp
}

pub fn freebusy_dtstart(fb: FreeBusy) -> Option(schedule_ast.DateTime) {
  fb.dtstart
}

pub fn freebusy_dtend(fb: FreeBusy) -> Option(schedule_ast.DateTime) {
  fb.dtend
}

pub fn freebusy_organizer(fb: FreeBusy) -> Option(String) {
  fb.organizer
}

pub fn freebusy_attendees(fb: FreeBusy) -> List(String) {
  fb.attendees
}

pub fn freebusy_periods(fb: FreeBusy) -> List(String) {
  fb.freebusy_periods
}

pub fn freebusy_x_properties(fb: FreeBusy) -> Dict(String, String) {
  fb.x_properties
}

// ============================================================
// Timezone accessors
// ============================================================

pub fn timezone_tzid(tz: Timezone) -> String {
  tz.tzid
}

pub fn timezone_last_modified(tz: Timezone) -> Option(schedule_ast.DateTime) {
  tz.last_modified
}

pub fn timezone_tzurl(tz: Timezone) -> Option(String) {
  tz.tzurl
}

pub fn timezone_standard(tz: Timezone) -> List(TimezoneRule) {
  tz.standard
}

pub fn timezone_daylight(tz: Timezone) -> List(TimezoneRule) {
  tz.daylight
}

pub fn timezone_x_properties(tz: Timezone) -> Dict(String, String) {
  tz.x_properties
}

// ============================================================
// Alarm accessors
// ============================================================

pub fn alarm_action(a: Alarm) -> String {
  a.action
}

pub fn alarm_trigger(a: Alarm) -> String {
  a.trigger
}

pub fn alarm_description(a: Alarm) -> Option(String) {
  a.description
}

pub fn alarm_summary(a: Alarm) -> Option(String) {
  a.summary
}

pub fn alarm_repeat(a: Alarm) -> Option(Int) {
  a.repeat
}

pub fn alarm_duration(a: Alarm) -> Option(String) {
  a.duration
}

pub fn alarm_attendees(a: Alarm) -> List(String) {
  a.attendees
}

pub fn alarm_x_properties(a: Alarm) -> Dict(String, String) {
  a.x_properties
}

// ============================================================
// Builders: Calendar
// ============================================================

pub fn new_calendar(
  version version: String,
  prod_id prod_id: String,
) -> Calendar {
  Calendar(
    version: version,
    product_id: prod_id,
    method: None,
    calscale: None,
    events_rev: [],
    todos_rev: [],
    journals_rev: [],
    freebusy_rev: [],
    timezones_rev: [],
    unknown_components_rev: [],
    x_properties: dict.new(),
  )
}

pub fn with_method(cal: Calendar, method: String) -> Calendar {
  Calendar(..cal, method: Some(method))
}

pub fn with_calscale(cal: Calendar, scale: String) -> Calendar {
  Calendar(..cal, calscale: Some(scale))
}

pub fn add_event(cal: Calendar, event: Event) -> Calendar {
  Calendar(..cal, events_rev: [event, ..cal.events_rev])
}

pub fn add_todo(cal: Calendar, t: Todo) -> Calendar {
  Calendar(..cal, todos_rev: [t, ..cal.todos_rev])
}

pub fn add_journal(cal: Calendar, j: Journal) -> Calendar {
  Calendar(..cal, journals_rev: [j, ..cal.journals_rev])
}

pub fn add_freebusy(cal: Calendar, fb: FreeBusy) -> Calendar {
  Calendar(..cal, freebusy_rev: [fb, ..cal.freebusy_rev])
}

pub fn add_timezone(cal: Calendar, tz: Timezone) -> Calendar {
  Calendar(..cal, timezones_rev: [tz, ..cal.timezones_rev])
}

pub fn add_unknown_component(
  cal: Calendar,
  component: UnknownComponent,
) -> Calendar {
  Calendar(..cal, unknown_components_rev: [
    component,
    ..cal.unknown_components_rev
  ])
}

pub fn with_calendar_x_property(
  cal: Calendar,
  name: String,
  value: String,
) -> Calendar {
  Calendar(..cal, x_properties: dict.insert(cal.x_properties, name, value))
}

// ============================================================
// Builders: Event
// ============================================================

pub fn new_event(
  uid uid: String,
  dtstamp dtstamp: schedule_ast.DateTime,
) -> Event {
  Event(
    uid: uid,
    dtstamp: dtstamp,
    dtstart: None,
    dtstart_tzid: None,
    dtend: None,
    dtend_tzid: None,
    duration: None,
    summary: None,
    description: None,
    location: None,
    status: None,
    organizer: None,
    attendees: [],
    categories: [],
    url: None,
    created: None,
    last_modified: None,
    sequence: 0,
    transparency: None,
    rrule: None,
    rdates: [],
    exdates: [],
    alarms: [],
    x_properties: dict.new(),
    forms: dict.new(),
  )
}

pub fn with_dtstart(event: Event, dt: schedule_ast.DateTime) -> Event {
  Event(
    ..event,
    dtstart: Some(dt),
    forms: replace_date_form(event.forms, "DTSTART", "DTEND"),
  )
}

pub fn with_dtstart_tzid(event: Event, tzid: String) -> Event {
  Event(..event, dtstart_tzid: Some(tzid))
}

pub fn with_dtend(event: Event, dt: schedule_ast.DateTime) -> Event {
  Event(
    ..event,
    dtend: Some(dt),
    forms: replace_date_form(event.forms, "DTEND", "DTSTART"),
  )
}

pub fn with_dtend_tzid(event: Event, tzid: String) -> Event {
  Event(..event, dtend_tzid: Some(tzid))
}

pub fn with_duration(event: Event, value: String) -> Event {
  Event(
    ..event,
    duration: Some(value),
    forms: dict.delete(event.forms, "DURATION"),
  )
}

pub fn with_summary(event: Event, value: String) -> Event {
  Event(
    ..event,
    summary: Some(value),
    forms: dict.delete(event.forms, "SUMMARY"),
  )
}

pub fn with_description(event: Event, value: String) -> Event {
  Event(
    ..event,
    description: Some(value),
    forms: dict.delete(event.forms, "DESCRIPTION"),
  )
}

pub fn with_location(event: Event, value: String) -> Event {
  Event(
    ..event,
    location: Some(value),
    forms: dict.delete(event.forms, "LOCATION"),
  )
}

pub fn with_status(event: Event, value: String) -> Event {
  Event(..event, status: Some(value), forms: dict.delete(event.forms, "STATUS"))
}

pub fn with_organizer(event: Event, value: String) -> Event {
  Event(
    ..event,
    organizer: Some(value),
    forms: dict.delete(event.forms, "ORGANIZER"),
  )
}

pub fn add_attendee(event: Event, value: String) -> Event {
  Event(
    ..event,
    attendees: list.append(event.attendees, [value]),
    forms: append_default_form(event.forms, "ATTENDEE"),
  )
}

pub fn add_category(event: Event, value: String) -> Event {
  Event(
    ..event,
    categories: list.append(event.categories, [value]),
    forms: append_default_form(event.forms, "CATEGORIES"),
  )
}

pub fn with_url(event: Event, value: String) -> Event {
  Event(..event, url: Some(value), forms: dict.delete(event.forms, "URL"))
}

pub fn with_created(event: Event, dt: schedule_ast.DateTime) -> Event {
  Event(..event, created: Some(dt), forms: dict.delete(event.forms, "CREATED"))
}

pub fn with_last_modified(event: Event, dt: schedule_ast.DateTime) -> Event {
  Event(
    ..event,
    last_modified: Some(dt),
    forms: dict.delete(event.forms, "LAST-MODIFIED"),
  )
}

pub fn with_sequence(event: Event, value: Int) -> Event {
  Event(..event, sequence: value, forms: dict.delete(event.forms, "SEQUENCE"))
}

pub fn with_transparency(event: Event, value: String) -> Event {
  Event(
    ..event,
    transparency: Some(value),
    forms: dict.delete(event.forms, "TRANSP"),
  )
}

pub fn with_rrule(event: Event, rule: rule_ast.RawRRule) -> Event {
  Event(..event, rrule: Some(rule), forms: dict.delete(event.forms, "RRULE"))
}

pub fn add_rdate(event: Event, dt: schedule_ast.DateTime) -> Event {
  Event(
    ..event,
    rdates: list.append(event.rdates, [dt]),
    forms: append_default_form(event.forms, "RDATE"),
  )
}

pub fn add_exdate(event: Event, dt: schedule_ast.DateTime) -> Event {
  Event(
    ..event,
    exdates: list.append(event.exdates, [dt]),
    forms: append_default_form(event.forms, "EXDATE"),
  )
}

pub fn add_alarm(event: Event, alarm: Alarm) -> Event {
  Event(..event, alarms: list.append(event.alarms, [alarm]))
}

pub fn with_event_x_property(
  event: Event,
  name: String,
  value: String,
) -> Event {
  Event(..event, x_properties: dict.insert(event.x_properties, name, value))
}

// ============================================================
// Builders: Todo
// ============================================================

pub fn new_todo(
  uid uid: String,
  dtstamp dtstamp: schedule_ast.DateTime,
) -> Todo {
  Todo(
    uid: uid,
    dtstamp: dtstamp,
    dtstart: None,
    due: None,
    completed: None,
    summary: None,
    description: None,
    status: None,
    percent_complete: None,
    priority: None,
    categories: [],
    rrule: None,
    rdates: [],
    exdates: [],
    alarms: [],
    x_properties: dict.new(),
    forms: dict.new(),
  )
}

pub fn with_todo_dtstart(t: Todo, dt: schedule_ast.DateTime) -> Todo {
  Todo(
    ..t,
    dtstart: Some(dt),
    forms: replace_date_form(t.forms, "DTSTART", "DUE"),
  )
}

pub fn with_todo_due(t: Todo, dt: schedule_ast.DateTime) -> Todo {
  Todo(..t, due: Some(dt), forms: replace_date_form(t.forms, "DUE", "DTSTART"))
}

pub fn with_todo_completed(t: Todo, dt: schedule_ast.DateTime) -> Todo {
  Todo(..t, completed: Some(dt), forms: dict.delete(t.forms, "COMPLETED"))
}

pub fn with_todo_summary(t: Todo, value: String) -> Todo {
  Todo(..t, summary: Some(value), forms: dict.delete(t.forms, "SUMMARY"))
}

pub fn with_todo_description(t: Todo, value: String) -> Todo {
  Todo(
    ..t,
    description: Some(value),
    forms: dict.delete(t.forms, "DESCRIPTION"),
  )
}

pub fn with_todo_status(t: Todo, value: String) -> Todo {
  Todo(..t, status: Some(value), forms: dict.delete(t.forms, "STATUS"))
}

pub fn with_todo_percent_complete(t: Todo, value: Int) -> Todo {
  Todo(
    ..t,
    percent_complete: Some(value),
    forms: dict.delete(t.forms, "PERCENT-COMPLETE"),
  )
}

pub fn with_todo_priority(t: Todo, value: Int) -> Todo {
  Todo(..t, priority: Some(value), forms: dict.delete(t.forms, "PRIORITY"))
}

pub fn add_todo_category(t: Todo, value: String) -> Todo {
  Todo(
    ..t,
    categories: list.append(t.categories, [value]),
    forms: append_default_form(t.forms, "CATEGORIES"),
  )
}

pub fn with_todo_rrule(t: Todo, rule: rule_ast.RawRRule) -> Todo {
  Todo(..t, rrule: Some(rule), forms: dict.delete(t.forms, "RRULE"))
}

pub fn add_todo_rdate(t: Todo, dt: schedule_ast.DateTime) -> Todo {
  Todo(
    ..t,
    rdates: list.append(t.rdates, [dt]),
    forms: append_default_form(t.forms, "RDATE"),
  )
}

pub fn add_todo_exdate(t: Todo, dt: schedule_ast.DateTime) -> Todo {
  Todo(
    ..t,
    exdates: list.append(t.exdates, [dt]),
    forms: append_default_form(t.forms, "EXDATE"),
  )
}

pub fn add_todo_alarm(t: Todo, alarm: Alarm) -> Todo {
  Todo(..t, alarms: list.append(t.alarms, [alarm]))
}

pub fn with_todo_x_property(t: Todo, name: String, value: String) -> Todo {
  Todo(..t, x_properties: dict.insert(t.x_properties, name, value))
}

// ============================================================
// Builders: Journal
// ============================================================

pub fn new_journal(
  uid uid: String,
  dtstamp dtstamp: schedule_ast.DateTime,
) -> Journal {
  Journal(
    uid: uid,
    dtstamp: dtstamp,
    dtstart: None,
    summary: None,
    description: None,
    status: None,
    categories: [],
    x_properties: dict.new(),
    forms: dict.new(),
  )
}

pub fn with_journal_dtstart(j: Journal, dt: schedule_ast.DateTime) -> Journal {
  Journal(..j, dtstart: Some(dt), forms: dict.delete(j.forms, "DTSTART"))
}

pub fn with_journal_summary(j: Journal, value: String) -> Journal {
  Journal(..j, summary: Some(value), forms: dict.delete(j.forms, "SUMMARY"))
}

pub fn with_journal_description(j: Journal, value: String) -> Journal {
  Journal(
    ..j,
    description: Some(value),
    forms: dict.delete(j.forms, "DESCRIPTION"),
  )
}

pub fn with_journal_status(j: Journal, value: String) -> Journal {
  Journal(..j, status: Some(value), forms: dict.delete(j.forms, "STATUS"))
}

pub fn add_journal_category(j: Journal, value: String) -> Journal {
  Journal(
    ..j,
    categories: list.append(j.categories, [value]),
    forms: append_default_form(j.forms, "CATEGORIES"),
  )
}

pub fn with_journal_x_property(
  j: Journal,
  name: String,
  value: String,
) -> Journal {
  Journal(..j, x_properties: dict.insert(j.x_properties, name, value))
}

// ============================================================
// Builders: FreeBusy
// ============================================================

pub fn new_freebusy(
  uid uid: String,
  dtstamp dtstamp: schedule_ast.DateTime,
) -> FreeBusy {
  FreeBusy(
    uid: uid,
    dtstamp: dtstamp,
    dtstart: None,
    dtend: None,
    organizer: None,
    attendees: [],
    freebusy_periods: [],
    x_properties: dict.new(),
    forms: dict.new(),
  )
}

pub fn with_freebusy_dtstart(
  fb: FreeBusy,
  dt: schedule_ast.DateTime,
) -> FreeBusy {
  FreeBusy(..fb, dtstart: Some(dt), forms: dict.delete(fb.forms, "DTSTART"))
}

pub fn with_freebusy_dtend(
  fb: FreeBusy,
  dt: schedule_ast.DateTime,
) -> FreeBusy {
  FreeBusy(..fb, dtend: Some(dt), forms: dict.delete(fb.forms, "DTEND"))
}

pub fn with_freebusy_organizer(fb: FreeBusy, value: String) -> FreeBusy {
  FreeBusy(
    ..fb,
    organizer: Some(value),
    forms: dict.delete(fb.forms, "ORGANIZER"),
  )
}

pub fn add_freebusy_attendee(fb: FreeBusy, value: String) -> FreeBusy {
  FreeBusy(
    ..fb,
    attendees: list.append(fb.attendees, [value]),
    forms: append_default_form(fb.forms, "ATTENDEE"),
  )
}

pub fn add_freebusy_period(fb: FreeBusy, value: String) -> FreeBusy {
  FreeBusy(
    ..fb,
    freebusy_periods: list.append(fb.freebusy_periods, [value]),
    forms: append_default_form(fb.forms, "FREEBUSY"),
  )
}

pub fn with_freebusy_x_property(
  fb: FreeBusy,
  name: String,
  value: String,
) -> FreeBusy {
  FreeBusy(..fb, x_properties: dict.insert(fb.x_properties, name, value))
}

// ============================================================
// Builders: Timezone
// ============================================================

pub fn new_timezone(tzid tzid: String) -> Timezone {
  Timezone(
    tzid: tzid,
    last_modified: None,
    tzurl: None,
    standard: [],
    daylight: [],
    x_properties: dict.new(),
  )
}

pub fn with_timezone_last_modified(
  tz: Timezone,
  dt: schedule_ast.DateTime,
) -> Timezone {
  Timezone(..tz, last_modified: Some(dt))
}

pub fn with_timezone_url(tz: Timezone, value: String) -> Timezone {
  Timezone(..tz, tzurl: Some(value))
}

pub fn add_timezone_standard(tz: Timezone, rule: TimezoneRule) -> Timezone {
  Timezone(..tz, standard: list.append(tz.standard, [rule]))
}

pub fn add_timezone_daylight(tz: Timezone, rule: TimezoneRule) -> Timezone {
  Timezone(..tz, daylight: list.append(tz.daylight, [rule]))
}

pub fn with_timezone_x_property(
  tz: Timezone,
  name: String,
  value: String,
) -> Timezone {
  Timezone(..tz, x_properties: dict.insert(tz.x_properties, name, value))
}

pub fn new_timezone_rule(
  dtstart dtstart: schedule_ast.DateTime,
  offset_from offset_from: String,
  offset_to offset_to: String,
) -> TimezoneRule {
  TimezoneRule(
    dtstart: dtstart,
    tzoffsetfrom: offset_from,
    tzoffsetto: offset_to,
    rrule: None,
    tzname: None,
  )
}

pub fn with_timezone_rule_rrule(
  rule: TimezoneRule,
  value: rule_ast.RawRRule,
) -> TimezoneRule {
  TimezoneRule(..rule, rrule: Some(value))
}

pub fn with_timezone_rule_name(
  rule: TimezoneRule,
  value: String,
) -> TimezoneRule {
  TimezoneRule(..rule, tzname: Some(value))
}

// ============================================================
// Builders: Alarm
// ============================================================

pub fn new_alarm(action action: String, trigger trigger: String) -> Alarm {
  Alarm(
    action: action,
    trigger: trigger,
    description: None,
    summary: None,
    repeat: None,
    duration: None,
    attendees: [],
    x_properties: dict.new(),
    forms: dict.new(),
  )
}

pub fn with_alarm_description(alarm: Alarm, value: String) -> Alarm {
  Alarm(
    ..alarm,
    description: Some(value),
    forms: dict.delete(alarm.forms, "DESCRIPTION"),
  )
}

pub fn with_alarm_summary(alarm: Alarm, value: String) -> Alarm {
  Alarm(
    ..alarm,
    summary: Some(value),
    forms: dict.delete(alarm.forms, "SUMMARY"),
  )
}

pub fn with_alarm_repeat(alarm: Alarm, value: Int) -> Alarm {
  Alarm(..alarm, repeat: Some(value), forms: dict.delete(alarm.forms, "REPEAT"))
}

pub fn with_alarm_duration(alarm: Alarm, value: String) -> Alarm {
  Alarm(
    ..alarm,
    duration: Some(value),
    forms: dict.delete(alarm.forms, "DURATION"),
  )
}

pub fn add_alarm_attendee(alarm: Alarm, value: String) -> Alarm {
  Alarm(
    ..alarm,
    attendees: list.append(alarm.attendees, [value]),
    forms: append_default_form(alarm.forms, "ATTENDEE"),
  )
}

pub fn with_alarm_x_property(
  alarm: Alarm,
  name: String,
  value: String,
) -> Alarm {
  Alarm(..alarm, x_properties: dict.insert(alarm.x_properties, name, value))
}
