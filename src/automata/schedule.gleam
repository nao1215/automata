import automata/cron/iterator as cron_iterator
import automata/cron/normalize as cron_normalize
import automata/cron/validator as cron_validator
import automata/rrule/iterator as rule_iterator
import automata/rrule/normalize as rule_normalize
import automata/rrule/validator as rule_validator
import automata/schedule/ast.{type ValidDateTime} as schedule_ast

pub type Schedule {
  CronSchedule(cron_normalize.CronPlan)
  RRuleSchedule(rule_normalize.RRulePlan)
}

pub type OccurrenceIterator {
  CronOccurrences(cron_iterator.CronIterator)
  RRuleOccurrences(rule_iterator.RRuleIterator)
}

pub type IterStep {
  Yield(at: ValidDateTime, next: OccurrenceIterator)
  Done
}

pub fn from_cron(spec spec: cron_validator.ValidCron) -> Schedule {
  spec
  |> cron_normalize.normalize
  |> CronSchedule
}

pub fn from_rrule(
  spec spec: rule_validator.ValidRRule,
  anchor anchor: ValidDateTime,
) -> Result(Schedule, rule_normalize.NormalizeError) {
  case
    rule_normalize.normalize(
      spec,
      anchor: schedule_ast.valid_datetime_value(anchor),
    )
  {
    Ok(plan) -> Ok(RRuleSchedule(plan))
    Error(error) -> Error(error)
  }
}
