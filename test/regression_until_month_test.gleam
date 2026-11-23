import automata as a
import gleam/time/calendar
import gleeunit/should

fn until(value: String) -> Result(a.RecurrenceRule, a.RruleValidationError) {
  let assert Ok(raw) = a.rrule_parse_raw(input: "FREQ=DAILY;UNTIL=" <> value)
  a.rrule_validate(raw: raw)
}

pub fn until_date_month_zero_is_an_error_test() {
  until("20260001")
  |> should.equal(Error(a.RruleUntilMalformedDateTime("20260001")))
}

pub fn until_date_month_thirteen_is_an_error_test() {
  until("20261301")
  |> should.equal(Error(a.RruleUntilMalformedDateTime("20261301")))
}

pub fn until_datetime_month_zero_is_an_error_test() {
  until("20260001T123456Z")
  |> should.equal(Error(a.RruleUntilMalformedDateTime("20260001T123456Z")))
}

pub fn until_datetime_month_thirteen_is_an_error_test() {
  until("20261301T123456Z")
  |> should.equal(Error(a.RruleUntilMalformedDateTime("20261301T123456Z")))
}

pub fn until_year_zero_leap_date_is_preserved_test() {
  let assert Ok(rule) = until("00000229")
  a.rrule_to_options(rule).end_condition
  |> should.equal(a.Until(a.UntilDate(calendar.Date(0, calendar.February, 29))))
}

pub fn until_year_zero_leap_datetime_is_preserved_test() {
  let assert Ok(rule) = until("00000229T123456Z")
  a.rrule_to_options(rule).end_condition
  |> should.equal(
    a.Until(
      a.UntilDateTime(a.DateTime(
        calendar.Date(0, calendar.February, 29),
        calendar.TimeOfDay(12, 34, 56, 0),
      )),
    ),
  )
}

pub fn until_century_nonleap_date_is_an_error_test() {
  until("19000229")
  |> should.equal(Error(a.RruleUntilMalformedDateTime("19000229")))
}

pub fn until_century_leap_date_is_preserved_test() {
  let assert Ok(rule) = until("20000229")
  a.rrule_to_options(rule).end_condition
  |> should.equal(
    a.Until(a.UntilDate(calendar.Date(2000, calendar.February, 29))),
  )
}
