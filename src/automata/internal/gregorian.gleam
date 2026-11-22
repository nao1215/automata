//// Proleptic Gregorian calendar rules shared by `automata/schedule/ast`
//// and `automata/internal/calendar`. This module does not depend on the
//// schedule types, so both can import it.

import gleam/int
import gleam/result

fn is_leap_year(year: Int) -> Bool {
  let by_4 = modulo(year, 4)
  let by_100 = modulo(year, 100)
  let by_400 = modulo(year, 400)

  by_400 == 0 || { by_4 == 0 && by_100 != 0 }
}

/// Days in `month` of `year`, or 0 for a month outside 1 to 12.
pub fn days_in_month(year: Int, month: Int) -> Int {
  case month {
    1 | 3 | 5 | 7 | 8 | 10 | 12 -> 31
    4 | 6 | 9 | 11 -> 30
    2 ->
      case is_leap_year(year) {
        True -> 29
        False -> 28
      }
    _ -> 0
  }
}

fn modulo(dividend: Int, divisor: Int) -> Int {
  int.modulo(dividend, by: divisor) |> result.unwrap(0)
}
