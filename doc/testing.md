# Testing

`just ci` runs local formatting, lint, type checks, and both target suites using the configured local toolchain. GitHub CI separately tests Gleam 1.14.0 / OTP 27 / Node 22 on Ubuntu and the latest Gleam 1.x on Linux, macOS, and Windows. The local recipe does not run that CI matrix, nightly repetitions, or mutation testing.

## Public behavior and independent expectations

Tests under `test/` cover state machines, cron and all seven recurrence frequencies, civil schedules, generic and built-in events, filesystem snapshots and differences, every iCalendar component, and deterministic retry decisions. Public calls assert concrete outputs, validation errors, and state transitions. The API consolidation retains these checks while replacing old wrapper calls and private-plan access.

Boundary tests include negative and zero years, leap centuries, exact arithmetic at the JavaScript safe-year limits, nanosecond rejection, and core Duration admission. Huge-interval expectations use independently calculated Gregorian-cycle remainders. Distant COUNT and UNTIL cases check remaining occurrences instead of only comparing two library entry points. A search-limit error is distinct from a completed sequence.

Calendar tests preserve parameters, DATE/floating/UTC/TZID forms, repeated-value order, setter resets, unknown components, embedded U+FEFF, and 75-byte UTF-8 folding. Encoding tests distinguish typed TEXT newline normalization from rejection of physical newlines in non-TEXT fields. Date admission covers every component field that consumes a typed DateTime.

Retry tests retain seeded jitter sequences, caps, total-attempt limits, permanent-failure priority, and cumulative overflow. Filesystem tests cover path validation, content hash precedence, rename identities, ambiguous hardlinks, overwrites, operation masks, and stable ordering. No test expects the library to read a clock, watch files, or sleep.

## Generated properties and differential checks

Metamon exercises state-machine determinism and parity, schedule behavior, retry decisions, and iCalendar round trips. Round-trip expectations respect documented normalization: typed TEXT line endings become LF when encoded, while stored values remain unchanged.

Cron differential tests compare next-occurrence search with a minute-by-minute scan over bounded ranges. Their selector cases include day-of-month/day-of-week OR, month boundaries, leap days, lists, and steps. Literal calendar fixtures and independent arithmetic oracles supplement these comparisons because two paths can share a defect.

Regression reproduction uses external child-process timeouts for old implementations that do not terminate promptly. Those bounds contain the reproduction process; permanent tests assert dates, errors, and sequence state rather than wall-clock speed.

## Nightly runs

`.github/workflows/nightly-property.yml` runs the Erlang suite ten times with `METAMON_RUNS_MULTIPLIER=10`, drawing a fresh seed for each pass. A failure report prints its seed so it can be replayed with `metamon.with_seed` and retained as a regression case.

## Historical mutation runs


The historical mutation runs below used `gleam_mutate.py` from the mutation-testing lab in nao1215/debimate, run by hand on a copy of the project. It rewrote one operator or boolean result at a time and ran `gleam test` on the Erlang target; a mutant that makes the suite hang past 120 seconds was counted as killed. For this run the script also mutated integer comparisons and `+` / `-`. The score is killed / (killed + lived).

The 2026-11-19 run covered the cron modules (`automata/cron/*`) and `automata/internal/calendar`, the code the differential test above exercises; the RRULE, iCalendar, event, filesystem and retry modules (about 450 more mutants) were not measured in that run. The paths below refer to the source layout at that date; these scores do not measure the consolidated API.

| Date | Files | Killed | Lived | Score |
|---|---|---:|---:|---:|
| 2026-11-19, first run | `cron/*`, `internal/calendar` (199; one mutant did not compile) | 146 | 53 | 73.4% |
| 2026-11-19, after the calendar tests | same | 166 | 33 | 83.4% |

The first run showed that `is_valid_time`, `is_valid_date` and `is_valid_datetime` were never asked about their exact bounds (23:59:59, 24:00, the last day of a month), that `days_since_epoch` had no reference values, and that stepping backwards across a minute, hour, day, month and year boundary was untested. The added calendar tests covered each, with `days_since_epoch` compared against Python's `date.toordinal()`. The survivors, grouped:

- `cron/validator` (12): range and step parsing at their exact bounds and the quartz-syntax rejection.
- `cron/iterator` (9) and `cron/evaluator` (3): the search jumps (`+ 1` to the next hour, day or month) where a smaller jump only costs extra steps and lands on the same answer, and the day-of-month / day-of-week shortcut branches.
- `internal/calendar` (6): `> 0` against `>= 0` on step counts that are never zero there, and the `set_month` / `set_year` clamp at its exact bound.
- `cron/parser` (3): whitespace characters other than space between fields.
