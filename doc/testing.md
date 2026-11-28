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

`.github/workflows/nightly-property.yml` runs the Erlang suite ten times with `METAMON_RUNS_MULTIPLIER=10`, drawing a fresh seed for each pass. A failure report prints its seed so it can be replayed with `metamon.Config(..metamon.default_config(), seed: Some(seed))` and retained as a regression case.

## Coverage

`gleam run -m metamon/mutation -- coverage` (`just coverage`) runs the tests on the Erlang target with every module under `src/` measured and writes `build/coverage/lcov.info`. It needs Gleam 1.19 or later, newer than the floor the package supports, because older compilers do not keep the Gleam line numbers that `cover` reports. Run `gleam build --target erlang` first (`just coverage` does), since `gleam run -m` of a dependency module does not compile the package. `.github/workflows/coverage.yml` reports it with octocov on pull requests and main. The first run (2026-11-28) reached 94.7% of the lines (2454 of 2590).

## Mutation testing

`gleam run -m metamon/mutation` changes one operator, `!` or boolean literal in a module under `src/` at a time and runs `gleam test --target erlang` on each change. `.github/workflows/mutation.yml` mutates the modules a pull request or push changes and fails on a survivor that `doc/mutation/baseline.json` does not list; the weekly run mutates every module. `just mutation` runs it locally and `just mutation-record` records the baseline. The score is (killed + timed out) / (killed + timed out + lived). Some mutants loop forever and allocate without end; since metamon 0.18.0 a test process that grows past 1 GiB is killed and the mutant counts as killed.

The first run (2026-11-27) scored 73.4% with 178 survivors. Tests were then added for retry caps, jitter against an independent Xorshift32 model and delay overflow at the safe-integer limit; iCalendar date and time components at their bounds, folding at exactly 75 octets and at UTF-8 boundaries, physical line numbers, the VALUE parameter and local DTSTART in a VTIMEZONE; cron field separators, single-value ranges, step spans, the value 7 outside day of week and missing operands; RRULE ordinal weekdays, extreme negative ordinals, UNTIL in year 9999, month 0, empty parts, COUNT with an exclusive boundary, intervals and occurrences across the 400-year Gregorian cycle and sub-daily phases, with expected values from python-dateutil; and daily steps through a leap year. The score rose to 89.8%. The 68 survivors left give the same results on Erlang, apart from the last group:

- Code for JavaScript only (25): the exact-integer and year-joining checks of the civil calendar, which only matter where integers are doubles, and an error `civil_datetime` never returns on Erlang.
- Branches that earlier checks rule out, or results nobody reads (12): content hashes compared only when both exist, day and ordinal 0 rejected by validation, a week-start flag never read after parsing, a `None` the caller discards, deleting a missing key, and periods longer than a day that always start at second 0.
- Boundaries where both branches agree (7): a delay exactly at its cap, a modulo of 1, values already inside their field, leap-year checks repeated by an earlier pass, and seconds that are normalised anyway.
- Shortcuts that only change the amount of work (13): the fixed-step fast path, early cut-offs in the time search, an over-counted COUNT that still reaches its limit, the skip-ahead guard, and one unit of the search budget.
- Stop conditions another check repeats (9): extra empty periods scanned before UNTIL stops the search, and the guard against crons that never fire, which validation already rejects.
- Mutants that recurse without end in the cron range builders (2): the tests kill them, but the test run is cut short in a way the runner counts as passing, so they are recorded as survivors.

<!-- mutation:start -->
| Module | Killed | Lived | Timed out | Score |
|---|---:|---:|---:|---:|
| `automata` | 597 | 67 | 2 | 89.9% |
| `automata/retry/internal/prng` | 1 | 1 | 0 | 50.0% |
| all | 598 | 68 | 2 | 89.8% |
<!-- mutation:end -->
