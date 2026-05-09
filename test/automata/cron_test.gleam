import automata/cron
import gleam/list
import gleam/option.{None, Some}
import gleeunit/should

type ValidCase {
  ValidCase(
    input: String,
    style: cron.ParseStyle,
    canonical: String,
    dialect: cron.Dialect,
  )
}

type InvalidCase {
  InvalidCase(input: String, style: cron.ParseStyle, error: cron.ParseError)
}

fn assert_valid_cases(cases: List(ValidCase)) -> Nil {
  list.fold(cases, Nil, fn(_, test_case) {
    assert_valid_case(test_case)
    Nil
  })
}

fn assert_valid_case(test_case: ValidCase) -> Nil {
  let ValidCase(input:, style:, canonical:, dialect:) = test_case

  canonicalize(input, style)
  |> should.equal(Ok(#(canonical, dialect)))
}

fn assert_invalid_cases(cases: List(InvalidCase)) -> Nil {
  list.fold(cases, Nil, fn(_, test_case) {
    assert_invalid_case(test_case)
    Nil
  })
}

fn assert_invalid_case(test_case: InvalidCase) -> Nil {
  let InvalidCase(input:, style:, error:) = test_case

  cron.parse(input, style: style)
  |> should.equal(Error(error))
}

fn canonicalize(
  input: String,
  style: cron.ParseStyle,
) -> Result(#(String, cron.Dialect), cron.ParseError) {
  case cron.parse(input, style: style) {
    Ok(expression) -> Ok(#(cron.to_string(expression), expression.dialect))
    Error(error) -> Error(error)
  }
}

pub fn parse_accepts_meaningful_unix_patterns_test() {
  assert_valid_cases([
    ValidCase("* * * * *", cron.UnixStyle, "* * * * *", cron.Unix),
    ValidCase("*/5 * * * *", cron.UnixStyle, "*/5 * * * *", cron.Unix),
    ValidCase("0 * * * *", cron.Auto, "0 * * * *", cron.Unix),
    ValidCase("59 23 31 12 0", cron.UnixStyle, "59 23 31 12 0", cron.Unix),
    ValidCase("1,15,30 6 * * *", cron.UnixStyle, "1,15,30 6 * * *", cron.Unix),
    ValidCase("1-10/2 4 * * *", cron.UnixStyle, "1-10/2 4 * * *", cron.Unix),
    ValidCase("5 9 * JAN MON-FRI", cron.UnixStyle, "5 9 * 1 1-5", cron.Unix),
    ValidCase("0 0 29 FEB *", cron.UnixStyle, "0 0 29 2 *", cron.Unix),
    ValidCase(
      "0 0 31 JAN,MAR,MAY,JUL,AUG,OCT,DEC *",
      cron.UnixStyle,
      "0 0 31 1,3,5,7,8,10,12 *",
      cron.Unix,
    ),
    ValidCase("7 14 1 */2 *", cron.UnixStyle, "7 14 1 */2 *", cron.Unix),
    ValidCase("0 12 * * SUN", cron.UnixStyle, "0 12 * * 0", cron.Unix),
    ValidCase("0 12 * * SAT", cron.UnixStyle, "0 12 * * 6", cron.Unix),
    ValidCase("0 12 * * 7", cron.UnixStyle, "0 12 * * 7", cron.Unix),
    ValidCase(
      "15 10 15 * MON,WED,FRI",
      cron.UnixStyle,
      "15 10 15 * 1,3,5",
      cron.Unix,
    ),
    ValidCase("0 8 1-5 * *", cron.UnixStyle, "0 8 1-5 * *", cron.Unix),
    ValidCase("0 8 */3 * *", cron.UnixStyle, "0 8 */3 * *", cron.Unix),
    ValidCase("0 8 10-20/5 * *", cron.UnixStyle, "0 8 10-20/5 * *", cron.Unix),
    ValidCase("0 8 * 1-6/2 *", cron.UnixStyle, "0 8 * 1-6/2 *", cron.Unix),
    ValidCase("0 8 * * 1-5/2", cron.UnixStyle, "0 8 * * 1-5/2", cron.Unix),
    ValidCase("5 4 1 1 *", cron.UnixStyle, "5 4 1 1 *", cron.Unix),
    ValidCase("0 0 31 4 1", cron.Auto, "0 0 31 4 1", cron.Unix),
    ValidCase("0 0 29 2 1", cron.Auto, "0 0 29 2 1", cron.Unix),
    ValidCase("0 0 30,31 4 *", cron.UnixStyle, "0 0 30,31 4 *", cron.Unix),
    ValidCase("0 0 29 2 *", cron.UnixStyle, "0 0 29 2 *", cron.Unix),
    ValidCase("\t0  9  * *  1-5\n", cron.Auto, "0 9 * * 1-5", cron.Unix),
    ValidCase("0 0 1-31/7 * *", cron.UnixStyle, "0 0 1-31/7 * *", cron.Unix),
    ValidCase(
      "0 0 * 2,4,6,9,11 *",
      cron.UnixStyle,
      "0 0 * 2,4,6,9,11 *",
      cron.Unix,
    ),
  ])
}

pub fn parse_accepts_meaningful_aws_patterns_test() {
  assert_valid_cases([
    ValidCase(
      "cron(0 9 ? * MON-FRI *)",
      cron.Auto,
      "cron(0 9 ? * 2-6 *)",
      cron.AwsEventBridge,
    ),
    ValidCase(
      "0 18 ? * 2-6",
      cron.AwsEventBridgeStyle,
      "cron(0 18 ? * 2-6)",
      cron.AwsEventBridge,
    ),
    ValidCase(
      "cron(15 10 L * ? *)",
      cron.AwsEventBridgeStyle,
      "cron(15 10 L * ? *)",
      cron.AwsEventBridge,
    ),
    ValidCase(
      "cron(0 8 1W * ? *)",
      cron.AwsEventBridgeStyle,
      "cron(0 8 1W * ? *)",
      cron.AwsEventBridge,
    ),
    ValidCase(
      "cron(0 8 ? * 6L *)",
      cron.AwsEventBridgeStyle,
      "cron(0 8 ? * 6L *)",
      cron.AwsEventBridge,
    ),
    ValidCase(
      "cron(0 8 ? * 3#2 *)",
      cron.AwsEventBridgeStyle,
      "cron(0 8 ? * 3#2 *)",
      cron.AwsEventBridge,
    ),
    ValidCase(
      "cron(0 0 29 2 ? 2024)",
      cron.AwsEventBridgeStyle,
      "cron(0 0 29 2 ? 2024)",
      cron.AwsEventBridge,
    ),
    ValidCase(
      "cron(0 0 29 2 ? *)",
      cron.AwsEventBridgeStyle,
      "cron(0 0 29 2 ? *)",
      cron.AwsEventBridge,
    ),
    ValidCase(
      "cron(0 0 31 1,3,5,7,8,10,12 ? *)",
      cron.AwsEventBridgeStyle,
      "cron(0 0 31 1,3,5,7,8,10,12 ? *)",
      cron.AwsEventBridge,
    ),
    ValidCase(
      "cron(0 0 31 * ? *)",
      cron.AwsEventBridgeStyle,
      "cron(0 0 31 * ? *)",
      cron.AwsEventBridge,
    ),
    ValidCase(
      "cron(0 0 30,31 4 ? *)",
      cron.AwsEventBridgeStyle,
      "cron(0 0 30,31 4 ? *)",
      cron.AwsEventBridge,
    ),
    ValidCase(
      "cron(0 0 31W * ? *)",
      cron.AwsEventBridgeStyle,
      "cron(0 0 31W * ? *)",
      cron.AwsEventBridge,
    ),
    ValidCase(
      "cron(0 0 29W 2 ? *)",
      cron.AwsEventBridgeStyle,
      "cron(0 0 29W 2 ? *)",
      cron.AwsEventBridge,
    ),
    ValidCase(
      "cron(0 12 ? JAN MON *)",
      cron.AwsEventBridgeStyle,
      "cron(0 12 ? 1 2 *)",
      cron.AwsEventBridge,
    ),
    ValidCase(
      "cron(0 12 ? * SUN *)",
      cron.AwsEventBridgeStyle,
      "cron(0 12 ? * 1 *)",
      cron.AwsEventBridge,
    ),
    ValidCase(
      "cron(0 12 ? * SAT *)",
      cron.AwsEventBridgeStyle,
      "cron(0 12 ? * 7 *)",
      cron.AwsEventBridge,
    ),
    ValidCase(
      "cron(0 12 ? * MON,WED,FRI *)",
      cron.AwsEventBridgeStyle,
      "cron(0 12 ? * 2,4,6 *)",
      cron.AwsEventBridge,
    ),
    ValidCase(
      "cron(0 12 ? * 2-6/2 *)",
      cron.AwsEventBridgeStyle,
      "cron(0 12 ? * 2-6/2 *)",
      cron.AwsEventBridge,
    ),
    ValidCase(
      "cron(0 12 ? 1-6/2 MON *)",
      cron.AwsEventBridgeStyle,
      "cron(0 12 ? 1-6/2 2 *)",
      cron.AwsEventBridge,
    ),
    ValidCase(
      "cron(0 12 ? * 5#5 *)",
      cron.AwsEventBridgeStyle,
      "cron(0 12 ? * 5#5 *)",
      cron.AwsEventBridge,
    ),
    ValidCase(
      "cron(0 12 ? 2 2#5 *)",
      cron.AwsEventBridgeStyle,
      "cron(0 12 ? 2 2#5 *)",
      cron.AwsEventBridge,
    ),
    ValidCase(
      "0 9 ? * MON-FRI 2026",
      cron.AwsEventBridgeStyle,
      "cron(0 9 ? * 2-6 2026)",
      cron.AwsEventBridge,
    ),
    ValidCase(
      "0 9 ? * MON-FRI",
      cron.Auto,
      "cron(0 9 ? * 2-6)",
      cron.AwsEventBridge,
    ),
    ValidCase(
      "cron(0 9 * * ? *)",
      cron.AwsEventBridgeStyle,
      "cron(0 9 * * ? *)",
      cron.AwsEventBridge,
    ),
    ValidCase(
      "cron(0 9 1-15/7 * ? 2026)",
      cron.AwsEventBridgeStyle,
      "cron(0 9 1-15/7 * ? 2026)",
      cron.AwsEventBridge,
    ),
    ValidCase(
      "cron(5 4 L FEB ? 2024)",
      cron.AwsEventBridgeStyle,
      "cron(5 4 L 2 ? 2024)",
      cron.AwsEventBridge,
    ),
    ValidCase(
      "cron(0 0 ? * 1L 2026)",
      cron.AwsEventBridgeStyle,
      "cron(0 0 ? * 1L 2026)",
      cron.AwsEventBridge,
    ),
  ])
}

pub fn parse_rejects_invalid_syntax_and_ranges_test() {
  assert_invalid_cases([
    InvalidCase("", cron.Auto, cron.InvalidExpression(value: "")),
    InvalidCase(
      "* * * *",
      cron.Auto,
      cron.InvalidFieldCount(min_expected: 5, max_expected: 6, actual: 4),
    ),
    InvalidCase(
      "* * * * * * *",
      cron.Auto,
      cron.InvalidFieldCount(min_expected: 5, max_expected: 6, actual: 7),
    ),
    InvalidCase(
      "60 * * * *",
      cron.UnixStyle,
      cron.OutOfRange(field: cron.Minute, min: 0, max: 59, actual: 60),
    ),
    InvalidCase(
      "* 24 * * *",
      cron.UnixStyle,
      cron.OutOfRange(field: cron.Hour, min: 0, max: 23, actual: 24),
    ),
    InvalidCase(
      "* * 0 * *",
      cron.UnixStyle,
      cron.OutOfRange(field: cron.DayOfMonth, min: 1, max: 31, actual: 0),
    ),
    InvalidCase(
      "* * * 13 *",
      cron.UnixStyle,
      cron.OutOfRange(field: cron.Month, min: 1, max: 12, actual: 13),
    ),
    InvalidCase(
      "* * * * 8",
      cron.UnixStyle,
      cron.OutOfRange(field: cron.DayOfWeek, min: 0, max: 7, actual: 8),
    ),
    InvalidCase(
      "*/0 * * * *",
      cron.UnixStyle,
      cron.InvalidStep(field: cron.Minute, value: "*/0"),
    ),
    InvalidCase(
      "1-5/0 * * * *",
      cron.UnixStyle,
      cron.InvalidStep(field: cron.Minute, value: "1-5/0"),
    ),
    InvalidCase(
      "5-1 * * * *",
      cron.UnixStyle,
      cron.InvalidRange(field: cron.Minute, value: "5-1"),
    ),
    InvalidCase(
      "1,,2 * * * *",
      cron.UnixStyle,
      cron.InvalidList(field: cron.Minute, value: "1,,2"),
    ),
    InvalidCase(
      "FOO * * * *",
      cron.UnixStyle,
      cron.InvalidNumber(field: cron.Minute, value: "FOO"),
    ),
    InvalidCase(
      "* * * FOO *",
      cron.UnixStyle,
      cron.InvalidAlias(field: cron.Month, value: "FOO"),
    ),
    InvalidCase(
      "* * * * FOO",
      cron.UnixStyle,
      cron.InvalidAlias(field: cron.DayOfWeek, value: "FOO"),
    ),
    InvalidCase(
      "cron(0 9 * * MON-FRI *)",
      cron.AwsEventBridgeStyle,
      cron.InvalidDayFieldCombination(day_of_month: "*", day_of_week: "MON-FRI"),
    ),
    InvalidCase(
      "cron(0 9 ? * ? *)",
      cron.AwsEventBridgeStyle,
      cron.InvalidDayFieldCombination(day_of_month: "?", day_of_week: "?"),
    ),
    InvalidCase(
      "cron(0 9 ? * MON#0 *)",
      cron.AwsEventBridgeStyle,
      cron.OutOfRange(field: cron.DayOfWeek, min: 1, max: 5, actual: 0),
    ),
    InvalidCase(
      "cron(0 9 ? * MON#6 *)",
      cron.AwsEventBridgeStyle,
      cron.OutOfRange(field: cron.DayOfWeek, min: 1, max: 5, actual: 6),
    ),
    InvalidCase(
      "cron(0 9 ? * MON,TUE#2 *)",
      cron.AwsEventBridgeStyle,
      cron.UnsupportedSyntax(field: cron.DayOfWeek, value: "MON,TUE#2"),
    ),
    InvalidCase(
      "cron(0 9 ? * MON-FRI#2 *)",
      cron.AwsEventBridgeStyle,
      cron.UnsupportedSyntax(field: cron.DayOfWeek, value: "MON-FRI#2"),
    ),
    InvalidCase(
      "cron(0 9 ? * 2-3L *)",
      cron.AwsEventBridgeStyle,
      cron.UnsupportedSyntax(field: cron.DayOfWeek, value: "2-3L"),
    ),
    InvalidCase(
      "cron(0 9 32W * ? *)",
      cron.AwsEventBridgeStyle,
      cron.OutOfRange(field: cron.DayOfMonth, min: 1, max: 31, actual: 32),
    ),
    InvalidCase(
      "cron(0 9 ? * MON-FRI ?)",
      cron.AwsEventBridgeStyle,
      cron.UnsupportedSyntax(field: cron.Year, value: "?"),
    ),
    InvalidCase(
      "0 0 12 * * ?",
      cron.AwsEventBridgeStyle,
      cron.UnsupportedSyntax(field: cron.Year, value: "?"),
    ),
    InvalidCase(
      "cron(0 9 ? * 8L *)",
      cron.AwsEventBridgeStyle,
      cron.OutOfRange(field: cron.DayOfWeek, min: 1, max: 7, actual: 8),
    ),
    InvalidCase(
      "cron(0 9 W * ? *)",
      cron.AwsEventBridgeStyle,
      cron.UnsupportedSyntax(field: cron.DayOfMonth, value: "W"),
    ),
  ])
}

pub fn parse_rejects_impossible_calendar_patterns_test() {
  assert_invalid_cases([
    InvalidCase(
      "0 0 31 4 *",
      cron.UnixStyle,
      cron.ImpossibleDate(day_of_month: "31", month: "4", year: None),
    ),
    InvalidCase(
      "0 0 31 6 *",
      cron.UnixStyle,
      cron.ImpossibleDate(day_of_month: "31", month: "6", year: None),
    ),
    InvalidCase(
      "0 0 31 9 *",
      cron.UnixStyle,
      cron.ImpossibleDate(day_of_month: "31", month: "9", year: None),
    ),
    InvalidCase(
      "0 0 31 11 *",
      cron.UnixStyle,
      cron.ImpossibleDate(day_of_month: "31", month: "11", year: None),
    ),
    InvalidCase(
      "0 0 30 2 *",
      cron.UnixStyle,
      cron.ImpossibleDate(day_of_month: "30", month: "2", year: None),
    ),
    InvalidCase(
      "0 0 31 2 *",
      cron.UnixStyle,
      cron.ImpossibleDate(day_of_month: "31", month: "2", year: None),
    ),
    InvalidCase(
      "cron(0 0 29 2 ? 2025)",
      cron.AwsEventBridgeStyle,
      cron.ImpossibleDate(day_of_month: "29", month: "2", year: Some("2025")),
    ),
    InvalidCase(
      "cron(0 0 29 2 ? 2100)",
      cron.AwsEventBridgeStyle,
      cron.ImpossibleDate(day_of_month: "29", month: "2", year: Some("2100")),
    ),
    InvalidCase(
      "cron(0 0 30 2 ? *)",
      cron.AwsEventBridgeStyle,
      cron.ImpossibleDate(day_of_month: "30", month: "2", year: Some("*")),
    ),
    InvalidCase(
      "cron(0 0 31 4 ? *)",
      cron.AwsEventBridgeStyle,
      cron.ImpossibleDate(day_of_month: "31", month: "4", year: Some("*")),
    ),
    InvalidCase(
      "cron(0 0 31 6 ? *)",
      cron.AwsEventBridgeStyle,
      cron.ImpossibleDate(day_of_month: "31", month: "6", year: Some("*")),
    ),
    InvalidCase(
      "cron(0 0 31 9 ? *)",
      cron.AwsEventBridgeStyle,
      cron.ImpossibleDate(day_of_month: "31", month: "9", year: Some("*")),
    ),
    InvalidCase(
      "cron(0 0 31 11 ? *)",
      cron.AwsEventBridgeStyle,
      cron.ImpossibleDate(day_of_month: "31", month: "11", year: Some("*")),
    ),
    InvalidCase(
      "cron(0 0 31W 4 ? *)",
      cron.AwsEventBridgeStyle,
      cron.ImpossibleDate(day_of_month: "31W", month: "4", year: Some("*")),
    ),
    InvalidCase(
      "cron(0 0 31W 2 ? 2024)",
      cron.AwsEventBridgeStyle,
      cron.ImpossibleDate(day_of_month: "31W", month: "2", year: Some("2024")),
    ),
    InvalidCase(
      "cron(0 0 29W 2 ? 2025)",
      cron.AwsEventBridgeStyle,
      cron.ImpossibleDate(day_of_month: "29W", month: "2", year: Some("2025")),
    ),
    InvalidCase(
      "cron(0 0 30-31 2 ? 2025)",
      cron.AwsEventBridgeStyle,
      cron.ImpossibleDate(day_of_month: "30-31", month: "2", year: Some("2025")),
    ),
    InvalidCase(
      "cron(0 0 29-31 2 ? 2025)",
      cron.AwsEventBridgeStyle,
      cron.ImpossibleDate(day_of_month: "29-31", month: "2", year: Some("2025")),
    ),
    InvalidCase(
      "cron(0 0 ? 2 1#5 2025)",
      cron.AwsEventBridgeStyle,
      cron.ImpossibleWeekdayOccurrence(
        day_of_week: "1#5",
        month: "2",
        year: Some("2025"),
      ),
    ),
    InvalidCase(
      "cron(0 0 ? 2 2#5 2025)",
      cron.AwsEventBridgeStyle,
      cron.ImpossibleWeekdayOccurrence(
        day_of_week: "2#5",
        month: "2",
        year: Some("2025"),
      ),
    ),
    InvalidCase(
      "cron(0 0 ? 2 3#5 2025)",
      cron.AwsEventBridgeStyle,
      cron.ImpossibleWeekdayOccurrence(
        day_of_week: "3#5",
        month: "2",
        year: Some("2025"),
      ),
    ),
    InvalidCase(
      "cron(0 0 ? 2 4#5 2025)",
      cron.AwsEventBridgeStyle,
      cron.ImpossibleWeekdayOccurrence(
        day_of_week: "4#5",
        month: "2",
        year: Some("2025"),
      ),
    ),
    InvalidCase(
      "cron(0 0 ? 2 5#5 2025)",
      cron.AwsEventBridgeStyle,
      cron.ImpossibleWeekdayOccurrence(
        day_of_week: "5#5",
        month: "2",
        year: Some("2025"),
      ),
    ),
    InvalidCase(
      "cron(0 0 ? 2 6#5 2025)",
      cron.AwsEventBridgeStyle,
      cron.ImpossibleWeekdayOccurrence(
        day_of_week: "6#5",
        month: "2",
        year: Some("2025"),
      ),
    ),
    InvalidCase(
      "cron(0 0 ? 2 7#5 2025)",
      cron.AwsEventBridgeStyle,
      cron.ImpossibleWeekdayOccurrence(
        day_of_week: "7#5",
        month: "2",
        year: Some("2025"),
      ),
    ),
    InvalidCase(
      "cron(0 0 ? 4 1#5 2025)",
      cron.AwsEventBridgeStyle,
      cron.ImpossibleWeekdayOccurrence(
        day_of_week: "1#5",
        month: "4",
        year: Some("2025"),
      ),
    ),
    InvalidCase(
      "cron(0 0 ? 4 2#5 2025)",
      cron.AwsEventBridgeStyle,
      cron.ImpossibleWeekdayOccurrence(
        day_of_week: "2#5",
        month: "4",
        year: Some("2025"),
      ),
    ),
  ])
}

pub fn builder_builds_unix_expression_test() {
  cron.builder(cron.Unix)
  |> cron.with_minute(cron.every(5))
  |> cron.with_hour(cron.at(9))
  |> cron.with_day_of_week(cron.DayOfWeekValues([cron.Range(1, 5)]))
  |> cron.build
  |> should.equal(cron.parse("*/5 9 * * 1-5", style: cron.UnixStyle))
}

pub fn builder_builds_aws_expression_test() {
  cron.builder(cron.AwsEventBridge)
  |> cron.with_minute(cron.at(0))
  |> cron.with_hour(cron.at(9))
  |> cron.with_day_of_month(cron.NoSpecificDayOfMonth)
  |> cron.with_day_of_week(cron.DayOfWeekValues([cron.Range(2, 6)]))
  |> cron.with_year(cron.at(2026))
  |> cron.build
  |> should.equal(cron.parse(
    "cron(0 9 ? * 2-6 2026)",
    style: cron.AwsEventBridgeStyle,
  ))
}

pub fn builder_rejects_unix_year_field_test() {
  cron.builder(cron.Unix)
  |> cron.with_year(cron.at(2026))
  |> cron.build
  |> should.equal(
    Error(cron.UnsupportedSyntax(field: cron.Year, value: "2026")),
  )
}

pub fn builder_rejects_empty_field_list_test() {
  cron.builder(cron.Unix)
  |> cron.with_minute(cron.one_of([]))
  |> cron.build
  |> should.equal(Error(cron.EmptyField(field: cron.Minute)))
}

pub fn builder_rejects_impossible_date_test() {
  cron.builder(cron.AwsEventBridge)
  |> cron.with_minute(cron.at(0))
  |> cron.with_hour(cron.at(0))
  |> cron.with_day_of_month(cron.DayOfMonthValues([cron.Exact(29)]))
  |> cron.with_month(cron.at(2))
  |> cron.with_day_of_week(cron.NoSpecificDayOfWeek)
  |> cron.with_year(cron.at(2025))
  |> cron.build
  |> should.equal(
    Error(cron.ImpossibleDate(
      day_of_month: "29",
      month: "2",
      year: Some("2025"),
    )),
  )
}

pub fn builder_rejects_impossible_weekday_occurrence_test() {
  cron.builder(cron.AwsEventBridge)
  |> cron.with_minute(cron.at(0))
  |> cron.with_hour(cron.at(0))
  |> cron.with_day_of_month(cron.NoSpecificDayOfMonth)
  |> cron.with_month(cron.at(2))
  |> cron.with_day_of_week(cron.NthWeekdayOfMonth(2, 5))
  |> cron.with_year(cron.at(2025))
  |> cron.build
  |> should.equal(
    Error(cron.ImpossibleWeekdayOccurrence(
      day_of_week: "2#5",
      month: "2",
      year: Some("2025"),
    )),
  )
}

pub fn to_string_renders_by_dialect_test() {
  let assert Ok(unix) = cron.parse("0 9 * * 1-5", style: cron.UnixStyle)
  cron.to_string(unix) |> should.equal("0 9 * * 1-5")

  let assert Ok(aws) =
    cron.parse("cron(0 9 ? * MON-FRI *)", style: cron.AwsEventBridgeStyle)
  cron.to_string(aws) |> should.equal("cron(0 9 ? * 2-6 *)")
}
