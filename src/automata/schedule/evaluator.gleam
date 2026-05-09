import automata/cron/evaluator as cron_evaluator
import automata/rrule/evaluator as rule_evaluator
import automata/schedule
import automata/schedule/ast.{type ValidDateTime} as schedule_ast

pub fn matches(
  schedule schedule: schedule.Schedule,
  at at: ValidDateTime,
) -> Bool {
  let raw = schedule_ast.valid_datetime_value(at)
  case schedule {
    schedule.CronSchedule(plan) -> cron_evaluator.matches(plan, at: raw)
    schedule.RRuleSchedule(plan) -> rule_evaluator.matches(plan, at: raw)
  }
}
