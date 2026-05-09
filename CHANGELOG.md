# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `automata/cron/{ast,parser,validator,normalize,evaluator,iterator,next,builder}`
  as a composable UNIX 5-field cron stack.
- `automata/rrule/{ast,parser,validator,normalize,evaluator,iterator,next,builder}`
  as a composable RFC 5545 RRULE stack for the initial supported subset.
- `automata/schedule` plus `automata/schedule/{ast,evaluator,iterator,next}`
  as a shared abstraction over compiled cron and RRULE schedules.
- Matching and next-occurrence calculation for both cron and RRULE.
- Iterator-based occurrence generation for both cron and RRULE.
- Anchor-aware RRULE normalization with typed builder APIs.

### Changed

- `automata/cron` is now a breaking, UNIX-only API with explicit phase
  separation between parse, validate, normalize, evaluate, iterate, and
  next-occurrence logic.
- `automata/rrule` is now a breaking, subset-focused API with explicit
  parsing, validation, normalization, matching, iteration, and
  next-occurrence boundaries.
- Project metadata and README now describe `automata` as a schedule
  library in addition to the original finite automata helper.

### Removed

- AWS/EventBridge cron support from the public `automata/cron` facade.
- Quartz- and Jenkins-style cron syntax from the supported surface.
- Unsupported RRULE parts from the public contract, including
  `BYSECOND`, `BYYEARDAY`, `BYWEEKNO`, `BYSETPOS`, and `WKST`.

## [0.1.0] - 2026-05-08

### Added

- Initial Gleam project scaffold with cross-target CI, release workflow,
  `justfile`, `mise`, contribution guide, and security policy.
