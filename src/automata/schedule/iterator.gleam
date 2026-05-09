import automata/cron/iterator as cron_iterator
import automata/rrule/iterator as rule_iterator
import automata/schedule
import automata/schedule/ast.{type Boundary}

pub fn after(
  schedule schedule: schedule.Schedule,
  boundary boundary: Boundary,
) -> schedule.OccurrenceIterator {
  case schedule {
    schedule.CronSchedule(plan) ->
      schedule.CronOccurrences(cron_iterator.after(plan, boundary: boundary))
    schedule.RRuleSchedule(plan) ->
      schedule.RRuleOccurrences(rule_iterator.after(plan, boundary: boundary))
  }
}

pub fn step(iterator iterator: schedule.OccurrenceIterator) -> schedule.IterStep {
  case iterator {
    schedule.CronOccurrences(cursor) ->
      case cron_iterator.step(cursor) {
        cron_iterator.Yield(at:, next:) ->
          schedule.Yield(at:, next: schedule.CronOccurrences(next))
        cron_iterator.Done -> schedule.Done
      }
    schedule.RRuleOccurrences(cursor) ->
      case rule_iterator.step(cursor) {
        rule_iterator.Yield(at:, next:) ->
          schedule.Yield(at:, next: schedule.RRuleOccurrences(next))
        rule_iterator.Done -> schedule.Done
      }
  }
}
