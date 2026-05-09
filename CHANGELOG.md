# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `automata/cron`: pure cron parser/validator with support for UNIX
  5-field expressions and AWS/EventBridge-style expressions, including
  `?`, `L`, `W`, and `#` in the supported day fields.
- `automata/cron`: immutable builder API for constructing cron
  expressions without parsing strings.

### Changed

- `automata/cron`: reject cron expressions that can never match a real
  calendar date, including fixed non-leap-year `2/29`, impossible
  month-end combinations, and impossible `#5` weekday occurrences.
- Expanded cron coverage with roughly 100 meaningful parser and builder
  test patterns across UNIX, AWS/EventBridge, syntax/range errors, and
  calendar edge cases.

## [0.1.0] - 2026-05-08

### Added

- Initial Gleam project scaffold with cross-target CI, release workflow,
  `justfile`, `mise`, contribution guide, and security policy.
