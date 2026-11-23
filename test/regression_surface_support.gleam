import automata as a
import gleam/string
import gleam/time/calendar

pub fn jan(day: Int, hour: Int) -> a.DateTime {
  a.DateTime(
    calendar.Date(2026, calendar.January, day),
    calendar.TimeOfDay(hour, 0, 0, 0),
  )
}

pub fn imported_calendar() -> a.IcalCalendar {
  let assert Ok(value) = a.ical_parse(imported_wire())
  value
}

pub fn imported_wire() -> String {
  string.join(
    [
      "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Independent client//EN",
      "METHOD;X-OLD=method:REQUEST", "CALSCALE;X-OLD=scale:GREGORIAN",
      "X-CALENDAR;X-OLD=form:original", "X-KEEP:calendar-kept", "BEGIN:VEVENT",
      "UID:event-1", "DTSTAMP:20260101T030000Z",
      "DTSTART;TZID=Europe/Paris;X-WALL=start:20260101T090000",
      "DTEND;TZID=Europe/Paris;X-WALL=end:20260101T100000",
      "SUMMARY;LANGUAGE=en:Planning", "DESCRIPTION:Keep this description",
      "STATUS:TENTATIVE", "ORGANIZER;CN=Owner:mailto:owner@example.org",
      "ATTENDEE;CN=Alice:mailto:alice@example.org",
      "ATTENDEE;ROLE=OPT-PARTICIPANT:mailto:bob@example.org",
      "CATEGORIES;LANGUAGE=en:planning,team", "CREATED:20260101T010000Z",
      "LAST-MODIFIED:20260101T020000Z", "SEQUENCE;X-OLD=sequence:1",
      "TRANSP:OPAQUE", "RRULE;X-OLD=rule:FREQ=DAILY;COUNT=2",
      "RDATE;VALUE=DATE:20260103,20260104",
      "EXDATE;TZID=Europe/Paris:20260102T090000", "X-EVENT:kept", "END:VEVENT",
      "BEGIN:VEVENT", "UID:event-2", "DTSTAMP:20260101T030000Z", "DURATION:PT1H",
      "END:VEVENT", "BEGIN:VTODO", "UID:todo-1", "DTSTAMP:20260101T030000Z",
      "DTSTART;VALUE=DATE:20260102", "DUE;VALUE=DATE:20260103",
      "COMPLETED:20260104T120000Z", "SUMMARY:Prepare agenda",
      "DESCRIPTION;LANGUAGE=en:Old details", "STATUS;X-OLD=status:IN-PROCESS",
      "PERCENT-COMPLETE;X-OLD=percent:25", "PRIORITY;X-OLD=priority:5",
      "CATEGORIES;LANGUAGE=en:work,shared",
      "RRULE;X-OLD=rule:FREQ=DAILY;COUNT=3",
      "RDATE;VALUE=DATE:20260105,20260106", "EXDATE;VALUE=DATE:20260107",
      "X-TODO;X-OLD=form:todo-old", "X-KEEP:todo-kept", "BEGIN:VALARM",
      "ACTION:EMAIL", "TRIGGER;RELATED=START:-PT10M",
      "DESCRIPTION;LANGUAGE=en:Reminder", "SUMMARY;LANGUAGE=en:Old reminder",
      "REPEAT;X-OLD=repeat:2", "DURATION;X-OLD=duration:PT5M",
      "ATTENDEE;CN=Alice:mailto:alice@example.org",
      "ATTENDEE:mailto:bob@example.org", "X-ALARM;X-OLD=form:alarm-old",
      "X-KEEP:alarm-kept", "END:VALARM", "END:VTODO", "BEGIN:VJOURNAL",
      "UID:journal-1", "DTSTAMP:20260101T030000Z", "DTSTART;VALUE=DATE:20260102",
      "SUMMARY;LANGUAGE=en:Daily notes",
      "DESCRIPTION;LANGUAGE=en:Original journal", "STATUS;X-OLD=status:DRAFT",
      "CATEGORIES;LANGUAGE=en:notes,team", "X-JOURNAL;X-OLD=form:journal-old",
      "X-KEEP:journal-kept", "END:VJOURNAL", "BEGIN:VFREEBUSY", "UID:freebusy-1",
      "DTSTAMP:20260101T030000Z", "DTSTART:20260101T090000Z",
      "DTEND:20260101T180000Z", "ORGANIZER;CN=Owner:mailto:owner@example.org",
      "ATTENDEE;CN=Alice:mailto:alice@example.org",
      "ATTENDEE:mailto:bob@example.org",
      "FREEBUSY;FBTYPE=BUSY:20260101T100000Z/20260101T110000Z",
      "FREEBUSY;FBTYPE=BUSY-TENTATIVE:20260101T140000Z/PT1H",
      "X-FREEBUSY;X-OLD=form:freebusy-old", "X-KEEP:freebusy-kept",
      "END:VFREEBUSY", "BEGIN:VTIMEZONE", "TZID:Test/Office",
      "LAST-MODIFIED:20260101T020000Z",
      "TZURL;X-OLD=url:https://example.org/old-zone",
      "X-TIMEZONE;X-OLD=form:zone-old", "X-KEEP:zone-kept", "BEGIN:STANDARD",
      "DTSTART:20260101T020000", "TZOFFSETFROM:+0200", "TZOFFSETTO:+0100",
      "TZNAME;LANGUAGE=en:First standard",
      "RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU", "END:STANDARD",
      "BEGIN:STANDARD", "DTSTART:20260102T020000", "TZOFFSETFROM:+0300",
      "TZOFFSETTO:+0100", "TZNAME:Second standard", "END:STANDARD",
      "BEGIN:DAYLIGHT", "DTSTART:20260103T020000", "TZOFFSETFROM:+0100",
      "TZOFFSETTO:+0200", "TZNAME:Summer", "END:DAYLIGHT", "END:VTIMEZONE",
      "END:VCALENDAR", "",
    ],
    "\r\n",
  )
}

pub fn fresh() -> a.IcalCalendar {
  a.ical_new_calendar("2.0", "-//Independent client//EN")
}

pub fn wire(value: a.IcalCalendar) -> String {
  let assert Ok(text) = a.ical_encode(value)
  text
}

pub fn contains_line(wire: String, line: String) {
  assert string.contains(wire, "\r\n" <> line <> "\r\n")
}

pub fn excludes_text(wire: String, text: String) {
  assert !string.contains(wire, text)
}
