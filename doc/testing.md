# Testing

`just ci` runs everything below except the nightly job and mutation testing. Tests run on the Erlang and JavaScript targets, on the Gleam floor (1.14.0, OTP 27, Node 22) and on the latest Gleam 1.x, on Linux, macOS and Windows.

## Examples and unit tests

Every module has a test file under `test/automata/`: cron and RRULE parsing, validation and next-occurrence examples, iCalendar lexing, parsing and emitting, event filters and matchers, filesystem snapshot diffs and watch rules, retry policies and the calendar arithmetic in `automata/internal/calendar`.

## Generated properties

`test/automata_metamon_test.gleam` uses metamon: the parity automaton accepts exactly the inputs with an even number of ones and is deterministic, durations round-trip through milliseconds, retry policies give up when they must, and iCalendar text survives parse, encode, parse unchanged with line folding inside the 75-octet limit.

## Differential testing

`test/automata/cron_differential_test.gleam` compares two independent code paths of the cron engine. `next_after` and `iterator_after` search the normalised plan field by field, skipping whole hours, days and months; `matches` checks one instant against every field. For random expressions and start times, the answer of the fast search must be the first minute a minute-by-minute scan with `matches` accepts (checked over the first three days), the iterator's first two steps must equal `next_after` applied twice, and an inclusive boundary on a matching minute must yield that minute. The field choices include day-of-month and day-of-week restrictions together (POSIX fires when either matches), month ends, leap days, steps and lists.

## Nightly runs

`.github/workflows/nightly-property.yml` runs the whole suite ten times with `METAMON_RUNS_MULTIPLIER=10`, each pass with a new seed. A failure report prints its seed, so the case can be replayed with `metamon.with_seed` and kept as a regression test.

## Mutation testing

There is no mutation testing tool for Gleam, so `gleam_mutate.py` (from the mutation-testing lab in nao1215/debimate) is run by hand on a copy of the project. It rewrites one operator or boolean result at a time and runs `gleam test` on the Erlang target; a mutant that makes the suite hang past 120 seconds counts as killed. For this run the script also mutated integer comparisons and `+` / `-`. The score is killed / (killed + lived).

This run covered the cron modules (`automata/cron/*`) and `automata/internal/calendar`, the code the differential test above exercises; the RRULE, iCalendar, event, filesystem and retry modules (about 450 more mutants) are left for a later run.

| Date | Files | Killed | Lived | Score |
|---|---|---:|---:|---:|
| 2026-11-19, first run | `cron/*`, `internal/calendar` (199; one mutant did not compile) | 146 | 53 | 73.4% |
| 2026-11-19, after the calendar tests | same | 166 | 33 | 83.4% |

The first run showed that `is_valid_time`, `is_valid_date` and `is_valid_datetime` were never asked about their exact bounds (23:59:59, 24:00, the last day of a month), that `days_since_epoch` had no reference values, and that stepping backwards across a minute, hour, day, month and year boundary was untested. `test/automata/internal/calendar_test.gleam` now covers each, with `days_since_epoch` compared against Python's `date.toordinal()`. The survivors, grouped:

- `cron/validator` (12): range and step parsing at their exact bounds and the quartz-syntax rejection.
- `cron/iterator` (9) and `cron/evaluator` (3): the search jumps (`+ 1` to the next hour, day or month) where a smaller jump only costs extra steps and lands on the same answer, and the day-of-month / day-of-week shortcut branches.
- `internal/calendar` (6): `> 0` against `>= 0` on step counts that are never zero there, and the `set_month` / `set_year` clamp at its exact bound.
- `cron/parser` (3): whitespace characters other than space between fields.
