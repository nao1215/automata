# automata

[![CI](https://github.com/nao1215/automata/actions/workflows/ci.yml/badge.svg)](https://github.com/nao1215/automata/actions/workflows/ci.yml)
![Coverage](https://raw.githubusercontent.com/nao1215/octocovs-central-repo/main/badges/nao1215/automata/coverage.svg)
[![Gitleaks](https://github.com/nao1215/automata/actions/workflows/gitleaks.yml/badge.svg)](https://github.com/nao1215/automata/actions/workflows/gitleaks.yml)
[![Trivy](https://github.com/nao1215/automata/actions/workflows/trivy.yml/badge.svg)](https://github.com/nao1215/automata/actions/workflows/trivy.yml)
[![OSV-Scanner](https://github.com/nao1215/automata/actions/workflows/osv-scan.yml/badge.svg)](https://github.com/nao1215/automata/actions/workflows/osv-scan.yml)
[![Hex](https://img.shields.io/hexpm/v/automata)](https://hex.pm/packages/automata)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/automata/)
[![Hex Downloads](https://img.shields.io/hexpm/dt/automata)](https://hex.pm/packages/automata)
[![License](https://img.shields.io/github/license/nao1215/automata)](https://github.com/nao1215/automata/blob/main/LICENSE)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/nao1215/automata/badge)](https://scorecard.dev/viewer/?uri=github.com/nao1215/automata)

automata provides state transitions, cron and recurrence schedules, and retry decisions for Gleam. It compares filesystem snapshots, reads and writes iCalendar, and represents events with typed bodies and metadata. The APIs run on Erlang and JavaScript. Your application supplies the clock, executes scheduled work, reads files, and waits between retries.

## Installation

```sh
gleam add automata
```

## Usage

This automaton changes between two states for each input and accepts a sequence that ends in the active state:

```gleam
import automata
import gleam/bool
import gleam/io

pub fn main() {
  let toggle = automata.Automaton(
    initial_state: False,
    transition: fn(state, _) { !state },
    accepting: fn(state) { state },
  )

  automata.accepts(toggle, [Nil, Nil, Nil])
  |> bool.to_string
  |> io.println
  // True
}
```

## Reference

| Area | Operations |
|---|---|
| Finite automata | [Run transitions and test acceptance](https://hexdocs.pm/automata/automata.html#run) using your own state and input types. |
| Cron | [Parse five-field UNIX expressions](https://hexdocs.pm/automata/automata.html#cron_parse_raw) or construct validated field selectors. |
| Recurrence rules | [Parse RRULEs](https://hexdocs.pm/automata/automata.html#rrule_parse_raw) with seven frequencies, intervals, count or until limits, and supported BY filters. |
| Schedules | [Find occurrences](https://hexdocs.pm/automata/automata.html#schedule_next) from cron, RRULE, fixed intervals, or one-shot schedules using civil dates and explicit boundaries. |
| Events | [Construct events](https://hexdocs.pm/automata/automata.html#Event) with custom bodies, sources, correlation, causation, and trace metadata. Filter them with ordinary predicates. |
| Filesystem changes | [Compare snapshots](https://hexdocs.pm/automata/automata.html#diff_snapshots) for Create, Write, Remove, Rename, and Chmod operations. File identities support rename detection. |
| iCalendar | [Read calendar documents](https://hexdocs.pm/automata/automata.html#ical_parse) containing events, tasks, journals, free/busy periods, timezones, alarms, and unknown components. |
| Retry decisions | [Choose the next action](https://hexdocs.pm/automata/automata.html#retry_decide) using fixed, exponential, or capped delays, optional jitter, and a reproducible seed. Attempt limits include the initial attempt. |

Schedule dates are civil times at whole-second precision without timezone conversion. Search returns an error if it reaches its work limit or exceeds the target’s exact numeric range. The RRULE scheduler supports `BYDAY`, `BYMONTH`, `BYMONTHDAY`, `BYHOUR`, `BYMINUTE`, and Monday week starts. See the [full API reference](https://hexdocs.pm/automata/) for input limits, validation errors, and iCalendar property preservation.

## Development

See [CONTRIBUTING.md](https://github.com/nao1215/automata/blob/main/CONTRIBUTING.md) for setup, tests, and release verification. Report problems in [GitHub Issues](https://github.com/nao1215/automata/issues). Release history is in [CHANGELOG.md](https://github.com/nao1215/automata/blob/main/CHANGELOG.md).

## License

[MIT](https://github.com/nao1215/automata/blob/main/LICENSE).
