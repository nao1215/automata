//// Public runtime types for cron expressions and their validated /
//// normalised forms. The parse / validate / iterate entry points live in
//// [`automata/cron`](./cron.html). Despite the `ast` suffix, these are
//// the domain types every cron caller needs at runtime — `Field`,
//// `Item`, `Selector`, `RawCron`, `ValidCron`, etc. — not parser
//// internals.

pub type Field {
  Expression
  Minute
  Hour
  DayOfMonth
  Month
  DayOfWeek
}

/// Raw UNIX cron expression after field splitting.
pub type RawCron {
  RawCron(
    minute: String,
    hour: String,
    day_of_month: String,
    month: String,
    day_of_week: String,
  )
}
