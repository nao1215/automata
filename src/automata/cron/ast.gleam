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
