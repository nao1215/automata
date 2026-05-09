import automata/cron/evaluator as cron_evaluator
import automata/rrule/evaluator as rule_evaluator
import automata/schedule
import automata/schedule/ast.{type DateTime}

pub fn matches(schedule schedule: schedule.Schedule, at at: DateTime) -> Bool {
  case schedule {
    schedule.CronSchedule(plan) -> cron_evaluator.matches(plan, at: at)
    schedule.RRuleSchedule(plan) -> rule_evaluator.matches(plan, at: at)
  }
}
