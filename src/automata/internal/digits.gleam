//// Zero-padded decimal rendering for date and time fields.

import gleam/int
import gleam/string

pub fn pad2(value: Int) -> String {
  string.pad_start(int.to_string(value), to: 2, with: "0")
}

/// At least four digits, with a leading minus sign before year 0 as in
/// ISO 8601 expanded years.
pub fn pad4(value: Int) -> String {
  case value < 0 {
    True -> "-" <> pad4(0 - value)
    False -> string.pad_start(int.to_string(value), to: 4, with: "0")
  }
}
