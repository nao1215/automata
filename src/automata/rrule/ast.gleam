//// Public runtime types for RRULE expressions (RFC 5545 §3.3.10) and
//// their validated / normalised forms. The parse / validate / iterate
//// entry points live in [`automata/rrule`](./rrule.html). Despite the
//// `ast` suffix, these are the domain types every RRULE caller needs at
//// runtime — `RawRulePart`, `RawRRule`, etc. — not parser internals.

pub type RawRulePart {
  RawRulePart(name: String, value: String)
}

pub type RawRRule {
  RawRRule(parts: List(RawRulePart))
}
