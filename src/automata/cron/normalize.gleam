import automata/cron/validator

pub type IntSet {
  AnyValue(min: Int, max: Int)
  Values(List(Int))
}

pub type CronPlan {
  CronPlan(
    minute: IntSet,
    hour: IntSet,
    day_of_month: IntSet,
    month: IntSet,
    day_of_week: IntSet,
  )
}

pub fn normalize(spec spec: validator.ValidCron) -> CronPlan {
  CronPlan(
    minute: normalize_selector(validator.minute(spec), 0, 59, False),
    hour: normalize_selector(validator.hour(spec), 0, 23, False),
    day_of_month: normalize_selector(validator.day_of_month(spec), 1, 31, False),
    month: normalize_selector(validator.month(spec), 1, 12, False),
    day_of_week: normalize_selector(validator.day_of_week(spec), 0, 6, True),
  )
}

fn normalize_selector(
  selector: validator.Selector,
  min: Int,
  max: Int,
  normalize_day_of_week: Bool,
) -> IntSet {
  case selector {
    validator.Any -> AnyValue(min:, max:)
    _ ->
      Values(validator.selector_values(
        selector,
        min,
        max,
        normalize_day_of_week: normalize_day_of_week,
      ))
  }
}
