# automata

[![CI](https://github.com/nao1215/automata/actions/workflows/ci.yml/badge.svg)](https://github.com/nao1215/automata/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/automata)](https://hex.pm/packages/automata)

Finite automata helpers for Gleam.

This repository is scaffolded as a cross-target Gleam library with:

- `just` tasks for day-to-day development
- `mise` toolchain management
- GitHub Actions for CI and release
- starter `CONTRIBUTING.md`, `SECURITY.md`, and `CHANGELOG.md`

Current modules:

- `automata` - small deterministic automaton helpers
- `automata/cron` - pure cron parser and validator

## Requirements

- Gleam 1.15 or later
- Erlang/OTP 28 or later
- Node.js 22 or later (for JavaScript-target checks)
- [just](https://just.systems/) (recommended)
- [mise](https://mise.jdx.dev/) (recommended)

## Install

```sh
gleam add automata
```

## Development setup

```sh
git clone https://github.com/nao1215/automata.git
cd automata
mise install
just deps
```

`just` recipes source `scripts/lib/mise_bootstrap.sh`, so `mise activate`
is not required in the current shell.

## Quick start

```gleam
import automata
import gleam/io

pub type State {
  Even
  Odd
}

pub fn parity_machine() {
  automata.new(
    initial_state: Even,
    transition: fn(state, symbol) {
      case state, symbol {
        Even, 1 -> Odd
        Odd, 1 -> Even
        _, _ -> state
      }
    },
    accepting: fn(state) { state == Even },
  )
}

pub fn main() {
  let machine = parity_machine()

  automata.accepts(machine, [1, 0, 1, 1])
  |> io.debug
  // False
}
```

## Cron parser

`automata/cron` currently supports two dialects:

- UNIX 5-field: `minute hour day_of_month month day_of_week`
- AWS/EventBridge-style: `minute hour day_of_month month day_of_week [year]`

Choose the interpretation explicitly with `style:`:

- `cron.UnixStyle`
- `cron.AwsEventBridgeStyle`
- `cron.Auto`

Supported AWS-only tokens:

- `?` in day-of-month / day-of-week
- `L` in day-of-month, and `nL` in day-of-week
- `W` in day-of-month (`1W`)
- `#` in day-of-week (`3#2`)

The parser also rejects expressions that can never match a real
calendar date, such as `31 4 *` for UNIX-style schedules or
`cron(0 0 ? 2 2#5 2025)` for a fixed month/year without a fifth Monday.

Not supported in the current version:

- seconds field
- `@daily`-style macros
- Jenkins `H`
- full Quartz compatibility
- embedded timezone syntax

```gleam
import automata/cron
import gleam/io

pub fn main() {
  cron.parse("*/5 * * * *", style: cron.UnixStyle)
  |> io.debug

  cron.parse("cron(0 9 ? * MON-FRI *)", style: cron.AwsEventBridgeStyle)
  |> io.debug
}
```

Builder usage:

```gleam
import automata/cron

pub fn business_hours() {
  cron.builder(cron.Unix)
  |> cron.with_minute(cron.every(15))
  |> cron.with_hour(cron.between(from: 9, to: 17))
  |> cron.with_day_of_week(cron.DayOfWeekValues([cron.Range(1, 5)]))
  |> cron.build
}
```

## Commands

```sh
just ci
```

Runs format check, lint, type check, Erlang/JavaScript builds, and
Erlang/JavaScript tests.

## License

MIT
