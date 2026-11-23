//// Compute state transitions, schedules, filesystem differences, calendar documents, and retry decisions.
////
//// All operations are pure and run on Erlang and JavaScript. Your application supplies dates and filesystem observations, executes scheduled work, and waits between retries.
////
//// ## Choosing an operation
////
//// | Area | Start here |
//// | --- | --- |
//// | Finite state machines | `Automaton`, `run`, `accepts` |
//// | Cron | `cron_parse_raw`, `cron_validate`, `cron_new` |
//// | Recurrence rules | `rrule_parse_raw`, `rrule_validate`, `rrule_new` |
//// | Occurrences | `schedule_from_cron`, `schedule_from_rrule`, `schedule_every`, `schedule_next` |
//// | Events | `Event`, `builtin_event`, `event_continue_from` |
//// | Filesystem changes | `path_normalize`, `snapshot_from_entries`, `diff_snapshots` |
//// | iCalendar | `ical_parse`, `ical_new_calendar`, `ical_encode` |
//// | Retries | `retry_fixed`, `retry_exponential`, `retry_start`, `retry_decide` |
////
//// ## Civil dates and schedules
////
//// `DateTime` uses Date and TimeOfDay from gleam_time's calendar module. Validate a real Gregorian date and zero nanoseconds with `datetime_validate`. These civil values carry no timezone; a TZID in an iCalendar document does not change schedule arithmetic.
////
//// Build a reusable Schedule from validated cron or recurrence input. A recurring rule keeps its original anchor and total COUNT when a query starts later. Use `schedule_iterator` for an inclusive or exclusive boundary and `schedule_step` for each occurrence. `Done` and `Ok(None)` describe established endings. Work-limit and numeric-range failures remain errors, so callers can distinguish a finished sequence from an incomplete search.
////
//// ## iCalendar values and forms
////
//// The calendar model covers VEVENT, VTODO, VJOURNAL, VFREEBUSY, VTIMEZONE, VALARM, and unknown nested components. Parsed values retain supported parameters and DATE, floating, UTC, or TZID forms. Scalar updates reset their property's preserved form, including when the value is unchanged; repeated-value additions preserve earlier values and forms. Getters return stored values in order.
////
//// Constructors and updates do not perform complete RFC validation. `ical_encode` checks typed dates, wire years, and raw physical newlines, then escapes TEXT and folds UTF-8 lines. It normalizes typed TEXT line endings during encoding; it does not change values returned by getters. Components are emitted in groups while preserving order within each kind.
////
//// ## Retry decisions
////
//// Retry policies use gleam_time Duration values with nonnegative whole-millisecond precision. The attempt limit includes the initial attempt. A context's seed makes jitter reproducible. `retry_decide` returns a delay and next context or a reason to give up; the application performs the wait and the next attempt.

import automata/retry/internal/prng
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{type Order, Eq, Gt, Lt}
import gleam/result
import gleam/set.{type Set}
import gleam/string
import gleam/time/calendar
import gleam/time/duration

/// A deterministic state machine with caller-supplied transition and acceptance functions.
///
/// The state and input symbol may be any types. `run` folds inputs from the initial state; `accepts` tests the resulting state.
pub type Automaton(state, symbol) {
  Automaton(
    initial_state: state,
    transition: fn(state, symbol) -> state,
    accepting: fn(state) -> Bool,
  )
}

/// Apply the transition function to each input, starting from the initial state.
///
/// Return the final state. Empty input returns `initial_state`; acceptance is not checked.
pub fn run(automaton: Automaton(state, symbol), inputs: List(symbol)) -> state {
  list.fold(inputs, automaton.initial_state, fn(state, symbol) {
    automaton.transition(state, symbol)
  })
}

/// Run the input sequence and test its final state with the accepting predicate.
///
/// An empty sequence tests the initial state.
pub fn accepts(
  automaton: Automaton(state, symbol),
  inputs: List(symbol),
) -> Bool {
  automaton.accepting(run(automaton, inputs))
}

/// An iCalendar lexical, structural, or supported typed-value error. Nested RRULE syntax errors retain their original details.
pub type IcalError {
  IcalUnexpectedEnd(line: Int)
  IcalMismatchedBlock(begin: String, end: String, line: Int)
  IcalMalformedProperty(line: Int, raw: String)
  IcalMalformedParameter(line: Int, raw: String)
  IcalMissingVersion
  IcalMissingProductId
  IcalMissingComponentProperty(component: String, name: String)
  IcalInvalidDateTime(name: String, raw: String)
  IcalInvalidEscape(raw: String)
  IcalInvalidInteger(name: String, raw: String)
  IcalInvalidRRule(raw: String, error: RruleParseError)
  IcalDuplicateRRule(component_uid: String)
  IcalEmptyInputError
}

/// Parse and validate an iCalendar document.
///
/// Return typed events, tasks, journals, free/busy components, timezones, alarms, and unknown components. Preserve supported property parameters and date forms. See `ical_parse_raw` for physical input handling and `ical_validate` for the validation boundary.
pub fn ical_parse(input: String) -> Result(IcalCalendar, IcalError) {
  use raw <- result.try(ical_parse_raw(input))
  ical_validate(raw)
}

/// A reusable cron, recurrence, fixed-interval, or one-shot schedule with validated inputs and private lookup data.
pub opaque type Schedule {
  PlanCron(plan: CronPlan)
  PlanRecurrence(plan: RecurrencePlan)
  PlanEvery(plan: EveryPlan)
  PlanOnce(at: DateTime)
}

type EveryPlan {
  EveryPlan(anchor: DateTime, interval_seconds: Int)
}

/// An immutable schedule position with its original anchor and consumed occurrence count.
///
/// Stepping returns a new position without changing the old one. This value owns no process, clock, or external resource.
pub opaque type OccurrenceIterator {
  CronOccurrences(plan: CronPlan, boundary: Boundary)
  RRuleOccurrences(plan: RecurrencePlan, boundary: Boundary, yielded: Int)
  EveryOccurrences(plan: EveryPlan, boundary: Boundary)
  OnceOccurrences(at: DateTime, eligible: Bool)
}

/// An occurrence with its continuation, or the established end of a sequence. Search failures are returned separately as errors.
pub type IterStep {
  Yield(at: ValidDateTime, next: OccurrenceIterator)
  Done
}

/// Compile a validated cron specification into a reusable schedule.
///
/// Occurrences fall at second zero. The schedule holds its lookup data, so it can be reused for matching and iteration.
pub fn schedule_from_cron(cron: Cron) -> Schedule {
  PlanCron(compile_cron(spec: cron))
}

/// Anchor a validated recurrence rule and prepare its schedule.
///
/// The anchor supplies omitted date/time fields according to frequency. COUNT counts occurrences from this anchor, including when a later query starts partway through the sequence. Invalid calendar dates are skipped rather than clamped. UNTIL includes its final date or second.
pub fn schedule_from_rrule(
  rule: RecurrenceRule,
  anchor anchor: ValidDateTime,
) -> Schedule {
  PlanRecurrence(compile_recurrence(spec: rule, anchor: anchor))
}

fn schedule_every_matches(plan: EveryPlan, at: DateTime) -> Bool {
  !internal_calendar_less_than(at, plan.anchor)
  && civil_seconds_modulo(plan.anchor, at, plan.interval_seconds) == 0
}

fn schedule_once_eligible(at: DateTime, boundary: Boundary) -> Bool {
  case boundary {
    Inclusive(valid) -> internal_calendar_less_or_equal(valid.value, at)
    Exclusive(valid) -> internal_calendar_less_than(valid.value, at)
  }
}

/// An event with an arbitrary body, producer, civil occurrence time, and metadata.
///
/// This is an ordinary record. The caller chooses its source/body combination; `builtin_event` derives the source kind for the built-in body variants.
pub type Event(body) {
  Event(
    id: String,
    occurred_at: ValidDateTime,
    source: Source,
    body: body,
    metadata: Metadata,
  )
}

/// Create an event with a new body while carrying the parent's metadata forward.
///
/// Set causation to the parent's id. Preserve its correlation id, including an absent correlation id. Preserve trace id and attributes. The new body may have a different type from the parent's.
pub fn event_continue_from(
  parent parent: Event(parent_body),
  id id: String,
  occurred_at occurred_at: ValidDateTime,
  source source: Source,
  body body: body,
) -> Event(body) {
  let parent_meta = parent.metadata
  let chained =
    Metadata(
      correlation_id: parent_meta.correlation_id,
      causation_id: Some(parent.id),
      trace_id: parent_meta.trace_id,
      attributes: parent_meta.attributes,
    )
  Event(
    id: id,
    occurred_at: occurred_at,
    source: source,
    body: body,
    metadata: chained,
  )
}

const retry_max_safe_milliseconds: Int = 9_007_199_254_740_991

/// Whether the failed operation may be retried. Permanent failures stop before policy and attempt-limit checks.
pub type FailureKind {
  Transient
  Permanent
}

/// Why a retry decision stops: policy, total attempt limit, permanent failure, or delay overflow.
pub type GiveUpReason {
  PolicyDisallowsRetry
  MaxAttemptsReached(attempts: Int, limit: Int)
  PermanentFailureSignaled(at_attempt: Int)
  DelayOverflow(at_attempt: Int)
}

/// An invalid retry duration or policy parameter.
///
/// Duration admission checks negative seconds first, fractional milliseconds second, and the supported maximum last. Duration errors preserve the normalized seconds/nanoseconds pair. Policy constructors document their argument-check order.
pub type RetryError {
  NegativeDuration(seconds: Int, nanoseconds: Int)
  FractionalMilliseconds(seconds: Int, nanoseconds: Int)
  DurationOverflow(seconds: Int, nanoseconds: Int)
  MaxAttemptsMustBePositive(actual: Int)
  MultiplierMustBeAtLeastTwo(actual: Int)
  InitialDelayMustBePositive(actual_milliseconds: Int)
  CapMustNotBeLessThanInitial(cap_milliseconds: Int, initial_milliseconds: Int)
}

/// How a retry policy varies its base delay in integer milliseconds using the context seed.
pub type Jitter {
  NoJitter
  FullJitter
  EqualJitter
}

fn retry_duration_milliseconds(duration duration: duration.Duration) -> Int {
  let #(seconds, nanoseconds) = duration.to_seconds_and_nanoseconds(duration)
  seconds * 1000 + nanoseconds / 1_000_000
}

/// A validated retry strategy with an optional jitter mode.
///
/// Durations are nonnegative whole milliseconds bounded by 9,007,199,254,740,991 milliseconds. Attempt limits count the initial attempt as well as retries.
pub opaque type RetryPolicy {
  NoRetry
  Fixed(delay: duration.Duration, max_attempts: Int, jitter: Jitter)
  Exponential(
    initial: duration.Duration,
    multiplier: Int,
    max_attempts: Int,
    jitter: Jitter,
  )
  CappedExponential(
    initial: duration.Duration,
    multiplier: Int,
    cap: duration.Duration,
    max_attempts: Int,
    jitter: Jitter,
  )
}

/// An immutable retry state containing its policy, attempt number, random state, and cumulative selected delay.
pub opaque type RetryContext {
  RetryContext(
    policy: RetryPolicy,
    attempt: Int,
    cumulative_delay: duration.Duration,
    prng: prng.PrngState,
  )
}

/// A delay and context for another attempt, or a reason to give up. The caller performs the wait and operation.
pub type RetryDecision {
  Retry(delay: duration.Duration, next: RetryContext)
  GiveUp(reason: GiveUpReason)
}

/// Return a policy that never schedules another attempt.
pub fn retry_no_retry() -> RetryPolicy {
  NoRetry
}

/// Create a policy with a fixed delay between attempts.
///
/// Check that max_attempts is positive, then validate the delay. Zero delay is allowed. Delays must be nonnegative whole milliseconds no greater than 9,007,199,254,740,991 milliseconds. The attempt limit includes the initial attempt.
///
/// ## Examples
///
/// ```gleam
/// import gleam/time/duration
///
/// retry_fixed(duration.milliseconds(100), 0)
/// // Error(MaxAttemptsMustBePositive(0))
///
/// let assert Ok(policy) = retry_fixed(duration.milliseconds(100), 2)
/// let context = retry_start(policy, seed: 42)
/// let assert Retry(delay, next) = retry_decide(context, failure: Transient)
/// duration.to_seconds_and_nanoseconds(delay)
/// // #(0, 100_000_000)
/// retry_current_attempt(next)
/// // 1
/// ```
pub fn retry_fixed(
  delay delay: duration.Duration,
  max_attempts max_attempts: Int,
) -> Result(RetryPolicy, RetryError) {
  case max_attempts <= 0 {
    True -> Error(MaxAttemptsMustBePositive(max_attempts))
    False -> {
      use Nil <- result.try(retry_admit_duration(delay))
      Ok(Fixed(delay, max_attempts, NoJitter))
    }
  }
}

/// Create an exponential retry policy.
///
/// The first retry uses the initial delay; each later retry multiplies it by the multiplier. Check the duration, then require a positive initial delay, multiplier at least two, and positive max_attempts. The attempt limit includes the initial attempt. A delay that exceeds the supported range during execution gives up with `DelayOverflow`.
pub fn retry_exponential(
  initial initial: duration.Duration,
  multiplier multiplier: Int,
  max_attempts max_attempts: Int,
) -> Result(RetryPolicy, RetryError) {
  use Nil <- result.try(retry_admit_duration(initial))
  use Nil <- result.try(retry_validate_exponential_params(
    initial,
    multiplier,
    max_attempts,
  ))
  Ok(Exponential(initial, multiplier, max_attempts, NoJitter))
}

/// Create an exponential retry policy with a maximum base delay.
///
/// Validate the initial duration and cap first, then require a positive initial delay, multiplier at least two, positive max_attempts, and cap at least initial. Apply the cap before jitter. Both durations must be nonnegative whole milliseconds within the supported range.
pub fn retry_capped_exponential(
  initial initial: duration.Duration,
  multiplier multiplier: Int,
  cap cap: duration.Duration,
  max_attempts max_attempts: Int,
) -> Result(RetryPolicy, RetryError) {
  use Nil <- result.try(retry_admit_duration(initial))
  use Nil <- result.try(retry_admit_duration(cap))
  use Nil <- result.try(retry_validate_exponential_params(
    initial,
    multiplier,
    max_attempts,
  ))
  let initial_ms = retry_duration_milliseconds(duration: initial)
  let cap_ms = retry_duration_milliseconds(duration: cap)
  case cap_ms < initial_ms {
    True -> Error(CapMustNotBeLessThanInitial(cap_ms, initial_ms))
    False ->
      Ok(CappedExponential(initial, multiplier, cap, max_attempts, NoJitter))
  }
}

/// Choose how the policy varies each retry delay.
///
/// NoJitter keeps the base delay. FullJitter chooses an integer number of milliseconds from zero through the base; EqualJitter chooses from half the base, rounded down, through the base. Choices are determined by the context's seed.
pub fn retry_jitter(
  policy policy: RetryPolicy,
  jitter jitter: Jitter,
) -> RetryPolicy {
  case policy {
    NoRetry -> NoRetry
    Fixed(delay: d, max_attempts: m, jitter: _) ->
      Fixed(delay: d, max_attempts: m, jitter: jitter)
    Exponential(initial: i, multiplier: mu, max_attempts: m, jitter: _) ->
      Exponential(initial: i, multiplier: mu, max_attempts: m, jitter: jitter)
    CappedExponential(
      initial: i,
      multiplier: mu,
      cap: c,
      max_attempts: m,
      jitter: _,
    ) ->
      CappedExponential(
        initial: i,
        multiplier: mu,
        cap: c,
        max_attempts: m,
        jitter: jitter,
      )
  }
}

/// Start a deterministic retry context at attempt zero with no accumulated delay.
///
/// The same policy, seed, and failure sequence produce the same decisions on both targets. The context computes decisions and does not sleep or perform the work.
pub fn retry_start(policy policy: RetryPolicy, seed seed: Int) -> RetryContext {
  RetryContext(
    policy: policy,
    attempt: 0,
    cumulative_delay: duration.milliseconds(0),
    prng: retry_warm_up(prng.new(seed: seed), 3),
  )
}

fn retry_warm_up(state: prng.PrngState, draws: Int) -> prng.PrngState {
  case draws <= 0 {
    True -> state
    False -> {
      let #(_, next) = prng.next_u32(state: state)
      retry_warm_up(next, draws - 1)
    }
  }
}

/// Read the zero-based attempt number in the context.
pub fn retry_current_attempt(ctx ctx: RetryContext) -> Int {
  ctx.attempt
}

/// Read the total delay selected by earlier retry decisions.
pub fn retry_cumulative_delay(ctx ctx: RetryContext) -> duration.Duration {
  ctx.cumulative_delay
}

/// Read the policy held by the retry context.
pub fn retry_policy(ctx ctx: RetryContext) -> RetryPolicy {
  ctx.policy
}

/// Choose whether to retry after the current attempt fails.
///
/// A permanent failure gives up before policy or attempt-limit checks. For a transient failure, apply the policy, attempt limit, delay range, jitter, and cumulative-delay range. `Retry` returns the delay and the context for the next attempt; callers execute that action themselves.
pub fn retry_decide(
  ctx ctx: RetryContext,
  failure failure: FailureKind,
) -> RetryDecision {
  let next_attempt = ctx.attempt + 1
  case failure {
    Permanent ->
      GiveUp(reason: PermanentFailureSignaled(at_attempt: next_attempt))
    Transient ->
      case ctx.policy {
        NoRetry -> GiveUp(reason: PolicyDisallowsRetry)
        Fixed(delay: d, max_attempts: m, jitter: j) ->
          retry_decide_fixed(ctx, d, m, j, next_attempt)
        Exponential(initial: i, multiplier: mu, max_attempts: m, jitter: j) ->
          retry_decide_exponential(ctx, i, mu, None, m, j, next_attempt)
        CappedExponential(
          initial: i,
          multiplier: mu,
          cap: c,
          max_attempts: m,
          jitter: j,
        ) -> retry_decide_exponential(ctx, i, mu, Some(c), m, j, next_attempt)
      }
  }
}

fn retry_validate_exponential_params(
  initial: duration.Duration,
  multiplier: Int,
  max_attempts: Int,
) -> Result(Nil, RetryError) {
  case retry_duration_milliseconds(duration: initial) <= 0 {
    True ->
      Error(
        InitialDelayMustBePositive(
          actual_milliseconds: retry_duration_milliseconds(duration: initial),
        ),
      )
    False ->
      case multiplier < 2 {
        True -> Error(MultiplierMustBeAtLeastTwo(actual: multiplier))
        False ->
          case max_attempts <= 0 {
            True -> Error(MaxAttemptsMustBePositive(actual: max_attempts))
            False -> Ok(Nil)
          }
      }
  }
}

fn retry_decide_fixed(
  ctx: RetryContext,
  delay: duration.Duration,
  max_attempts: Int,
  jitter: Jitter,
  next_attempt: Int,
) -> RetryDecision {
  case next_attempt >= max_attempts {
    True ->
      GiveUp(reason: MaxAttemptsReached(
        attempts: next_attempt,
        limit: max_attempts,
      ))
    False -> {
      let base_ms = retry_duration_milliseconds(duration: delay)
      let #(final_ms, next_prng) = retry_apply_jitter(base_ms, jitter, ctx.prng)
      retry_finish_decision(ctx, final_ms, next_attempt, next_prng)
    }
  }
}

fn retry_decide_exponential(
  ctx: RetryContext,
  initial: duration.Duration,
  multiplier: Int,
  cap: Option(duration.Duration),
  max_attempts: Int,
  jitter: Jitter,
  next_attempt: Int,
) -> RetryDecision {
  case next_attempt >= max_attempts {
    True ->
      GiveUp(reason: MaxAttemptsReached(
        attempts: next_attempt,
        limit: max_attempts,
      ))
    False -> {
      let initial_ms = retry_duration_milliseconds(duration: initial)
      let cap_ms = case cap {
        Some(c) -> Some(retry_duration_milliseconds(duration: c))
        None -> None
      }
      case
        retry_compute_exponential_base(
          initial_ms,
          multiplier,
          next_attempt,
          cap_ms,
        )
      {
        Error(Nil) -> GiveUp(reason: DelayOverflow(at_attempt: next_attempt))
        Ok(base_ms) -> {
          let #(final_ms, next_prng) =
            retry_apply_jitter(base_ms, jitter, ctx.prng)
          retry_finish_decision(ctx, final_ms, next_attempt, next_prng)
        }
      }
    }
  }
}

fn retry_compute_exponential_base(
  initial_ms: Int,
  multiplier: Int,
  next_attempt: Int,
  cap_ms: Option(Int),
) -> Result(Int, Nil) {
  retry_exponential_step(initial_ms, multiplier, next_attempt - 1, cap_ms)
}

fn retry_exponential_step(
  current: Int,
  multiplier: Int,
  remaining_steps: Int,
  cap_ms: Option(Int),
) -> Result(Int, Nil) {
  case remaining_steps <= 0 {
    True ->
      case cap_ms {
        Some(c) ->
          case current > c {
            True -> Ok(c)
            False -> Ok(current)
          }
        None -> Ok(current)
      }
    False ->
      case cap_ms {
        Some(c) ->
          case current >= c {
            True -> Ok(c)
            False ->
              retry_advance_or_overflow(
                current,
                multiplier,
                remaining_steps,
                cap_ms,
              )
          }
        None ->
          retry_advance_or_overflow(
            current,
            multiplier,
            remaining_steps,
            cap_ms,
          )
      }
  }
}

fn retry_advance_or_overflow(
  current: Int,
  multiplier: Int,
  remaining_steps: Int,
  cap_ms: Option(Int),
) -> Result(Int, Nil) {
  case current > retry_max_safe_milliseconds / multiplier {
    True ->
      case cap_ms {
        Some(c) -> Ok(c)
        None -> Error(Nil)
      }
    False ->
      retry_exponential_step(
        current * multiplier,
        multiplier,
        remaining_steps - 1,
        cap_ms,
      )
  }
}

fn retry_apply_jitter(
  base_ms: Int,
  jitter: Jitter,
  state: prng.PrngState,
) -> #(Int, prng.PrngState) {
  case jitter {
    NoJitter -> {
      let #(_, next) = prng.next_u32(state: state)
      #(base_ms, next)
    }
    FullJitter -> retry_uniform(state, base_ms)
    EqualJitter -> {
      let half = base_ms / 2
      let #(extra, next) = retry_uniform(state, base_ms - half)
      #(half + extra, next)
    }
  }
}

const retry_max_u32 = 0xFFFFFFFF

fn retry_uniform(
  state: prng.PrngState,
  max_inclusive: Int,
) -> #(Int, prng.PrngState) {
  case max_inclusive <= retry_max_u32 {
    True -> prng.bounded(state: state, max_inclusive: max_inclusive)
    False -> {
      let #(high, state) = prng.next_u32(state: state)
      let #(low, state) = prng.next_u32(state: state)
      let wide = int.bitwise_and(high, 0x1FFFFF) * { retry_max_u32 + 1 } + low
      #(wide % { max_inclusive + 1 }, state)
    }
  }
}

fn retry_finish_decision(
  ctx: RetryContext,
  final_ms: Int,
  next_attempt: Int,
  next_prng: prng.PrngState,
) -> RetryDecision {
  let prev_cum = retry_duration_milliseconds(duration: ctx.cumulative_delay)
  case final_ms > retry_max_safe_milliseconds - prev_cum {
    True -> GiveUp(reason: DelayOverflow(at_attempt: next_attempt))
    False -> {
      let new_cum = duration.milliseconds(prev_cum + final_ms)
      Retry(
        delay: duration.milliseconds(final_ms),
        next: RetryContext(
          policy: ctx.policy,
          attempt: next_attempt,
          cumulative_delay: new_cum,
          prng: next_prng,
        ),
      )
    }
  }
}

fn filesystem_diff_diff(
  prev prev: Snapshot,
  curr curr: Snapshot,
  watch watch: Set(Op),
) -> List(WatchEvent) {
  // A watch without Rename gets the Remove and Create pair, so a move is
  // still visible to a Create or Remove subscriber.
  let fold_renames = set.contains(watch, Rename)
  let renames = case fold_renames {
    True -> filesystem_diff_detect_renames(prev, curr)
    False -> dict.new()
  }
  let suppressed_old_paths =
    filesystem_diff_renames_suppressed_paths(renames, curr)
  let union = filesystem_diff_path_union(prev, curr)

  union
  |> list.filter_map(fn(key) {
    case set.contains(suppressed_old_paths, key) {
      True -> Error(Nil)
      False ->
        filesystem_diff_build_event_for(key, prev, curr, renames)
        |> filesystem_diff_apply_op_mask(watch)
    }
  })
  |> list.sort(fn(a, b) {
    string.compare(
      path_to_string(path: filesystem_event_path(event: a)),
      path_to_string(path: filesystem_event_path(event: b)),
    )
  })
}

fn filesystem_diff_compare_entry(
  old old: Option(Entry),
  new new: Option(Entry),
) -> Set(Op) {
  case old, new {
    None, None -> set.new()
    None, Some(e) -> filesystem_diff_ops_for_creation(e)
    Some(_), None -> set.from_list([Remove])
    Some(o), Some(n) ->
      case entry_kind(entry: o) == entry_kind(entry: n) {
        False -> set.from_list([Remove, Create])
        True -> filesystem_diff_ops_for_modification(o, n)
      }
  }
}

fn filesystem_diff_replaced(old: Entry, new: Entry) -> Bool {
  case entry_file_id(entry: old), entry_file_id(entry: new) {
    Some(old_id), Some(new_id) -> old_id != new_id
    _, _ -> False
  }
}

fn filesystem_diff_ops_for_creation(e: Entry) -> Set(Op) {
  case entry_kind(entry: e) {
    File ->
      case entry_size(entry: e) > 0 {
        True -> set.from_list([Create, Write])
        False -> set.from_list([Create])
      }
    Directory | Symlink -> set.from_list([Create])
  }
}

fn filesystem_diff_ops_for_modification(old: Entry, new: Entry) -> Set(Op) {
  let mode_changed = entry_mode(entry: old) != entry_mode(entry: new)
  let content_changed = filesystem_diff_content_changed(old, new)
  case content_changed, mode_changed {
    False, False -> set.new()
    False, True -> set.from_list([Chmod])
    True, False -> set.from_list([Write])
    True, True -> set.from_list([Write, Chmod])
  }
}

fn filesystem_diff_content_changed(old: Entry, new: Entry) -> Bool {
  case filesystem_entry_entries_have_both_hashes(a: old, b: new) {
    True -> !filesystem_entry_entries_content_hash_equal(a: old, b: new)
    False ->
      entry_size(entry: old) != entry_size(entry: new)
      || entry_mtime(entry: old) != entry_mtime(entry: new)
  }
}

fn filesystem_diff_build_event_for(
  key: String,
  prev: Snapshot,
  curr: Snapshot,
  renames: Dict(String, NormalizedPath),
) -> Result(WatchEvent, Nil) {
  let prev_entry = filesystem_snapshot_lookup_by_key(prev, key)
  let curr_entry = filesystem_snapshot_lookup_by_key(curr, key)
  let base_ops = case prev_entry, curr_entry {
    // A changed identity is a replacement even when metadata is unchanged.
    // apply_rename folds this pair only if this path is a rename destination.
    Some(o), Some(n) ->
      case filesystem_diff_replaced(o, n) {
        True -> set.insert(filesystem_diff_ops_for_creation(n), Remove)
        False -> filesystem_diff_compare_entry(old: prev_entry, new: curr_entry)
      }
    _, _ -> filesystem_diff_compare_entry(old: prev_entry, new: curr_entry)
  }
  let #(final_ops, renamed_from) =
    filesystem_diff_apply_rename(key, base_ops, prev, curr_entry, renames)
  case set.size(final_ops) == 0 {
    True -> Error(Nil)
    False -> {
      let target_path = filesystem_diff_primary_path(curr_entry, prev_entry)
      case target_path {
        None -> Error(Nil)
        Some(p) ->
          case
            filesystem_event(
              path: p,
              ops: final_ops,
              renamed_from: renamed_from,
            )
          {
            Ok(ev) -> Ok(ev)
            Error(_) -> Error(Nil)
          }
      }
    }
  }
}

fn filesystem_diff_apply_rename(
  key: String,
  base_ops: Set(Op),
  prev: Snapshot,
  curr_entry: Option(Entry),
  renames: Dict(String, NormalizedPath),
) -> #(Set(Op), Option(NormalizedPath)) {
  case curr_entry {
    None -> #(base_ops, None)
    Some(curr) ->
      case dict.get(renames, key) {
        Error(Nil) -> #(base_ops, None)
        Ok(from) -> {
          // For renames we recompute the modification ops between the
          // entry at the *old* path and the new path's entry: a pure
          // rename emits {Rename}, a rename whose contents also changed
          // emits {Rename, Write} or {Rename, Write, Chmod}.
          let from_key = path_to_string(path: from)
          let prev_at_from = filesystem_snapshot_lookup_by_key(prev, from_key)
          let modification_ops = case prev_at_from {
            Some(old) -> filesystem_diff_ops_for_modification(old, curr)
            None -> set.delete(base_ops, Create)
          }
          let with_rename = set.insert(modification_ops, Rename)
          #(with_rename, Some(from))
        }
      }
  }
}

fn filesystem_diff_apply_op_mask(
  result: Result(WatchEvent, Nil),
  watch: Set(Op),
) -> Result(WatchEvent, Nil) {
  use event <- result.try(result)
  let masked = set.intersection(event.ops, watch)
  case set.is_empty(masked) {
    True -> Error(Nil)
    False -> {
      let renamed_from = case set.contains(masked, Rename) {
        True -> event.renamed_from
        False -> None
      }
      Ok(WatchEvent(event.path, masked, renamed_from))
    }
  }
}

fn filesystem_diff_primary_path(
  curr_entry: Option(Entry),
  prev_entry: Option(Entry),
) -> Option(NormalizedPath) {
  case curr_entry {
    Some(e) -> Some(entry_path(entry: e))
    None ->
      case prev_entry {
        Some(e) -> Some(entry_path(entry: e))
        None -> None
      }
  }
}

fn filesystem_diff_path_union(prev: Snapshot, curr: Snapshot) -> List(String) {
  let prev_keys = set.from_list(filesystem_snapshot_paths(prev))
  let curr_keys = set.from_list(filesystem_snapshot_paths(curr))
  set.union(prev_keys, curr_keys)
  |> set.to_list
}

fn filesystem_diff_detect_renames(
  prev: Snapshot,
  curr: Snapshot,
) -> Dict(String, NormalizedPath) {
  let prev_groups =
    filesystem_diff_group_by_file_id(filesystem_snapshot_entries_unsorted(prev))
  let curr_groups =
    filesystem_diff_group_by_file_id(filesystem_snapshot_entries_unsorted(curr))

  prev_groups
  |> dict.to_list
  |> list.fold(dict.new(), fn(acc, pair) {
    let #(file_id, prev_entries) = pair
    case dict.get(curr_groups, file_id) {
      Error(Nil) -> acc
      Ok(curr_entries) ->
        filesystem_diff_match_disappearance_to_appearance(
          file_id,
          prev_entries,
          curr_entries,
          prev,
          curr,
          acc,
        )
    }
  })
}

fn filesystem_diff_match_disappearance_to_appearance(
  file_id: String,
  prev_entries: List(Entry),
  curr_entries: List(Entry),
  prev: Snapshot,
  curr: Snapshot,
  acc: Dict(String, NormalizedPath),
) -> Dict(String, NormalizedPath) {
  let disappeared =
    list.filter(prev_entries, fn(e) {
      !filesystem_diff_holds_file_id(
        curr,
        filesystem_snapshot_entry_key(e),
        file_id,
      )
    })
  let appeared =
    list.filter(curr_entries, fn(e) {
      !filesystem_diff_holds_file_id(
        prev,
        filesystem_snapshot_entry_key(e),
        file_id,
      )
    })
  case disappeared, appeared {
    [old], [new] ->
      dict.insert(
        acc,
        filesystem_snapshot_entry_key(new),
        entry_path(entry: old),
      )
    _, _ -> acc
  }
}

fn filesystem_diff_holds_file_id(
  s: Snapshot,
  key: String,
  file_id: String,
) -> Bool {
  case filesystem_snapshot_lookup_by_key(s, key) {
    Some(e) -> entry_file_id(entry: e) == Some(file_id)
    None -> False
  }
}

fn filesystem_diff_group_by_file_id(
  entries: List(Entry),
) -> Dict(String, List(Entry)) {
  list.fold(entries, dict.new(), fn(acc, e) {
    case entry_file_id(entry: e) {
      None -> acc
      Some(id) ->
        case dict.get(acc, id) {
          Ok(existing) -> dict.insert(acc, id, [e, ..existing])
          Error(Nil) -> dict.insert(acc, id, [e])
        }
    }
  })
}

fn filesystem_diff_renames_suppressed_paths(
  renames: Dict(String, NormalizedPath),
  curr: Snapshot,
) -> Set(String) {
  renames
  |> dict.values
  |> list.map(path_to_string)
  |> list.filter(fn(key) {
    filesystem_snapshot_lookup_by_key(curr, key) == None
  })
  |> set.from_list
}

/// Return a set containing Create, Write, Remove, Rename, and Chmod.
pub fn all_ops() -> Set(Op) {
  set.from_list(filesystem_op_canonical_order())
}

/// List selected operations in Create, Write, Remove, Rename, Chmod order.
pub fn ops_to_list(ops ops: Set(Op)) -> List(Op) {
  list.filter(filesystem_op_canonical_order(), fn(op) { set.contains(ops, op) })
}

/// Return CREATE, WRITE, REMOVE, RENAME, or CHMOD.
pub fn op_to_string(op op: Op) -> String {
  case op {
    Create -> "CREATE"
    Write -> "WRITE"
    Remove -> "REMOVE"
    Rename -> "RENAME"
    Chmod -> "CHMOD"
  }
}

/// Join selected operation labels with `|` in canonical order.
///
/// An empty set returns an empty string.
pub fn ops_to_string(ops ops: Set(Op)) -> String {
  ops
  |> ops_to_list
  |> list.map(op_to_string)
  |> string.join("|")
}

fn filesystem_op_canonical_order() -> List(Op) {
  [Create, Write, Remove, Rename, Chmod]
}

const fsevent_entry_max_safe_int: Int = 9_007_199_254_740_991

/// A validated filesystem observation supplied by the caller.
///
/// Size and modification time are nonnegative safe integers on both targets. Optional hash and identity strings are nonempty when present; mode is stored as supplied. The caller chooses consistent modification-time units.
pub opaque type Entry {
  Entry(
    path: NormalizedPath,
    kind: EntryKind,
    size: Int,
    mtime: Int,
    mode: Int,
    content_hash: Option(String),
    file_id: Option(String),
  )
}

/// Validate a file observation for a snapshot.
///
/// Check size, then mtime, within 0 through 9,007,199,254,740,991. If supplied, content_hash and file_id must be nonempty, checked in that order. Mode is stored as supplied. Choose one mtime unit and use it consistently across compared snapshots; only equality is tested.
pub fn entry_file(
  path path: NormalizedPath,
  size size: Int,
  mtime mtime: Int,
  mode mode: Int,
  content_hash content_hash: Option(String),
  file_id file_id: Option(String),
) -> Result(Entry, FilesystemError) {
  case filesystem_entry_validate_size(size) {
    Error(error) -> Error(error)
    Ok(_) ->
      case filesystem_entry_validate_mtime(mtime) {
        Error(error) -> Error(error)
        Ok(_) ->
          case
            filesystem_entry_validate_optional_string(
              "content_hash",
              content_hash,
            )
          {
            Error(error) -> Error(error)
            Ok(_) ->
              case
                filesystem_entry_validate_optional_string("file_id", file_id)
              {
                Error(error) -> Error(error)
                Ok(_) ->
                  Ok(Entry(
                    path: path,
                    kind: File,
                    size: size,
                    mtime: mtime,
                    mode: mode,
                    content_hash: content_hash,
                    file_id: file_id,
                  ))
              }
          }
      }
  }
}

/// Validate a directory observation, storing size zero and no content hash.
///
/// Require mtime within the nonnegative safe integer range and a nonempty file_id when supplied. Mode is stored as supplied.
pub fn entry_directory(
  path path: NormalizedPath,
  mtime mtime: Int,
  mode mode: Int,
  file_id file_id: Option(String),
) -> Result(Entry, FilesystemError) {
  filesystem_entry_build_non_file(path, Directory, mtime, mode, file_id)
}

/// Validate a symbolic-link observation, storing size zero and no content hash.
///
/// Require mtime within the nonnegative safe integer range and a nonempty file_id when supplied. The library does not resolve the link or read its target.
pub fn entry_symlink(
  path path: NormalizedPath,
  mtime mtime: Int,
  mode mode: Int,
  file_id file_id: Option(String),
) -> Result(Entry, FilesystemError) {
  filesystem_entry_build_non_file(path, Symlink, mtime, mode, file_id)
}

/// Read the entry's normalized path.
pub fn entry_path(entry entry: Entry) -> NormalizedPath {
  entry.path
}

/// Read whether the entry is a file, directory, or symbolic link.
pub fn entry_kind(entry entry: Entry) -> EntryKind {
  entry.kind
}

/// Read the file size; directory and symbolic-link entries return zero.
pub fn entry_size(entry entry: Entry) -> Int {
  entry.size
}

/// Read the modification-time value in the unit supplied by the caller.
pub fn entry_mtime(entry entry: Entry) -> Int {
  entry.mtime
}

/// Read the caller-supplied mode value.
pub fn entry_mode(entry entry: Entry) -> Int {
  entry.mode
}

/// Read the optional content hash. Directory and symbolic-link entries have none.
pub fn entry_content_hash(entry entry: Entry) -> Option(String) {
  entry.content_hash
}

/// Read the optional identity used to detect moves between paths.
pub fn entry_file_id(entry entry: Entry) -> Option(String) {
  entry.file_id
}

fn filesystem_entry_entries_content_hash_equal(a a: Entry, b b: Entry) -> Bool {
  case a.content_hash, b.content_hash {
    Some(left), Some(right) -> left == right
    _, _ -> False
  }
}

fn filesystem_entry_entries_have_both_hashes(a a: Entry, b b: Entry) -> Bool {
  case a.content_hash, b.content_hash {
    Some(_), Some(_) -> True
    _, _ -> False
  }
}

fn filesystem_entry_build_non_file(
  path: NormalizedPath,
  kind: EntryKind,
  mtime: Int,
  mode: Int,
  file_id: Option(String),
) -> Result(Entry, FilesystemError) {
  case filesystem_entry_validate_mtime(mtime) {
    Error(error) -> Error(error)
    Ok(_) ->
      case filesystem_entry_validate_optional_string("file_id", file_id) {
        Error(error) -> Error(error)
        Ok(_) ->
          Ok(Entry(
            path: path,
            kind: kind,
            size: 0,
            mtime: mtime,
            mode: mode,
            content_hash: None,
            file_id: file_id,
          ))
      }
  }
}

fn filesystem_entry_validate_size(size: Int) -> Result(Nil, FilesystemError) {
  filesystem_entry_validate_non_negative_bounded("size", size)
}

fn filesystem_entry_validate_mtime(mtime: Int) -> Result(Nil, FilesystemError) {
  filesystem_entry_validate_non_negative_bounded("mtime", mtime)
}

fn filesystem_entry_validate_non_negative_bounded(
  field: String,
  value: Int,
) -> Result(Nil, FilesystemError) {
  case value < 0 {
    True -> Error(NegativeEntryField(field: field, actual: value))
    False ->
      case value > fsevent_entry_max_safe_int {
        True -> Error(EntryFieldOverflow(field: field, actual: value))
        False -> Ok(Nil)
      }
  }
}

fn filesystem_entry_validate_optional_string(
  field: String,
  value: Option(String),
) -> Result(Nil, FilesystemError) {
  case value {
    None -> Ok(Nil)
    Some("") -> Error(EmptyOptionalField(field: field))
    Some(_) -> Ok(Nil)
  }
}

/// A validated portable path with normalized separators and complete segments.
///
/// Construct it with `path_normalize`. Normalization is purely textual and does not resolve the filesystem.
pub opaque type NormalizedPath {
  NormalizedPath(value: String, segments: List(String), absolute: Bool)
}

/// Normalize and validate a portable path without consulting the filesystem.
///
/// Replace backslashes with slashes, collapse repeated separators, and remove trailing separators except for roots. Reject empty input, NUL, dot or dot-dot segments, and exactly two leading separators used for UNC paths. Three or more leading separators form a single rooted path. Preserve case; do not resolve symbolic links.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(path) = path_normalize("/tmp//sample/")
/// path_to_string(path)
/// // "/tmp/sample"
///
/// path_normalize("/tmp/../sample")
/// // Error(PathContainsDotSegment("/tmp/../sample", ".."))
/// ```
pub fn path_normalize(
  path path: String,
) -> Result(NormalizedPath, FilesystemError) {
  use _ <- result.try(filesystem_path_reject_empty(path))
  use _ <- result.try(filesystem_path_reject_null_byte(path))
  let unified = string.replace(path, "\\", "/")
  use _ <- result.try(filesystem_path_reject_unc_prefix(path, unified))
  let raw_segments = string.split(unified, "/")
  let segments = list.filter(raw_segments, fn(s) { s != "" })
  use _ <- result.try(filesystem_path_validate_segments(path, segments))
  Ok(filesystem_path_build(unified, segments))
}

fn filesystem_path_reject_empty(path: String) -> Result(Nil, FilesystemError) {
  case path {
    "" -> Error(EmptyPath)
    _ -> Ok(Nil)
  }
}

fn filesystem_path_reject_null_byte(
  path: String,
) -> Result(Nil, FilesystemError) {
  case string.contains(path, "\u{0000}") {
    True -> Error(PathContainsNullByte(path: path))
    False -> Ok(Nil)
  }
}

fn filesystem_path_reject_unc_prefix(
  original: String,
  unified: String,
) -> Result(Nil, FilesystemError) {
  case filesystem_path_is_unc_prefix(unified) {
    True -> Error(UncPathNotSupported(path: original))
    False -> Ok(Nil)
  }
}

fn filesystem_path_is_unc_prefix(unified: String) -> Bool {
  string.starts_with(unified, "//") && !string.starts_with(unified, "///")
}

/// Read the normalized path string.
pub fn path_to_string(path path: NormalizedPath) -> String {
  path.value
}

/// Read the path segments in order, without separator characters.
pub fn path_segments(path path: NormalizedPath) -> List(String) {
  path.segments
}

/// Return whether the normalized path is rooted or begins with a Windows drive-letter segment.
pub fn path_is_absolute(path path: NormalizedPath) -> Bool {
  path.absolute
}

/// Test a path prefix by complete segments, including equality.
///
/// Absolute and relative paths cannot match each other. `/var/log` is below `/var`, but not below `/var/lo`.
pub fn path_starts_with(
  path path: NormalizedPath,
  prefix prefix: NormalizedPath,
) -> Bool {
  case prefix.absolute == path.absolute {
    False -> False
    True -> filesystem_path_segments_start_with(path.segments, prefix.segments)
  }
}

fn filesystem_path_segments_start_with(
  path: List(String),
  prefix: List(String),
) -> Bool {
  case prefix {
    [] -> True
    [head_prefix, ..rest_prefix] ->
      case path {
        [] -> False
        [head_path, ..rest_path] ->
          case head_path == head_prefix {
            False -> False
            True -> filesystem_path_segments_start_with(rest_path, rest_prefix)
          }
      }
  }
}

fn filesystem_path_validate_segments(
  original: String,
  segments: List(String),
) -> Result(Nil, FilesystemError) {
  case segments {
    [] -> Ok(Nil)
    [head, ..rest] ->
      case head {
        "." -> Error(PathContainsDotSegment(path: original, segment: "."))
        ".." -> Error(PathContainsDotSegment(path: original, segment: ".."))
        _ -> filesystem_path_validate_segments(original, rest)
      }
  }
}

fn filesystem_path_starts_with_drive_letter(segments: List(String)) -> Bool {
  case segments {
    [first, ..] -> filesystem_path_is_drive_letter(first)
    [] -> False
  }
}

fn filesystem_path_is_drive_letter(segment: String) -> Bool {
  case segment {
    "A:"
    | "B:"
    | "C:"
    | "D:"
    | "E:"
    | "F:"
    | "G:"
    | "H:"
    | "I:"
    | "J:"
    | "K:"
    | "L:"
    | "M:"
    | "N:"
    | "O:"
    | "P:"
    | "Q:"
    | "R:"
    | "S:"
    | "T:"
    | "U:"
    | "V:"
    | "W:"
    | "X:"
    | "Y:"
    | "Z:" -> True
    "a:"
    | "b:"
    | "c:"
    | "d:"
    | "e:"
    | "f:"
    | "g:"
    | "h:"
    | "i:"
    | "j:"
    | "k:"
    | "l:"
    | "m:"
    | "n:"
    | "o:"
    | "p:"
    | "q:"
    | "r:"
    | "s:"
    | "t:"
    | "u:"
    | "v:"
    | "w:"
    | "x:"
    | "y:"
    | "z:" -> True
    _ -> False
  }
}

fn filesystem_path_build(
  unified: String,
  segments: List(String),
) -> NormalizedPath {
  let joined = string.join(segments, "/")
  let slash_prefix = string.starts_with(unified, "/")
  let absolute =
    slash_prefix || filesystem_path_starts_with_drive_letter(segments)
  let value = case slash_prefix, joined {
    True, "" -> "/"
    True, _ -> "/" <> joined
    False, _ -> joined
  }
  NormalizedPath(value: value, segments: segments, absolute: absolute)
}

/// A filesystem create, content write, removal, rename, or mode change.
pub type Op {
  Create
  Write
  Remove
  Rename
  Chmod
}

/// The observed entry kind: file, directory, or symbolic link.
pub type EntryKind {
  File
  Directory
  Symlink
}

/// An invalid path, entry value, duplicate snapshot path, or inconsistent event operation set.
pub type FilesystemError {
  EmptyPath
  PathContainsDotSegment(path: String, segment: String)
  PathContainsNullByte(path: String)
  UncPathNotSupported(path: String)
  DuplicatePath(path: String)
  NegativeEntryField(field: String, actual: Int)
  EntryFieldOverflow(field: String, actual: Int)
  EmptyOptionalField(field: String)
  EmptyOps
  RenamedFromWithoutRenameOp(path: String)
}

/// A collection with one entry per normalized path. Duplicate paths are rejected on construction or insertion.
pub opaque type Snapshot {
  Snapshot(by_path: Dict(String, Entry))
}

/// Create a snapshot containing no entries.
pub fn snapshot_empty() -> Snapshot {
  Snapshot(by_path: dict.new())
}

/// Create a snapshot keyed by normalized path.
///
/// Reject duplicate paths instead of overwriting an entry.
pub fn snapshot_from_entries(
  entries entries: List(Entry),
) -> Result(Snapshot, FilesystemError) {
  filesystem_snapshot_insert_all(snapshot_empty(), entries)
}

/// Add an entry to a snapshot, rejecting a path already present.
pub fn snapshot_add(
  snapshot snapshot: Snapshot,
  entry entry: Entry,
) -> Result(Snapshot, FilesystemError) {
  let key = filesystem_snapshot_entry_key(entry)
  case dict.has_key(snapshot.by_path, key) {
    True -> Error(DuplicatePath(path: key))
    False -> Ok(Snapshot(by_path: dict.insert(snapshot.by_path, key, entry)))
  }
}

/// Return snapshot entries in normalized-path order.
pub fn snapshot_entries(snapshot snapshot: Snapshot) -> List(Entry) {
  snapshot.by_path
  |> dict.to_list
  |> list.sort(fn(a, b) {
    let #(left_key, _) = a
    let #(right_key, _) = b
    string.compare(left_key, right_key)
  })
  |> list.map(fn(pair) { pair.1 })
}

/// Find the entry at a normalized path, or return None.
pub fn snapshot_get(
  snapshot snapshot: Snapshot,
  path path: NormalizedPath,
) -> Option(Entry) {
  case dict.get(snapshot.by_path, path_to_string(path: path)) {
    Ok(value) -> Some(value)
    Error(Nil) -> None
  }
}

/// Return the number of entries in the snapshot.
pub fn snapshot_size(snapshot snapshot: Snapshot) -> Int {
  dict.size(snapshot.by_path)
}

fn filesystem_snapshot_entries_unsorted(snapshot: Snapshot) -> List(Entry) {
  dict.values(snapshot.by_path)
}

fn filesystem_snapshot_paths(snapshot: Snapshot) -> List(String) {
  dict.keys(snapshot.by_path)
}

fn filesystem_snapshot_entry_key(e: Entry) -> String {
  e
  |> entry_path
  |> path_to_string
}

fn filesystem_snapshot_lookup_by_key(
  snapshot: Snapshot,
  key: String,
) -> Option(Entry) {
  case dict.get(snapshot.by_path, key) {
    Ok(value) -> Some(value)
    Error(Nil) -> None
  }
}

fn filesystem_snapshot_insert_all(
  snapshot: Snapshot,
  remaining: List(Entry),
) -> Result(Snapshot, FilesystemError) {
  case remaining {
    [] -> Ok(snapshot)
    [head, ..rest] ->
      case snapshot_add(snapshot: snapshot, entry: head) {
        Error(error) -> Error(error)
        Ok(updated) -> filesystem_snapshot_insert_all(updated, rest)
      }
  }
}

/// A filesystem event with a nonempty operation set.
///
/// An old path can be present only when Rename is included. Rename itself may omit the old path.
pub opaque type WatchEvent {
  WatchEvent(
    path: NormalizedPath,
    ops: Set(Op),
    renamed_from: Option(NormalizedPath),
  )
}

/// Construct an event with one or more operations.
///
/// Reject an empty operation set. A supplied old path requires Rename, but Rename may be used without an old path. The event's main path is the new path for a rename.
///
/// ## Examples
///
/// ```gleam
/// import gleam/option.{None}
/// import gleam/set
///
/// let assert Ok(path) = path_normalize("/tmp/sample")
/// filesystem_event(path, set.new(), None)
/// // Error(EmptyOps)
///
/// let assert Ok(event) = filesystem_event(path, set.from_list([Write]), None)
/// filesystem_event_to_string(event)
/// // "WRITE /tmp/sample"
/// ```
pub fn filesystem_event(
  path path: NormalizedPath,
  ops ops: Set(Op),
  renamed_from from: Option(NormalizedPath),
) -> Result(WatchEvent, FilesystemError) {
  case set.size(ops) == 0 {
    True -> Error(EmptyOps)
    False ->
      case from {
        None -> Ok(WatchEvent(path: path, ops: ops, renamed_from: None))
        Some(_) ->
          case set.contains(ops, Rename) {
            False ->
              Error(
                RenamedFromWithoutRenameOp(path: path_to_string(path: path)),
              )
            True -> Ok(WatchEvent(path: path, ops: ops, renamed_from: from))
          }
      }
  }
}

/// Read the event's path, which is the new path for a rename.
pub fn filesystem_event_path(event event: WatchEvent) -> NormalizedPath {
  event.path
}

/// Read the nonempty set of observed operations.
pub fn filesystem_event_ops(event event: WatchEvent) -> Set(Op) {
  event.ops
}

/// Read the old path when a rename carries one.
pub fn filesystem_event_renamed_from(
  event event: WatchEvent,
) -> Option(NormalizedPath) {
  event.renamed_from
}

/// Render operations and path, for example `CREATE|WRITE /tmp/a`.
///
/// Append ` <- ` and the old path when present, as in `RENAME /tmp/b <- /tmp/a`. Operations use their canonical order.
pub fn filesystem_event_to_string(event event: WatchEvent) -> String {
  let head =
    ops_to_string(ops: event.ops) <> " " <> path_to_string(path: event.path)
  case event.renamed_from {
    None -> head
    Some(from) -> head <> " <- " <> path_to_string(path: from)
  }
}

/// A civil Gregorian date and time using the core gleam_time types.
///
/// This record may contain invalid values or fractional seconds. `datetime_validate` checks it for whole-second scheduling. It carries no timezone or UTC offset.
pub type DateTime {
  DateTime(date: calendar.Date, time: calendar.TimeOfDay)
}

/// A real Gregorian date and valid time with zero nanoseconds.
///
/// Year zero and negative years are supported. JavaScript years must be safe integers; Erlang years retain arbitrary precision. Construct a value with `datetime_validate`.
pub opaque type ValidDateTime {
  ValidDateTime(value: DateTime)
}

/// Whether an occurrence exactly at the supplied civil time is included in a query.
pub type Boundary {
  Inclusive(ValidDateTime)
  Exclusive(ValidDateTime)
}

/// An out-of-range JavaScript year, invalid Gregorian date, or invalid whole-second time.
pub type DateTimeError {
  InvalidDate(year: Int, month: Int, day: Int)
  InvalidTime(hour: Int, minute: Int, second: Int, nanoseconds: Int)
  DateTimeYearOutOfRange(year: Int)
}

fn schedule_ast_try_datetime(
  year year: Int,
  month month: Int,
  day day: Int,
  hour hour: Int,
  minute minute: Int,
  second second: Int,
) -> Result(DateTime, DateTimeError) {
  case schedule_ast_is_valid_date_components(year, month, day) {
    False -> Error(InvalidDate(year, month, day))
    True ->
      case schedule_ast_is_valid_time_components(hour, minute, second) {
        False -> Error(InvalidTime(hour, minute, second, 0))
        True -> {
          use valid_month <- result.try(
            calendar.month_from_int(month)
            |> result.replace_error(InvalidDate(year, month, day)),
          )
          Ok(DateTime(
            calendar.Date(year, valid_month, day),
            civil_time(hour: hour, minute: minute, second: second),
          ))
        }
      }
  }
}

fn schedule_ast_is_valid_date_components(
  year: Int,
  month: Int,
  day: Int,
) -> Bool {
  month >= 1
  && month <= 12
  && day >= 1
  && day <= internal_gregorian_days_in_month(year, month)
}

fn schedule_ast_is_valid_time_components(
  hour: Int,
  minute: Int,
  second: Int,
) -> Bool {
  hour >= 0
  && hour <= 23
  && minute >= 0
  && minute <= 59
  && second >= 0
  && second <= 59
}

fn schedule_ast_to_string(datetime: DateTime) -> String {
  internal_digits_pad4(datetime.date.year)
  <> "-"
  <> internal_digits_pad2(calendar.month_to_int(datetime.date.month))
  <> "-"
  <> internal_digits_pad2(datetime.date.day)
  <> "T"
  <> internal_digits_pad2(datetime.time.hours)
  <> ":"
  <> internal_digits_pad2(datetime.time.minutes)
  <> ":"
  <> internal_digits_pad2(datetime.time.seconds)
}

/// Return the RRULE weekday label: MO, TU, WE, TH, FR, SA, or SU.
pub fn weekday_to_string(day: calendar.DayOfWeek) -> String {
  case day {
    calendar.Monday -> "MO"
    calendar.Tuesday -> "TU"
    calendar.Wednesday -> "WE"
    calendar.Thursday -> "TH"
    calendar.Friday -> "FR"
    calendar.Saturday -> "SA"
    calendar.Sunday -> "SU"
  }
}

type CronSelection {
  AnyCronValue(min: Int, max: Int)
  SelectedCronValues(List(Int))
}

type CronPlan {
  CronPlan(
    minute: CronSelection,
    hour: CronSelection,
    day_of_month: CronSelection,
    month: CronSelection,
    day_of_week: CronSelection,
  )
}

fn compile_cron(spec spec: Cron) -> CronPlan {
  CronPlan(
    minute: cron_normalize_normalize_selector(spec.minute, 0, 59, False),
    hour: cron_normalize_normalize_selector(spec.hour, 0, 23, False),
    day_of_month: cron_normalize_normalize_selector(
      spec.day_of_month,
      1,
      31,
      False,
    ),
    month: cron_normalize_normalize_selector(spec.month, 1, 12, False),
    day_of_week: cron_normalize_normalize_selector(spec.day_of_week, 0, 6, True),
  )
}

fn cron_normalize_normalize_selector(
  selector: CronSelector,
  min: Int,
  max: Int,
  normalize_day_of_week: Bool,
) -> CronSelection {
  case selector {
    CronAny -> AnyCronValue(min:, max:)
    CronValues(_) ->
      SelectedCronValues(cron_validator_selector_values(
        selector,
        min,
        max,
        normalize_day_of_week: normalize_day_of_week,
      ))
  }
}

/// An unvalidated field selector: wildcard or a nonempty list of items.
///
/// `cron_new` checks the selector against its field's range. A wildcard retains its day-matching meaning even when an explicit value list covers the same range.
pub type CronSelector {
  CronAny
  CronValues(List(CronItem))
}

/// An exact value, inclusive range, or stepped selection within a cron field.
///
/// Validate these values through `cron_new`; constructing an item does not check its range or step.
pub type CronItem {
  CronExact(Int)
  CronRange(Int, Int)
  CronStep(CronStepBase, Int)
}

/// The full field range, a starting value, or an inclusive range to which a step applies.
pub type CronStepBase {
  CronStepAny
  CronStepExact(Int)
  CronStepRange(Int, Int)
}

/// A validated cron specification. Create it with `cron_validate` or `cron_new`.
pub opaque type Cron {
  Cron(
    minute: CronSelector,
    hour: CronSelector,
    day_of_month: CronSelector,
    month: CronSelector,
    day_of_week: CronSelector,
  )
}

/// An invalid cron field value, unsupported field syntax, or impossible date selection.
pub type CronValidationError {
  CronUnsupportedSyntax(field: CronField, value: String)
  CronInvalidNumber(field: CronField, value: String)
  CronInvalidAlias(field: CronField, value: String)
  CronInvalidRange(field: CronField, value: String)
  CronInvalidStep(field: CronField, value: String)
  CronInvalidList(field: CronField, value: String)
  CronOutOfRange(field: CronField, min: Int, max: Int, actual: Int)
  CronImpossibleDate(day_of_month: String, month: String)
}

type CronAliases {
  NoCronAliases
  CronMonthAliases
  CronValidatorDayAliases
}

/// Validate raw cron fields and produce a reusable cron specification.
///
/// Check minute, hour, day of month, month, and day of week in that order, then date constraints. Sunday accepts 0 or 7. Numbers are unsigned decimal digits. When both day fields are restricted, a match in either field is sufficient. Only a plain `*` is a wildcard for this rule, as in croniter: `*/2` restricts its field, while Vixie cron treats a field beginning with `*` as a wildcard. Preserve the distinction between a wildcard and an explicitly listed full range.
pub fn cron_validate(raw raw: RawCron) -> Result(Cron, CronValidationError) {
  {
    use minute <- result.try(cron_validator_parse_selector(
      CronMinute,
      raw.minute,
      0,
      59,
      NoCronAliases,
    ))
    use hour <- result.try(cron_validator_parse_selector(
      CronHour,
      raw.hour,
      0,
      23,
      NoCronAliases,
    ))
    use day_of_month <- result.try(cron_validator_parse_selector(
      CronDayOfMonth,
      raw.day_of_month,
      1,
      31,
      NoCronAliases,
    ))
    use month <- result.try(cron_validator_parse_selector(
      CronMonth,
      raw.month,
      1,
      12,
      CronMonthAliases,
    ))
    use day_of_week <- result.try(cron_validator_parse_selector(
      CronDayOfWeek,
      raw.day_of_week,
      0,
      7,
      CronValidatorDayAliases,
    ))

    let spec = Cron(minute:, hour:, day_of_month:, month:, day_of_week:)

    case cron_validator_validate_semantics(spec) {
      Ok(_) -> Ok(spec)
      Error(error) -> Error(error)
    }
  }
}

fn cron_validator_from_selectors(
  minute minute: CronSelector,
  hour hour: CronSelector,
  day_of_month day_of_month: CronSelector,
  month month: CronSelector,
  day_of_week day_of_week: CronSelector,
) -> Result(Cron, CronValidationError) {
  use minute <- result.try(cron_validator_check_selector(
    CronMinute,
    minute,
    0,
    59,
  ))
  use hour <- result.try(cron_validator_check_selector(CronHour, hour, 0, 23))
  use day_of_month <- result.try(cron_validator_check_selector(
    CronDayOfMonth,
    day_of_month,
    1,
    31,
  ))
  use month <- result.try(cron_validator_check_selector(CronMonth, month, 1, 12))
  use day_of_week <- result.try(cron_validator_check_selector(
    CronDayOfWeek,
    day_of_week,
    0,
    7,
  ))
  let spec = Cron(minute:, hour:, day_of_month:, month:, day_of_week:)
  case cron_validator_validate_semantics(spec) {
    Ok(_) -> Ok(spec)
    Error(error) -> Error(error)
  }
}

fn cron_validator_check_selector(
  field: CronField,
  selector: CronSelector,
  min: Int,
  max: Int,
) -> Result(CronSelector, CronValidationError) {
  case selector {
    CronAny -> Ok(CronAny)
    CronValues([]) -> Error(CronInvalidList(field: field, value: ""))
    CronValues(items) ->
      list.try_each(items, cron_validator_check_item(field, _, min, max))
      |> result.replace(selector)
  }
}

fn cron_validator_check_item(
  field: CronField,
  item: CronItem,
  min: Int,
  max: Int,
) -> Result(Nil, CronValidationError) {
  case item {
    CronExact(value) ->
      cron_validator_ensure_range(field, value, min, max) |> result.replace(Nil)
    CronRange(start, end) ->
      cron_validator_check_bounds(
        field,
        start,
        end,
        min,
        max,
        cron_validator_item_to_string(item),
      )
    CronStep(base, step) ->
      case cron_validator_step_in_bounds(step, min, max) {
        False ->
          Error(CronInvalidStep(
            field: field,
            value: cron_validator_item_to_string(item),
          ))
        True ->
          case base {
            CronStepAny -> Ok(Nil)
            CronStepExact(value) ->
              cron_validator_ensure_range(field, value, min, max)
              |> result.replace(Nil)
            CronStepRange(start, end) ->
              cron_validator_check_bounds(
                field,
                start,
                end,
                min,
                max,
                cron_validator_step_base_to_string(base),
              )
          }
      }
  }
}

fn cron_validator_check_bounds(
  field: CronField,
  start: Int,
  end: Int,
  min: Int,
  max: Int,
  text: String,
) -> Result(Nil, CronValidationError) {
  use _ <- result.try(cron_validator_ensure_range(field, start, min, max))
  use _ <- result.try(cron_validator_ensure_range(field, end, min, max))
  case start <= end {
    True -> Ok(Nil)
    False -> Error(CronInvalidRange(field: field, value: text))
  }
}

fn cron_validator_step_in_bounds(step: Int, min: Int, max: Int) -> Bool {
  step > 0 && step <= max - min + 1
}

/// Render the specification as a canonical five-field cron expression.
pub fn cron_to_string(spec spec: Cron) -> String {
  string.join(
    [
      cron_validator_selector_to_string(spec.minute),
      cron_validator_selector_to_string(spec.hour),
      cron_validator_selector_to_string(spec.day_of_month),
      cron_validator_selector_to_string(spec.month),
      cron_validator_selector_to_string(spec.day_of_week),
    ],
    with: " ",
  )
}

fn cron_validator_validate_semantics(
  spec: Cron,
) -> Result(Nil, CronValidationError) {
  case cron_validator_day_of_week_is_any(spec.day_of_week) {
    False -> Ok(Nil)
    True ->
      case cron_validator_schedule_possible(spec.day_of_month, spec.month) {
        True -> Ok(Nil)
        False ->
          Error(CronImpossibleDate(
            day_of_month: cron_validator_selector_to_string(spec.day_of_month),
            month: cron_validator_selector_to_string(spec.month),
          ))
      }
  }
}

fn cron_validator_day_of_week_is_any(selector: CronSelector) -> Bool {
  case selector {
    CronAny -> True
    CronValues(_) -> False
  }
}

fn cron_validator_schedule_possible(
  day_of_month: CronSelector,
  month: CronSelector,
) -> Bool {
  let months =
    cron_validator_selector_values(month, 1, 12, normalize_day_of_week: False)
  let days =
    cron_validator_selector_values(
      day_of_month,
      1,
      31,
      normalize_day_of_week: False,
    )

  list.any(months, fn(month) {
    let maximum = internal_gregorian_days_in_month(2024, month)
    list.any(days, fn(day) { day <= maximum })
    || list.any(days, fn(day) {
      internal_gregorian_days_in_month(2025, month) >= day
    })
  })
}

fn cron_validator_parse_selector(
  field: CronField,
  value: String,
  min: Int,
  max: Int,
  aliases: CronAliases,
) -> Result(CronSelector, CronValidationError) {
  case value {
    "*" -> Ok(CronAny)
    _ ->
      case list.any(string.split(value, on: ","), string.is_empty) {
        True -> Error(CronInvalidList(field: field, value: value))
        False ->
          cron_validator_parse_items(
            string.split(value, on: ","),
            field,
            min,
            max,
            aliases,
            [],
          )
      }
  }
}

fn cron_validator_parse_items(
  parts: List(String),
  field: CronField,
  min: Int,
  max: Int,
  aliases: CronAliases,
  acc: List(CronItem),
) -> Result(CronSelector, CronValidationError) {
  case parts {
    [] -> Ok(CronValues(list.reverse(acc)))
    [part, ..rest] ->
      case cron_validator_parse_item(field, part, min, max, aliases) {
        Ok(item) ->
          cron_validator_parse_items(rest, field, min, max, aliases, [
            item,
            ..acc
          ])
        Error(error) -> Error(error)
      }
  }
}

fn cron_validator_parse_item(
  field: CronField,
  part: String,
  min: Int,
  max: Int,
  aliases: CronAliases,
) -> Result(CronItem, CronValidationError) {
  case string.contains(part, contain: "/") {
    True -> cron_validator_parse_step(field, part, min, max, aliases)
    False ->
      case string.contains(part, contain: "-") {
        True -> cron_validator_parse_range(field, part, min, max, aliases)
        False ->
          case cron_validator_parse_value(field, part, min, max, aliases) {
            Ok(value) -> Ok(CronExact(value))
            Error(error) -> Error(error)
          }
      }
  }
}

fn cron_validator_parse_step(
  field: CronField,
  part: String,
  min: Int,
  max: Int,
  aliases: CronAliases,
) -> Result(CronItem, CronValidationError) {
  case string.split(part, on: "/") {
    [base, step_text] if base != "" && step_text != "" -> {
      use step <- result.try(
        parse_digits(step_text)
        |> result.replace_error(CronInvalidStep(field, part)),
      )
      case cron_validator_step_in_bounds(step, min, max) {
        False -> Error(CronInvalidStep(field, part))
        True ->
          cron_validator_parse_step_base(field, base, min, max, aliases)
          |> result.map(CronStep(_, step))
      }
    }
    _ -> Error(CronInvalidStep(field, part))
  }
}

fn cron_validator_parse_step_base(
  field: CronField,
  base: String,
  min: Int,
  max: Int,
  aliases: CronAliases,
) -> Result(CronStepBase, CronValidationError) {
  case base {
    "*" -> Ok(CronStepAny)
    _ ->
      case string.contains(base, "-") {
        True -> cron_parse_step_range(field, base, min, max, aliases)
        False ->
          cron_validator_parse_value(field, base, min, max, aliases)
          |> result.map(CronStepExact)
      }
  }
}

fn cron_validator_parse_range(
  field: CronField,
  part: String,
  min: Int,
  max: Int,
  aliases: CronAliases,
) -> Result(CronItem, CronValidationError) {
  case string.split(part, on: "-") {
    [start_text, end_text] ->
      case start_text == "" || end_text == "" {
        True -> Error(CronInvalidRange(field: field, value: part))
        False -> {
          use start <- result.try(cron_validator_parse_value(
            field,
            start_text,
            min,
            max,
            aliases,
          ))
          use end <- result.try(cron_validator_parse_value(
            field,
            end_text,
            min,
            max,
            aliases,
          ))
          case start <= end {
            True -> Ok(CronRange(start, end))
            False -> Error(CronInvalidRange(field: field, value: part))
          }
        }
      }
    _ -> Error(CronInvalidRange(field: field, value: part))
  }
}

fn cron_validator_parse_value(
  field: CronField,
  value: String,
  min: Int,
  max: Int,
  aliases: CronAliases,
) -> Result(Int, CronValidationError) {
  case parse_digits(value) {
    Ok(number) -> cron_validator_ensure_range(field, number, min, max)
    Error(Nil) ->
      case cron_validator_parse_alias(field, value, aliases) {
        Ok(number) -> cron_validator_ensure_range(field, number, min, max)
        Error(Nil) ->
          case cron_validator_has_reserved_quartz_syntax(value) {
            True -> Error(CronUnsupportedSyntax(field: field, value: value))
            False ->
              case aliases {
                NoCronAliases ->
                  Error(CronInvalidNumber(field: field, value: value))
                CronMonthAliases | CronValidatorDayAliases ->
                  Error(CronInvalidAlias(field: field, value: value))
              }
          }
      }
  }
}

fn cron_validator_has_reserved_quartz_syntax(value: String) -> Bool {
  string.contains(value, contain: "?")
  || string.contains(value, contain: "L")
  || string.contains(value, contain: "W")
  || string.contains(value, contain: "#")
  || string.contains(value, contain: "H")
}

fn cron_validator_ensure_range(
  field: CronField,
  number: Int,
  min: Int,
  max: Int,
) -> Result(Int, CronValidationError) {
  case number < min || number > max {
    True ->
      Error(CronOutOfRange(field: field, min: min, max: max, actual: number))
    False -> Ok(number)
  }
}

fn cron_validator_parse_alias(
  _field: CronField,
  value: String,
  aliases: CronAliases,
) -> Result(Int, Nil) {
  let upper = string.uppercase(value)

  case aliases {
    NoCronAliases -> Error(Nil)
    CronMonthAliases ->
      case upper {
        "JAN" -> Ok(1)
        "FEB" -> Ok(2)
        "MAR" -> Ok(3)
        "APR" -> Ok(4)
        "MAY" -> Ok(5)
        "JUN" -> Ok(6)
        "JUL" -> Ok(7)
        "AUG" -> Ok(8)
        "SEP" -> Ok(9)
        "OCT" -> Ok(10)
        "NOV" -> Ok(11)
        "DEC" -> Ok(12)
        _ -> Error(Nil)
      }
    CronValidatorDayAliases ->
      case upper {
        "SUN" -> Ok(0)
        "MON" -> Ok(1)
        "TUE" -> Ok(2)
        "WED" -> Ok(3)
        "THU" -> Ok(4)
        "FRI" -> Ok(5)
        "SAT" -> Ok(6)
        _ -> Error(Nil)
      }
  }
}

fn cron_validator_selector_values(
  selector: CronSelector,
  min: Int,
  max: Int,
  normalize_day_of_week normalize_day_of_week: Bool,
) -> List(Int) {
  let values = case selector {
    CronAny -> cron_validator_inclusive_range(min, max)
    CronValues(items) ->
      items
      |> list.flat_map(fn(item) { cron_validator_item_values(item, min, max) })
  }

  case normalize_day_of_week {
    True ->
      values
      |> list.map(fn(value) {
        case value == 7 {
          True -> 0
          False -> value
        }
      })
      |> list.sort(by: int.compare)
      |> list.unique
    False -> list.unique(list.sort(values, by: int.compare))
  }
}

fn cron_validator_item_values(item: CronItem, min: Int, max: Int) -> List(Int) {
  case item {
    CronExact(value) -> [value]
    CronRange(start, end) -> cron_validator_inclusive_range(start, end)
    CronStep(base, step) ->
      case base {
        CronStepAny -> cron_validator_stepped_values(min, max, step)
        CronStepExact(start) -> cron_validator_stepped_values(start, max, step)
        CronStepRange(start, end) ->
          cron_validator_stepped_values(start, end, step)
      }
  }
}

fn cron_validator_stepped_values(
  start: Int,
  stop: Int,
  step: Int,
) -> List(Int) {
  case start > stop {
    True -> []
    False -> [start, ..cron_validator_stepped_values(start + step, stop, step)]
  }
}

fn cron_validator_inclusive_range(start: Int, stop: Int) -> List(Int) {
  case start > stop {
    True -> []
    False -> [start, ..cron_validator_inclusive_range(start + 1, stop)]
  }
}

fn cron_validator_selector_to_string(selector: CronSelector) -> String {
  case selector {
    CronAny -> "*"
    CronValues(items) ->
      string.join(list.map(items, cron_validator_item_to_string), with: ",")
  }
}

fn cron_validator_item_to_string(item: CronItem) -> String {
  case item {
    CronExact(value) -> int.to_string(value)
    CronRange(start, end) -> int.to_string(start) <> "-" <> int.to_string(end)
    CronStep(base, step) ->
      cron_validator_step_base_to_string(base) <> "/" <> int.to_string(step)
  }
}

fn cron_validator_step_base_to_string(base: CronStepBase) -> String {
  case base {
    CronStepAny -> "*"
    CronStepExact(value) -> int.to_string(value)
    CronStepRange(start, end) ->
      int.to_string(start) <> "-" <> int.to_string(end)
  }
}

/// An expression-level syntax error found before cron field validation.
pub type CronParseError {
  CronParseInvalidExpression(value: String)
  CronParseInvalidFieldCount(expected: Int, actual: Int)
  CronParseUnsupportedSyntax(field: CronField, value: String)
  CronParseRebootNotSupported(value: String)
}

/// Parse a five-field UNIX cron expression into unvalidated field text.
///
/// Fields are minute, hour, day of month, month, and day of week. This stage checks expression syntax; call `cron_validate` to check ranges, aliases, steps, and date constraints.
pub fn cron_parse_raw(input input: String) -> Result(RawCron, CronParseError) {
  let trimmed = string.trim(input)

  case trimmed {
    "" -> Error(CronParseInvalidExpression(value: input))
    _ ->
      case string.starts_with(trimmed, "@") {
        True -> cron_parser_parse_nickname(trimmed)
        False -> cron_parser_parse_five_field(trimmed)
      }
  }
}

fn cron_parser_parse_five_field(
  trimmed: String,
) -> Result(RawCron, CronParseError) {
  case cron_parser_split_whitespace(trimmed) {
    [minute, hour, day_of_month, month, day_of_week] ->
      Ok(RawCron(minute, hour, day_of_month, month, day_of_week))
    fields ->
      Error(CronParseInvalidFieldCount(expected: 5, actual: list.length(fields)))
  }
}

fn cron_parser_parse_nickname(
  value: String,
) -> Result(RawCron, CronParseError) {
  case string.lowercase(value) {
    "@yearly" | "@annually" ->
      Ok(RawCron(
        minute: "0",
        hour: "0",
        day_of_month: "1",
        month: "1",
        day_of_week: "*",
      ))
    "@monthly" ->
      Ok(RawCron(
        minute: "0",
        hour: "0",
        day_of_month: "1",
        month: "*",
        day_of_week: "*",
      ))
    "@weekly" ->
      Ok(RawCron(
        minute: "0",
        hour: "0",
        day_of_month: "*",
        month: "*",
        day_of_week: "0",
      ))
    "@daily" | "@midnight" ->
      Ok(RawCron(
        minute: "0",
        hour: "0",
        day_of_month: "*",
        month: "*",
        day_of_week: "*",
      ))
    "@hourly" ->
      Ok(RawCron(
        minute: "0",
        hour: "*",
        day_of_month: "*",
        month: "*",
        day_of_week: "*",
      ))
    "@reboot" -> Error(CronParseRebootNotSupported(value: value))
    _ -> Error(CronParseUnsupportedSyntax(field: CronExpression, value: value))
  }
}

fn cron_parser_split_whitespace(input: String) -> List(String) {
  input
  |> string.to_graphemes
  |> list.fold(#([], ""), fn(acc, grapheme) {
    let #(parts, current) = acc
    case cron_parser_is_whitespace(grapheme) {
      True ->
        case current == "" {
          True -> #(parts, "")
          False -> #([current, ..parts], "")
        }
      False -> #(parts, current <> grapheme)
    }
  })
  |> cron_parser_flush_split_parts
}

fn cron_parser_flush_split_parts(
  parts: #(List(String), String),
) -> List(String) {
  let #(collected, current) = parts

  case current == "" {
    True -> list.reverse(collected)
    False -> list.reverse([current, ..collected])
  }
}

fn cron_parser_is_whitespace(grapheme: String) -> Bool {
  case grapheme {
    " " -> True
    "\t" -> True
    "\n" -> True
    "\r" -> True
    _ -> False
  }
}

fn cron_evaluator_matches(plan plan: CronPlan, at at: DateTime) -> Bool {
  let minute_match =
    cron_evaluator_int_set_contains(plan.minute, at.time.minutes)
  let hour_match = cron_evaluator_int_set_contains(plan.hour, at.time.hours)
  let month_match =
    cron_evaluator_int_set_contains(
      plan.month,
      calendar.month_to_int(at.date.month),
    )
  let day_of_month_match =
    cron_evaluator_int_set_contains(plan.day_of_month, at.date.day)
  let day_of_week_match =
    cron_evaluator_int_set_contains(
      plan.day_of_week,
      internal_calendar_day_of_week_number(at),
    )

  // UNIX cron is minute-granular per POSIX — the five fields are minute /
  // hour / day-of-month / month / day-of-week with no second field. Any
  // instant within a matching minute is a firing, regardless of seconds.
  minute_match
  && hour_match
  && month_match
  && cron_evaluator_matches_day(plan, day_of_month_match, day_of_week_match)
}

fn cron_evaluator_int_set_contains(int_set: CronSelection, value: Int) -> Bool {
  case int_set {
    AnyCronValue(min:, max:) -> value >= min && value <= max
    SelectedCronValues(values) -> list.any(values, fn(item) { item == value })
  }
}

fn cron_evaluator_matches_day(
  plan: CronPlan,
  day_of_month_match: Bool,
  day_of_week_match: Bool,
) -> Bool {
  let dom_any = cron_evaluator_is_any(plan.day_of_month)
  let dow_any = cron_evaluator_is_any(plan.day_of_week)

  case dom_any, dow_any {
    True, True -> True
    True, False -> day_of_week_match
    False, True -> day_of_month_match
    False, False -> day_of_month_match || day_of_week_match
  }
}

fn cron_evaluator_is_any(int_set: CronSelection) -> Bool {
  case int_set {
    AnyCronValue(_, _) -> True
    SelectedCronValues(_) -> False
  }
}

/// The expression or cron field associated with a parse or validation error.
pub type CronField {
  CronExpression
  CronMinute
  CronHour
  CronDayOfMonth
  CronMonth
  CronDayOfWeek
}

/// Unvalidated text for the five UNIX cron fields, in minute-to-weekday order.
pub type RawCron {
  RawCron(
    minute: String,
    hour: String,
    day_of_month: String,
    month: String,
    day_of_week: String,
  )
}

/// Optional correlation, causation, and trace identifiers, plus caller-defined string attributes.
pub type Metadata {
  Metadata(
    correlation_id: Option(String),
    causation_id: Option(String),
    trace_id: Option(String),
    attributes: Dict(String, String),
  )
}

fn event_metadata_empty() -> Metadata {
  Metadata(
    correlation_id: None,
    causation_id: None,
    trace_id: None,
    attributes: dict.new(),
  )
}

/// An event producer classification, including a caller-named custom source.
pub type SourceKind {
  ScheduleSource
  FileSystemSource
  ManualSource
  WebhookSource
  QueueSource
  SignalSource
  HttpSource
  CloudEventSource
  CustomSource(String)
}

/// An event producer's kind, identifier, and optional display name.
pub type Source {
  Source(kind: SourceKind, id: String, name: Option(String))
}

fn event_source_new(kind kind: SourceKind, id id: String) -> Source {
  Source(kind: kind, id: id, name: None)
}

/// Return the stable source label.
///
/// Built-in labels include `schedule`, `file_system`, `manual`, and their transport names. A custom source returns `custom:` followed by its name.
pub fn source_kind_to_string(kind: SourceKind) -> String {
  case kind {
    ScheduleSource -> "schedule"
    FileSystemSource -> "file_system"
    ManualSource -> "manual"
    WebhookSource -> "webhook"
    QueueSource -> "queue"
    SignalSource -> "signal"
    HttpSource -> "http"
    CloudEventSource -> "cloud_event"
    CustomSource(name) -> "custom:" <> name
  }
}

fn internal_gregorian_is_leap_year(year: Int) -> Bool {
  let by_4 = internal_gregorian_modulo(year, 4)
  let by_100 = internal_gregorian_modulo(year, 100)
  let by_400 = internal_gregorian_modulo(year, 400)

  by_400 == 0 || { by_4 == 0 && by_100 != 0 }
}

fn internal_gregorian_days_in_month(year: Int, month: Int) -> Int {
  case month {
    1 | 3 | 5 | 7 | 8 | 10 | 12 -> 31
    4 | 6 | 9 | 11 -> 30
    2 ->
      case internal_gregorian_is_leap_year(year) {
        True -> 29
        False -> 28
      }
    _ -> 0
  }
}

fn internal_gregorian_modulo(dividend: Int, divisor: Int) -> Int {
  int.modulo(dividend, by: divisor) |> result.unwrap(0)
}

fn internal_digits_pad2(value: Int) -> String {
  string.pad_start(int.to_string(value), to: 2, with: "0")
}

fn internal_digits_pad4(value: Int) -> String {
  case value < 0 {
    True -> "-" <> internal_digits_pad4(0 - value)
    False -> string.pad_start(int.to_string(value), to: 4, with: "0")
  }
}

fn internal_calendar_compare(left: DateTime, right: DateTime) -> Order {
  int.compare(left.date.year, right.date.year)
  |> order.break_tie(with: int.compare(
    calendar.month_to_int(left.date.month),
    calendar.month_to_int(right.date.month),
  ))
  |> order.break_tie(with: int.compare(left.date.day, right.date.day))
  |> order.break_tie(with: int.compare(left.time.hours, right.time.hours))
  |> order.break_tie(with: int.compare(left.time.minutes, right.time.minutes))
  |> order.break_tie(with: int.compare(left.time.seconds, right.time.seconds))
}

fn internal_calendar_less_than(left: DateTime, right: DateTime) -> Bool {
  internal_calendar_compare(left, right) == Lt
}

fn internal_calendar_less_or_equal(left: DateTime, right: DateTime) -> Bool {
  case internal_calendar_compare(left, right) {
    Lt -> True
    Eq -> True
    Gt -> False
  }
}

fn internal_calendar_greater_than(left: DateTime, right: DateTime) -> Bool {
  internal_calendar_compare(left, right) == Gt
}

fn internal_calendar_greater_or_equal(left: DateTime, right: DateTime) -> Bool {
  case internal_calendar_compare(left, right) {
    Gt -> True
    Eq -> True
    Lt -> False
  }
}

fn internal_calendar_equals(left: DateTime, right: DateTime) -> Bool {
  internal_calendar_compare(left, right) == Eq
}

fn internal_calendar_is_valid_date(date: calendar.Date) -> Bool {
  calendar.month_to_int(date.month) >= 1
  && calendar.month_to_int(date.month) <= 12
  && date.day >= 1
  && date.day
  <= internal_gregorian_days_in_month(
    date.year,
    calendar.month_to_int(date.month),
  )
}

fn internal_calendar_is_valid_time(time: calendar.TimeOfDay) -> Bool {
  calendar.is_valid_time_of_day(time) && time.nanoseconds == 0
}

fn internal_calendar_is_valid_datetime(datetime: DateTime) -> Bool {
  internal_calendar_is_valid_date(datetime.date)
  && internal_calendar_is_valid_time(datetime.time)
}

fn internal_calendar_weekday(datetime: DateTime) -> calendar.DayOfWeek {
  let date = datetime.date
  calendar.day_of_week(
    calendar.Date(..date, year: civil_divmod(date.year, 400).1),
  )
}

fn internal_calendar_day_of_week_number(datetime: DateTime) -> Int {
  case internal_calendar_weekday(datetime) {
    calendar.Sunday -> 0
    calendar.Monday -> 1
    calendar.Tuesday -> 2
    calendar.Wednesday -> 3
    calendar.Thursday -> 4
    calendar.Friday -> 5
    calendar.Saturday -> 6
  }
}

fn internal_calendar_days_before_month(year: Int, month: Int) -> Int {
  internal_calendar_days_before_month_loop(year, month, 1, 0)
}

fn internal_calendar_days_before_month_loop(
  year: Int,
  target: Int,
  month: Int,
  acc: Int,
) -> Int {
  case month >= target {
    True -> acc
    False ->
      internal_calendar_days_before_month_loop(
        year,
        target,
        month + 1,
        acc + internal_gregorian_days_in_month(year, month),
      )
  }
}

type RecurrencePlan {
  RecurrencePlan(
    anchor: DateTime,
    frequency: Frequency,
    interval: Int,
    end_condition: EndCondition,
    by_day: Option(List(WeekdaySpecifier)),
    by_month: Option(List(Int)),
    by_month_day: Option(List(Int)),
    by_hour: List(Int),
    by_minute: List(Int),
    seconds: List(Int),
    time_reachable: Bool,
    // Seconds between occurrences when every period holds exactly one
    // occurrence at the anchor's offset, so COUNT can be computed directly.
    fixed_step: Option(Int),
  )
}

fn compile_recurrence(
  spec spec: RecurrenceRule,
  anchor validated: ValidDateTime,
) -> RecurrencePlan {
  let anchor = validated.value
  let frequency = spec.frequency
  let by_hour = case spec.by_hour {
    Some(values) -> values
    None -> rrule_normalize_default_by_hour(frequency, anchor)
  }
  let by_minute = case spec.by_minute {
    Some(values) -> values
    None -> rrule_normalize_default_by_minute(frequency, anchor)
  }
  let seconds = rrule_normalize_default_seconds(frequency, anchor)
  RecurrencePlan(
    anchor: anchor,
    frequency: frequency,
    interval: spec.interval,
    end_condition: spec.end_condition,
    by_day: rrule_normalize_default_by_day(spec, anchor),
    by_month: rrule_normalize_default_by_month(spec, anchor),
    by_month_day: rrule_normalize_default_by_month_day(spec, anchor),
    by_hour: by_hour,
    by_minute: by_minute,
    seconds: seconds,
    time_reachable: recurrence_time_reachable(
      frequency,
      spec.interval,
      anchor,
      by_hour,
      by_minute,
      seconds,
    ),
    fixed_step: recurrence_fixed_step(spec),
  )
}

fn recurrence_fixed_step(spec: RecurrenceRule) -> Option(Int) {
  let unit = case spec.frequency {
    Secondly -> Some(1)
    Minutely -> Some(60)
    Hourly -> Some(3600)
    Daily -> Some(86_400)
    Weekly -> Some(604_800)
    Monthly | Yearly -> None
  }
  case
    unit,
    spec.by_day,
    spec.by_month,
    spec.by_month_day,
    spec.by_hour,
    spec.by_minute
  {
    Some(unit), None, None, None, None, None ->
      case spec.interval <= 1_000_000_000 {
        True -> Some(spec.interval * unit)
        False -> None
      }
    _, _, _, _, _, _ -> None
  }
}

// Count the occurrences from the anchor that come before the boundary.
fn recurrence_count_from_anchor(
  plan: RecurrencePlan,
  boundary: Boundary,
  limit: Int,
  budget: SearchBudget,
) -> Result(#(Int, SearchBudget), ScheduleError) {
  let #(target, exclusive) = boundary_position(boundary)
  let anchor = civil_position(plan.anchor)
  let eras = target.era - anchor.era
  case plan.fixed_step {
    Some(step) if eras < 700_000 && eras > -700_000 -> {
      let distance =
        eras
        * 12_622_780_800
        + { target.day - anchor.day }
        * 86_400
        + target.second
        - anchor.second
      let count = case distance < 0, exclusive {
        True, _ -> 0
        False, False -> { distance + step - 1 } / step
        False, True -> distance / step + 1
      }
      Ok(#(int.min(count, limit), budget))
    }
    _ ->
      recurrence_count_before(
        plan,
        boundary,
        Inclusive(ValidDateTime(plan.anchor)),
        0,
        limit,
        budget,
      )
  }
}

fn rrule_normalize_default_by_hour(
  frequency: Frequency,
  anchor: DateTime,
) -> List(Int) {
  case frequency {
    Secondly | Minutely | Hourly -> rrule_normalize_range_inclusive(0, 23)
    Daily | Weekly | Monthly | Yearly -> [
      anchor.time.hours,
    ]
  }
}

fn rrule_normalize_default_by_minute(
  frequency: Frequency,
  anchor: DateTime,
) -> List(Int) {
  case frequency {
    Secondly | Minutely -> rrule_normalize_range_inclusive(0, 59)
    Hourly | Daily | Weekly | Monthly | Yearly -> [anchor.time.minutes]
  }
}

fn rrule_normalize_default_seconds(
  frequency: Frequency,
  anchor: DateTime,
) -> List(Int) {
  case frequency {
    Secondly -> rrule_normalize_range_inclusive(0, 59)
    Minutely | Hourly | Daily | Weekly | Monthly | Yearly -> [
      anchor.time.seconds,
    ]
  }
}

fn rrule_normalize_range_inclusive(from: Int, to: Int) -> List(Int) {
  rrule_normalize_range_loop(to, from, [])
}

fn rrule_normalize_range_loop(
  current: Int,
  from: Int,
  acc: List(Int),
) -> List(Int) {
  case current < from {
    True -> acc
    False -> rrule_normalize_range_loop(current - 1, from, [current, ..acc])
  }
}

fn rrule_normalize_default_by_day(
  spec: RecurrenceRule,
  anchor: DateTime,
) -> Option(List(WeekdaySpecifier)) {
  case spec.by_day {
    Some(values) -> Some(values)
    None ->
      case spec.frequency {
        Weekly -> Some([EveryWeekday(internal_calendar_weekday(anchor))])
        Secondly | Minutely | Hourly | Daily | Monthly | Yearly -> None
      }
  }
}

fn rrule_normalize_default_by_month(
  spec: RecurrenceRule,
  anchor: DateTime,
) -> Option(List(Int)) {
  case spec.by_month {
    Some(values) -> Some(values)
    None ->
      case spec.frequency {
        Yearly ->
          case spec.by_day, spec.by_month_day {
            None, None -> Some([calendar.month_to_int(anchor.date.month)])
            _, _ -> None
          }
        Secondly | Minutely | Hourly | Daily | Weekly | Monthly -> None
      }
  }
}

fn rrule_normalize_default_by_month_day(
  spec: RecurrenceRule,
  anchor: DateTime,
) -> Option(List(Int)) {
  case spec.by_month_day {
    Some(values) -> Some(values)
    None ->
      case spec.by_day {
        Some(_) -> None
        None ->
          case spec.frequency {
            Monthly | Yearly -> Some([anchor.date.day])
            Secondly | Minutely | Hourly | Daily | Weekly -> None
          }
      }
  }
}

/// The recurrence period, from seconds through years.
pub type Frequency {
  Secondly
  Minutely
  Hourly
  Daily
  Weekly
  Monthly
  Yearly
}

/// A weekday filter, optionally with a positive or negative ordinal.
///
/// Ordinal zero is invalid. Numbered weekdays require a monthly or yearly rule; other range and combination checks occur in `rrule_new` or `rrule_validate`.
pub type WeekdaySpecifier {
  EveryWeekday(calendar.DayOfWeek)
  NthWeekday(Int, calendar.DayOfWeek)
}

/// An inclusive recurrence end date or whole-second end time.
///
/// A date includes its entire day. The supported UNTIL year range is 0 through 9999; a DateTime end must have zero nanoseconds.
pub type Until {
  UntilDate(calendar.Date)
  UntilDateTime(DateTime)
}

/// An unbounded rule, a total occurrence count, or an inclusive UNTIL limit.
pub type EndCondition {
  Forever
  Count(Int)
  Until(Until)
}

/// The recurrence field associated with a validation error.
pub type RulePart {
  FreqPart
  IntervalPart
  CountPart
  UntilPart
  ByDayPart
  ByMonthPart
  ByMonthDayPart
  ByHourPart
  ByMinutePart
}

/// A validated recurrence specification without an anchor. Anchor it using `schedule_from_rrule`.
pub opaque type RecurrenceRule {
  RecurrenceRule(
    frequency: Frequency,
    interval: Int,
    end_condition: EndCondition,
    by_day: Option(List(WeekdaySpecifier)),
    by_month: Option(List(Int)),
    by_month_day: Option(List(Int)),
    by_hour: Option(List(Int)),
    by_minute: Option(List(Int)),
  )
}

/// An invalid or unsupported recurrence value, combination, or target integer range.
pub type RruleValidationError {
  RruleMissingPart(part: RulePart)
  RruleDuplicatePart(part: RulePart)
  RruleUnknownPart(name: String)
  RruleUnsupportedPart(name: String)
  RruleInvalidNumber(part: RulePart, value: String)
  RruleInvalidPartValue(part: RulePart, value: String)
  RruleInvalidList(part: RulePart, value: String)
  RruleOutOfRange(part: RulePart, min: Int, max: Int, actual: Int)
  RruleMustBePositive(part: RulePart, actual: Int)
  RruleMutuallyExclusiveParts(left: RulePart, right: RulePart)
  RruleNumericWeekdayRequiresMonthlyOrYearly(frequency: Frequency)
  RruleImpossibleDate(by_month: String, by_month_day: String)
  RruleIncompatibleFrequencyAndPart(frequency: Frequency, part: RulePart)
  RruleUntilMissingZ(value: String)
  RruleUntilMalformedDateTime(value: String)
  RruleIntegerOutOfRange(part: RulePart, actual: Int)
}

type PartialRecurrenceRule {
  PartialRecurrenceRule(
    frequency: Option(Frequency),
    interval: Option(Int),
    end_condition: EndCondition,
    by_day: Option(List(WeekdaySpecifier)),
    by_month: Option(List(Int)),
    by_month_day: Option(List(Int)),
    by_hour: Option(List(Int)),
    by_minute: Option(List(Int)),
    week_start_seen: Bool,
  )
}

/// Validate a raw recurrence rule for the supported scheduler subset.
///
/// Support all seven frequencies, INTERVAL, COUNT or UNTIL, BYDAY, BYMONTH, BYMONTHDAY, BYHOUR, and BYMINUTE. Week starts must be Monday. Reject duplicate or unsupported parts, invalid ranges, and incompatible combinations. COUNT and UNTIL cannot be combined. UNTIL dates use years 0 through 9999; DATE-TIME requires UTC Z notation.
pub fn rrule_validate(
  raw raw: RawRRule,
) -> Result(RecurrenceRule, RruleValidationError) {
  rrule_validator_collect(raw.parts, rrule_validator_empty_partial_rule())
}

fn rrule_validator_from_parts(
  frequency frequency: Frequency,
  interval interval: Int,
  end_condition end_condition: EndCondition,
  by_day by_day: Option(List(WeekdaySpecifier)),
  by_month by_month: Option(List(Int)),
  by_month_day by_month_day: Option(List(Int)),
  by_hour by_hour: Option(List(Int)),
  by_minute by_minute: Option(List(Int)),
) -> Result(RecurrenceRule, RruleValidationError) {
  use _ <- result.try(case interval > 0 {
    True -> Ok(Nil)
    False -> Error(RruleMustBePositive(part: IntervalPart, actual: interval))
  })
  use _ <- result.try(rrule_validate_integer(IntervalPart, interval))
  use _ <- result.try(rrule_validator_check_end_condition(end_condition))
  use by_day <- result.try(rrule_validator_check_weekday_list(by_day))
  use by_month <- result.try(rrule_validator_check_int_list(
    ByMonthPart,
    by_month,
    1,
    12,
    False,
  ))
  use by_month_day <- result.try(rrule_validator_check_int_list(
    ByMonthDayPart,
    by_month_day,
    -31,
    31,
    True,
  ))
  use by_hour <- result.try(rrule_validator_check_int_list(
    ByHourPart,
    by_hour,
    0,
    23,
    False,
  ))
  use by_minute <- result.try(rrule_validator_check_int_list(
    ByMinutePart,
    by_minute,
    0,
    59,
    False,
  ))
  rrule_validator_finalize(PartialRecurrenceRule(
    frequency: Some(frequency),
    interval: Some(interval),
    end_condition:,
    by_day:,
    by_month:,
    by_month_day:,
    by_hour:,
    by_minute:,
    week_start_seen: False,
  ))
}

fn rrule_validator_check_end_condition(
  end_condition: EndCondition,
) -> Result(Nil, RruleValidationError) {
  case end_condition {
    Forever -> Ok(Nil)
    Count(count) ->
      case count > 0 {
        True -> rrule_validate_integer(CountPart, count)
        False -> Error(RruleMustBePositive(part: CountPart, actual: count))
      }
    Until(until) -> {
      // Same rule as for parsed text: UNTIL must be a real date with a
      // four-digit year.
      let #(date, time_ok) = case until {
        UntilDate(date) -> #(date, True)
        UntilDateTime(datetime) -> #(
          datetime.date,
          internal_calendar_is_valid_datetime(datetime),
        )
      }
      case
        time_ok
        && date.year >= 0
        && date.year <= 9999
        && internal_calendar_is_valid_date(date)
      {
        True -> Ok(Nil)
        False ->
          Error(
            RruleUntilMalformedDateTime(value: rrule_validator_until_to_string(
              until,
            )),
          )
      }
    }
  }
}

fn rrule_validator_check_weekday_list(
  values: Option(List(WeekdaySpecifier)),
) -> Result(Option(List(WeekdaySpecifier)), RruleValidationError) {
  case values {
    None -> Ok(None)
    Some([]) -> Error(RruleInvalidList(part: ByDayPart, value: ""))
    Some(items) ->
      list.try_each(items, fn(item) {
        case item {
          NthWeekday(0, day) ->
            Error(RruleInvalidPartValue(
              part: ByDayPart,
              value: "0" <> weekday_to_string(day),
            ))
          NthWeekday(_, _) | EveryWeekday(_) -> Ok(Nil)
        }
      })
      |> result.replace(Some(list.unique(items)))
  }
}

fn rrule_validator_check_int_list(
  part: RulePart,
  values: Option(List(Int)),
  min: Int,
  max: Int,
  reject_zero: Bool,
) -> Result(Option(List(Int)), RruleValidationError) {
  case values {
    None -> Ok(None)
    Some([]) -> Error(RruleInvalidList(part: part, value: ""))
    Some(items) ->
      list.try_each(items, fn(item) {
        rrule_validator_check_int(
          part,
          item,
          int.to_string(item),
          min,
          max,
          reject_zero,
        )
      })
      |> result.replace(Some(list.unique(list.sort(items, by: int.compare))))
  }
}

fn rrule_validator_check_int(
  part: RulePart,
  number: Int,
  text: String,
  min: Int,
  max: Int,
  reject_zero: Bool,
) -> Result(Nil, RruleValidationError) {
  case reject_zero && number == 0 {
    True -> Error(RruleInvalidPartValue(part: part, value: text))
    False ->
      case number < min || number > max {
        True ->
          Error(RruleOutOfRange(part: part, min: min, max: max, actual: number))
        False -> Ok(Nil)
      }
  }
}

/// Render the validated rule as a canonical RRULE string.
pub fn rrule_to_string(spec spec: RecurrenceRule) -> String {
  let parts = ["FREQ=" <> rrule_validator_frequency_to_string(spec.frequency)]

  let parts = case spec.end_condition {
    Forever -> parts
    Count(count) -> list.append(parts, ["COUNT=" <> int.to_string(count)])
    Until(until) ->
      list.append(parts, ["UNTIL=" <> rrule_validator_until_to_string(until)])
  }

  let parts = case spec.interval == 1 {
    True -> parts
    False -> list.append(parts, ["INTERVAL=" <> int.to_string(spec.interval)])
  }

  let parts = rrule_validator_append_weekday_part(parts, spec.by_day)
  let parts = rrule_validator_append_int_part(parts, "BYMONTH", spec.by_month)
  let parts =
    rrule_validator_append_int_part(parts, "BYMONTHDAY", spec.by_month_day)
  let parts = rrule_validator_append_int_part(parts, "BYHOUR", spec.by_hour)
  let parts = rrule_validator_append_int_part(parts, "BYMINUTE", spec.by_minute)

  string.join(parts, with: ";")
}

fn rrule_validator_empty_partial_rule() -> PartialRecurrenceRule {
  PartialRecurrenceRule(
    frequency: None,
    interval: None,
    end_condition: Forever,
    by_day: None,
    by_month: None,
    by_month_day: None,
    by_hour: None,
    by_minute: None,
    week_start_seen: False,
  )
}

fn rrule_validator_collect(
  parts: List(RawRulePart),
  partial: PartialRecurrenceRule,
) -> Result(RecurrenceRule, RruleValidationError) {
  case parts {
    [] -> rrule_validator_finalize(partial)
    [RawRulePart(name:, value:), ..rest] ->
      case rrule_validator_apply_part(name, value, partial) {
        Ok(next) -> rrule_validator_collect(rest, next)
        Error(error) -> Error(error)
      }
  }
}

fn rrule_validator_apply_part(
  name: String,
  value: String,
  partial: PartialRecurrenceRule,
) -> Result(PartialRecurrenceRule, RruleValidationError) {
  case name {
    "FREQ" ->
      rrule_validator_set_optional(
        partial.frequency,
        rrule_validator_parse_frequency(value),
        FreqPart,
        fn(updated) { PartialRecurrenceRule(..partial, frequency: updated) },
      )
    "INTERVAL" ->
      rrule_validator_set_optional(
        partial.interval,
        rrule_validator_parse_positive_int(IntervalPart, value),
        IntervalPart,
        fn(updated) { PartialRecurrenceRule(..partial, interval: updated) },
      )
    "COUNT" ->
      case rrule_validator_parse_positive_int(CountPart, value) {
        Error(error) -> Error(error)
        Ok(count) ->
          case partial.end_condition {
            Forever ->
              Ok(PartialRecurrenceRule(..partial, end_condition: Count(count)))
            Count(_) -> Error(RruleDuplicatePart(part: CountPart))
            Until(_) ->
              Error(RruleMutuallyExclusiveParts(
                left: CountPart,
                right: UntilPart,
              ))
          }
      }
    "UNTIL" ->
      case rrule_validator_parse_until(value) {
        Error(error) -> Error(error)
        Ok(until) ->
          case partial.end_condition {
            Forever ->
              Ok(PartialRecurrenceRule(..partial, end_condition: Until(until)))
            Count(_) ->
              Error(RruleMutuallyExclusiveParts(
                left: CountPart,
                right: UntilPart,
              ))
            Until(_) -> Error(RruleDuplicatePart(part: UntilPart))
          }
      }
    "BYDAY" ->
      rrule_validator_set_optional(
        partial.by_day,
        rrule_validator_parse_weekday_specifiers(value),
        ByDayPart,
        fn(updated) { PartialRecurrenceRule(..partial, by_day: updated) },
      )
    "BYMONTH" ->
      rrule_validator_set_optional(
        partial.by_month,
        rrule_validator_parse_int_list(ByMonthPart, value, 1, 12, False),
        ByMonthPart,
        fn(updated) { PartialRecurrenceRule(..partial, by_month: updated) },
      )
    "BYMONTHDAY" ->
      rrule_validator_set_optional(
        partial.by_month_day,
        rrule_validator_parse_int_list(ByMonthDayPart, value, -31, 31, True),
        ByMonthDayPart,
        fn(updated) { PartialRecurrenceRule(..partial, by_month_day: updated) },
      )
    "BYHOUR" ->
      rrule_validator_set_optional(
        partial.by_hour,
        rrule_validator_parse_int_list(ByHourPart, value, 0, 23, False),
        ByHourPart,
        fn(updated) { PartialRecurrenceRule(..partial, by_hour: updated) },
      )
    "BYMINUTE" ->
      rrule_validator_set_optional(
        partial.by_minute,
        rrule_validator_parse_int_list(ByMinutePart, value, 0, 59, False),
        ByMinutePart,
        fn(updated) { PartialRecurrenceRule(..partial, by_minute: updated) },
      )
    "BYSECOND" -> Error(RruleUnsupportedPart(name: "BYSECOND"))
    "BYYEARDAY" -> Error(RruleUnsupportedPart(name: "BYYEARDAY"))
    "BYWEEKNO" -> Error(RruleUnsupportedPart(name: "BYWEEKNO"))
    "BYSETPOS" -> Error(RruleUnsupportedPart(name: "BYSETPOS"))
    // Weeks always start on Monday here, which is the RFC 5545 default,
    // so WKST=MO changes nothing and is accepted. Other week starts are
    // not implemented.
    // A second WKST is rejected like any repeated part; RulePart has no
    // WKST variant, so it is reported as UnsupportedPart.
    "WKST" ->
      case partial.week_start_seen, string.uppercase(value) {
        False, "MO" ->
          Ok(PartialRecurrenceRule(..partial, week_start_seen: True))
        _, _ -> Error(RruleUnsupportedPart(name: "WKST"))
      }
    "BYEASTER" -> Error(RruleUnsupportedPart(name: "BYEASTER"))
    _ -> Error(RruleUnknownPart(name: name))
  }
}

fn rrule_validator_set_optional(
  current: Option(a),
  parsed: Result(a, RruleValidationError),
  part: RulePart,
  setter: fn(Option(a)) -> PartialRecurrenceRule,
) -> Result(PartialRecurrenceRule, RruleValidationError) {
  case parsed {
    Error(error) -> Error(error)
    Ok(value) ->
      case current {
        None -> Ok(setter(Some(value)))
        Some(_) -> Error(RruleDuplicatePart(part: part))
      }
  }
}

fn rrule_validator_finalize(
  partial: PartialRecurrenceRule,
) -> Result(RecurrenceRule, RruleValidationError) {
  case partial.frequency {
    None -> Error(RruleMissingPart(part: FreqPart))
    Some(frequency) -> {
      let spec =
        RecurrenceRule(
          frequency: frequency,
          interval: case partial.interval {
            None -> 1
            Some(interval) -> interval
          },
          end_condition: partial.end_condition,
          by_day: partial.by_day,
          by_month: partial.by_month,
          by_month_day: partial.by_month_day,
          by_hour: partial.by_hour,
          by_minute: partial.by_minute,
        )

      case rrule_validator_validate_semantics(spec) {
        Ok(_) -> Ok(spec)
        Error(error) -> Error(error)
      }
    }
  }
}

fn rrule_validator_validate_semantics(
  spec: RecurrenceRule,
) -> Result(Nil, RruleValidationError) {
  case rrule_validator_validate_frequency_compatibility(spec) {
    Error(error) -> Error(error)
    Ok(_) ->
      case
        rrule_validator_validate_weekday_ordinals(spec.frequency, spec.by_day)
      {
        Error(error) -> Error(error)
        Ok(_) ->
          case
            rrule_validator_impossible_month_day(
              spec.by_month,
              spec.by_month_day,
            )
          {
            True ->
              Error(
                RruleImpossibleDate(
                  by_month: case spec.by_month {
                    Some(values) -> rrule_validator_int_list_to_string(values)
                    None -> "*"
                  },
                  by_month_day: case spec.by_month_day {
                    Some(values) -> rrule_validator_int_list_to_string(values)
                    None -> "*"
                  },
                ),
              )
            False -> Ok(Nil)
          }
      }
  }
}

fn rrule_validator_validate_frequency_compatibility(
  spec: RecurrenceRule,
) -> Result(Nil, RruleValidationError) {
  case spec.frequency, spec.by_month_day {
    Weekly, Some(_) ->
      Error(RruleIncompatibleFrequencyAndPart(
        frequency: Weekly,
        part: ByMonthDayPart,
      ))
    Weekly, None
    | Secondly, _
    | Minutely, _
    | Hourly, _
    | Daily, _
    | Monthly, _
    | Yearly, _
    -> Ok(Nil)
  }
}

fn rrule_validator_validate_weekday_ordinals(
  frequency: Frequency,
  by_day: Option(List(WeekdaySpecifier)),
) -> Result(Nil, RruleValidationError) {
  case by_day {
    None -> Ok(Nil)
    Some(values) ->
      case
        list.any(values, fn(item) {
          case item {
            EveryWeekday(_) -> False
            NthWeekday(_, _) -> True
          }
        })
      {
        False -> Ok(Nil)
        True ->
          case frequency {
            Monthly -> rrule_validator_validate_ordinal_range(values, 5)
            Yearly -> rrule_validator_validate_ordinal_range(values, 53)
            Secondly | Minutely | Hourly | Daily | Weekly ->
              Error(RruleNumericWeekdayRequiresMonthlyOrYearly(
                frequency: frequency,
              ))
          }
      }
  }
}

fn rrule_validator_validate_ordinal_range(
  values: List(WeekdaySpecifier),
  bound: Int,
) -> Result(Nil, RruleValidationError) {
  case values {
    [] -> Ok(Nil)
    [item, ..rest] ->
      case item {
        NthWeekday(ordinal, day) ->
          case rrule_validator_ordinal_within_bound(ordinal, bound) {
            True -> rrule_validator_validate_ordinal_range(rest, bound)
            False ->
              Error(RruleInvalidPartValue(
                part: ByDayPart,
                value: int.to_string(ordinal) <> weekday_to_string(day),
              ))
          }
        EveryWeekday(_) -> rrule_validator_validate_ordinal_range(rest, bound)
      }
  }
}

fn rrule_validator_ordinal_within_bound(ordinal: Int, bound: Int) -> Bool {
  ordinal != 0 && ordinal >= 0 - bound && ordinal <= bound
}

fn rrule_validator_impossible_month_day(
  by_month: Option(List(Int)),
  by_month_day: Option(List(Int)),
) -> Bool {
  case by_month, by_month_day {
    Some(months), Some(days) ->
      !list.any(months, fn(month) {
        let maximum = internal_gregorian_days_in_month(2024, month)
        list.any(days, fn(day) {
          rrule_validator_day_matches_month_day(day, maximum)
        })
        || list.any(days, fn(day) {
          rrule_validator_day_matches_month_day(
            day,
            internal_gregorian_days_in_month(2025, month),
          )
        })
      })
    _, _ -> False
  }
}

fn rrule_validator_day_matches_month_day(day: Int, maximum: Int) -> Bool {
  case day > 0 {
    True -> day <= maximum
    False -> 0 - day <= maximum
  }
}

fn rrule_validator_parse_frequency(
  value: String,
) -> Result(Frequency, RruleValidationError) {
  case string.uppercase(value) {
    "SECONDLY" -> Ok(Secondly)
    "MINUTELY" -> Ok(Minutely)
    "HOURLY" -> Ok(Hourly)
    "DAILY" -> Ok(Daily)
    "WEEKLY" -> Ok(Weekly)
    "MONTHLY" -> Ok(Monthly)
    "YEARLY" -> Ok(Yearly)
    _ -> Error(RruleInvalidPartValue(part: FreqPart, value: value))
  }
}

fn rrule_validator_parse_positive_int(
  part: RulePart,
  value: String,
) -> Result(Int, RruleValidationError) {
  case parse_digits(value) {
    Error(_) -> Error(RruleInvalidNumber(part, value))
    Ok(number) ->
      case civil_integer_is_exact(number) {
        False -> Error(RruleInvalidNumber(part, value))
        True ->
          case number > 0 {
            True -> Ok(number)
            False -> Error(RruleMustBePositive(part, number))
          }
      }
  }
}

fn rrule_validator_parse_int_list(
  part: RulePart,
  value: String,
  min: Int,
  max: Int,
  reject_zero: Bool,
) -> Result(List(Int), RruleValidationError) {
  case list.any(string.split(value, on: ","), string.is_empty) {
    True -> Error(RruleInvalidList(part: part, value: value))
    False ->
      rrule_validator_parse_int_items(
        string.split(value, on: ","),
        part,
        min,
        max,
        reject_zero,
        [],
      )
  }
}

fn rrule_validator_parse_int_items(
  values: List(String),
  part: RulePart,
  min: Int,
  max: Int,
  reject_zero: Bool,
  acc: List(Int),
) -> Result(List(Int), RruleValidationError) {
  case values {
    [] -> Ok(list.unique(list.sort(acc, by: int.compare)))
    [value, ..rest] ->
      // Only BYMONTHDAY, the list that rejects zero, has signed values.
      case
        case reject_zero {
          True -> int.parse(value)
          False -> parse_digits(value)
        }
      {
        Error(_) -> Error(RruleInvalidNumber(part: part, value: value))
        Ok(number) ->
          case
            rrule_validator_check_int(
              part,
              number,
              value,
              min,
              max,
              reject_zero,
            )
          {
            Error(error) -> Error(error)
            Ok(_) ->
              rrule_validator_parse_int_items(
                rest,
                part,
                min,
                max,
                reject_zero,
                [number, ..acc],
              )
          }
      }
  }
}

fn rrule_validator_parse_weekday_specifiers(
  value: String,
) -> Result(List(WeekdaySpecifier), RruleValidationError) {
  case list.any(string.split(value, on: ","), string.is_empty) {
    True -> Error(RruleInvalidList(part: ByDayPart, value: value))
    False ->
      rrule_validator_collect_weekdays(string.split(value, on: ","), [], value)
  }
}

fn rrule_validator_collect_weekdays(
  values: List(String),
  acc: List(WeekdaySpecifier),
  original: String,
) -> Result(List(WeekdaySpecifier), RruleValidationError) {
  case values {
    [] -> Ok(list.unique(list.reverse(acc)))
    [value, ..rest] ->
      case rrule_validator_parse_weekday_specifier(value) {
        Ok(item) ->
          rrule_validator_collect_weekdays(rest, [item, ..acc], original)
        Error(Nil) ->
          Error(RruleInvalidPartValue(part: ByDayPart, value: original))
      }
  }
}

fn rrule_validator_parse_weekday_specifier(
  value: String,
) -> Result(WeekdaySpecifier, Nil) {
  let upper = string.uppercase(value)
  let length = string.length(upper)
  case length < 2 {
    True -> Error(Nil)
    False -> {
      let prefix_length = length - 2
      let prefix = string.slice(upper, 0, prefix_length)
      let suffix = string.slice(upper, prefix_length, 2)
      use weekday <- result.try(rrule_validator_parse_weekday(suffix))
      rrule_weekday_ordinal(prefix, weekday)
    }
  }
}

fn rrule_validator_parse_weekday(
  value: String,
) -> Result(calendar.DayOfWeek, Nil) {
  case value {
    "MO" -> Ok(calendar.Monday)
    "TU" -> Ok(calendar.Tuesday)
    "WE" -> Ok(calendar.Wednesday)
    "TH" -> Ok(calendar.Thursday)
    "FR" -> Ok(calendar.Friday)
    "SA" -> Ok(calendar.Saturday)
    "SU" -> Ok(calendar.Sunday)
    _ -> Error(Nil)
  }
}

fn rrule_validator_parse_until(
  value: String,
) -> Result(Until, RruleValidationError) {
  case string.length(value) {
    8 ->
      case rrule_validator_parse_date(value) {
        Ok(date) -> Ok(UntilDate(date))
        Error(error) -> Error(error)
      }
    15 ->
      case string.slice(from: value, at_index: 8, length: 1) == "T" {
        True -> rrule_validator_classify_unzed_local_form(value)
        False -> Error(RruleUntilMalformedDateTime(value: value))
      }
    16 ->
      case string.slice(from: value, at_index: 8, length: 1) == "T" {
        False -> Error(RruleUntilMalformedDateTime(value: value))
        True ->
          case string.slice(from: value, at_index: 15, length: 1) == "Z" {
            False -> Error(RruleUntilMissingZ(value: value))
            True ->
              case rrule_validator_parse_datetime(value) {
                Ok(datetime) -> Ok(UntilDateTime(datetime))
                Error(error) -> Error(error)
              }
          }
      }
    _ -> Error(RruleUntilMalformedDateTime(value: value))
  }
}

fn rrule_validator_classify_unzed_local_form(
  value: String,
) -> Result(Until, RruleValidationError) {
  case rrule_validator_parse_local_datetime_components(value) {
    Ok(_) -> Error(RruleUntilMissingZ(value: value))
    Error(_) -> Error(RruleUntilMalformedDateTime(value: value))
  }
}

fn rrule_validator_parse_local_datetime_components(
  value: String,
) -> Result(Nil, Nil) {
  {
    use _ <- result.try(
      rrule_validator_parse_fixed_int(value, 0, 4) |> result.replace_error(Nil),
    )
    use _ <- result.try(
      rrule_validator_parse_fixed_int(value, 4, 2) |> result.replace_error(Nil),
    )
    use _ <- result.try(
      rrule_validator_parse_fixed_int(value, 6, 2) |> result.replace_error(Nil),
    )
    use _ <- result.try(
      rrule_validator_parse_fixed_int(value, 9, 2) |> result.replace_error(Nil),
    )
    use _ <- result.try(
      rrule_validator_parse_fixed_int(value, 11, 2) |> result.replace_error(Nil),
    )
    use _ <- result.try(
      rrule_validator_parse_fixed_int(value, 13, 2) |> result.replace_error(Nil),
    )
    Ok(Nil)
  }
}

fn rrule_validator_parse_date(
  value: String,
) -> Result(calendar.Date, RruleValidationError) {
  use year <- result.try(
    rrule_validator_parse_fixed_int(value, 0, 4)
    |> result.replace_error(RruleUntilMalformedDateTime(value)),
  )
  use month <- result.try(
    rrule_validator_parse_fixed_int(value, 4, 2)
    |> result.replace_error(RruleUntilMalformedDateTime(value)),
  )
  use day <- result.try(
    rrule_validator_parse_fixed_int(value, 6, 2)
    |> result.replace_error(RruleUntilMalformedDateTime(value)),
  )
  use month <- result.try(
    calendar.month_from_int(month)
    |> result.replace_error(RruleUntilMalformedDateTime(value)),
  )
  let date = calendar.Date(year, month, day)
  case internal_calendar_is_valid_date(date) {
    True -> Ok(date)
    False -> Error(RruleUntilMalformedDateTime(value))
  }
}

fn rrule_validator_parse_datetime(
  value: String,
) -> Result(DateTime, RruleValidationError) {
  {
    use date <- result.try(rrule_validator_parse_date_in_datetime(value))
    use hour <- result.try(
      rrule_validator_parse_fixed_int(value, 9, 2)
      |> result.replace_error(RruleUntilMalformedDateTime(value: value)),
    )
    use minute <- result.try(
      rrule_validator_parse_fixed_int(value, 11, 2)
      |> result.replace_error(RruleUntilMalformedDateTime(value: value)),
    )
    use second <- result.try(
      rrule_validator_parse_fixed_int(value, 13, 2)
      |> result.replace_error(RruleUntilMalformedDateTime(value: value)),
    )

    let datetime =
      DateTime(
        date: date,
        time: civil_time(hour: hour, minute: minute, second: second),
      )
    case internal_calendar_is_valid_datetime(datetime) {
      True -> Ok(datetime)
      False -> Error(RruleUntilMalformedDateTime(value: value))
    }
  }
}

fn rrule_validator_parse_date_in_datetime(
  value: String,
) -> Result(calendar.Date, RruleValidationError) {
  case
    rrule_validator_parse_date(string.slice(from: value, at_index: 0, length: 8))
  {
    Ok(date) -> Ok(date)
    Error(_) -> Error(RruleUntilMalformedDateTime(value: value))
  }
}

fn rrule_validator_parse_fixed_int(
  value: String,
  start: Int,
  length: Int,
) -> Result(Int, Nil) {
  let text = string.slice(from: value, at_index: start, length: length)
  case string.length(text) == length {
    True -> parse_digits(text)
    False -> Error(Nil)
  }
}

// Parse one or more ASCII digits. int.parse alone also accepts a sign, which
// cron fields, RRULE counts, and date-time digits do not allow.
fn parse_digits(text: String) -> Result(Int, Nil) {
  case
    text != ""
    && list.all(string.to_graphemes(text), fn(digit) {
      string.contains("0123456789", digit)
    })
  {
    True -> int.parse(text)
    False -> Error(Nil)
  }
}

fn rrule_validator_append_int_part(
  parts: List(String),
  name: String,
  values: Option(List(Int)),
) -> List(String) {
  case values {
    None -> parts
    Some(items) ->
      list.append(parts, [
        name <> "=" <> rrule_validator_int_list_to_string(items),
      ])
  }
}

fn rrule_validator_append_weekday_part(
  parts: List(String),
  values: Option(List(WeekdaySpecifier)),
) -> List(String) {
  case values {
    None -> parts
    Some(items) ->
      list.append(parts, [
        "BYDAY="
        <> string.join(
          list.map(items, rrule_validator_weekday_specifier_to_string),
          with: ",",
        ),
      ])
  }
}

fn rrule_validator_weekday_specifier_to_string(
  specifier: WeekdaySpecifier,
) -> String {
  case specifier {
    EveryWeekday(day) -> weekday_to_string(day)
    NthWeekday(ordinal, day) -> int.to_string(ordinal) <> weekday_to_string(day)
  }
}

fn rrule_validator_frequency_to_string(frequency: Frequency) -> String {
  case frequency {
    Secondly -> "SECONDLY"
    Minutely -> "MINUTELY"
    Hourly -> "HOURLY"
    Daily -> "DAILY"
    Weekly -> "WEEKLY"
    Monthly -> "MONTHLY"
    Yearly -> "YEARLY"
  }
}

fn rrule_validator_until_to_string(until: Until) -> String {
  case until {
    UntilDate(date) -> rrule_validator_date_to_string(date)
    UntilDateTime(datetime) -> rrule_validator_datetime_to_string(datetime)
  }
}

fn rrule_validator_date_to_string(date: calendar.Date) -> String {
  internal_digits_pad4(date.year)
  <> internal_digits_pad2(calendar.month_to_int(date.month))
  <> internal_digits_pad2(date.day)
}

fn rrule_validator_datetime_to_string(datetime: DateTime) -> String {
  let fraction = case datetime.time.nanoseconds {
    0 -> ""
    nanos -> "." <> string.pad_start(int.to_string(nanos), 9, "0")
  }
  rrule_validator_date_to_string(datetime.date)
  <> "T"
  <> internal_digits_pad2(datetime.time.hours)
  <> internal_digits_pad2(datetime.time.minutes)
  <> internal_digits_pad2(datetime.time.seconds)
  <> fraction
  <> "Z"
}

fn rrule_validator_int_list_to_string(items: List(Int)) -> String {
  string.join(list.map(items, int.to_string), with: ",")
}

/// A syntax error in RRULE parts, before semantic validation.
pub type RruleParseError {
  RruleParseInvalidRule(value: String)
  RruleParseInvalidPartSyntax(value: String)
  RruleParseEmptyPart(value: String)
}

/// Parse RRULE syntax while preserving its ordered name/value parts.
///
/// This stage does not check supported frequencies, duplicate parts, or value ranges. Call `rrule_validate` for those checks. Raw rules can also be stored in iCalendar components without compiling a schedule.
pub fn rrule_parse_raw(
  input input: String,
) -> Result(RawRRule, RruleParseError) {
  let trimmed = string.trim(input)

  case trimmed {
    "" -> Error(RruleParseInvalidRule(value: input))
    _ -> rrule_parser_parse_parts(rrule_parser_strip_prefix(trimmed))
  }
}

fn rrule_parser_strip_prefix(input: String) -> String {
  case string.starts_with(string.uppercase(input), "RRULE:") {
    True -> string.drop_start(input, up_to: 6)
    False -> input
  }
}

fn rrule_parser_parse_parts(body: String) -> Result(RawRRule, RruleParseError) {
  case body {
    "" -> Error(RruleParseInvalidRule(value: body))
    _ ->
      case list.any(string.split(body, on: ";"), string.is_empty) {
        True -> Error(RruleParseInvalidRule(value: body))
        False -> rrule_parser_collect_parts(string.split(body, on: ";"), [])
      }
  }
}

fn rrule_parser_collect_parts(
  parts: List(String),
  acc: List(RawRulePart),
) -> Result(RawRRule, RruleParseError) {
  case parts {
    [] -> Ok(RawRRule(parts: list.reverse(acc)))
    [part, ..rest] ->
      case string.split_once(string.trim(part), on: "=") {
        Error(_) -> Error(RruleParseInvalidPartSyntax(value: part))
        Ok(#(name, value)) ->
          case string.trim(name) == "" || string.trim(value) == "" {
            True -> Error(RruleParseEmptyPart(value: part))
            False ->
              rrule_parser_collect_parts(rest, [
                RawRulePart(
                  name: string.uppercase(string.trim(name)),
                  value: string.trim(value),
                ),
                ..acc
              ])
          }
      }
  }
}

fn rrule_evaluator_day_matches(
  plan: RecurrencePlan,
  date: calendar.Date,
) -> Bool {
  let datetime =
    DateTime(date:, time: civil_time(hour: 0, minute: 0, second: 0))
  let month_match = case plan.by_month {
    None -> True
    Some(values) ->
      list.any(values, fn(item) { item == calendar.month_to_int(date.month) })
  }
  let month_day_match =
    rrule_evaluator_month_day_matches(plan.by_month_day, date)
  let weekday_match =
    rrule_evaluator_weekday_matches(plan, plan.by_day, datetime)

  month_match
  && case plan.by_month_day, plan.by_day {
    Some(_), Some(_) -> month_day_match && weekday_match
    Some(_), None -> month_day_match
    None, Some(_) -> weekday_match
    None, None -> True
  }
}

fn rrule_evaluator_base_match(plan: RecurrencePlan, at: DateTime) -> Bool {
  rrule_evaluator_aligned(plan, at)
  && rrule_evaluator_day_matches(plan, at.date)
  && list.any(plan.by_hour, fn(hour) { hour == at.time.hours })
  && list.any(plan.by_minute, fn(minute) { minute == at.time.minutes })
  && list.any(plan.seconds, fn(second) { second == at.time.seconds })
}

fn rrule_evaluator_aligned(plan: RecurrencePlan, at: DateTime) -> Bool {
  recurrence_period_remainder(plan, at) == 0
}

fn rrule_evaluator_within_until(
  end_condition: EndCondition,
  at: DateTime,
) -> Bool {
  case end_condition {
    Until(UntilDate(date)) ->
      internal_calendar_less_or_equal(
        at,
        rrule_evaluator_date_to_datetime(date),
      )
    Until(UntilDateTime(limit)) -> internal_calendar_less_or_equal(at, limit)
    Forever | Count(_) -> True
  }
}

fn rrule_evaluator_date_to_datetime(date: calendar.Date) -> DateTime {
  DateTime(date:, time: civil_time(hour: 23, minute: 59, second: 59))
}

fn rrule_evaluator_month_day_matches(
  values: Option(List(Int)),
  date: calendar.Date,
) -> Bool {
  case values {
    None -> True
    Some(items) -> {
      let maximum =
        internal_gregorian_days_in_month(
          date.year,
          calendar.month_to_int(date.month),
        )
      list.any(items, fn(item) {
        case item > 0 {
          True -> item == date.day
          False -> maximum + item + 1 == date.day
        }
      })
    }
  }
}

fn rrule_evaluator_weekday_matches(
  plan: RecurrencePlan,
  values: Option(List(WeekdaySpecifier)),
  at: DateTime,
) -> Bool {
  case values {
    None -> True
    Some(items) -> {
      let actual = internal_calendar_weekday(at)
      list.any(items, fn(item) {
        rrule_evaluator_weekday_specifier_matches(plan, item, actual, at.date)
      })
    }
  }
}

fn rrule_evaluator_weekday_specifier_matches(
  plan: RecurrencePlan,
  specifier: WeekdaySpecifier,
  actual: calendar.DayOfWeek,
  date: calendar.Date,
) -> Bool {
  case specifier {
    EveryWeekday(expected) -> expected == actual
    NthWeekday(ordinal, expected) ->
      expected == actual
      && rrule_evaluator_nth_weekday_matches(plan, ordinal, expected, date)
  }
}

fn rrule_evaluator_nth_weekday_matches(
  plan: RecurrencePlan,
  ordinal: Int,
  weekday: calendar.DayOfWeek,
  date: calendar.Date,
) -> Bool {
  let occurrences = case rrule_evaluator_nth_scope(plan) {
    YearScope -> rrule_evaluator_weekday_occurrences_in_year(weekday, date.year)
    MonthScope ->
      rrule_evaluator_weekday_occurrences_in_month(
        weekday,
        date.year,
        date.month,
      )
  }

  case ordinal > 0 {
    True ->
      case list.drop(occurrences, ordinal - 1) {
        [match, ..] ->
          match.month == calendar.month_to_int(date.month)
          && match.day == date.day
        [] -> False
      }
    False ->
      case list.drop(list.reverse(occurrences), { 0 - ordinal } - 1) {
        [match, ..] ->
          match.month == calendar.month_to_int(date.month)
          && match.day == date.day
        [] -> False
      }
  }
}

type WeekdayScope {
  MonthScope
  YearScope
}

type WeekdayOccurrence {
  WeekdayOccurrence(month: Int, day: Int)
}

fn rrule_evaluator_nth_scope(plan: RecurrencePlan) -> WeekdayScope {
  case plan.frequency, plan.by_month {
    Yearly, None -> YearScope
    Yearly, Some(_)
    | Monthly, _
    | Weekly, _
    | Daily, _
    | Hourly, _
    | Minutely, _
    | Secondly, _
    -> MonthScope
  }
}

fn rrule_evaluator_weekday_occurrences_in_month(
  weekday: calendar.DayOfWeek,
  year: Int,
  month: calendar.Month,
) -> List(WeekdayOccurrence) {
  rrule_evaluator_weekday_occurrences_in_month_loop(weekday, year, month, 1, [])
}

fn rrule_evaluator_weekday_occurrences_in_month_loop(
  weekday: calendar.DayOfWeek,
  year: Int,
  month: calendar.Month,
  day: Int,
  acc: List(WeekdayOccurrence),
) -> List(WeekdayOccurrence) {
  let maximum =
    internal_gregorian_days_in_month(year, calendar.month_to_int(month))

  case day > maximum {
    True -> list.reverse(acc)
    False -> {
      let datetime =
        DateTime(
          date: calendar.Date(year, month, day),
          time: civil_time(hour: 0, minute: 0, second: 0),
        )
      case internal_calendar_weekday(datetime) == weekday {
        True ->
          rrule_evaluator_weekday_occurrences_in_month_loop(
            weekday,
            year,
            month,
            day + 1,
            [
              WeekdayOccurrence(month: calendar.month_to_int(month), day: day),
              ..acc
            ],
          )
        False ->
          rrule_evaluator_weekday_occurrences_in_month_loop(
            weekday,
            year,
            month,
            day + 1,
            acc,
          )
      }
    }
  }
}

fn rrule_evaluator_weekday_occurrences_in_year(
  weekday: calendar.DayOfWeek,
  year: Int,
) -> List(WeekdayOccurrence) {
  [
    calendar.January,
    calendar.February,
    calendar.March,
    calendar.April,
    calendar.May,
    calendar.June,
    calendar.July,
    calendar.August,
    calendar.September,
    calendar.October,
    calendar.November,
    calendar.December,
  ]
  |> list.flat_map(rrule_evaluator_weekday_occurrences_in_month(
    weekday,
    year,
    _,
  ))
}

fn rrule_evaluator_weekday_offset(day: calendar.DayOfWeek) -> Int {
  case day {
    calendar.Monday -> 0
    calendar.Tuesday -> 1
    calendar.Wednesday -> 2
    calendar.Thursday -> 3
    calendar.Friday -> 4
    calendar.Saturday -> 5
    calendar.Sunday -> 6
  }
}

/// One RRULE name and its unvalidated text value.
pub type RawRulePart {
  RawRulePart(name: String, value: String)
}

/// Ordered, unvalidated RRULE name/value parts. Duplicate names are still representable.
pub type RawRRule {
  RawRRule(parts: List(RawRulePart))
}

/// Calendar components and properties with their preserved wire forms.
///
/// The opaque representation keeps values and forms aligned. It does not guarantee complete RFC validity; construction stores supplied values and `ical_encode` checks supported wire constraints.
pub opaque type IcalCalendar {
  IcalCalendar(
    version: String,
    product_id: String,
    method: Option(String),
    calscale: Option(String),
    // Components are kept newest first so that `add_*` is O(1); the
    // accessors reverse them back into document order.
    events_rev: List(IcalEvent),
    todos_rev: List(IcalTodo),
    journals_rev: List(IcalJournal),
    freebusy_rev: List(IcalFreeBusy),
    timezones_rev: List(IcalTimezone),
    unknown_components_rev: List(IcalUnknownComponent),
    x_properties: Dict(String, String),
    forms: Dict(String, PropertyForm),
  )
}

/// A VEVENT with typed fields and preserved parameters, date forms, repeated values, and alarms.
pub opaque type IcalEvent {
  IcalEvent(
    uid: String,
    dtstamp: DateTime,
    dtstart: Option(DateTime),
    dtstart_tzid: Option(String),
    dtend: Option(DateTime),
    dtend_tzid: Option(String),
    duration: Option(String),
    summary: Option(String),
    description: Option(String),
    location: Option(String),
    status: Option(String),
    organizer: Option(String),
    attendees_rev: List(#(String, PropertyForm)),
    categories_rev: List(#(String, PropertyForm)),
    url: Option(String),
    created: Option(DateTime),
    last_modified: Option(DateTime),
    sequence: Int,
    transparency: Option(String),
    rrule: Option(RawRRule),
    rdates_rev: List(#(DateTime, PropertyForm)),
    exdates_rev: List(#(DateTime, PropertyForm)),
    alarms_rev: List(IcalAlarm),
    x_properties: Dict(String, String),
    forms: Dict(String, PropertyForm),
  )
}

/// A VTODO task with typed fields, preserved property forms, recurrence dates, and alarms.
pub opaque type IcalTodo {
  IcalTodo(
    uid: String,
    dtstamp: DateTime,
    dtstart: Option(DateTime),
    due: Option(DateTime),
    completed: Option(DateTime),
    summary: Option(String),
    description: Option(String),
    status: Option(String),
    percent_complete: Option(Int),
    priority: Option(Int),
    categories_rev: List(#(String, PropertyForm)),
    rrule: Option(RawRRule),
    rdates_rev: List(#(DateTime, PropertyForm)),
    exdates_rev: List(#(DateTime, PropertyForm)),
    alarms_rev: List(IcalAlarm),
    x_properties: Dict(String, String),
    forms: Dict(String, PropertyForm),
  )
}

/// A VJOURNAL with typed fields, categories, extension properties, and preserved forms.
pub opaque type IcalJournal {
  IcalJournal(
    uid: String,
    dtstamp: DateTime,
    dtstart: Option(DateTime),
    summary: Option(String),
    description: Option(String),
    status: Option(String),
    categories_rev: List(#(String, PropertyForm)),
    x_properties: Dict(String, String),
    forms: Dict(String, PropertyForm),
  )
}

/// A VFREEBUSY with typed date fields, attendees, string-valued periods, and preserved forms.
pub opaque type IcalFreeBusy {
  IcalFreeBusy(
    uid: String,
    dtstamp: DateTime,
    dtstart: Option(DateTime),
    dtend: Option(DateTime),
    organizer: Option(String),
    attendees_rev: List(#(String, PropertyForm)),
    freebusy_periods_rev: List(#(String, PropertyForm)),
    x_properties: Dict(String, String),
    forms: Dict(String, PropertyForm),
  )
}

/// A VTIMEZONE with STANDARD and DAYLIGHT rules and their preserved forms. It does not perform timezone conversion.
pub opaque type IcalTimezone {
  IcalTimezone(
    tzid: String,
    last_modified: Option(DateTime),
    tzurl: Option(String),
    standard_rev: List(#(IcalTimezoneRule, Dict(String, PropertyForm))),
    daylight_rev: List(#(IcalTimezoneRule, Dict(String, PropertyForm))),
    x_properties: Dict(String, String),
    forms: Dict(String, PropertyForm),
  )
}

/// A STANDARD or DAYLIGHT rule for a timezone component.
///
/// Use record construction and updates. DTSTART is a civil value; offsets and recurrence syntax are stored without executing a timezone calculation.
pub type IcalTimezoneRule {
  IcalTimezoneRule(
    dtstart: DateTime,
    tzoffsetfrom: String,
    tzoffsetto: String,
    rrule: Option(RawRRule),
    tzname: Option(String),
  )
}

/// A VALARM with string-valued action and trigger, optional fields, attendees, and preserved forms.
pub opaque type IcalAlarm {
  IcalAlarm(
    action: String,
    trigger: String,
    description: Option(String),
    summary: Option(String),
    repeat: Option(Int),
    duration: Option(String),
    attendees_rev: List(#(String, PropertyForm)),
    x_properties: Dict(String, String),
    forms: Dict(String, PropertyForm),
  )
}

type PropertyForm {
  PropertyForm(
    parameters: List(IcalParameter),
    utc: Bool,
    date_only: Bool,
    raw_text: Bool,
  )
}

const ical_validator_utc_form =
  PropertyForm(parameters: [], utc: True, date_only: False, raw_text: False)

/// An unrecognized component whose raw properties and nested components are preserved.
pub type IcalUnknownComponent {
  IcalUnknownComponent(
    kind: String,
    properties: List(IcalRawProperty),
    children: List(IcalRawComponent),
  )
}

/// Interpret a raw calendar as typed components and preserved unknown components.
///
/// Check required properties and supported date, integer, escape, and RRULE syntax. RRULE values remain raw rules; this step does not validate them for scheduling. Keep DATE, floating, UTC, TZID, and parameter forms for later encoding. This is not a complete RFC conformance check.
pub fn ical_validate(raw: IcalRawCalendar) -> Result(IcalCalendar, IcalError) {
  let IcalRawCalendar(properties: properties, components: components) = raw
  case ical_validator_find_value(properties, "VERSION") {
    None -> Error(IcalMissingVersion)
    Some(version_raw) ->
      case ical_validator_find_value(properties, "PRODID") {
        None -> Error(IcalMissingProductId)
        Some(prod_raw) -> {
          let method = ical_validator_find_value(properties, "METHOD")
          let calscale = ical_validator_find_value(properties, "CALSCALE")
          let x_props = ical_validator_collect_x_properties(properties)
          {
            use buckets <- result.try(ical_validator_classify_components(
              components,
            ))

            let CalendarComponents(
              events: ical_events,
              todos: ical_todos,
              journals: ical_journals,
              freebusy: ical_freebusy,
              timezones: ical_timezones,
              unknowns: unknowns,
            ) = buckets
            Ok(IcalCalendar(
              version: version_raw,
              product_id: prod_raw,
              method: method,
              calscale: calscale,
              events_rev: ical_events,
              todos_rev: ical_todos,
              journals_rev: ical_journals,
              freebusy_rev: ical_freebusy,
              timezones_rev: ical_timezones,
              unknown_components_rev: unknowns,
              x_properties: x_props,
              forms: ical_validator_forms_of(properties),
            ))
          }
        }
      }
  }
}

type CalendarComponents {
  CalendarComponents(
    events: List(IcalEvent),
    todos: List(IcalTodo),
    journals: List(IcalJournal),
    freebusy: List(IcalFreeBusy),
    timezones: List(IcalTimezone),
    unknowns: List(IcalUnknownComponent),
  )
}

fn ical_validator_empty_buckets() -> CalendarComponents {
  CalendarComponents(
    events: [],
    todos: [],
    journals: [],
    freebusy: [],
    timezones: [],
    unknowns: [],
  )
}

fn ical_validator_classify_components(
  components: List(IcalRawComponent),
) -> Result(CalendarComponents, IcalError) {
  // The buckets come out newest first, which is how `Calendar` stores
  // its components.
  ical_validator_do_classify(components, ical_validator_empty_buckets())
}

fn ical_validator_do_classify(
  components: List(IcalRawComponent),
  acc: CalendarComponents,
) -> Result(CalendarComponents, IcalError) {
  case components {
    [] -> Ok(acc)
    [first, ..rest] -> {
      let IcalRawComponent(kind: kind, ..) = first
      case kind {
        "VEVENT" ->
          case ical_validator_validate_event(first) {
            Error(err) -> Error(err)
            Ok(event) ->
              ical_validator_do_classify(
                rest,
                CalendarComponents(..acc, events: [event, ..acc.events]),
              )
          }
        "VTODO" ->
          case ical_validator_validate_todo(first) {
            Error(err) -> Error(err)
            Ok(todo_item) ->
              ical_validator_do_classify(
                rest,
                CalendarComponents(..acc, todos: [todo_item, ..acc.todos]),
              )
          }
        "VJOURNAL" ->
          case ical_validator_validate_journal(first) {
            Error(err) -> Error(err)
            Ok(j) ->
              ical_validator_do_classify(
                rest,
                CalendarComponents(..acc, journals: [j, ..acc.journals]),
              )
          }
        "VFREEBUSY" ->
          case ical_validator_validate_freebusy(first) {
            Error(err) -> Error(err)
            Ok(fb) ->
              ical_validator_do_classify(
                rest,
                CalendarComponents(..acc, freebusy: [fb, ..acc.freebusy]),
              )
          }
        "VTIMEZONE" ->
          case ical_validator_validate_timezone(first) {
            Error(err) -> Error(err)
            Ok(tz) ->
              ical_validator_do_classify(
                rest,
                CalendarComponents(..acc, timezones: [tz, ..acc.timezones]),
              )
          }
        _ -> {
          let IcalRawComponent(properties: props, children: children, ..) =
            first
          let unknown =
            IcalUnknownComponent(
              kind: kind,
              properties: props,
              children: children,
            )
          ical_validator_do_classify(
            rest,
            CalendarComponents(..acc, unknowns: [unknown, ..acc.unknowns]),
          )
        }
      }
    }
  }
}

fn ical_validator_validate_event(
  comp: IcalRawComponent,
) -> Result(IcalEvent, IcalError) {
  let IcalRawComponent(properties: props, children: children, ..) = comp
  case ical_validator_find_value(props, "UID") {
    None ->
      Error(IcalMissingComponentProperty(component: "VEVENT", name: "UID"))
    Some(uid) ->
      case ical_validator_find_dt(props, "DTSTAMP") {
        Error(err) -> Error(err)
        Ok(None) ->
          Error(IcalMissingComponentProperty(
            component: "VEVENT",
            name: "DTSTAMP",
          ))
        Ok(Some(dtstamp)) ->
          ical_validator_build_event_body(uid, dtstamp, props, children)
      }
  }
}

fn ical_validator_build_event_body(
  uid: String,
  dtstamp: DateTime,
  props: List(IcalRawProperty),
  children: List(IcalRawComponent),
) -> Result(IcalEvent, IcalError) {
  case ical_validator_find_dt(props, "DTSTART") {
    Error(err) -> Error(err)
    Ok(dtstart) -> {
      let dtstart_tzid = ical_validator_find_tzid(props, "DTSTART")
      case ical_validator_find_dt(props, "DTEND") {
        Error(err) -> Error(err)
        Ok(dtend) -> {
          let dtend_tzid = ical_validator_find_tzid(props, "DTEND")
          ical_validator_build_event_optional(
            uid,
            dtstamp,
            dtstart,
            dtstart_tzid,
            dtend,
            dtend_tzid,
            props,
            children,
          )
        }
      }
    }
  }
}

fn ical_validator_build_event_optional(
  uid: String,
  dtstamp: DateTime,
  dtstart: Option(DateTime),
  dtstart_tzid: Option(String),
  dtend: Option(DateTime),
  dtend_tzid: Option(String),
  props: List(IcalRawProperty),
  children: List(IcalRawComponent),
) -> Result(IcalEvent, IcalError) {
  case
    ical_validator_opt_unescape(ical_validator_find_value(props, "SUMMARY"))
  {
    Error(err) -> Error(err)
    Ok(summary) ->
      case
        ical_validator_opt_unescape(ical_validator_find_value(
          props,
          "DESCRIPTION",
        ))
      {
        Error(err) -> Error(err)
        Ok(description) ->
          case
            ical_validator_opt_unescape(ical_validator_find_value(
              props,
              "LOCATION",
            ))
          {
            Error(err) -> Error(err)
            Ok(location) ->
              ical_validator_build_event_rest(
                uid,
                dtstamp,
                dtstart,
                dtstart_tzid,
                dtend,
                dtend_tzid,
                summary,
                description,
                location,
                props,
                children,
              )
          }
      }
  }
}

fn ical_validator_build_event_rest(
  uid: String,
  dtstamp: DateTime,
  dtstart: Option(DateTime),
  dtstart_tzid: Option(String),
  dtend: Option(DateTime),
  dtend_tzid: Option(String),
  summary: Option(String),
  description: Option(String),
  location: Option(String),
  props: List(IcalRawProperty),
  children: List(IcalRawComponent),
) -> Result(IcalEvent, IcalError) {
  {
    use categories_rev <- result.try(ical_validator_categories_of(props))
    use sequence <- result.try(ical_validator_parse_sequence(props))
    use created <- result.try(ical_validator_find_dt(props, "CREATED"))
    use last_modified <- result.try(ical_validator_find_dt(
      props,
      "LAST-MODIFIED",
    ))
    use rrule_value <- result.try(ical_validator_parse_event_rrule(uid, props))
    use rdates_rev <- result.try(ical_validator_parse_datetime_list_prop(
      props,
      "RDATE",
    ))
    use exdates_rev <- result.try(ical_validator_parse_datetime_list_prop(
      props,
      "EXDATE",
    ))
    ical_validator_finalize_event(
      uid,
      dtstamp,
      dtstart,
      dtstart_tzid,
      dtend,
      dtend_tzid,
      summary,
      description,
      location,
      categories_rev,
      sequence,
      created,
      last_modified,
      rrule_value,
      rdates_rev,
      exdates_rev,
      props,
      children,
    )
  }
}

fn ical_validator_finalize_event(
  uid: String,
  dtstamp: DateTime,
  dtstart: Option(DateTime),
  dtstart_tzid: Option(String),
  dtend: Option(DateTime),
  dtend_tzid: Option(String),
  summary: Option(String),
  description: Option(String),
  location: Option(String),
  categories_rev: List(#(String, PropertyForm)),
  sequence: Int,
  created: Option(DateTime),
  last_modified: Option(DateTime),
  rrule_value: Option(RawRRule),
  rdates_rev: List(#(DateTime, PropertyForm)),
  exdates_rev: List(#(DateTime, PropertyForm)),
  props: List(IcalRawProperty),
  children: List(IcalRawComponent),
) -> Result(IcalEvent, IcalError) {
  case ical_validator_collect_alarms(children) {
    Error(err) -> Error(err)
    Ok(alarms_rev) -> {
      let duration = ical_validator_find_value(props, "DURATION")
      let status = ical_validator_find_value(props, "STATUS")
      let organizer = ical_validator_find_value(props, "ORGANIZER")
      let url = ical_validator_find_value(props, "URL")
      let transparency = ical_validator_find_value(props, "TRANSP")
      let attendees_rev = ical_repeated_values(props, "ATTENDEE")
      let x_props = ical_validator_collect_x_properties(props)
      Ok(IcalEvent(
        uid: uid,
        dtstamp: dtstamp,
        dtstart: dtstart,
        dtstart_tzid: dtstart_tzid,
        dtend: dtend,
        dtend_tzid: dtend_tzid,
        duration: duration,
        summary: summary,
        description: description,
        location: location,
        status: status,
        organizer: organizer,
        attendees_rev: attendees_rev,
        categories_rev: categories_rev,
        url: url,
        created: created,
        last_modified: last_modified,
        sequence: sequence,
        transparency: transparency,
        rrule: rrule_value,
        rdates_rev: rdates_rev,
        exdates_rev: exdates_rev,
        alarms_rev: alarms_rev,
        x_properties: x_props,
        forms: ical_validator_forms_of(props),
      ))
    }
  }
}

fn ical_validator_parse_sequence(
  props: List(IcalRawProperty),
) -> Result(Int, IcalError) {
  case ical_validator_find_value(props, "SEQUENCE") {
    None -> Ok(0)
    Some(raw) ->
      case int.parse(raw) {
        Ok(v) -> Ok(v)
        Error(_) -> Error(IcalInvalidInteger(name: "SEQUENCE", raw: raw))
      }
  }
}

fn ical_validator_parse_event_rrule(
  uid: String,
  props: List(IcalRawProperty),
) -> Result(Option(RawRRule), IcalError) {
  case ical_validator_collect_values(props, "RRULE") {
    [] -> Ok(None)
    [single] ->
      case rrule_parse_raw(input: single) {
        Ok(parsed) -> Ok(Some(parsed))
        Error(err) -> Error(IcalInvalidRRule(raw: single, error: err))
      }
    [_, _, ..] -> Error(IcalDuplicateRRule(component_uid: uid))
  }
}

fn ical_validator_validate_todo(
  comp: IcalRawComponent,
) -> Result(IcalTodo, IcalError) {
  let IcalRawComponent(properties: props, children: children, ..) = comp
  case ical_validator_find_value(props, "UID") {
    None -> Error(IcalMissingComponentProperty(component: "VTODO", name: "UID"))
    Some(uid) ->
      case ical_validator_find_dt(props, "DTSTAMP") {
        Error(err) -> Error(err)
        Ok(None) ->
          Error(IcalMissingComponentProperty(
            component: "VTODO",
            name: "DTSTAMP",
          ))
        Ok(Some(dtstamp)) ->
          ical_validator_build_todo_body(uid, dtstamp, props, children)
      }
  }
}

fn ical_validator_build_todo_body(
  uid: String,
  dtstamp: DateTime,
  props: List(IcalRawProperty),
  children: List(IcalRawComponent),
) -> Result(IcalTodo, IcalError) {
  case ical_validator_find_dt(props, "DTSTART") {
    Error(err) -> Error(err)
    Ok(dtstart) ->
      case ical_validator_find_dt(props, "DUE") {
        Error(err) -> Error(err)
        Ok(due) ->
          case ical_validator_find_dt(props, "COMPLETED") {
            Error(err) -> Error(err)
            Ok(completed) ->
              ical_validator_build_todo_optionals(
                uid,
                dtstamp,
                dtstart,
                due,
                completed,
                props,
                children,
              )
          }
      }
  }
}

fn ical_validator_build_todo_optionals(
  uid: String,
  dtstamp: DateTime,
  dtstart: Option(DateTime),
  due: Option(DateTime),
  completed: Option(DateTime),
  props: List(IcalRawProperty),
  children: List(IcalRawComponent),
) -> Result(IcalTodo, IcalError) {
  case
    ical_validator_opt_unescape(ical_validator_find_value(props, "SUMMARY"))
  {
    Error(err) -> Error(err)
    Ok(summary) ->
      case
        ical_validator_opt_unescape(ical_validator_find_value(
          props,
          "DESCRIPTION",
        ))
      {
        Error(err) -> Error(err)
        Ok(description) ->
          case ical_validator_categories_of(props) {
            Error(err) -> Error(err)
            Ok(categories_rev) ->
              ical_validator_build_todo_numbers(
                uid,
                dtstamp,
                dtstart,
                due,
                completed,
                summary,
                description,
                categories_rev,
                props,
                children,
              )
          }
      }
  }
}

fn ical_validator_build_todo_numbers(
  uid: String,
  dtstamp: DateTime,
  dtstart: Option(DateTime),
  due: Option(DateTime),
  completed: Option(DateTime),
  summary: Option(String),
  description: Option(String),
  categories_rev: List(#(String, PropertyForm)),
  props: List(IcalRawProperty),
  children: List(IcalRawComponent),
) -> Result(IcalTodo, IcalError) {
  {
    use percent_complete <- result.try(ical_validator_parse_optional_int(
      props,
      "PERCENT-COMPLETE",
    ))
    use priority <- result.try(ical_validator_parse_optional_int(
      props,
      "PRIORITY",
    ))
    use rrule_value <- result.try(ical_validator_parse_event_rrule(uid, props))
    use rdates_rev <- result.try(ical_validator_parse_datetime_list_prop(
      props,
      "RDATE",
    ))
    use exdates_rev <- result.try(ical_validator_parse_datetime_list_prop(
      props,
      "EXDATE",
    ))
    ical_validator_finalize_todo(
      uid,
      dtstamp,
      dtstart,
      due,
      completed,
      summary,
      description,
      categories_rev,
      percent_complete,
      priority,
      rrule_value,
      rdates_rev,
      exdates_rev,
      props,
      children,
    )
  }
}

fn ical_validator_finalize_todo(
  uid: String,
  dtstamp: DateTime,
  dtstart: Option(DateTime),
  due: Option(DateTime),
  completed: Option(DateTime),
  summary: Option(String),
  description: Option(String),
  categories_rev: List(#(String, PropertyForm)),
  percent_complete: Option(Int),
  priority: Option(Int),
  rrule_value: Option(RawRRule),
  rdates_rev: List(#(DateTime, PropertyForm)),
  exdates_rev: List(#(DateTime, PropertyForm)),
  props: List(IcalRawProperty),
  children: List(IcalRawComponent),
) -> Result(IcalTodo, IcalError) {
  case ical_validator_collect_alarms(children) {
    Error(err) -> Error(err)
    Ok(alarms_rev) -> {
      let status = ical_validator_find_value(props, "STATUS")
      let x_props = ical_validator_collect_x_properties(props)
      Ok(IcalTodo(
        uid: uid,
        dtstamp: dtstamp,
        dtstart: dtstart,
        due: due,
        completed: completed,
        summary: summary,
        description: description,
        status: status,
        percent_complete: percent_complete,
        priority: priority,
        categories_rev: categories_rev,
        rrule: rrule_value,
        rdates_rev: rdates_rev,
        exdates_rev: exdates_rev,
        alarms_rev: alarms_rev,
        x_properties: x_props,
        forms: ical_validator_forms_of(props),
      ))
    }
  }
}

fn ical_validator_parse_optional_int(
  props: List(IcalRawProperty),
  name: String,
) -> Result(Option(Int), IcalError) {
  case ical_validator_find_value(props, name) {
    None -> Ok(None)
    Some(raw) ->
      case int.parse(raw) {
        Ok(v) -> Ok(Some(v))
        Error(_) -> Error(IcalInvalidInteger(name: name, raw: raw))
      }
  }
}

fn ical_validator_validate_journal(
  comp: IcalRawComponent,
) -> Result(IcalJournal, IcalError) {
  let IcalRawComponent(properties: props, ..) = comp
  case ical_validator_find_value(props, "UID") {
    None ->
      Error(IcalMissingComponentProperty(component: "VJOURNAL", name: "UID"))
    Some(uid) ->
      case ical_validator_find_dt(props, "DTSTAMP") {
        Error(err) -> Error(err)
        Ok(None) ->
          Error(IcalMissingComponentProperty(
            component: "VJOURNAL",
            name: "DTSTAMP",
          ))
        Ok(Some(dtstamp)) ->
          ical_validator_build_journal_body(uid, dtstamp, props)
      }
  }
}

fn ical_validator_build_journal_body(
  uid: String,
  dtstamp: DateTime,
  props: List(IcalRawProperty),
) -> Result(IcalJournal, IcalError) {
  {
    use dtstart <- result.try(ical_validator_find_dt(props, "DTSTART"))
    use summary <- result.try(
      ical_validator_opt_unescape(ical_validator_find_value(props, "SUMMARY")),
    )
    use description <- result.try(
      ical_validator_opt_unescape(ical_validator_find_value(
        props,
        "DESCRIPTION",
      )),
    )
    use categories_rev <- result.try(ical_validator_categories_of(props))

    let status = ical_validator_find_value(props, "STATUS")
    let x_props = ical_validator_collect_x_properties(props)
    Ok(IcalJournal(
      uid: uid,
      dtstamp: dtstamp,
      dtstart: dtstart,
      summary: summary,
      description: description,
      status: status,
      categories_rev: categories_rev,
      x_properties: x_props,
      forms: ical_validator_forms_of(props),
    ))
  }
}

fn ical_validator_validate_freebusy(
  comp: IcalRawComponent,
) -> Result(IcalFreeBusy, IcalError) {
  let IcalRawComponent(properties: props, ..) = comp
  case ical_validator_find_value(props, "UID") {
    None ->
      Error(IcalMissingComponentProperty(component: "VFREEBUSY", name: "UID"))
    Some(uid) ->
      case ical_validator_find_dt(props, "DTSTAMP") {
        Error(err) -> Error(err)
        Ok(None) ->
          Error(IcalMissingComponentProperty(
            component: "VFREEBUSY",
            name: "DTSTAMP",
          ))
        Ok(Some(dtstamp)) ->
          ical_validator_build_freebusy_body(uid, dtstamp, props)
      }
  }
}

fn ical_validator_build_freebusy_body(
  uid: String,
  dtstamp: DateTime,
  props: List(IcalRawProperty),
) -> Result(IcalFreeBusy, IcalError) {
  case ical_validator_find_dt(props, "DTSTART") {
    Error(err) -> Error(err)
    Ok(dtstart) ->
      case ical_validator_find_dt(props, "DTEND") {
        Error(err) -> Error(err)
        Ok(dtend) -> {
          let organizer = ical_validator_find_value(props, "ORGANIZER")
          let attendees_rev = ical_repeated_values(props, "ATTENDEE")
          let periods = ical_repeated_values(props, "FREEBUSY")
          let x_props = ical_validator_collect_x_properties(props)
          Ok(IcalFreeBusy(
            uid: uid,
            dtstamp: dtstamp,
            dtstart: dtstart,
            dtend: dtend,
            organizer: organizer,
            attendees_rev: attendees_rev,
            freebusy_periods_rev: periods,
            x_properties: x_props,
            forms: ical_validator_forms_of(props),
          ))
        }
      }
  }
}

fn ical_validator_validate_timezone(
  comp: IcalRawComponent,
) -> Result(IcalTimezone, IcalError) {
  let IcalRawComponent(properties: props, children: children, ..) = comp
  case ical_validator_find_value(props, "TZID") {
    None ->
      Error(IcalMissingComponentProperty(component: "VTIMEZONE", name: "TZID"))
    Some(tzid) -> {
      use last_modified <- result.try(ical_validator_find_dt(
        props,
        "LAST-MODIFIED",
      ))

      let tzurl = ical_validator_find_value(props, "TZURL")
      {
        use #(standard_rev, daylight_rev) <- result.try(
          ical_validator_classify_timezone_children(children),
        )

        let x_props = ical_validator_collect_x_properties(props)
        Ok(IcalTimezone(
          tzid: tzid,
          last_modified: last_modified,
          tzurl: tzurl,
          standard_rev: standard_rev,
          daylight_rev: daylight_rev,
          x_properties: x_props,
          forms: ical_validator_forms_of(props),
        ))
      }
    }
  }
}

fn ical_validator_classify_timezone_children(
  children: List(IcalRawComponent),
) -> Result(
  #(
    List(#(IcalTimezoneRule, Dict(String, PropertyForm))),
    List(#(IcalTimezoneRule, Dict(String, PropertyForm))),
  ),
  IcalError,
) {
  ical_validator_do_classify_tz_children(children, [], [])
}

fn ical_validator_do_classify_tz_children(
  children: List(IcalRawComponent),
  acc_std: List(#(IcalTimezoneRule, Dict(String, PropertyForm))),
  acc_dst: List(#(IcalTimezoneRule, Dict(String, PropertyForm))),
) -> Result(
  #(
    List(#(IcalTimezoneRule, Dict(String, PropertyForm))),
    List(#(IcalTimezoneRule, Dict(String, PropertyForm))),
  ),
  IcalError,
) {
  case children {
    [] -> Ok(#(acc_std, acc_dst))
    [first, ..rest] -> {
      let IcalRawComponent(kind: kind, ..) = first
      case kind {
        "STANDARD" ->
          case ical_validator_validate_tz_rule(first) {
            Error(err) -> Error(err)
            Ok(rule) ->
              ical_validator_do_classify_tz_children(
                rest,
                [#(rule, ical_timezone_rule_form(first)), ..acc_std],
                acc_dst,
              )
          }
        "DAYLIGHT" ->
          case ical_validator_validate_tz_rule(first) {
            Error(err) -> Error(err)
            Ok(rule) ->
              ical_validator_do_classify_tz_children(rest, acc_std, [
                #(rule, ical_timezone_rule_form(first)),
                ..acc_dst
              ])
          }
        _ -> ical_validator_do_classify_tz_children(rest, acc_std, acc_dst)
      }
    }
  }
}

fn ical_validator_validate_tz_rule(
  comp: IcalRawComponent,
) -> Result(IcalTimezoneRule, IcalError) {
  let IcalRawComponent(properties: props, kind: kind, ..) = comp
  case ical_validator_find_dt(props, "DTSTART") {
    Error(err) -> Error(err)
    Ok(None) ->
      Error(IcalMissingComponentProperty(component: kind, name: "DTSTART"))
    Ok(Some(dtstart)) ->
      case ical_validator_find_value(props, "TZOFFSETFROM") {
        None ->
          Error(IcalMissingComponentProperty(
            component: kind,
            name: "TZOFFSETFROM",
          ))
        Some(from) ->
          case ical_validator_find_value(props, "TZOFFSETTO") {
            None ->
              Error(IcalMissingComponentProperty(
                component: kind,
                name: "TZOFFSETTO",
              ))
            Some(to) -> {
              use rrule_value <- result.try(ical_validator_parse_event_rrule(
                kind,
                props,
              ))

              let tzname = ical_validator_find_value(props, "TZNAME")
              Ok(IcalTimezoneRule(
                dtstart: dtstart,
                tzoffsetfrom: from,
                tzoffsetto: to,
                rrule: rrule_value,
                tzname: tzname,
              ))
            }
          }
      }
  }
}

fn ical_validator_collect_alarms(
  children: List(IcalRawComponent),
) -> Result(List(IcalAlarm), IcalError) {
  ical_validator_do_collect_alarms(children, [])
}

fn ical_validator_do_collect_alarms(
  children: List(IcalRawComponent),
  acc: List(IcalAlarm),
) -> Result(List(IcalAlarm), IcalError) {
  case children {
    [] -> Ok(acc)
    [first, ..rest] -> {
      let IcalRawComponent(kind: kind, ..) = first
      case kind {
        "VALARM" ->
          case ical_validator_validate_alarm(first) {
            Error(err) -> Error(err)
            Ok(alarm) -> ical_validator_do_collect_alarms(rest, [alarm, ..acc])
          }
        _ -> ical_validator_do_collect_alarms(rest, acc)
      }
    }
  }
}

fn ical_validator_validate_alarm(
  comp: IcalRawComponent,
) -> Result(IcalAlarm, IcalError) {
  let IcalRawComponent(properties: props, ..) = comp
  case ical_validator_find_value(props, "ACTION") {
    None ->
      Error(IcalMissingComponentProperty(component: "VALARM", name: "ACTION"))
    Some(action) ->
      case ical_validator_find_value(props, "TRIGGER") {
        None ->
          Error(IcalMissingComponentProperty(
            component: "VALARM",
            name: "TRIGGER",
          ))
        Some(trigger) -> ical_validator_build_alarm_body(action, trigger, props)
      }
  }
}

fn ical_validator_build_alarm_body(
  action: String,
  trigger: String,
  props: List(IcalRawProperty),
) -> Result(IcalAlarm, IcalError) {
  case
    ical_validator_opt_unescape(ical_validator_find_value(props, "DESCRIPTION"))
  {
    Error(err) -> Error(err)
    Ok(description) ->
      case
        ical_validator_opt_unescape(ical_validator_find_value(props, "SUMMARY"))
      {
        Error(err) -> Error(err)
        Ok(summary) ->
          case ical_validator_parse_optional_int(props, "REPEAT") {
            Error(err) -> Error(err)
            Ok(repeat) -> {
              let duration = ical_validator_find_value(props, "DURATION")
              let attendees_rev = ical_repeated_values(props, "ATTENDEE")
              let x_props = ical_validator_collect_x_properties(props)
              Ok(IcalAlarm(
                action: action,
                trigger: trigger,
                description: description,
                summary: summary,
                repeat: repeat,
                duration: duration,
                attendees_rev: attendees_rev,
                x_properties: x_props,
                forms: ical_validator_forms_of(props),
              ))
            }
          }
      }
  }
}

const ical_validator_date_properties = [
  "DTSTART",
  "DTEND",
  "DUE",
  "RDATE",
  "EXDATE",
  "DTSTAMP",
  "CREATED",
  "LAST-MODIFIED",
  "COMPLETED",
]

const ical_validator_repeated_properties = [
  "RDATE",
  "EXDATE",
  "CATEGORIES",
  "ATTENDEE",
  "FREEBUSY",
]

fn ical_validator_forms_of(
  props: List(IcalRawProperty),
) -> Dict(String, PropertyForm) {
  list.fold(props, dict.new(), fn(forms, prop) {
    case
      list.contains(ical_validator_repeated_properties, prop.name)
      || dict.has_key(forms, prop.name)
      && !string.starts_with(prop.name, "X-")
    {
      True -> forms
      False ->
        dict.insert(
          forms,
          prop.name,
          ical_validator_value_form(prop.name, prop.parameters, prop.raw_value),
        )
    }
  })
  |> dict.filter(fn(name, form) {
    form.parameters != []
    || form.raw_text
    || !form.utc
    && list.contains(ical_validator_date_properties, name)
  })
}

fn ical_validator_value_form(
  name: String,
  params: List(IcalParameter),
  raw: String,
) -> PropertyForm {
  PropertyForm(
    parameters: params,
    utc: string.ends_with(raw, "Z"),
    date_only: !string.contains(raw, "T"),
    raw_text: {
      string.starts_with(name, "X-") || name == "PRODID" || name == "TZNAME"
    }
      && {
      string.contains(raw, "\\")
      || string.contains(raw, ",")
      || string.contains(raw, ";")
    },
  )
}

fn ical_validator_is_date_form(
  forms: Dict(String, PropertyForm),
  name: String,
) -> Bool {
  case dict.get(forms, name) {
    Ok(form) ->
      form.date_only
      || list.any(form.parameters, fn(parameter) {
        string.uppercase(parameter.name) == "VALUE"
        && string.uppercase(parameter.value) == "DATE"
      })
    Error(Nil) -> False
  }
}

fn ical_validator_replace_date_form(
  forms: Dict(String, PropertyForm),
  name: String,
  partner: String,
) -> Dict(String, PropertyForm) {
  let forms = dict.delete(forms, name)
  case ical_validator_is_date_form(forms, partner) {
    True -> dict.delete(forms, partner)
    False -> forms
  }
}

fn ical_validator_find_value(
  props: List(IcalRawProperty),
  name: String,
) -> Option(String) {
  case list.find(props, fn(p) { p.name == name }) {
    Ok(prop) -> Some(prop.raw_value)
    Error(Nil) -> None
  }
}

fn ical_validator_collect_values(
  props: List(IcalRawProperty),
  name: String,
) -> List(String) {
  list.filter_map(props, fn(p) {
    case p.name == name {
      True -> Ok(p.raw_value)
      False -> Error(Nil)
    }
  })
}

fn ical_validator_find_prop(
  props: List(IcalRawProperty),
  name: String,
) -> Option(IcalRawProperty) {
  case list.find(props, fn(p) { p.name == name }) {
    Ok(prop) -> Some(prop)
    Error(Nil) -> None
  }
}

fn ical_validator_find_tzid(
  props: List(IcalRawProperty),
  name: String,
) -> Option(String) {
  case ical_validator_find_prop(props, name) {
    None -> None
    Some(IcalRawProperty(parameters: params, ..)) ->
      ical_validator_find_param(params, "TZID")
  }
}

fn ical_validator_find_param(
  params: List(IcalParameter),
  name: String,
) -> Option(String) {
  case list.find(params, fn(p) { p.name == name }) {
    Ok(IcalParameter(value: v, ..)) -> Some(v)
    Error(Nil) -> None
  }
}

fn ical_validator_find_dt(
  props: List(IcalRawProperty),
  name: String,
) -> Result(Option(DateTime), IcalError) {
  case ical_validator_find_value(props, name) {
    None -> Ok(None)
    Some(raw) ->
      case ical_validator_parse_datetime(name, raw) {
        Ok(dt) -> Ok(Some(dt))
        Error(err) -> Error(err)
      }
  }
}

fn ical_validator_collect_x_properties(
  props: List(IcalRawProperty),
) -> Dict(String, String) {
  list.fold(props, dict.new(), fn(acc, p) {
    case string.starts_with(p.name, "X-") {
      True -> dict.insert(acc, p.name, p.raw_value)
      False -> acc
    }
  })
}

fn ical_validator_opt_unescape(
  value: Option(String),
) -> Result(Option(String), IcalError) {
  case value {
    None -> Ok(None)
    Some(raw) ->
      case ical_validator_unescape_text(raw) {
        Ok(s) -> Ok(Some(s))
        Error(err) -> Error(err)
      }
  }
}

fn ical_validator_categories_of(
  props: List(IcalRawProperty),
) -> Result(List(#(String, PropertyForm)), IcalError) {
  ical_repeated_parsed(props, "CATEGORIES", ical_validator_split_text_list, [])
}

fn ical_validator_split_text_list(
  raw: String,
) -> Result(List(String), IcalError) {
  ical_validator_split_text_values(string.to_graphemes(raw), [], [])
  |> list.try_map(ical_validator_unescape_text)
}

fn ical_validator_split_text_values(
  rest: List(String),
  current: List(String),
  acc: List(String),
) -> List(String) {
  case rest {
    [] -> list.reverse([string.concat(list.reverse(current)), ..acc])
    ["\\", escaped, ..tail] ->
      ical_validator_split_text_values(tail, [escaped, "\\", ..current], acc)
    [",", ..tail] ->
      ical_validator_split_text_values(tail, [], [
        string.concat(list.reverse(current)),
        ..acc
      ])
    [char, ..tail] ->
      ical_validator_split_text_values(tail, [char, ..current], acc)
  }
}

fn ical_validator_unescape_text(raw: String) -> Result(String, IcalError) {
  ical_validator_do_unescape(string.to_graphemes(raw), raw, [])
}

fn ical_validator_do_unescape(
  graphemes: List(String),
  original: String,
  acc: List(String),
) -> Result(String, IcalError) {
  case graphemes {
    [] -> Ok(string.concat(list.reverse(acc)))
    ["\\", second, ..rest] ->
      case second {
        "\\" -> ical_validator_do_unescape(rest, original, ["\\", ..acc])
        "," -> ical_validator_do_unescape(rest, original, [",", ..acc])
        ";" -> ical_validator_do_unescape(rest, original, [";", ..acc])
        "n" -> ical_validator_do_unescape(rest, original, ["\n", ..acc])
        "N" -> ical_validator_do_unescape(rest, original, ["\n", ..acc])
        _ -> Error(IcalInvalidEscape(raw: original))
      }
    ["\\"] -> Error(IcalInvalidEscape(raw: original))
    [first, ..rest] ->
      ical_validator_do_unescape(rest, original, [first, ..acc])
  }
}

fn ical_validator_parse_datetime(
  name: String,
  raw: String,
) -> Result(DateTime, IcalError) {
  let stripped = case string.ends_with(raw, "Z") {
    True -> string.drop_end(raw, 1)
    False -> raw
  }
  case string.split_once(stripped, "T") {
    Ok(#(date_part, time_part)) ->
      ical_validator_parse_dt_components(name, raw, date_part, time_part)
    Error(Nil) ->
      case string.length(stripped) == 8 {
        True ->
          ical_validator_parse_dt_components(name, raw, stripped, "000000")
        False -> Error(IcalInvalidDateTime(name: name, raw: raw))
      }
  }
}

fn ical_validator_parse_dt_components(
  name: String,
  raw: String,
  date_part: String,
  time_part: String,
) -> Result(DateTime, IcalError) {
  case string.length(date_part) == 8 && string.length(time_part) == 6 {
    False -> Error(IcalInvalidDateTime(name: name, raw: raw))
    True ->
      case ical_validator_slice_date_time(date_part, time_part) {
        Error(_) -> Error(IcalInvalidDateTime(name: name, raw: raw))
        Ok(#(y, mo, d, h, mi, s)) ->
          case
            schedule_ast_try_datetime(
              year: y,
              month: mo,
              day: d,
              hour: h,
              minute: mi,
              second: s,
            )
          {
            Ok(dt) -> Ok(dt)
            Error(_) -> Error(IcalInvalidDateTime(name: name, raw: raw))
          }
      }
  }
}

fn ical_validator_slice_date_time(
  date_part: String,
  time_part: String,
) -> Result(#(Int, Int, Int, Int, Int, Int), Nil) {
  let year = string.slice(date_part, 0, 4)
  let month = string.slice(date_part, 4, 2)
  let day = string.slice(date_part, 6, 2)
  let hour = string.slice(time_part, 0, 2)
  let minute = string.slice(time_part, 2, 2)
  let second = string.slice(time_part, 4, 2)
  {
    use y <- result.try(int.parse(year) |> result.replace_error(Nil))
    use mo <- result.try(int.parse(month) |> result.replace_error(Nil))
    use d <- result.try(int.parse(day) |> result.replace_error(Nil))
    use h <- result.try(int.parse(hour) |> result.replace_error(Nil))
    use mi <- result.try(int.parse(minute) |> result.replace_error(Nil))
    use s <- result.try(int.parse(second) |> result.replace_error(Nil))
    Ok(#(y, mo, d, h, mi, s))
  }
}

fn ical_validator_parse_datetime_list_prop(
  props: List(IcalRawProperty),
  name: String,
) -> Result(List(#(DateTime, PropertyForm)), IcalError) {
  ical_repeated_parsed(
    props,
    name,
    ical_validator_parse_datetime_list(name, _),
    [],
  )
}

fn ical_validator_parse_datetime_list(
  name: String,
  raw: String,
) -> Result(List(DateTime), IcalError) {
  let parts = string.split(raw, ",")
  ical_validator_do_parse_datetime_list(name, parts, [])
}

fn ical_validator_do_parse_datetime_list(
  name: String,
  parts: List(String),
  acc: List(DateTime),
) -> Result(List(DateTime), IcalError) {
  case parts {
    [] -> Ok(list.reverse(acc))
    [first, ..rest] ->
      case ical_validator_parse_datetime(name, first) {
        Error(err) -> Error(err)
        Ok(dt) -> ical_validator_do_parse_datetime_list(name, rest, [dt, ..acc])
      }
  }
}

/// Read VERSION from the calendar.
pub fn ical_version(cal: IcalCalendar) -> String {
  cal.version
}

/// Read PRODID from the calendar.
pub fn ical_product_id(cal: IcalCalendar) -> String {
  cal.product_id
}

/// Read METHOD from the calendar.
pub fn ical_method(cal: IcalCalendar) -> Option(String) {
  cal.method
}

/// Read CALSCALE from the calendar.
pub fn ical_calscale(cal: IcalCalendar) -> Option(String) {
  cal.calscale
}

/// Read the calendar's events in their stored order.
pub fn ical_events(cal: IcalCalendar) -> List(IcalEvent) {
  list.reverse(cal.events_rev)
}

/// Read the calendar's tasks in their stored order.
pub fn ical_todos(cal: IcalCalendar) -> List(IcalTodo) {
  list.reverse(cal.todos_rev)
}

/// Read the calendar's journals in their stored order.
pub fn ical_journals(cal: IcalCalendar) -> List(IcalJournal) {
  list.reverse(cal.journals_rev)
}

/// Read the calendar's free/busy components in their stored order.
pub fn ical_freebusy(cal: IcalCalendar) -> List(IcalFreeBusy) {
  list.reverse(cal.freebusy_rev)
}

/// Read the calendar's timezones in their stored order.
pub fn ical_timezones(cal: IcalCalendar) -> List(IcalTimezone) {
  list.reverse(cal.timezones_rev)
}

/// Read the calendar's unknown components in their stored order.
pub fn ical_unknown_components(
  cal: IcalCalendar,
) -> List(IcalUnknownComponent) {
  list.reverse(cal.unknown_components_rev)
}

/// Read the calendar's extension-property name/value map.
pub fn ical_calendar_x_properties(cal: IcalCalendar) -> Dict(String, String) {
  cal.x_properties
}

/// Read UID from the event.
pub fn ical_event_uid(event: IcalEvent) -> String {
  event.uid
}

/// Read DTSTAMP from the event.
pub fn ical_event_dtstamp(event: IcalEvent) -> DateTime {
  event.dtstamp
}

/// Read DTSTART from the event.
pub fn ical_event_dtstart(event: IcalEvent) -> Option(DateTime) {
  event.dtstart
}

/// Read DTSTART timezone label from the event.
pub fn ical_event_dtstart_tzid(event: IcalEvent) -> Option(String) {
  event.dtstart_tzid
}

/// Read DTEND from the event.
pub fn ical_event_dtend(event: IcalEvent) -> Option(DateTime) {
  event.dtend
}

/// Read DTEND timezone label from the event.
pub fn ical_event_dtend_tzid(event: IcalEvent) -> Option(String) {
  event.dtend_tzid
}

/// Read DURATION from the event.
pub fn ical_event_duration(event: IcalEvent) -> Option(String) {
  event.duration
}

/// Read SUMMARY from the event.
pub fn ical_event_summary(event: IcalEvent) -> Option(String) {
  event.summary
}

/// Read DESCRIPTION from the event.
pub fn ical_event_description(event: IcalEvent) -> Option(String) {
  event.description
}

/// Read LOCATION from the event.
pub fn ical_event_location(event: IcalEvent) -> Option(String) {
  event.location
}

/// Read STATUS from the event.
pub fn ical_event_status(event: IcalEvent) -> Option(String) {
  event.status
}

/// Read ORGANIZER from the event.
pub fn ical_event_organizer(event: IcalEvent) -> Option(String) {
  event.organizer
}

/// Read the event's attendees in their stored order.
pub fn ical_event_attendees(event: IcalEvent) -> List(String) {
  ical_repeated_in_order(event.attendees_rev)
}

/// Read the event's categories in their stored order.
pub fn ical_event_categories(event: IcalEvent) -> List(String) {
  ical_repeated_in_order(event.categories_rev)
}

/// Read URL from the event.
pub fn ical_event_url(event: IcalEvent) -> Option(String) {
  event.url
}

/// Read CREATED from the event.
pub fn ical_event_created(event: IcalEvent) -> Option(DateTime) {
  event.created
}

/// Read LAST-MODIFIED from the event.
pub fn ical_event_last_modified(event: IcalEvent) -> Option(DateTime) {
  event.last_modified
}

/// Read SEQUENCE from the event.
pub fn ical_event_sequence(event: IcalEvent) -> Int {
  event.sequence
}

/// Read TRANSP from the event.
pub fn ical_event_transparency(event: IcalEvent) -> Option(String) {
  event.transparency
}

/// Read RRULE from the event.
pub fn ical_event_rrule(event: IcalEvent) -> Option(RawRRule) {
  event.rrule
}

/// Read the event's additional dates in their stored order.
pub fn ical_event_rdates(event: IcalEvent) -> List(DateTime) {
  ical_repeated_in_order(event.rdates_rev)
}

/// Read the event's excluded dates in their stored order.
pub fn ical_event_exdates(event: IcalEvent) -> List(DateTime) {
  ical_repeated_in_order(event.exdates_rev)
}

/// Read the event's alarms in their stored order.
pub fn ical_event_alarms(event: IcalEvent) -> List(IcalAlarm) {
  list.reverse(event.alarms_rev)
}

/// Read the event's extension-property name/value map.
pub fn ical_event_x_properties(event: IcalEvent) -> Dict(String, String) {
  event.x_properties
}

/// Read UID from the task.
pub fn ical_todo_uid(t: IcalTodo) -> String {
  t.uid
}

/// Read DTSTAMP from the task.
pub fn ical_todo_dtstamp(t: IcalTodo) -> DateTime {
  t.dtstamp
}

/// Read DTSTART from the task.
pub fn ical_todo_dtstart(t: IcalTodo) -> Option(DateTime) {
  t.dtstart
}

/// Read DUE from the task.
pub fn ical_todo_due(t: IcalTodo) -> Option(DateTime) {
  t.due
}

/// Read COMPLETED from the task.
pub fn ical_todo_completed(t: IcalTodo) -> Option(DateTime) {
  t.completed
}

/// Read SUMMARY from the task.
pub fn ical_todo_summary(t: IcalTodo) -> Option(String) {
  t.summary
}

/// Read DESCRIPTION from the task.
pub fn ical_todo_description(t: IcalTodo) -> Option(String) {
  t.description
}

/// Read STATUS from the task.
pub fn ical_todo_status(t: IcalTodo) -> Option(String) {
  t.status
}

/// Read PERCENT-COMPLETE from the task.
pub fn ical_todo_percent_complete(t: IcalTodo) -> Option(Int) {
  t.percent_complete
}

/// Read PRIORITY from the task.
pub fn ical_todo_priority(t: IcalTodo) -> Option(Int) {
  t.priority
}

/// Read the task's categories in their stored order.
pub fn ical_todo_categories(t: IcalTodo) -> List(String) {
  ical_repeated_in_order(t.categories_rev)
}

/// Read RRULE from the task.
pub fn ical_todo_rrule(t: IcalTodo) -> Option(RawRRule) {
  t.rrule
}

/// Read the task's additional dates in their stored order.
pub fn ical_todo_rdates(t: IcalTodo) -> List(DateTime) {
  ical_repeated_in_order(t.rdates_rev)
}

/// Read the task's excluded dates in their stored order.
pub fn ical_todo_exdates(t: IcalTodo) -> List(DateTime) {
  ical_repeated_in_order(t.exdates_rev)
}

/// Read the task's alarms in their stored order.
pub fn ical_todo_alarms(t: IcalTodo) -> List(IcalAlarm) {
  list.reverse(t.alarms_rev)
}

/// Read the task's extension-property name/value map.
pub fn ical_todo_x_properties(t: IcalTodo) -> Dict(String, String) {
  t.x_properties
}

/// Read UID from the journal.
pub fn ical_journal_uid(j: IcalJournal) -> String {
  j.uid
}

/// Read DTSTAMP from the journal.
pub fn ical_journal_dtstamp(j: IcalJournal) -> DateTime {
  j.dtstamp
}

/// Read DTSTART from the journal.
pub fn ical_journal_dtstart(j: IcalJournal) -> Option(DateTime) {
  j.dtstart
}

/// Read SUMMARY from the journal.
pub fn ical_journal_summary(j: IcalJournal) -> Option(String) {
  j.summary
}

/// Read DESCRIPTION from the journal.
pub fn ical_journal_description(j: IcalJournal) -> Option(String) {
  j.description
}

/// Read STATUS from the journal.
pub fn ical_journal_status(j: IcalJournal) -> Option(String) {
  j.status
}

/// Read the journal's categories in their stored order.
pub fn ical_journal_categories(j: IcalJournal) -> List(String) {
  ical_repeated_in_order(j.categories_rev)
}

/// Read the journal's extension-property name/value map.
pub fn ical_journal_x_properties(j: IcalJournal) -> Dict(String, String) {
  j.x_properties
}

/// Read UID from the free/busy component.
pub fn ical_freebusy_uid(fb: IcalFreeBusy) -> String {
  fb.uid
}

/// Read DTSTAMP from the free/busy component.
pub fn ical_freebusy_dtstamp(fb: IcalFreeBusy) -> DateTime {
  fb.dtstamp
}

/// Read DTSTART from the free/busy component.
pub fn ical_freebusy_dtstart(fb: IcalFreeBusy) -> Option(DateTime) {
  fb.dtstart
}

/// Read DTEND from the free/busy component.
pub fn ical_freebusy_dtend(fb: IcalFreeBusy) -> Option(DateTime) {
  fb.dtend
}

/// Read ORGANIZER from the free/busy component.
pub fn ical_freebusy_organizer(fb: IcalFreeBusy) -> Option(String) {
  fb.organizer
}

/// Read the free/busy component's attendees in their stored order.
pub fn ical_freebusy_attendees(fb: IcalFreeBusy) -> List(String) {
  ical_repeated_in_order(fb.attendees_rev)
}

/// Read the free/busy component's free/busy period strings in their stored order.
pub fn ical_freebusy_periods(fb: IcalFreeBusy) -> List(String) {
  ical_repeated_in_order(fb.freebusy_periods_rev)
}

/// Read the free/busy component's extension-property name/value map.
pub fn ical_freebusy_x_properties(fb: IcalFreeBusy) -> Dict(String, String) {
  fb.x_properties
}

/// Read TZID from the timezone.
pub fn ical_timezone_tzid(tz: IcalTimezone) -> String {
  tz.tzid
}

/// Read LAST-MODIFIED from the timezone.
pub fn ical_timezone_last_modified(tz: IcalTimezone) -> Option(DateTime) {
  tz.last_modified
}

/// Read TZURL from the timezone.
pub fn ical_timezone_tzurl(tz: IcalTimezone) -> Option(String) {
  tz.tzurl
}

/// Read the timezone's STANDARD rules in their stored order.
pub fn ical_timezone_standard(tz: IcalTimezone) -> List(IcalTimezoneRule) {
  tz.standard_rev |> list.reverse |> list.map(fn(pair) { pair.0 })
}

/// Read the timezone's DAYLIGHT rules in their stored order.
pub fn ical_timezone_daylight(tz: IcalTimezone) -> List(IcalTimezoneRule) {
  tz.daylight_rev |> list.reverse |> list.map(fn(pair) { pair.0 })
}

/// Read the timezone's extension-property name/value map.
pub fn ical_timezone_x_properties(tz: IcalTimezone) -> Dict(String, String) {
  tz.x_properties
}

/// Read ACTION from the alarm.
pub fn ical_alarm_action(a: IcalAlarm) -> String {
  a.action
}

/// Read TRIGGER from the alarm.
pub fn ical_alarm_trigger(a: IcalAlarm) -> String {
  a.trigger
}

/// Read DESCRIPTION from the alarm.
pub fn ical_alarm_description(a: IcalAlarm) -> Option(String) {
  a.description
}

/// Read SUMMARY from the alarm.
pub fn ical_alarm_summary(a: IcalAlarm) -> Option(String) {
  a.summary
}

/// Read REPEAT from the alarm.
pub fn ical_alarm_repeat(a: IcalAlarm) -> Option(Int) {
  a.repeat
}

/// Read DURATION from the alarm.
pub fn ical_alarm_duration(a: IcalAlarm) -> Option(String) {
  a.duration
}

/// Read the alarm's attendees in their stored order.
pub fn ical_alarm_attendees(a: IcalAlarm) -> List(String) {
  ical_repeated_in_order(a.attendees_rev)
}

/// Read the alarm's extension-property name/value map.
pub fn ical_alarm_x_properties(a: IcalAlarm) -> Dict(String, String) {
  a.x_properties
}

/// Create an empty calendar with the supplied VERSION and PRODID.
///
/// Optional properties and component lists start empty. Values are stored as supplied; wire validation occurs in `ical_encode`.
pub fn ical_new_calendar(
  version version: String,
  prod_id prod_id: String,
) -> IcalCalendar {
  IcalCalendar(
    version: version,
    product_id: prod_id,
    method: None,
    calscale: None,
    events_rev: [],
    todos_rev: [],
    journals_rev: [],
    freebusy_rev: [],
    timezones_rev: [],
    unknown_components_rev: [],
    x_properties: dict.new(),
    forms: dict.new(),
  )
}

/// Set METHOD on the calendar and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_method(cal: IcalCalendar, method: String) -> IcalCalendar {
  IcalCalendar(
    ..cal,
    method: Some(method),
    forms: dict.delete(cal.forms, "METHOD"),
  )
}

/// Set CALSCALE on the calendar and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_calscale(cal: IcalCalendar, scale: String) -> IcalCalendar {
  IcalCalendar(
    ..cal,
    calscale: Some(scale),
    forms: dict.delete(cal.forms, "CALSCALE"),
  )
}

/// Append a event to the calendar, preserving order within that component kind.
pub fn ical_add_event(cal: IcalCalendar, event: IcalEvent) -> IcalCalendar {
  IcalCalendar(..cal, events_rev: [event, ..cal.events_rev])
}

/// Append a task to the calendar, preserving order within that component kind.
pub fn ical_add_todo(cal: IcalCalendar, t: IcalTodo) -> IcalCalendar {
  IcalCalendar(..cal, todos_rev: [t, ..cal.todos_rev])
}

/// Append a journal to the calendar, preserving order within that component kind.
pub fn ical_add_journal(cal: IcalCalendar, j: IcalJournal) -> IcalCalendar {
  IcalCalendar(..cal, journals_rev: [j, ..cal.journals_rev])
}

/// Append a free/busy component to the calendar, preserving order within that component kind.
pub fn ical_add_freebusy(cal: IcalCalendar, fb: IcalFreeBusy) -> IcalCalendar {
  IcalCalendar(..cal, freebusy_rev: [fb, ..cal.freebusy_rev])
}

/// Append a timezone to the calendar, preserving order within that component kind.
pub fn ical_add_timezone(cal: IcalCalendar, tz: IcalTimezone) -> IcalCalendar {
  IcalCalendar(..cal, timezones_rev: [tz, ..cal.timezones_rev])
}

/// Append a unknown component to the calendar, preserving order within that component kind.
pub fn ical_add_unknown_component(
  cal: IcalCalendar,
  component: IcalUnknownComponent,
) -> IcalCalendar {
  IcalCalendar(..cal, unknown_components_rev: [
    component,
    ..cal.unknown_components_rev
  ])
}

/// Set an extension property on the calendar, replacing any value with the same name.
///
/// Discard the preserved form for that name, even when the value is unchanged.
pub fn ical_with_calendar_x_property(
  cal: IcalCalendar,
  name: String,
  value: String,
) -> IcalCalendar {
  IcalCalendar(
    ..cal,
    x_properties: dict.insert(cal.x_properties, name, value),
    forms: dict.delete(cal.forms, name),
  )
}

/// Create an event with UID, DTSTAMP, and sequence zero.
///
/// Optional properties and repeated values start empty. Dates use the default UTC wire form until a timezone label or preserved form applies; no time conversion is performed. `ical_encode` validates the date and wire values.
pub fn ical_new_event(uid uid: String, dtstamp dtstamp: DateTime) -> IcalEvent {
  IcalEvent(
    uid: uid,
    dtstamp: dtstamp,
    dtstart: None,
    dtstart_tzid: None,
    dtend: None,
    dtend_tzid: None,
    duration: None,
    summary: None,
    description: None,
    location: None,
    status: None,
    organizer: None,
    attendees_rev: [],
    categories_rev: [],
    url: None,
    created: None,
    last_modified: None,
    sequence: 0,
    transparency: None,
    rrule: None,
    rdates_rev: [],
    exdates_rev: [],
    alarms_rev: [],
    x_properties: dict.new(),
    forms: dict.new(),
  )
}

/// Set DTSTART on the event and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms. If DTEND was a DATE-only value, reset its form too. The default is UTC DATE-TIME unless an explicit timezone label applies; the civil value is not converted. The date is validated when encoded.
pub fn ical_with_dtstart(event: IcalEvent, dt: DateTime) -> IcalEvent {
  IcalEvent(
    ..event,
    dtstart: Some(dt),
    forms: ical_validator_replace_date_form(event.forms, "DTSTART", "DTEND"),
  )
}

/// Set the event's DTSTART timezone label without converting its civil time.
///
/// This explicit label overrides a parsed TZID during encoding; other preserved parameters remain.
pub fn ical_with_dtstart_tzid(event: IcalEvent, tzid: String) -> IcalEvent {
  IcalEvent(..event, dtstart_tzid: Some(tzid))
}

/// Set DTEND on the event and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms. If DTSTART was a DATE-only value, reset its form too. The default is UTC DATE-TIME unless an explicit timezone label applies; the civil value is not converted. The date is validated when encoded.
pub fn ical_with_dtend(event: IcalEvent, dt: DateTime) -> IcalEvent {
  IcalEvent(
    ..event,
    dtend: Some(dt),
    forms: ical_validator_replace_date_form(event.forms, "DTEND", "DTSTART"),
  )
}

/// Set the event's DTEND timezone label without converting its civil time.
///
/// This explicit label overrides a parsed TZID during encoding; other preserved parameters remain.
pub fn ical_with_dtend_tzid(event: IcalEvent, tzid: String) -> IcalEvent {
  IcalEvent(..event, dtend_tzid: Some(tzid))
}

/// Set DURATION on the event and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_duration(event: IcalEvent, value: String) -> IcalEvent {
  IcalEvent(
    ..event,
    duration: Some(value),
    forms: dict.delete(event.forms, "DURATION"),
  )
}

/// Set SUMMARY on the event and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_summary(event: IcalEvent, value: String) -> IcalEvent {
  IcalEvent(
    ..event,
    summary: Some(value),
    forms: dict.delete(event.forms, "SUMMARY"),
  )
}

/// Set DESCRIPTION on the event and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_description(event: IcalEvent, value: String) -> IcalEvent {
  IcalEvent(
    ..event,
    description: Some(value),
    forms: dict.delete(event.forms, "DESCRIPTION"),
  )
}

/// Set LOCATION on the event and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_location(event: IcalEvent, value: String) -> IcalEvent {
  IcalEvent(
    ..event,
    location: Some(value),
    forms: dict.delete(event.forms, "LOCATION"),
  )
}

/// Set STATUS on the event and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_status(event: IcalEvent, value: String) -> IcalEvent {
  IcalEvent(
    ..event,
    status: Some(value),
    forms: dict.delete(event.forms, "STATUS"),
  )
}

/// Set ORGANIZER on the event and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_organizer(event: IcalEvent, value: String) -> IcalEvent {
  IcalEvent(
    ..event,
    organizer: Some(value),
    forms: dict.delete(event.forms, "ORGANIZER"),
  )
}

/// Append a attendee to the event.
///
/// Keep existing values and their parameters in order; the new value has no parsed parameters.
pub fn ical_add_attendee(event: IcalEvent, value: String) -> IcalEvent {
  IcalEvent(..event, attendees_rev: [
    #(value, ical_validator_utc_form),
    ..event.attendees_rev
  ])
}

/// Append a category to the event.
///
/// Keep existing values and their parameters in order; the new value has no parsed parameters.
pub fn ical_add_category(event: IcalEvent, value: String) -> IcalEvent {
  IcalEvent(..event, categories_rev: [
    #(value, ical_validator_utc_form),
    ..event.categories_rev
  ])
}

/// Set URL on the event and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_url(event: IcalEvent, value: String) -> IcalEvent {
  IcalEvent(..event, url: Some(value), forms: dict.delete(event.forms, "URL"))
}

/// Set CREATED on the event and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms. The date is validated when encoded.
pub fn ical_with_created(event: IcalEvent, dt: DateTime) -> IcalEvent {
  IcalEvent(
    ..event,
    created: Some(dt),
    forms: dict.delete(event.forms, "CREATED"),
  )
}

/// Set LAST-MODIFIED on the event and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms. The date is validated when encoded.
pub fn ical_with_last_modified(event: IcalEvent, dt: DateTime) -> IcalEvent {
  IcalEvent(
    ..event,
    last_modified: Some(dt),
    forms: dict.delete(event.forms, "LAST-MODIFIED"),
  )
}

/// Set SEQUENCE on the event and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_sequence(event: IcalEvent, value: Int) -> IcalEvent {
  IcalEvent(
    ..event,
    sequence: value,
    forms: dict.delete(event.forms, "SEQUENCE"),
  )
}

/// Set TRANSP on the event and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_transparency(event: IcalEvent, value: String) -> IcalEvent {
  IcalEvent(
    ..event,
    transparency: Some(value),
    forms: dict.delete(event.forms, "TRANSP"),
  )
}

/// Set RRULE on the event and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_rrule(event: IcalEvent, rule: RawRRule) -> IcalEvent {
  IcalEvent(
    ..event,
    rrule: Some(rule),
    forms: dict.delete(event.forms, "RRULE"),
  )
}

/// Append a additional date to the event.
///
/// Keep existing values and their parameters in order; the new value has no parsed parameters. The new date uses the default UTC form and is validated when encoded.
pub fn ical_add_rdate(event: IcalEvent, dt: DateTime) -> IcalEvent {
  IcalEvent(..event, rdates_rev: [
    #(dt, ical_validator_utc_form),
    ..event.rdates_rev
  ])
}

/// Append a excluded date to the event.
///
/// Keep existing values and their parameters in order; the new value has no parsed parameters. The new date uses the default UTC form and is validated when encoded.
pub fn ical_add_exdate(event: IcalEvent, dt: DateTime) -> IcalEvent {
  IcalEvent(..event, exdates_rev: [
    #(dt, ical_validator_utc_form),
    ..event.exdates_rev
  ])
}

/// Append an alarm to the event, after its existing alarms.
pub fn ical_add_alarm(event: IcalEvent, alarm: IcalAlarm) -> IcalEvent {
  IcalEvent(..event, alarms_rev: [alarm, ..event.alarms_rev])
}

/// Set EVENT-X-PROPERTY on the event and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_event_x_property(
  event: IcalEvent,
  name: String,
  value: String,
) -> IcalEvent {
  IcalEvent(
    ..event,
    x_properties: dict.insert(event.x_properties, name, value),
    forms: dict.delete(event.forms, name),
  )
}

/// Create a task with UID and DTSTAMP, leaving optional properties and repeated values empty.
///
/// `ical_encode` validates the stored date and wire values.
pub fn ical_new_todo(uid uid: String, dtstamp dtstamp: DateTime) -> IcalTodo {
  IcalTodo(
    uid: uid,
    dtstamp: dtstamp,
    dtstart: None,
    due: None,
    completed: None,
    summary: None,
    description: None,
    status: None,
    percent_complete: None,
    priority: None,
    categories_rev: [],
    rrule: None,
    rdates_rev: [],
    exdates_rev: [],
    alarms_rev: [],
    x_properties: dict.new(),
    forms: dict.new(),
  )
}

/// Set DTSTART on the task and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms. If DUE was a DATE-only value, reset its form too. The default is UTC DATE-TIME unless an explicit timezone label applies; the civil value is not converted. The date is validated when encoded.
pub fn ical_with_todo_dtstart(t: IcalTodo, dt: DateTime) -> IcalTodo {
  IcalTodo(
    ..t,
    dtstart: Some(dt),
    forms: ical_validator_replace_date_form(t.forms, "DTSTART", "DUE"),
  )
}

/// Set DUE on the task and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms. If DTSTART was a DATE-only value, reset its form too. The default is UTC DATE-TIME unless an explicit timezone label applies; the civil value is not converted. The date is validated when encoded.
pub fn ical_with_todo_due(t: IcalTodo, dt: DateTime) -> IcalTodo {
  IcalTodo(
    ..t,
    due: Some(dt),
    forms: ical_validator_replace_date_form(t.forms, "DUE", "DTSTART"),
  )
}

/// Set COMPLETED on the task and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms. The date is validated when encoded.
pub fn ical_with_todo_completed(t: IcalTodo, dt: DateTime) -> IcalTodo {
  IcalTodo(..t, completed: Some(dt), forms: dict.delete(t.forms, "COMPLETED"))
}

/// Set SUMMARY on the task and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_todo_summary(t: IcalTodo, value: String) -> IcalTodo {
  IcalTodo(..t, summary: Some(value), forms: dict.delete(t.forms, "SUMMARY"))
}

/// Set DESCRIPTION on the task and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_todo_description(t: IcalTodo, value: String) -> IcalTodo {
  IcalTodo(
    ..t,
    description: Some(value),
    forms: dict.delete(t.forms, "DESCRIPTION"),
  )
}

/// Set STATUS on the task and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_todo_status(t: IcalTodo, value: String) -> IcalTodo {
  IcalTodo(..t, status: Some(value), forms: dict.delete(t.forms, "STATUS"))
}

/// Set PERCENT-COMPLETE on the task and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_todo_percent_complete(t: IcalTodo, value: Int) -> IcalTodo {
  IcalTodo(
    ..t,
    percent_complete: Some(value),
    forms: dict.delete(t.forms, "PERCENT-COMPLETE"),
  )
}

/// Set PRIORITY on the task and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_todo_priority(t: IcalTodo, value: Int) -> IcalTodo {
  IcalTodo(..t, priority: Some(value), forms: dict.delete(t.forms, "PRIORITY"))
}

/// Append a category to the task.
///
/// Keep existing values and their parameters in order; the new value has no parsed parameters.
pub fn ical_add_todo_category(t: IcalTodo, value: String) -> IcalTodo {
  IcalTodo(..t, categories_rev: [
    #(value, ical_validator_utc_form),
    ..t.categories_rev
  ])
}

/// Set RRULE on the task and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_todo_rrule(t: IcalTodo, rule: RawRRule) -> IcalTodo {
  IcalTodo(..t, rrule: Some(rule), forms: dict.delete(t.forms, "RRULE"))
}

/// Append a additional date to the task.
///
/// Keep existing values and their parameters in order; the new value has no parsed parameters. The new date uses the default UTC form and is validated when encoded.
pub fn ical_add_todo_rdate(t: IcalTodo, dt: DateTime) -> IcalTodo {
  IcalTodo(..t, rdates_rev: [#(dt, ical_validator_utc_form), ..t.rdates_rev])
}

/// Append a excluded date to the task.
///
/// Keep existing values and their parameters in order; the new value has no parsed parameters. The new date uses the default UTC form and is validated when encoded.
pub fn ical_add_todo_exdate(t: IcalTodo, dt: DateTime) -> IcalTodo {
  IcalTodo(..t, exdates_rev: [#(dt, ical_validator_utc_form), ..t.exdates_rev])
}

/// Append an alarm to the task, after its existing alarms.
pub fn ical_add_todo_alarm(t: IcalTodo, alarm: IcalAlarm) -> IcalTodo {
  IcalTodo(..t, alarms_rev: [alarm, ..t.alarms_rev])
}

/// Set an extension property on the task, replacing any value with the same name.
///
/// Discard the preserved form for that name, even when the value is unchanged.
pub fn ical_with_todo_x_property(
  t: IcalTodo,
  name: String,
  value: String,
) -> IcalTodo {
  IcalTodo(
    ..t,
    x_properties: dict.insert(t.x_properties, name, value),
    forms: dict.delete(t.forms, name),
  )
}

/// Create a journal with UID and DTSTAMP, leaving optional properties and categories empty.
///
/// `ical_encode` validates the stored date and wire values.
pub fn ical_new_journal(
  uid uid: String,
  dtstamp dtstamp: DateTime,
) -> IcalJournal {
  IcalJournal(
    uid: uid,
    dtstamp: dtstamp,
    dtstart: None,
    summary: None,
    description: None,
    status: None,
    categories_rev: [],
    x_properties: dict.new(),
    forms: dict.new(),
  )
}

/// Set DTSTART on the journal and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms. The date is validated when encoded.
pub fn ical_with_journal_dtstart(j: IcalJournal, dt: DateTime) -> IcalJournal {
  IcalJournal(..j, dtstart: Some(dt), forms: dict.delete(j.forms, "DTSTART"))
}

/// Set SUMMARY on the journal and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_journal_summary(j: IcalJournal, value: String) -> IcalJournal {
  IcalJournal(..j, summary: Some(value), forms: dict.delete(j.forms, "SUMMARY"))
}

/// Set DESCRIPTION on the journal and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_journal_description(
  j: IcalJournal,
  value: String,
) -> IcalJournal {
  IcalJournal(
    ..j,
    description: Some(value),
    forms: dict.delete(j.forms, "DESCRIPTION"),
  )
}

/// Set STATUS on the journal and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_journal_status(j: IcalJournal, value: String) -> IcalJournal {
  IcalJournal(..j, status: Some(value), forms: dict.delete(j.forms, "STATUS"))
}

/// Append a category to the journal.
///
/// Keep existing values and their parameters in order; the new value has no parsed parameters.
pub fn ical_add_journal_category(j: IcalJournal, value: String) -> IcalJournal {
  IcalJournal(..j, categories_rev: [
    #(value, ical_validator_utc_form),
    ..j.categories_rev
  ])
}

/// Set an extension property on the journal, replacing any value with the same name.
///
/// Discard the preserved form for that name, even when the value is unchanged.
pub fn ical_with_journal_x_property(
  j: IcalJournal,
  name: String,
  value: String,
) -> IcalJournal {
  IcalJournal(
    ..j,
    x_properties: dict.insert(j.x_properties, name, value),
    forms: dict.delete(j.forms, name),
  )
}

/// Create a free/busy component with UID and DTSTAMP and no optional properties or periods.
///
/// `ical_encode` validates the stored date and wire values.
pub fn ical_new_freebusy(
  uid uid: String,
  dtstamp dtstamp: DateTime,
) -> IcalFreeBusy {
  IcalFreeBusy(
    uid: uid,
    dtstamp: dtstamp,
    dtstart: None,
    dtend: None,
    organizer: None,
    attendees_rev: [],
    freebusy_periods_rev: [],
    x_properties: dict.new(),
    forms: dict.new(),
  )
}

/// Set DTSTART on the free/busy component and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms. The date is validated when encoded.
pub fn ical_with_freebusy_dtstart(
  fb: IcalFreeBusy,
  dt: DateTime,
) -> IcalFreeBusy {
  IcalFreeBusy(..fb, dtstart: Some(dt), forms: dict.delete(fb.forms, "DTSTART"))
}

/// Set DTEND on the free/busy component and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms. The date is validated when encoded.
pub fn ical_with_freebusy_dtend(
  fb: IcalFreeBusy,
  dt: DateTime,
) -> IcalFreeBusy {
  IcalFreeBusy(..fb, dtend: Some(dt), forms: dict.delete(fb.forms, "DTEND"))
}

/// Set ORGANIZER on the free/busy component and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_freebusy_organizer(
  fb: IcalFreeBusy,
  value: String,
) -> IcalFreeBusy {
  IcalFreeBusy(
    ..fb,
    organizer: Some(value),
    forms: dict.delete(fb.forms, "ORGANIZER"),
  )
}

/// Append a attendee to the free/busy component.
///
/// Keep existing values and their parameters in order; the new value has no parsed parameters.
pub fn ical_add_freebusy_attendee(
  fb: IcalFreeBusy,
  value: String,
) -> IcalFreeBusy {
  IcalFreeBusy(..fb, attendees_rev: [
    #(value, ical_validator_utc_form),
    ..fb.attendees_rev
  ])
}

/// Append a free/busy period string to the free/busy component.
///
/// Keep existing values and their parameters in order; the new value has no parsed parameters.
pub fn ical_add_freebusy_period(
  fb: IcalFreeBusy,
  value: String,
) -> IcalFreeBusy {
  IcalFreeBusy(..fb, freebusy_periods_rev: [
    #(value, ical_validator_utc_form),
    ..fb.freebusy_periods_rev
  ])
}

/// Set an extension property on the free/busy component, replacing any value with the same name.
///
/// Discard the preserved form for that name, even when the value is unchanged.
pub fn ical_with_freebusy_x_property(
  fb: IcalFreeBusy,
  name: String,
  value: String,
) -> IcalFreeBusy {
  IcalFreeBusy(
    ..fb,
    x_properties: dict.insert(fb.x_properties, name, value),
    forms: dict.delete(fb.forms, name),
  )
}

/// Create a timezone with TZID and no rules or optional properties.
///
/// The timezone is stored as calendar data; it is not used to convert schedule times.
pub fn ical_new_timezone(tzid tzid: String) -> IcalTimezone {
  IcalTimezone(
    tzid: tzid,
    last_modified: None,
    tzurl: None,
    standard_rev: [],
    daylight_rev: [],
    x_properties: dict.new(),
    forms: dict.new(),
  )
}

/// Set LAST-MODIFIED on the timezone and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms. The date is validated when encoded.
pub fn ical_with_timezone_last_modified(
  tz: IcalTimezone,
  dt: DateTime,
) -> IcalTimezone {
  IcalTimezone(
    ..tz,
    last_modified: Some(dt),
    forms: dict.delete(tz.forms, "LAST-MODIFIED"),
  )
}

/// Set TZURL on the timezone and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_timezone_url(tz: IcalTimezone, value: String) -> IcalTimezone {
  IcalTimezone(..tz, tzurl: Some(value), forms: dict.delete(tz.forms, "TZURL"))
}

/// Append a STANDARD rule to the timezone, after existing rules of that kind.
///
/// Existing rules keep their parameters. The new rule starts without parsed parameters and its DTSTART uses the floating form.
pub fn ical_add_timezone_standard(
  tz: IcalTimezone,
  rule: IcalTimezoneRule,
) -> IcalTimezone {
  IcalTimezone(..tz, standard_rev: [#(rule, dict.new()), ..tz.standard_rev])
}

/// Append a DAYLIGHT rule to the timezone, after existing rules of that kind.
///
/// Existing rules keep their parameters. The new rule starts without parsed parameters and its DTSTART uses the floating form.
pub fn ical_add_timezone_daylight(
  tz: IcalTimezone,
  rule: IcalTimezoneRule,
) -> IcalTimezone {
  IcalTimezone(..tz, daylight_rev: [#(rule, dict.new()), ..tz.daylight_rev])
}

/// Set an extension property on the timezone, replacing any value with the same name.
///
/// Discard the preserved form for that name, even when the value is unchanged.
pub fn ical_with_timezone_x_property(
  tz: IcalTimezone,
  name: String,
  value: String,
) -> IcalTimezone {
  IcalTimezone(
    ..tz,
    x_properties: dict.insert(tz.x_properties, name, value),
    forms: dict.delete(tz.forms, name),
  )
}

/// Create an alarm with ACTION and TRIGGER and no optional properties or attendees.
///
/// The trigger remains a string. `ical_encode` checks its rendered line for physical newlines, without interpreting the trigger as a duration or date.
pub fn ical_new_alarm(
  action action: String,
  trigger trigger: String,
) -> IcalAlarm {
  IcalAlarm(
    action: action,
    trigger: trigger,
    description: None,
    summary: None,
    repeat: None,
    duration: None,
    attendees_rev: [],
    x_properties: dict.new(),
    forms: dict.new(),
  )
}

/// Set DESCRIPTION on the alarm and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_alarm_description(
  alarm: IcalAlarm,
  value: String,
) -> IcalAlarm {
  IcalAlarm(
    ..alarm,
    description: Some(value),
    forms: dict.delete(alarm.forms, "DESCRIPTION"),
  )
}

/// Set SUMMARY on the alarm and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_alarm_summary(alarm: IcalAlarm, value: String) -> IcalAlarm {
  IcalAlarm(
    ..alarm,
    summary: Some(value),
    forms: dict.delete(alarm.forms, "SUMMARY"),
  )
}

/// Set REPEAT on the alarm and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_alarm_repeat(alarm: IcalAlarm, value: Int) -> IcalAlarm {
  IcalAlarm(
    ..alarm,
    repeat: Some(value),
    forms: dict.delete(alarm.forms, "REPEAT"),
  )
}

/// Set DURATION on the alarm and discard that property's preserved form.
///
/// An update resets the form even when the value is unchanged. Other properties retain their values and forms.
pub fn ical_with_alarm_duration(alarm: IcalAlarm, value: String) -> IcalAlarm {
  IcalAlarm(
    ..alarm,
    duration: Some(value),
    forms: dict.delete(alarm.forms, "DURATION"),
  )
}

/// Append a attendee to the alarm.
///
/// Keep existing values and their parameters in order; the new value has no parsed parameters.
pub fn ical_add_alarm_attendee(alarm: IcalAlarm, value: String) -> IcalAlarm {
  IcalAlarm(..alarm, attendees_rev: [
    #(value, ical_validator_utc_form),
    ..alarm.attendees_rev
  ])
}

/// Set an extension property on the alarm, replacing any value with the same name.
///
/// Discard the preserved form for that name, even when the value is unchanged.
pub fn ical_with_alarm_x_property(
  alarm: IcalAlarm,
  name: String,
  value: String,
) -> IcalAlarm {
  IcalAlarm(
    ..alarm,
    x_properties: dict.insert(alarm.x_properties, name, value),
    forms: dict.delete(alarm.forms, name),
  )
}

/// Encode a calendar with CRLF endings and folding at 75 UTF-8 bytes per physical line.
///
/// Check typed dates, representable years, and rendered logical lines in emission order, returning the first error. Dates must be real whole-second civil values, including fields emitted as DATE. Wire years range from -999 through 9999; negative years use the parser's existing sign-plus-three-digits form. A raw line containing CR or LF is rejected.
///
/// Normalize CRLF and bare CR in typed TEXT to LF before escaping it. Getters continue to return the stored text; encoding and parsing can therefore normalize line endings. Preserve parsed raw-text handling and DATE/floating/UTC/TZID forms unless an update replaced them. This does not perform timezone conversion or complete RFC validation.
///
/// Emit component groups in timezone, event, task, journal, free/busy, unknown order, retaining order within each group. Folding includes the continuation space in its byte limit.
///
/// ## Examples
///
/// ```gleam
/// let calendar = ical_new_calendar("2.0", "example")
/// let assert Ok(wire) = ical_encode(calendar)
/// let assert Ok(_) = ical_parse(wire)
///
/// ical_new_calendar("2.0", "example")
/// |> ical_with_method("PUBLISH\nOTHER")
/// |> ical_encode
/// // Error(IcalPhysicalNewline("METHOD:PUBLISH\nOTHER"))
/// ```
pub fn ical_encode(cal: IcalCalendar) -> Result(String, IcalEncodeError) {
  use lines <- result.try(list.try_map(
    ical_emitter_render_calendar(cal),
    ical_emit_line,
  ))
  lines
  |> list.flat_map(ical_emitter_fold_line)
  |> list.map(fn(physical) { physical <> "\r\n" })
  |> string.concat
  |> Ok
}

fn ical_emitter_render_calendar(cal: IcalCalendar) -> List(IcalEmission) {
  let forms = cal.forms
  let header = [
    IcalLine("BEGIN:VCALENDAR"),
    ical_emitter_property(forms, "VERSION", ical_version(cal)),
    ical_emitter_raw_text_property(forms, "PRODID", ical_product_id(cal)),
  ]
  let method_lines = case ical_method(cal) {
    Some(m) -> [ical_emitter_property(forms, "METHOD", m)]
    None -> []
  }
  let calscale_lines = case ical_calscale(cal) {
    Some(s) -> [ical_emitter_property(forms, "CALSCALE", s)]
    None -> []
  }
  let x_lines =
    ical_emitter_render_x_properties(forms, ical_calendar_x_properties(cal))
  let tz_lines =
    list.flat_map(ical_timezones(cal), ical_emitter_render_timezone)
  let event_lines = list.flat_map(ical_events(cal), ical_emitter_render_event)
  let todo_lines = list.flat_map(ical_todos(cal), ical_emitter_render_todo)
  let journal_lines =
    list.flat_map(ical_journals(cal), ical_emitter_render_journal)
  let freebusy_lines =
    list.flat_map(ical_freebusy(cal), ical_emitter_render_freebusy)
  let unknown_lines =
    list.flat_map(
      ical_unknown_components(cal),
      ical_emitter_render_unknown_component,
    )

  list.flatten([
    header,
    method_lines,
    calscale_lines,
    x_lines,
    tz_lines,
    event_lines,
    todo_lines,
    journal_lines,
    freebusy_lines,
    unknown_lines,
    [IcalLine("END:VCALENDAR")],
  ])
}

fn ical_emitter_render_x_properties(
  forms: Dict(String, PropertyForm),
  x_props: dict.Dict(String, String),
) -> List(IcalEmission) {
  x_props
  |> dict.to_list
  |> list.map(fn(pair) {
    let #(name, value) = pair
    ical_emitter_raw_text_property(forms, name, value)
  })
}

fn ical_emitter_render_event(event: IcalEvent) -> List(IcalEmission) {
  let forms = event.forms
  let header = [
    IcalLine("BEGIN:VEVENT"),
    ical_emitter_property(forms, "UID", ical_event_uid(event)),
    ical_emitter_render_dt_values(
      ical_emitter_form_of(forms, "DTSTAMP"),
      "DTSTAMP",
      [ical_event_dtstamp(event)],
      None,
    ),
  ]
  let dtstart_lines =
    ical_emitter_render_dt_opt(
      forms,
      "DTSTART",
      ical_event_dtstart(event),
      ical_event_dtstart_tzid(event),
    )
  let dtend_lines =
    ical_emitter_render_dt_opt(
      forms,
      "DTEND",
      ical_event_dtend(event),
      ical_event_dtend_tzid(event),
    )
  let duration_lines =
    ical_emitter_render_opt(forms, "DURATION", ical_event_duration(event))
  let summary_lines =
    ical_emitter_render_text_opt(forms, "SUMMARY", ical_event_summary(event))
  let description_lines =
    ical_emitter_render_text_opt(
      forms,
      "DESCRIPTION",
      ical_event_description(event),
    )
  let location_lines =
    ical_emitter_render_text_opt(forms, "LOCATION", ical_event_location(event))
  let status_lines =
    ical_emitter_render_opt(forms, "STATUS", ical_event_status(event))
  let organizer_lines =
    ical_emitter_render_opt(forms, "ORGANIZER", ical_event_organizer(event))
  let attendee_lines =
    ical_emitter_render_lines("ATTENDEE", event.attendees_rev)
  let categories_lines = ical_emitter_render_categories(event.categories_rev)
  let url_lines = ical_emitter_render_opt(forms, "URL", ical_event_url(event))
  let created_lines = case ical_event_created(event) {
    Some(dt) -> [
      ical_emitter_render_dt_values(
        ical_emitter_form_of(forms, "CREATED"),
        "CREATED",
        [dt],
        None,
      ),
    ]
    None -> []
  }
  let last_mod_lines = case ical_event_last_modified(event) {
    Some(dt) -> [
      ical_emitter_render_dt_values(
        ical_emitter_form_of(forms, "LAST-MODIFIED"),
        "LAST-MODIFIED",
        [dt],
        None,
      ),
    ]
    None -> []
  }
  let sequence = ical_event_sequence(event)
  let sequence_lines = case sequence == 0 && !dict.has_key(forms, "SEQUENCE") {
    True -> []
    False -> [ical_emitter_property(forms, "SEQUENCE", int.to_string(sequence))]
  }
  let transp_lines =
    ical_emitter_render_opt(forms, "TRANSP", ical_event_transparency(event))
  let rrule_lines = case ical_event_rrule(event) {
    Some(raw) -> [
      ical_emitter_property(forms, "RRULE", ical_emitter_render_raw_rrule(raw)),
    ]
    None -> []
  }
  let rdate_lines = ical_emitter_render_dt_list("RDATE", event.rdates_rev)
  let exdate_lines = ical_emitter_render_dt_list("EXDATE", event.exdates_rev)
  let alarm_lines =
    list.flat_map(ical_event_alarms(event), ical_emitter_render_alarm)
  let x_lines =
    ical_emitter_render_x_properties(forms, ical_event_x_properties(event))

  list.flatten([
    header,
    dtstart_lines,
    dtend_lines,
    duration_lines,
    summary_lines,
    description_lines,
    location_lines,
    status_lines,
    organizer_lines,
    attendee_lines,
    categories_lines,
    url_lines,
    created_lines,
    last_mod_lines,
    sequence_lines,
    transp_lines,
    rrule_lines,
    rdate_lines,
    exdate_lines,
    alarm_lines,
    x_lines,
    [IcalLine("END:VEVENT")],
  ])
}

fn ical_emitter_render_todo(t: IcalTodo) -> List(IcalEmission) {
  let forms = t.forms
  let header = [
    IcalLine("BEGIN:VTODO"),
    ical_emitter_property(forms, "UID", ical_todo_uid(t)),
    ical_emitter_render_dt_values(
      ical_emitter_form_of(forms, "DTSTAMP"),
      "DTSTAMP",
      [ical_todo_dtstamp(t)],
      None,
    ),
  ]
  let dtstart_lines =
    ical_emitter_render_dt_opt(forms, "DTSTART", ical_todo_dtstart(t), None)
  let due_lines =
    ical_emitter_render_dt_opt(forms, "DUE", ical_todo_due(t), None)
  let completed_lines = case ical_todo_completed(t) {
    Some(dt) -> [
      ical_emitter_render_dt_values(
        ical_emitter_form_of(forms, "COMPLETED"),
        "COMPLETED",
        [dt],
        None,
      ),
    ]
    None -> []
  }
  let summary_lines =
    ical_emitter_render_text_opt(forms, "SUMMARY", ical_todo_summary(t))
  let description_lines =
    ical_emitter_render_text_opt(forms, "DESCRIPTION", ical_todo_description(t))
  let status_lines =
    ical_emitter_render_opt(forms, "STATUS", ical_todo_status(t))
  let percent_lines = case ical_todo_percent_complete(t) {
    Some(n) -> [
      ical_emitter_property(forms, "PERCENT-COMPLETE", int.to_string(n)),
    ]
    None -> []
  }
  let priority_lines = case ical_todo_priority(t) {
    Some(n) -> [ical_emitter_property(forms, "PRIORITY", int.to_string(n))]
    None -> []
  }
  let categories_lines = ical_emitter_render_categories(t.categories_rev)
  let rrule_lines = case ical_todo_rrule(t) {
    Some(raw) -> [
      ical_emitter_property(forms, "RRULE", ical_emitter_render_raw_rrule(raw)),
    ]
    None -> []
  }
  let rdate_lines = ical_emitter_render_dt_list("RDATE", t.rdates_rev)
  let exdate_lines = ical_emitter_render_dt_list("EXDATE", t.exdates_rev)
  let alarm_lines =
    list.flat_map(ical_todo_alarms(t), ical_emitter_render_alarm)
  let x_lines =
    ical_emitter_render_x_properties(forms, ical_todo_x_properties(t))

  list.flatten([
    header,
    dtstart_lines,
    due_lines,
    completed_lines,
    summary_lines,
    description_lines,
    status_lines,
    percent_lines,
    priority_lines,
    categories_lines,
    rrule_lines,
    rdate_lines,
    exdate_lines,
    alarm_lines,
    x_lines,
    [IcalLine("END:VTODO")],
  ])
}

fn ical_emitter_render_journal(j: IcalJournal) -> List(IcalEmission) {
  let forms = j.forms
  let header = [
    IcalLine("BEGIN:VJOURNAL"),
    ical_emitter_property(forms, "UID", ical_journal_uid(j)),
    ical_emitter_render_dt_values(
      ical_emitter_form_of(forms, "DTSTAMP"),
      "DTSTAMP",
      [ical_journal_dtstamp(j)],
      None,
    ),
  ]
  let dtstart_lines =
    ical_emitter_render_dt_opt(forms, "DTSTART", ical_journal_dtstart(j), None)
  let summary_lines =
    ical_emitter_render_text_opt(forms, "SUMMARY", ical_journal_summary(j))
  let description_lines =
    ical_emitter_render_text_opt(
      forms,
      "DESCRIPTION",
      ical_journal_description(j),
    )
  let status_lines =
    ical_emitter_render_opt(forms, "STATUS", ical_journal_status(j))
  let categories_lines = ical_emitter_render_categories(j.categories_rev)
  let x_lines =
    ical_emitter_render_x_properties(forms, ical_journal_x_properties(j))

  list.flatten([
    header,
    dtstart_lines,
    summary_lines,
    description_lines,
    status_lines,
    categories_lines,
    x_lines,
    [IcalLine("END:VJOURNAL")],
  ])
}

fn ical_emitter_render_freebusy(fb: IcalFreeBusy) -> List(IcalEmission) {
  let forms = fb.forms
  let header = [
    IcalLine("BEGIN:VFREEBUSY"),
    ical_emitter_property(forms, "UID", ical_freebusy_uid(fb)),
    ical_emitter_render_dt_values(
      ical_emitter_form_of(forms, "DTSTAMP"),
      "DTSTAMP",
      [ical_freebusy_dtstamp(fb)],
      None,
    ),
  ]
  let dtstart_lines =
    ical_emitter_render_dt_opt(
      forms,
      "DTSTART",
      ical_freebusy_dtstart(fb),
      None,
    )
  let dtend_lines =
    ical_emitter_render_dt_opt(forms, "DTEND", ical_freebusy_dtend(fb), None)
  let organizer_lines =
    ical_emitter_render_opt(forms, "ORGANIZER", ical_freebusy_organizer(fb))
  let attendee_lines = ical_emitter_render_lines("ATTENDEE", fb.attendees_rev)
  let period_lines =
    ical_emitter_render_lines("FREEBUSY", fb.freebusy_periods_rev)
  let x_lines =
    ical_emitter_render_x_properties(forms, ical_freebusy_x_properties(fb))

  list.flatten([
    header,
    dtstart_lines,
    dtend_lines,
    organizer_lines,
    attendee_lines,
    period_lines,
    x_lines,
    [IcalLine("END:VFREEBUSY")],
  ])
}

fn ical_emitter_render_timezone(tz: IcalTimezone) -> List(IcalEmission) {
  let forms = tz.forms
  let header = [
    IcalLine("BEGIN:VTIMEZONE"),
    ical_emitter_property(forms, "TZID", ical_timezone_tzid(tz)),
  ]
  let last_mod_lines = case ical_timezone_last_modified(tz) {
    Some(dt) -> [
      ical_emitter_render_dt_values(
        ical_emitter_form_of(forms, "LAST-MODIFIED"),
        "LAST-MODIFIED",
        [dt],
        None,
      ),
    ]
    None -> []
  }
  let tzurl_lines = case ical_timezone_tzurl(tz) {
    Some(v) -> [ical_emitter_property(forms, "TZURL", v)]
    None -> []
  }
  let standard_lines =
    list.flat_map(list.reverse(tz.standard_rev), fn(pair) {
      ical_emitter_render_timezone_rule("STANDARD", pair.0, pair.1)
    })
  let daylight_lines =
    list.flat_map(list.reverse(tz.daylight_rev), fn(pair) {
      ical_emitter_render_timezone_rule("DAYLIGHT", pair.0, pair.1)
    })
  let x_lines =
    ical_emitter_render_x_properties(forms, ical_timezone_x_properties(tz))

  list.flatten([
    header,
    last_mod_lines,
    tzurl_lines,
    standard_lines,
    daylight_lines,
    x_lines,
    [IcalLine("END:VTIMEZONE")],
  ])
}

fn ical_emitter_render_timezone_rule(
  kind: String,
  rule: IcalTimezoneRule,
  forms: Dict(String, PropertyForm),
) -> List(IcalEmission) {
  let IcalTimezoneRule(
    dtstart: dtstart,
    tzoffsetfrom: from,
    tzoffsetto: to,
    rrule: rrule_opt,
    tzname: tzname_opt,
  ) = rule
  let start_form = case dict.get(forms, "DTSTART") {
    Ok(form) -> form
    Error(Nil) -> PropertyForm(..ical_validator_utc_form, utc: False)
  }
  let header = [
    IcalLine("BEGIN:" <> kind),
    ical_emitter_render_dt_values(start_form, "DTSTART", [dtstart], None),
    ical_emitter_property(forms, "TZOFFSETFROM", from),
    ical_emitter_property(forms, "TZOFFSETTO", to),
  ]
  let rrule_lines = case rrule_opt {
    Some(raw) -> [
      ical_emitter_property(forms, "RRULE", ical_emitter_render_raw_rrule(raw)),
    ]
    None -> []
  }
  let tzname_lines = case tzname_opt {
    Some(name) -> [ical_emitter_raw_text_property(forms, "TZNAME", name)]
    None -> []
  }
  list.flatten([header, rrule_lines, tzname_lines, [IcalLine("END:" <> kind)]])
}

fn ical_emitter_render_alarm(alarm: IcalAlarm) -> List(IcalEmission) {
  let forms = alarm.forms
  let header = [
    IcalLine("BEGIN:VALARM"),
    ical_emitter_property(forms, "ACTION", ical_alarm_action(alarm)),
    ical_emitter_property(forms, "TRIGGER", ical_alarm_trigger(alarm)),
  ]
  let description_lines =
    ical_emitter_render_text_opt(
      forms,
      "DESCRIPTION",
      ical_alarm_description(alarm),
    )
  let summary_lines =
    ical_emitter_render_text_opt(forms, "SUMMARY", ical_alarm_summary(alarm))
  let repeat_lines = case ical_alarm_repeat(alarm) {
    Some(n) -> [ical_emitter_property(forms, "REPEAT", int.to_string(n))]
    None -> []
  }
  let duration_lines =
    ical_emitter_render_opt(forms, "DURATION", ical_alarm_duration(alarm))
  let attendee_lines =
    ical_emitter_render_lines("ATTENDEE", alarm.attendees_rev)
  let x_lines =
    ical_emitter_render_x_properties(forms, ical_alarm_x_properties(alarm))

  list.flatten([
    header,
    description_lines,
    summary_lines,
    repeat_lines,
    duration_lines,
    attendee_lines,
    x_lines,
    [IcalLine("END:VALARM")],
  ])
}

fn ical_emitter_render_unknown_component(
  uc: IcalUnknownComponent,
) -> List(IcalEmission) {
  let IcalUnknownComponent(kind: kind, properties: props, children: children) =
    uc
  let prop_lines = list.map(props, ical_emitter_render_raw_property)
  let child_lines = list.flat_map(children, ical_emitter_render_raw_component)
  list.flatten([
    [IcalLine("BEGIN:" <> kind)],
    prop_lines,
    child_lines,
    [IcalLine("END:" <> kind)],
  ])
}

fn ical_emitter_render_raw_component(
  comp: IcalRawComponent,
) -> List(IcalEmission) {
  let IcalRawComponent(kind: kind, properties: props, children: children, ..) =
    comp
  let prop_lines = list.map(props, ical_emitter_render_raw_property)
  let child_lines = list.flat_map(children, ical_emitter_render_raw_component)
  list.flatten([
    [IcalLine("BEGIN:" <> kind)],
    prop_lines,
    child_lines,
    [IcalLine("END:" <> kind)],
  ])
}

fn ical_emitter_render_raw_property(prop: IcalRawProperty) -> IcalEmission {
  let IcalRawProperty(name: name, parameters: params, raw_value: value, ..) =
    prop
  IcalPropertyLine(name, params, value)
}

fn ical_emitter_quote_param_if_needed(value: String) -> String {
  case
    string.contains(value, ":")
    || string.contains(value, ";")
    || string.contains(value, ",")
  {
    True -> "\"" <> value <> "\""
    False -> value
  }
}

fn ical_emitter_form_of(
  forms: Dict(String, PropertyForm),
  name: String,
) -> PropertyForm {
  dict.get(forms, name) |> result.unwrap(ical_validator_utc_form)
}

fn ical_emitter_property(
  forms: Dict(String, PropertyForm),
  name: String,
  value: String,
) -> IcalEmission {
  IcalPropertyLine(name, ical_emitter_form_of(forms, name).parameters, value)
}

fn ical_emitter_raw_text_property(
  forms: Dict(String, PropertyForm),
  name: String,
  value: String,
) -> IcalEmission {
  let encoded = case ical_emitter_form_of(forms, name).raw_text {
    True -> value
    False -> ical_emitter_escape_text(value)
  }
  ical_emitter_property(forms, name, encoded)
}

fn ical_emitter_render_parameters(params: List(IcalParameter)) -> String {
  params
  |> list.chunk(fn(p) { p.name })
  |> list.map(fn(group) {
    case group {
      [] -> ""
      [first, ..] ->
        ";"
        <> first.name
        <> "="
        <> string.join(
          list.map(group, fn(p) { ical_emitter_quote_param_if_needed(p.value) }),
          ",",
        )
    }
  })
  |> string.concat
}

fn ical_emitter_render_opt(
  forms: Dict(String, PropertyForm),
  name: String,
  value: Option(String),
) -> List(IcalEmission) {
  case value {
    Some(v) -> [ical_emitter_property(forms, name, v)]
    None -> []
  }
}

fn ical_emitter_render_text_opt(
  forms: Dict(String, PropertyForm),
  name: String,
  value: Option(String),
) -> List(IcalEmission) {
  ical_emitter_render_opt(
    forms,
    name,
    option.map(value, ical_emitter_escape_text),
  )
}

fn ical_emitter_render_dt_opt(
  forms: Dict(String, PropertyForm),
  name: String,
  dt_opt: Option(DateTime),
  tzid_opt: Option(String),
) -> List(IcalEmission) {
  case dt_opt {
    None -> []
    Some(dt) -> [
      ical_emitter_render_dt_values(
        ical_emitter_form_of(forms, name),
        name,
        [dt],
        tzid_opt,
      ),
    ]
  }
}

fn ical_emitter_render_dt_list(
  name: String,
  values: List(#(DateTime, PropertyForm)),
) -> List(IcalEmission) {
  values
  |> list.reverse
  |> list.map(fn(pair) { #(pair.1, pair.0) })
  |> ical_emitter_group_by_form([])
  |> list.map(fn(group) {
    ical_emitter_render_dt_values(group.0, name, group.1, None)
  })
}

fn ical_emitter_group_by_form(
  pairs: List(#(PropertyForm, a)),
  acc: List(#(PropertyForm, List(a))),
) -> List(#(PropertyForm, List(a))) {
  case pairs, acc {
    [], _ ->
      list.reverse(
        list.map(acc, fn(group) { #(group.0, list.reverse(group.1)) }),
      )
    [#(form, value), ..rest], [#(current, values), ..done] if form == current ->
      ical_emitter_group_by_form(rest, [#(current, [value, ..values]), ..done])
    [#(form, value), ..rest], _ ->
      ical_emitter_group_by_form(rest, [#(form, [value]), ..acc])
  }
}

fn ical_emitter_dt_parameters(
  form: PropertyForm,
  tzid_opt: Option(String),
) -> List(IcalParameter) {
  case tzid_opt {
    None -> form.parameters
    Some(tzid) -> [
      IcalParameter(name: "TZID", value: tzid),
      ..list.filter(form.parameters, fn(p) {
        !ical_emitter_parameter_is(p, "TZID")
      })
    ]
  }
}

fn ical_emitter_format_dt_values(
  form: PropertyForm,
  name: String,
  values: List(DateTime),
  params: List(IcalParameter),
) -> String {
  let is_date =
    form.date_only
    || list.any(params, fn(p) {
      ical_emitter_parameter_is(p, "VALUE")
      && string.uppercase(p.value) == "DATE"
    })
  let is_local =
    !form.utc || list.any(params, ical_emitter_parameter_is(_, "TZID"))
  let render = case is_date, is_local {
    True, _ -> ical_emitter_render_date
    False, True -> ical_emitter_render_datetime
    False, False -> ical_emitter_render_datetime_utc
  }
  name
  <> ical_emitter_render_parameters(params)
  <> ":"
  <> string.join(list.map(values, render), ",")
}

fn ical_emitter_parameter_is(p: IcalParameter, name: String) -> Bool {
  string.uppercase(p.name) == name
}

fn ical_emitter_render_lines(
  name: String,
  values: List(#(String, PropertyForm)),
) -> List(IcalEmission) {
  values
  |> list.reverse
  |> list.map(fn(pair) { IcalPropertyLine(name, pair.1.parameters, pair.0) })
}

fn ical_emitter_render_categories(
  categories: List(#(String, PropertyForm)),
) -> List(IcalEmission) {
  categories
  |> list.reverse
  |> list.map(fn(pair) { #(pair.1, pair.0) })
  |> ical_emitter_group_by_form([])
  |> list.map(fn(group) {
    IcalPropertyLine(
      "CATEGORIES",
      group.0.parameters,
      string.join(list.map(group.1, ical_emitter_escape_text), ","),
    )
  })
}

fn ical_emitter_render_raw_rrule(raw: RawRRule) -> String {
  let RawRRule(parts: parts) = raw
  parts
  |> list.map(fn(p) {
    let RawRulePart(name: name, value: value) = p
    name <> "=" <> value
  })
  |> string.join(";")
}

fn ical_emitter_render_date(dt: DateTime) -> String {
  let calendar.Date(year: y, month: month, day: d) = dt.date
  let mo = calendar.month_to_int(month)
  ical_wire_year(y) <> internal_digits_pad2(mo) <> internal_digits_pad2(d)
}

fn ical_emitter_render_datetime(dt: DateTime) -> String {
  let DateTime(date: date, time: time) = dt
  let calendar.Date(year: y, month: month, day: d) = date
  let mo = calendar.month_to_int(month)
  let calendar.TimeOfDay(hours: h, minutes: mi, seconds: s, nanoseconds: _) =
    time
  ical_wire_year(y)
  <> internal_digits_pad2(mo)
  <> internal_digits_pad2(d)
  <> "T"
  <> internal_digits_pad2(h)
  <> internal_digits_pad2(mi)
  <> internal_digits_pad2(s)
}

fn ical_emitter_render_datetime_utc(dt: DateTime) -> String {
  ical_emitter_render_datetime(dt) <> "Z"
}

fn ical_emitter_escape_text(s: String) -> String {
  s
  |> string.replace("\r\n", "\n")
  |> string.replace("\r", "\n")
  |> string.replace("\\", "\\\\")
  |> string.replace("\n", "\\n")
  |> string.replace(",", "\\,")
  |> string.replace(";", "\\;")
}

fn ical_emitter_fold_line(line: String) -> List(String) {
  let codepoints = string.to_utf_codepoints(line)
  ical_emitter_fold_loop(codepoints, [], 0, [], False)
}

fn ical_emitter_fold_loop(
  codepoints: List(UtfCodepoint),
  current: List(UtfCodepoint),
  current_bytes: Int,
  acc: List(String),
  is_continuation: Bool,
) -> List(String) {
  case codepoints {
    [] -> {
      let final_line = ical_emitter_build_line(current, is_continuation)
      list.reverse([final_line, ..acc])
    }
    [cp, ..rest] -> {
      let cp_bytes = ical_emitter_utf8_byte_length(cp)
      let limit = case is_continuation {
        True -> 74
        False -> 75
      }
      case current_bytes + cp_bytes > limit {
        True -> {
          let finished = ical_emitter_build_line(current, is_continuation)
          ical_emitter_fold_loop(rest, [cp], cp_bytes, [finished, ..acc], True)
        }
        False ->
          ical_emitter_fold_loop(
            rest,
            [cp, ..current],
            current_bytes + cp_bytes,
            acc,
            is_continuation,
          )
      }
    }
  }
}

fn ical_emitter_build_line(
  current: List(UtfCodepoint),
  is_continuation: Bool,
) -> String {
  let body = string.from_utf_codepoints(list.reverse(current))
  case is_continuation {
    True -> " " <> body
    False -> body
  }
}

fn ical_emitter_utf8_byte_length(cp: UtfCodepoint) -> Int {
  let value = string.utf_codepoint_to_int(cp)
  case value {
    _ if value < 0x80 -> 1
    _ if value < 0x800 -> 2
    _ if value < 0x10000 -> 3
    _ -> 4
  }
}

/// Read an iCalendar document into a raw property/component tree.
///
/// Unfold continuation lines and retain property parameters, raw values, and line positions. Accept CRLF, LF, and bare CR physical line endings. Remove one leading BOM only; preserve U+FEFF elsewhere. Typed component requirements are checked separately by `ical_validate`.
pub fn ical_parse_raw(input: String) -> Result(IcalRawCalendar, IcalError) {
  use logical_lines <- result.try(
    ical_lexer_unfold(input)
    |> result.map_error(ical_parser_lex_error_to_parse_error),
  )
  use properties <- result.try(ical_parser_tokenize_all(logical_lines, []))
  ical_parser_build_calendar(properties)
}

fn ical_parser_lex_error_to_parse_error(err: IcalLexError) -> IcalError {
  case err {
    EmptyIcalInput -> IcalEmptyInputError
    MalformedIcalLine(line: ln, raw: raw) ->
      IcalMalformedProperty(line: ln, raw: raw)
    MalformedIcalParameter(line: ln, raw: raw) ->
      IcalMalformedParameter(line: ln, raw: raw)
  }
}

fn ical_parser_tokenize_all(
  lines: List(LogicalLine),
  acc: List(IcalRawProperty),
) -> Result(List(IcalRawProperty), IcalError) {
  case lines {
    [] -> Ok(list.reverse(acc))
    [first, ..rest] ->
      case ical_lexer_tokenize_line(first) {
        Error(err) -> Error(ical_parser_lex_error_to_parse_error(err))
        Ok(prop) -> ical_parser_tokenize_all(rest, [prop, ..acc])
      }
  }
}

fn ical_parser_build_calendar(
  properties: List(IcalRawProperty),
) -> Result(IcalRawCalendar, IcalError) {
  case properties {
    [] -> Error(IcalEmptyInputError)
    [first, ..rest] -> ical_parse_calendar_body(first, rest)
  }
}

fn ical_parser_consume_component(
  kind: String,
  begin_line: Int,
  properties: List(IcalRawProperty),
  acc_props: List(IcalRawProperty),
  acc_children: List(IcalRawComponent),
) -> Result(#(IcalRawComponent, List(IcalRawProperty)), IcalError) {
  case properties {
    [] -> Error(IcalMismatchedBlock(kind, "<eof>", begin_line))
    [IcalRawProperty(name: "END", raw_value: ending, line: line, ..), ..rest] -> {
      let ending = string.uppercase(ending)
      case ending == kind {
        False -> Error(IcalMismatchedBlock(kind, ending, line))
        True ->
          Ok(#(
            IcalRawComponent(
              kind,
              list.reverse(acc_props),
              list.reverse(acc_children),
              begin_line,
            ),
            rest,
          ))
      }
    }
    [
      IcalRawProperty(name: "BEGIN", raw_value: child_kind, line: line, ..),
      ..rest
    ] ->
      case
        ical_parser_consume_component(
          string.uppercase(child_kind),
          line,
          rest,
          [],
          [],
        )
      {
        Error(error) -> Error(error)
        Ok(#(child, after)) ->
          ical_parser_consume_component(kind, begin_line, after, acc_props, [
            child,
            ..acc_children
          ])
      }
    [first, ..rest] ->
      ical_parser_consume_component(
        kind,
        begin_line,
        rest,
        [first, ..acc_props],
        acc_children,
      )
  }
}

/// An iCalendar property parameter name and value.
pub type IcalParameter {
  IcalParameter(name: String, value: String)
}

/// A property name, ordered parameters, raw value, and source line position before typed interpretation.
pub type IcalRawProperty {
  IcalRawProperty(
    name: String,
    parameters: List(IcalParameter),
    raw_value: String,
    line: Int,
  )
}

/// A raw component with its kind, properties, child components, and opening line position.
pub type IcalRawComponent {
  IcalRawComponent(
    kind: String,
    properties: List(IcalRawProperty),
    children: List(IcalRawComponent),
    begin_line: Int,
  )
}

/// The raw top-level calendar properties and component tree returned by `ical_parse_raw`.
pub type IcalRawCalendar {
  IcalRawCalendar(
    properties: List(IcalRawProperty),
    components: List(IcalRawComponent),
  )
}

type LogicalLine {
  LogicalLine(text: String, line: Int)
}

type IcalLexError {
  EmptyIcalInput
  MalformedIcalLine(line: Int, raw: String)
  MalformedIcalParameter(line: Int, raw: String)
}

fn ical_lexer_unfold(input: String) -> Result(List(LogicalLine), IcalLexError) {
  case input {
    "" -> Error(EmptyIcalInput)
    _ -> {
      let stripped = ical_lexer_strip_bom(input)
      let normalized =
        stripped
        |> string.replace("\r\n", "\n")
        |> string.replace("\r", "\n")
      let physical_lines = string.split(normalized, "\n")
      let folded = ical_lexer_fold_lines(physical_lines, 1, [])
      let non_empty =
        list.filter(folded, fn(line) {
          let LogicalLine(text: text, ..) = line
          text != ""
        })
      case non_empty {
        [] -> Error(EmptyIcalInput)
        _ -> Ok(non_empty)
      }
    }
  }
}

fn ical_lexer_strip_bom(input: String) -> String {
  case input {
    "\u{FEFF}" <> rest -> rest
    _ -> input
  }
}

fn ical_lexer_fold_lines(
  physical_lines: List(String),
  current_line: Int,
  acc: List(LogicalLine),
) -> List(LogicalLine) {
  case physical_lines {
    [] -> list.reverse(acc)
    [first, ..rest] -> {
      let is_continuation =
        string.starts_with(first, " ") || string.starts_with(first, "\t")
      case is_continuation, acc {
        True, [LogicalLine(text: prev_text, line: prev_ln), ..tail] -> {
          let appended = prev_text <> string.drop_start(first, 1)
          let new_acc = [LogicalLine(text: appended, line: prev_ln), ..tail]
          ical_lexer_fold_lines(rest, current_line + 1, new_acc)
        }
        // 先頭が継続行の場合は仕様外だが、ロバストに新規行として扱う。
        True, [] ->
          ical_lexer_fold_lines(rest, current_line + 1, [
            LogicalLine(text: first, line: current_line),
            ..acc
          ])
        False, _ ->
          ical_lexer_fold_lines(rest, current_line + 1, [
            LogicalLine(text: first, line: current_line),
            ..acc
          ])
      }
    }
  }
}

fn ical_lexer_tokenize_line(
  line: LogicalLine,
) -> Result(IcalRawProperty, IcalLexError) {
  let LogicalLine(text, line_number) = line
  use #(head, raw_value) <- result.try(
    ical_lexer_split_at_unquoted(string.to_graphemes(text), ":")
    |> result.replace_error(MalformedIcalLine(line_number, text)),
  )
  case ical_lexer_split_all_unquoted(string.to_graphemes(head), ";") {
    [name, ..parameters] if name != "" -> {
      use parameters <- result.try(
        ical_lexer_parse_parameters(parameters, line_number, []),
      )
      Ok(IcalRawProperty(
        string.uppercase(name),
        parameters,
        raw_value,
        line_number,
      ))
    }
    _ -> Error(MalformedIcalLine(line_number, text))
  }
}

fn ical_lexer_parse_parameters(
  tokens: List(String),
  ln: Int,
  acc: List(IcalParameter),
) -> Result(List(IcalParameter), IcalLexError) {
  case tokens {
    [] -> Ok(list.reverse(acc))
    [first, ..rest] ->
      case ical_lexer_parse_parameter(first, ln) {
        Error(err) -> Error(err)
        Ok(params) ->
          ical_lexer_parse_parameters(
            rest,
            ln,
            list.append(list.reverse(params), acc),
          )
      }
  }
}

fn ical_lexer_parse_parameter(
  raw: String,
  ln: Int,
) -> Result(List(IcalParameter), IcalLexError) {
  let graphemes = string.to_graphemes(raw)
  case ical_lexer_split_at_unquoted(graphemes, "=") {
    Error(_) -> Error(MalformedIcalParameter(line: ln, raw: raw))
    Ok(#(name, value)) ->
      case name, value {
        "", _ -> Error(MalformedIcalParameter(line: ln, raw: raw))
        _, _ ->
          ical_lexer_split_all_unquoted(string.to_graphemes(value), ",")
          |> list.try_map(fn(item) {
            ical_lexer_strip_dquotes(item, raw, ln)
            |> result.map(fn(stripped) {
              IcalParameter(name: string.uppercase(name), value: stripped)
            })
          })
      }
  }
}

fn ical_lexer_strip_dquotes(
  value: String,
  raw: String,
  ln: Int,
) -> Result(String, IcalLexError) {
  let starts = string.starts_with(value, "\"")
  let ends = string.ends_with(value, "\"")
  case starts, ends {
    True, True -> {
      // 両端 quote。長さ 1 の場合は中身が空文字列 (というか不正) なので空扱い。
      let dropped_start = string.drop_start(value, 1)
      let stripped = string.drop_end(dropped_start, 1)
      Ok(stripped)
    }
    False, False -> Ok(value)
    _, _ -> Error(MalformedIcalParameter(line: ln, raw: raw))
  }
}

fn ical_lexer_split_at_unquoted(
  graphemes: List(String),
  separator: String,
) -> Result(#(String, String), Nil) {
  ical_lexer_do_split_at_unquoted(graphemes, separator, False, [])
}

fn ical_lexer_do_split_at_unquoted(
  graphemes: List(String),
  separator: String,
  in_quote: Bool,
  acc: List(String),
) -> Result(#(String, String), Nil) {
  case graphemes {
    [] -> Error(Nil)
    [g, ..rest] ->
      case g, in_quote {
        "\"", _ ->
          ical_lexer_do_split_at_unquoted(rest, separator, !in_quote, [g, ..acc])
        _, False ->
          case g == separator {
            True -> {
              let head = string.concat(list.reverse(acc))
              let tail = string.concat(rest)
              Ok(#(head, tail))
            }
            False ->
              ical_lexer_do_split_at_unquoted(rest, separator, in_quote, [
                g,
                ..acc
              ])
          }
        _, True ->
          ical_lexer_do_split_at_unquoted(rest, separator, in_quote, [g, ..acc])
      }
  }
}

fn ical_lexer_split_all_unquoted(
  graphemes: List(String),
  separator: String,
) -> List(String) {
  ical_lexer_do_split_all_unquoted(graphemes, separator, False, [], [])
}

fn ical_lexer_do_split_all_unquoted(
  graphemes: List(String),
  separator: String,
  in_quote: Bool,
  current: List(String),
  acc: List(String),
) -> List(String) {
  case graphemes {
    [] -> {
      let last = string.concat(list.reverse(current))
      list.reverse([last, ..acc])
    }
    [g, ..rest] ->
      case g, in_quote {
        "\"", _ ->
          ical_lexer_do_split_all_unquoted(
            rest,
            separator,
            !in_quote,
            [g, ..current],
            acc,
          )
        _, False ->
          case g == separator {
            True -> {
              let token = string.concat(list.reverse(current))
              ical_lexer_do_split_all_unquoted(rest, separator, in_quote, [], [
                token,
                ..acc
              ])
            }
            False ->
              ical_lexer_do_split_all_unquoted(
                rest,
                separator,
                in_quote,
                [g, ..current],
                acc,
              )
          }
        _, True ->
          ical_lexer_do_split_all_unquoted(
            rest,
            separator,
            in_quote,
            [g, ..current],
            acc,
          )
      }
  }
}

/// Built-in scheduled, filesystem, manual, and custom event bodies. Generic `Event` records can use other body types.
pub type EventBody {
  Scheduled(
    plan_id: String,
    fired_at: ValidDateTime,
    schedule_kind: ScheduleKind,
  )
  FileSystem(event: WatchEvent)
  Manual(reason: Option(String), actor: Option(String))
  Custom(kind: String, attributes: Dict(String, String))
}

/// Whether a built-in scheduled event identifies a cron or RRULE schedule.
pub type ScheduleKind {
  CronSchedule
  RRuleSchedule
}

/// Return the stable kind label of a built-in event body.
pub fn event_body_kind(body: EventBody) -> String {
  case body {
    Scheduled(_, _, _) -> "scheduled"
    FileSystem(event) ->
      "file_system:" <> event_builtin_body_file_system_op_label(event)
    Manual(_, _) -> "manual"
    Custom(name, _) -> "custom:" <> name
  }
}

/// Create an event whose source classification is derived from its built-in body.
///
/// Use the supplied source id with no display name and empty metadata. Ordinary `Event` records also support arbitrary body types; constructing those records directly does not validate source/body agreement.
pub fn builtin_event(
  id id: String,
  occurred_at occurred_at: ValidDateTime,
  source_id source_id: String,
  body body: EventBody,
) -> Event(EventBody) {
  Event(
    id: id,
    occurred_at: occurred_at,
    source: event_builtin_body_derived_source(body, source_id),
    body: body,
    metadata: event_metadata_empty(),
  )
}

fn event_builtin_body_derived_source(
  body: EventBody,
  source_id: String,
) -> Source {
  event_source_new(kind: event_body_source_kind(body), id: source_id)
}

/// Derive the source classification of a built-in event body.
pub fn event_body_source_kind(body: EventBody) -> SourceKind {
  case body {
    Scheduled(_, _, _) -> ScheduleSource
    FileSystem(_) -> FileSystemSource
    Manual(_, _) -> ManualSource
    Custom(name, _) -> CustomSource(name)
  }
}

fn event_builtin_body_file_system_op_label(event: WatchEvent) -> String {
  event
  |> filesystem_event_ops
  |> ops_to_list
  |> list.map(event_builtin_body_op_label)
  |> string.join("+")
}

fn event_builtin_body_op_label(op: Op) -> String {
  op_to_string(op: op)
  |> string.lowercase
}

fn civil_time(
  hour hour: Int,
  minute minute: Int,
  second second: Int,
) -> calendar.TimeOfDay {
  calendar.TimeOfDay(
    hours: hour,
    minutes: minute,
    seconds: second,
    nanoseconds: 0,
  )
}

/// Validate a civil date and whole-second time.
///
/// Check JavaScript's safe integer year range first, then the Gregorian date, then the time with nanoseconds equal to zero. Year zero and negative years are supported. Erlang retains arbitrary-precision years. The value has no timezone or daylight-saving interpretation.
///
/// ## Examples
///
/// ```gleam
/// import gleam/time/calendar
///
/// let date = calendar.Date(2026, calendar.January, 1)
/// datetime_validate(DateTime(date, calendar.TimeOfDay(12, 0, 0, 1)))
/// // Error(InvalidTime(12, 0, 0, 1))
///
/// let assert Ok(at) = datetime_validate(DateTime(
///   date, calendar.TimeOfDay(12, 0, 0, 0),
/// ))
/// datetime_to_string(at)
/// // "2026-01-01T12:00:00"
/// ```
pub fn datetime_validate(
  value: DateTime,
) -> Result(ValidDateTime, DateTimeError) {
  let date = value.date
  let time = value.time
  case civil_integer_is_exact(date.year) {
    False -> Error(DateTimeYearOutOfRange(date.year))
    True ->
      case calendar.is_valid_date(date) {
        False ->
          Error(InvalidDate(
            date.year,
            calendar.month_to_int(date.month),
            date.day,
          ))
        True ->
          case calendar.is_valid_time_of_day(time) && time.nanoseconds == 0 {
            False ->
              Error(InvalidTime(
                time.hours,
                time.minutes,
                time.seconds,
                time.nanoseconds,
              ))
            True -> Ok(ValidDateTime(value))
          }
      }
  }
}

/// Read the civil date and time held by a validated value.
pub fn datetime_value(value: ValidDateTime) -> DateTime {
  value.value
}

/// Format a validated civil value as `YYYY-MM-DDTHH:MM:SS`.
///
/// Use at least four year digits, with a leading minus for negative years and all digits for larger years. Append no timezone suffix.
pub fn datetime_to_string(value: ValidDateTime) -> String {
  schedule_ast_to_string(value.value)
}

/// Unvalidated cron selectors that can be changed with record updates.
///
/// Start with `cron_options` for all-wildcard fields, then validate using `cron_new`.
pub type CronOptions {
  CronOptions(
    minute: CronSelector,
    hour: CronSelector,
    day_of_month: CronSelector,
    month: CronSelector,
    day_of_week: CronSelector,
  )
}

/// Unvalidated recurrence settings for record updates.
///
/// None means a BY filter was omitted; Some([]) is invalid. `rrule_options` supplies interval one and no end or filters. Validate the updated record with `rrule_new`.
pub type RecurrenceOptions {
  RecurrenceOptions(
    frequency: Frequency,
    interval: Int,
    end_condition: EndCondition,
    by_day: Option(List(WeekdaySpecifier)),
    by_month: Option(List(Int)),
    by_month_day: Option(List(Int)),
    by_hour: Option(List(Int)),
    by_minute: Option(List(Int)),
  )
}

/// An invalid fixed interval or a failure to compute a schedule result.
///
/// ScheduleSearchLimitReached reports a candidate-work limit, not the end of a sequence. ScheduleNumericOverflow means a necessary value exceeds the target's exact integer range. Callers should retain these distinctions from a successful empty result.
pub type ScheduleError {
  EveryIntervalMustBePositive(actual: Int)
  ScheduleSearchLimitReached(limit: Int)
  ScheduleNumericOverflow
}

/// A typed date, year representation, parameter value, or physical-newline error during encoding.
///
/// Errors follow logical emission order. Date validation precedes wire-year validation for a date field. Parameter values cannot contain DQUOTE. A completed logical line is then checked for raw CR or LF.
pub type IcalEncodeError {
  IcalInvalidDateValue(property: String, value: DateTime, error: DateTimeError)
  IcalYearNotRepresentable(property: String, year: Int)
  IcalInvalidParameterValue(property: String, parameter: String, value: String)
  IcalPhysicalNewline(logical_line: String)
}

/// Return cron options with all five fields set to `CronAny`.
///
/// Use record updates to select fields, then call `cron_new` to validate them.
pub fn cron_options() -> CronOptions {
  CronOptions(CronAny, CronAny, CronAny, CronAny, CronAny)
}

/// Validate typed cron options.
///
/// Reject empty value lists, nonpositive steps, invalid ranges, and out-of-range values. Check fields in minute, hour, day-of-month, month, day-of-week order, then date constraints. The resulting specification can be passed to `schedule_from_cron`.
///
/// ## Examples
///
/// ```gleam
/// let options = cron_options()
/// let assert Ok(cron) = cron_new(CronOptions(
///   ..options, minute: CronValues([CronExact(15)]),
/// ))
/// cron_to_string(cron)
/// // "15 * * * *"
///
/// cron_new(CronOptions(..options, minute: CronValues([CronExact(90)])))
/// // Error(CronOutOfRange(CronMinute, 0, 59, 90))
/// ```
pub fn cron_new(options: CronOptions) -> Result(Cron, CronValidationError) {
  cron_validator_from_selectors(
    minute: options.minute,
    hour: options.hour,
    day_of_month: options.day_of_month,
    month: options.month,
    day_of_week: options.day_of_week,
  )
}

/// Return the validated selectors as ordinary cron options.
///
/// Updating these options does not change the original specification. Pass the updated record through `cron_new`.
pub fn cron_to_options(cron: Cron) -> CronOptions {
  CronOptions(
    cron.minute,
    cron.hour,
    cron.day_of_month,
    cron.month,
    cron.day_of_week,
  )
}

/// Return options for the given frequency, with interval one, no end, and no BY filters.
///
/// Update the record and pass it to `rrule_new`. Omitted fields use frequency-dependent defaults when the rule is anchored by `schedule_from_rrule`.
pub fn rrule_options(frequency: Frequency) -> RecurrenceOptions {
  RecurrenceOptions(frequency, 1, Forever, None, None, None, None, None)
}

/// Validate typed recurrence options without choosing an anchor.
///
/// Check interval, end condition, BYDAY, BYMONTH, BYMONTHDAY, BYHOUR, then BYMINUTE and combined constraints. Intervals and counts must be positive and exactly representable on the target. Reject empty supplied filters. UNTIL uses years 0 through 9999; a DateTime end must have zero nanoseconds.
///
/// ## Examples
///
/// ```gleam
/// let options = rrule_options(Daily)
/// let assert Ok(rule) = rrule_new(RecurrenceOptions(
///   ..options, end_condition: Count(2),
/// ))
/// rrule_to_options(rule).end_condition
/// // Count(2)
///
/// rrule_new(RecurrenceOptions(..options, interval: 0))
/// // Error(RruleMustBePositive(IntervalPart, 0))
/// ```
pub fn rrule_new(
  options: RecurrenceOptions,
) -> Result(RecurrenceRule, RruleValidationError) {
  rrule_validator_from_parts(
    frequency: options.frequency,
    interval: options.interval,
    end_condition: options.end_condition,
    by_day: options.by_day,
    by_month: options.by_month,
    by_month_day: options.by_month_day,
    by_hour: options.by_hour,
    by_minute: options.by_minute,
  )
}

/// Return the validated rule as ordinary recurrence options.
///
/// Selectors are normalized. Validate any record updates with `rrule_new` before scheduling them.
pub fn rrule_to_options(rule: RecurrenceRule) -> RecurrenceOptions {
  RecurrenceOptions(
    rule.frequency,
    rule.interval,
    rule.end_condition,
    rule.by_day,
    rule.by_month,
    rule.by_month_day,
    rule.by_hour,
    rule.by_minute,
  )
}

/// Create a schedule containing exactly the supplied occurrence.
pub fn schedule_once(at: ValidDateTime) -> Schedule {
  PlanOnce(at.value)
}

/// Create a fixed-interval schedule beginning at the anchor.
///
/// Require a positive interval in seconds; JavaScript also requires an exactly representable safe integer. Occurrences include the anchor and advance by whole intervals without timezone conversion.
pub fn schedule_every(
  interval_seconds interval_seconds: Int,
  anchor anchor: ValidDateTime,
) -> Result(Schedule, ScheduleError) {
  case interval_seconds <= 0 {
    True -> Error(EveryIntervalMustBePositive(interval_seconds))
    False ->
      case civil_integer_is_exact(interval_seconds) {
        False -> Error(ScheduleNumericOverflow)
        True -> Ok(PlanEvery(EveryPlan(anchor.value, interval_seconds)))
      }
  }
}

/// Check whether the schedule matches a validated civil time.
///
/// Cron matching uses the minute and ignores the seconds field, while cron iteration emits second zero. An iterator whose boundary has nonzero seconds therefore starts after the boundary's minute even when that minute matches. Recurrence COUNT is measured from the original anchor. Return a search-limit or numeric error if the answer cannot be determined within the supported computation limits.
pub fn schedule_matches(
  schedule: Schedule,
  at at: ValidDateTime,
) -> Result(Bool, ScheduleError) {
  let raw = at.value
  case schedule {
    PlanCron(plan) -> Ok(cron_evaluator_matches(plan: plan, at: raw))
    PlanEvery(plan) -> Ok(schedule_every_matches(plan, raw))
    PlanOnce(when) -> Ok(internal_calendar_equals(when, raw))
    PlanRecurrence(plan) -> {
      recurrence_matches(plan, at)
    }
  }
}

/// Prepare an immutable occurrence iterator at an inclusive or exclusive boundary.
///
/// For COUNT-limited rules, account for occurrences before the boundary instead of restarting the count. This work can return a search-limit or numeric error. The iterator owns no external resource; stepping the same value again returns the same result.
pub fn schedule_iterator(
  schedule: Schedule,
  boundary boundary: Boundary,
) -> Result(OccurrenceIterator, ScheduleError) {
  schedule_prepare(schedule, boundary, SearchBudget(1_000_000))
  |> result.map(fn(value) { value.0 })
}

/// Return the next occurrence and continuation, or `Done` for a finished sequence.
///
/// `Done` means an end condition was reached or a complete empty calendar cycle was established. Reaching the search work limit or the target's exact numeric range returns an error. A yielded final occurrence remains available even when there is no representable later time.
pub fn schedule_step(
  iterator: OccurrenceIterator,
) -> Result(IterStep, ScheduleError) {
  schedule_step_with_budget(iterator, SearchBudget(1_000_000))
  |> result.map(fn(value) { value.0 })
}

/// Find the first occurrence strictly after the supplied time.
///
/// Return `Ok(None)` for a finished sequence. Search-limit and numeric failures remain errors. For an inclusive start or repeated traversal, use `schedule_iterator` and `schedule_step`.
pub fn schedule_next(
  schedule: Schedule,
  after after: ValidDateTime,
) -> Result(Option(ValidDateTime), ScheduleError) {
  use #(iterator, budget) <- result.try(schedule_prepare(
    schedule,
    Exclusive(after),
    SearchBudget(1_000_000),
  ))
  use #(step, _) <- result.try(schedule_step_with_budget(iterator, budget))
  Ok(case step {
    Yield(at, _) -> Some(at)
    Done -> None
  })
}

/// Compare two supplied snapshots and retain only observed operations.
///
/// Detect create, write, remove, rename, and mode changes. For file content, compare hashes when both are available; otherwise compare size and mtime. Match unique file identities for renames, including identities whose entry kind changes; ambiguous identities are not treated as a rename.
///
/// Intersect each event's operations with observing and drop empty events. If Rename is removed by this filter, also remove its old path. Pass `all_ops()` to observe every operation. This function reads no files and starts no watcher.
pub fn diff_snapshots(
  previous: Snapshot,
  current: Snapshot,
  observing observing: Set(Op),
) -> List(WatchEvent) {
  filesystem_diff_diff(prev: previous, curr: current, watch: observing)
}

/// Return whether the event occurred strictly after the supplied civil time.
pub fn event_occurred_after(
  event: Event(body),
  after after: ValidDateTime,
) -> Bool {
  internal_calendar_greater_than(event.occurred_at.value, after.value)
}

/// Return whether the event occurred strictly before the supplied civil time.
pub fn event_occurred_before(
  event: Event(body),
  before before: ValidDateTime,
) -> Bool {
  internal_calendar_less_than(event.occurred_at.value, before.value)
}

/// Return whether the event's civil time is within the range, including both endpoints.
pub fn event_occurred_between(
  event: Event(body),
  from from: ValidDateTime,
  until until: ValidDateTime,
) -> Bool {
  internal_calendar_greater_or_equal(event.occurred_at.value, from.value)
  && internal_calendar_less_or_equal(event.occurred_at.value, until.value)
}

// A day and second within a 400-year Gregorian era. Keeping the era separate
// avoids rounding nearby dates at the JavaScript integer boundaries.
type CivilPosition {
  CivilPosition(era: Int, day: Int, second: Int)
}

fn civil_divmod(value: Int, divisor: Int) -> #(Int, Int) {
  let remainder = value % divisor
  let quotient = { value - remainder } / divisor
  case remainder < 0 {
    True -> #(quotient - 1, remainder + divisor)
    False -> #(quotient, remainder)
  }
}

@target(erlang)
fn civil_integer_is_exact(_value: Int) -> Bool {
  True
}

@target(javascript)
fn civil_integer_is_exact(value: Int) -> Bool {
  value >= -9_007_199_254_740_991
  && value <= 9_007_199_254_740_991
  && value % 1 == 0
}

fn civil_position(value: DateTime) -> CivilPosition {
  let #(era, year) = civil_divmod(value.date.year, 400)
  let day =
    civil_days_before_year(year)
    + internal_calendar_days_before_month(
      year,
      calendar.month_to_int(value.date.month),
    )
    + value.date.day
    - 1
  let time = value.time
  CivilPosition(era, day, time.hours * 3600 + time.minutes * 60 + time.seconds)
}

fn civil_days_before_year(year: Int) -> Int {
  365 * year + { year + 3 } / 4 - { year + 99 } / 100 + { year + 399 } / 400
}

fn civil_year_in_era(day: Int, low: Int, high: Int) -> Int {
  case low == high {
    True -> low
    False -> {
      let middle = { low + high + 1 } / 2
      case civil_days_before_year(middle) <= day {
        True -> civil_year_in_era(day, middle, high)
        False -> civil_year_in_era(day, low, middle - 1)
      }
    }
  }
}

fn civil_month_and_day(year: Int, ordinal: Int) -> #(calendar.Month, Int) {
  let leap_day = case internal_gregorian_is_leap_year(year) {
    True -> 1
    False -> 0
  }
  case ordinal {
    day if day < 31 -> #(calendar.January, day + 1)
    day if day < 59 + leap_day -> #(calendar.February, day - 30)
    day if day < 90 + leap_day -> #(calendar.March, day - 58 - leap_day)
    day if day < 120 + leap_day -> #(calendar.April, day - 89 - leap_day)
    day if day < 151 + leap_day -> #(calendar.May, day - 119 - leap_day)
    day if day < 181 + leap_day -> #(calendar.June, day - 150 - leap_day)
    day if day < 212 + leap_day -> #(calendar.July, day - 180 - leap_day)
    day if day < 243 + leap_day -> #(calendar.August, day - 211 - leap_day)
    day if day < 273 + leap_day -> #(calendar.September, day - 242 - leap_day)
    day if day < 304 + leap_day -> #(calendar.October, day - 272 - leap_day)
    day if day < 334 + leap_day -> #(calendar.November, day - 303 - leap_day)
    day -> #(calendar.December, day - 333 - leap_day)
  }
}

@target(erlang)
fn civil_join_year(era: Int, year: Int) -> Result(Int, ScheduleError) {
  Ok(era * 400 + year)
}

@target(javascript)
fn civil_join_year(era: Int, year: Int) -> Result(Int, ScheduleError) {
  let #(minimum_era, minimum_year) = civil_divmod(-9_007_199_254_740_991, 400)
  let #(maximum_era, maximum_year) = civil_divmod(9_007_199_254_740_991, 400)
  case
    era < minimum_era
    || era > maximum_era
    || { era == minimum_era && year < minimum_year }
    || { era == maximum_era && year > maximum_year }
  {
    True -> Error(ScheduleNumericOverflow)
    False ->
      case era < 0 {
        True -> Ok({ era + 1 } * 400 + { year - 400 })
        False -> Ok(era * 400 + year)
      }
  }
}

fn civil_datetime(position: CivilPosition) -> Result(DateTime, ScheduleError) {
  let year_in_era = civil_year_in_era(position.day, 0, 399)
  use year <- result.try(civil_join_year(position.era, year_in_era))
  let day_of_year = position.day - civil_days_before_year(year_in_era)
  let #(month, day) = civil_month_and_day(year_in_era, day_of_year)
  Ok(DateTime(
    calendar.Date(year, month, day),
    civil_time(
      hour: position.second / 3600,
      minute: position.second % 3600 / 60,
      second: position.second % 60,
    ),
  ))
}

fn civil_add_days_to_position(
  position: CivilPosition,
  days: Int,
) -> CivilPosition {
  let #(eras, days) = civil_divmod(days, 146_097)
  let #(carry, day) = civil_divmod(position.day + days, 146_097)
  CivilPosition(position.era + eras + carry, day, position.second)
}

fn civil_add_seconds(
  value: DateTime,
  seconds: Int,
) -> Result(DateTime, ScheduleError) {
  let position = civil_position(value)
  let #(days, seconds) = civil_divmod(seconds, 86_400)
  let #(carry, second) = civil_divmod(position.second + seconds, 86_400)
  civil_datetime(civil_add_days_to_position(
    CivilPosition(..position, second: second),
    days + carry,
  ))
}

// Both operands are normalized before entering the doubling loop, so neither
// addition nor the multiplication's intermediate values exceed the modulus.
fn civil_modular_add(left: Int, right: Int, modulus: Int) -> Int {
  case left >= modulus - right {
    True -> left - { modulus - right }
    False -> left + right
  }
}

fn civil_modular_multiply(left: Int, right: Int, modulus: Int) -> Int {
  civil_modular_multiply_loop(
    civil_divmod(left, modulus).1,
    civil_divmod(right, modulus).1,
    modulus,
    0,
  )
}

fn civil_modular_multiply_loop(
  left: Int,
  right: Int,
  modulus: Int,
  accumulated: Int,
) -> Int {
  case right == 0 {
    True -> accumulated
    False -> {
      let accumulated = case right % 2 == 1 {
        True -> civil_modular_add(accumulated, left, modulus)
        False -> accumulated
      }
      civil_modular_multiply_loop(
        civil_modular_add(left, left, modulus),
        right / 2,
        modulus,
        accumulated,
      )
    }
  }
}

fn civil_seconds_modulo(from: DateTime, to: DateTime, modulus: Int) -> Int {
  let first = civil_position(from)
  let last = civil_position(to)
  let eras =
    civil_modular_multiply(last.era - first.era, 12_622_780_800, modulus)
  let local = { last.day - first.day } * 86_400 + last.second - first.second
  civil_modular_add(eras, civil_divmod(local, modulus).1, modulus)
}

fn every_next(
  plan: EveryPlan,
  boundary: Boundary,
) -> Result(DateTime, ScheduleError) {
  let #(target, exclusive) = case boundary {
    Inclusive(value) -> #(value.value, False)
    Exclusive(value) -> #(value.value, True)
  }
  case internal_calendar_less_than(target, plan.anchor) {
    True -> Ok(plan.anchor)
    False -> {
      let remainder =
        civil_seconds_modulo(plan.anchor, target, plan.interval_seconds)
      let delta = case remainder == 0 && !exclusive {
        True -> 0
        False -> plan.interval_seconds - remainder
      }
      civil_add_seconds(target, delta)
    }
  }
}

type SearchBudget {
  SearchBudget(remaining: Int)
}

type PeriodScan {
  PeriodScan(
    found: Option(CivilPosition),
    whole_empty: Bool,
    budget: SearchBudget,
  )
}

fn search_spend(budget: SearchBudget) -> Result(SearchBudget, ScheduleError) {
  case budget.remaining <= 0 {
    True -> Error(ScheduleSearchLimitReached(1_000_000))
    False -> Ok(SearchBudget(budget.remaining - 1))
  }
}

fn civil_position_compare(left: CivilPosition, right: CivilPosition) -> Order {
  case int.compare(left.era, right.era) {
    Eq ->
      case int.compare(left.day, right.day) {
        Eq -> int.compare(left.second, right.second)
        result -> result
      }
    result -> result
  }
}

fn civil_position_add_seconds(
  position: CivilPosition,
  seconds: Int,
) -> CivilPosition {
  let #(days, seconds) = civil_divmod(seconds, 86_400)
  let #(carry, second) = civil_divmod(position.second + seconds, 86_400)
  civil_add_days_to_position(
    CivilPosition(..position, second: second),
    days + carry,
  )
}

fn civil_cycle_date(position: CivilPosition) -> calendar.Date {
  let year = civil_year_in_era(position.day, 0, 399)
  let #(month, day) =
    civil_month_and_day(year, position.day - civil_days_before_year(year))
  calendar.Date(year, month, day)
}

fn civil_position_month_start(
  era: Int,
  year: Int,
  month: Int,
) -> CivilPosition {
  CivilPosition(
    era,
    civil_days_before_year(year)
      + internal_calendar_days_before_month(year, month),
    0,
  )
}

fn recurrence_period_start(
  plan: RecurrencePlan,
  value: DateTime,
) -> CivilPosition {
  let position = civil_position(value)
  let date = civil_cycle_date(position)
  case plan.frequency {
    Secondly -> position
    // RFC 5545 sub-daily periods are clock minutes and hours. BYSECOND and
    // BYMINUTE values select instants inside them.
    Minutely -> CivilPosition(..position, second: position.second / 60 * 60)
    Hourly -> CivilPosition(..position, second: position.second / 3600 * 3600)
    Daily -> CivilPosition(..position, second: 0)
    Weekly ->
      civil_add_days_to_position(
        CivilPosition(..position, second: 0),
        0 - rrule_evaluator_weekday_offset(calendar.day_of_week(date)),
      )
    Monthly ->
      civil_position_month_start(
        position.era,
        date.year,
        calendar.month_to_int(date.month),
      )
    Yearly -> civil_position_month_start(position.era, date.year, 1)
  }
}

fn civil_shift_period(
  start: CivilPosition,
  frequency: Frequency,
  count: Int,
) -> CivilPosition {
  case frequency {
    Secondly -> civil_position_add_seconds(start, count)
    Minutely -> civil_shift_subdaily(start, count, 60)
    Hourly -> civil_shift_subdaily(start, count, 3600)
    Daily -> civil_add_days_to_position(start, count)
    Weekly -> {
      let #(eras, weeks) = civil_divmod(count, 20_871)
      civil_add_days_to_position(
        CivilPosition(..start, era: start.era + eras),
        weeks * 7,
      )
    }
    Monthly -> {
      let date = civil_cycle_date(start)
      let #(eras, months) = civil_divmod(count, 4800)
      let #(carry, month) =
        civil_divmod(
          date.year * 12 + calendar.month_to_int(date.month) - 1 + months,
          4800,
        )
      civil_position_month_start(
        start.era + eras + carry,
        month / 12,
        month % 12 + 1,
      )
    }
    Yearly -> {
      let year = civil_year_in_era(start.day, 0, 399)
      let #(eras, years) = civil_divmod(count, 400)
      let #(carry, year) = civil_divmod(year + years, 400)
      civil_position_month_start(start.era + eras + carry, year, 1)
    }
  }
}

fn civil_shift_subdaily(
  start: CivilPosition,
  count: Int,
  unit: Int,
) -> CivilPosition {
  let #(days, units) = civil_divmod(count, 86_400 / unit)
  civil_position_add_seconds(
    civil_add_days_to_position(start, days),
    units * unit,
  )
}

fn recurrence_period_remainder(plan: RecurrencePlan, at: DateTime) -> Int {
  let first = civil_position(plan.anchor)
  let last = civil_position(at)
  let #(era_delta, local, base) = case plan.frequency {
    Secondly -> recurrence_subdaily_difference(first, last, 1)
    Minutely -> recurrence_subdaily_difference(first, last, 60)
    Hourly -> recurrence_subdaily_difference(first, last, 3600)
    Daily -> #(last.era - first.era, last.day - first.day, 146_097)
    Weekly -> {
      let first = recurrence_period_start(plan, plan.anchor)
      let last = recurrence_period_start(plan, at)
      #(last.era - first.era, { last.day - first.day } / 7, 20_871)
    }
    Monthly -> {
      let from = civil_cycle_date(first)
      let to = civil_cycle_date(last)
      #(
        last.era - first.era,
        { to.year - from.year }
          * 12
          + calendar.month_to_int(to.month)
          - calendar.month_to_int(from.month),
        4800,
      )
    }
    Yearly -> #(
      last.era - first.era,
      civil_year_in_era(last.day, 0, 399) - civil_year_in_era(first.day, 0, 399),
      400,
    )
  }
  civil_modular_add(
    civil_modular_multiply(era_delta, base, plan.interval),
    civil_divmod(local, plan.interval).1,
    plan.interval,
  )
}

fn recurrence_cycle(plan: RecurrencePlan) -> Int {
  let base = case plan.frequency {
    Secondly -> 12_622_780_800
    Minutely -> 210_379_680
    Hourly -> 3_506_328
    Daily -> 146_097
    Weekly -> 20_871
    Monthly -> 4800
    Yearly -> 400
  }
  base / recurrence_gcd(base, plan.interval % base)
}

fn recurrence_gcd(left: Int, right: Int) -> Int {
  case right {
    0 -> left
    _ -> recurrence_gcd(right, left % right)
  }
}

fn boundary_position(boundary: Boundary) -> #(CivilPosition, Bool) {
  case boundary {
    Inclusive(value) -> #(civil_position(value.value), False)
    Exclusive(value) -> #(civil_position(value.value), True)
  }
}

fn position_satisfies_boundary(
  position: CivilPosition,
  boundary: Boundary,
) -> Bool {
  let #(limit, exclusive) = boundary_position(boundary)
  case civil_position_compare(position, limit) {
    Gt -> True
    Lt -> False
    Eq -> !exclusive
  }
}

fn recurrence_until_position(plan: RecurrencePlan) -> Option(CivilPosition) {
  case plan.end_condition {
    Until(UntilDate(date)) ->
      Some(
        civil_position(DateTime(
          date,
          civil_time(hour: 23, minute: 59, second: 59),
        )),
      )
    Until(UntilDateTime(value)) -> Some(civil_position(value))
    Forever | Count(_) -> None
  }
}

fn recurrence_after_until(
  plan: RecurrencePlan,
  position: CivilPosition,
) -> Bool {
  case recurrence_until_position(plan) {
    None -> False
    Some(limit) -> civil_position_compare(position, limit) == Gt
  }
}

fn recurrence_find(
  plan: RecurrencePlan,
  boundary: Boundary,
  budget: SearchBudget,
) -> Result(#(Option(DateTime), SearchBudget), ScheduleError) {
  let target = case boundary {
    Inclusive(value) | Exclusive(value) -> value.value
  }
  let target = case internal_calendar_less_than(target, plan.anchor) {
    True -> plan.anchor
    False -> target
  }
  case
    !plan.time_reachable || recurrence_after_until(plan, civil_position(target))
  {
    True -> Ok(#(None, budget))
    False -> {
      let start = recurrence_period_start(plan, target)
      let remainder = recurrence_period_remainder(plan, target)
      case remainder == 0 {
        True ->
          recurrence_search_periods(
            plan,
            boundary,
            start,
            0,
            recurrence_cycle(plan),
            budget,
          )
        False -> {
          use budget <- result.try(search_spend(budget))
          let next =
            civil_shift_period(start, plan.frequency, plan.interval - remainder)
          recurrence_search_periods(
            plan,
            boundary,
            next,
            0,
            recurrence_cycle(plan),
            budget,
          )
        }
      }
    }
  }
}

fn recurrence_search_periods(
  plan: RecurrencePlan,
  boundary: Boundary,
  start: CivilPosition,
  empty_periods: Int,
  cycle: Int,
  budget: SearchBudget,
) -> Result(#(Option(DateTime), SearchBudget), ScheduleError) {
  case
    recurrence_inspect_period(
      plan,
      boundary,
      start,
      empty_periods,
      cycle,
      budget,
    )
  {
    Error(error) -> Error(error)
    Ok(SearchFinished(found, budget)) -> Ok(#(found, budget))
    Ok(SearchContinue(next, count, budget)) ->
      recurrence_search_periods(plan, boundary, next, count, cycle, budget)
  }
}

fn recurrence_scan_period(
  plan: RecurrencePlan,
  boundary: Boundary,
  start: CivilPosition,
  end: CivilPosition,
  day: CivilPosition,
  has_candidate: Bool,
  budget: SearchBudget,
) -> Result(PeriodScan, ScheduleError) {
  case
    recurrence_inspect_day(
      plan,
      boundary,
      start,
      end,
      day,
      has_candidate,
      budget,
    )
  {
    Error(error) -> Error(error)
    Ok(ScanFinished(scan)) -> Ok(scan)
    Ok(ScanContinue(next, has_candidate, budget)) ->
      recurrence_scan_period(
        plan,
        boundary,
        start,
        end,
        next,
        has_candidate,
        budget,
      )
  }
}

fn recurrence_first_time(
  hours: List(Int),
  minutes: List(Int),
  seconds: List(Int),
  low: Int,
  high: Int,
) -> Option(Int) {
  case hours {
    [] -> None
    [hour, ..rest] ->
      case hour * 3600 >= high {
        True -> None
        False ->
          case { hour + 1 } * 3600 <= low {
            True -> recurrence_first_time(rest, minutes, seconds, low, high)
            False ->
              case recurrence_first_minute(hour, minutes, seconds, low, high) {
                Some(value) -> Some(value)
                None -> recurrence_first_time(rest, minutes, seconds, low, high)
              }
          }
      }
  }
}

fn recurrence_first_minute(
  hour: Int,
  minutes: List(Int),
  seconds: List(Int),
  low: Int,
  high: Int,
) -> Option(Int) {
  case minutes {
    [] -> None
    [minute, ..rest] -> {
      let base = hour * 3600 + minute * 60
      case base >= high, base + 60 <= low {
        True, _ -> None
        False, True -> recurrence_first_minute(hour, rest, seconds, low, high)
        False, False ->
          case recurrence_first_second(base, seconds, low, high) {
            Some(value) -> Some(value)
            None -> recurrence_first_minute(hour, rest, seconds, low, high)
          }
      }
    }
  }
}

fn recurrence_first_second(
  base: Int,
  seconds: List(Int),
  low: Int,
  high: Int,
) -> Option(Int) {
  case seconds {
    [] -> None
    [second, ..rest] -> {
      let value = base + second
      case value < low {
        True -> recurrence_first_second(base, rest, low, high)
        False ->
          case value < high {
            True -> Some(value)
            False -> None
          }
      }
    }
  }
}

fn recurrence_count_before(
  plan: RecurrencePlan,
  boundary: Boundary,
  cursor: Boundary,
  count: Int,
  limit: Int,
  budget: SearchBudget,
) -> Result(#(Int, SearchBudget), ScheduleError) {
  case count >= limit {
    True -> Ok(#(count, budget))
    False ->
      case recurrence_find(plan, cursor, budget) {
        Error(error) -> Error(error)
        Ok(#(None, budget)) -> Ok(#(count, budget))
        Ok(#(Some(value), budget)) ->
          case position_satisfies_boundary(civil_position(value), boundary) {
            True -> Ok(#(count, budget))
            False ->
              case search_spend(budget) {
                Error(error) -> Error(error)
                Ok(budget) ->
                  recurrence_count_before(
                    plan,
                    boundary,
                    Exclusive(ValidDateTime(value)),
                    count + 1,
                    limit,
                    budget,
                  )
              }
          }
      }
  }
}

fn schedule_prepare(
  schedule: Schedule,
  boundary: Boundary,
  budget: SearchBudget,
) -> Result(#(OccurrenceIterator, SearchBudget), ScheduleError) {
  case schedule {
    PlanCron(plan) -> Ok(#(CronOccurrences(plan, boundary), budget))
    PlanEvery(plan) -> Ok(#(EveryOccurrences(plan, boundary), budget))
    PlanOnce(at) ->
      Ok(#(OnceOccurrences(at, schedule_once_eligible(at, boundary)), budget))
    PlanRecurrence(plan) -> {
      use #(count, budget) <- result.try(recurrence_initial_count(
        plan,
        boundary,
        budget,
      ))
      Ok(#(RRuleOccurrences(plan, boundary, count), budget))
    }
  }
}

fn schedule_step_with_budget(
  iterator: OccurrenceIterator,
  budget: SearchBudget,
) -> Result(#(IterStep, SearchBudget), ScheduleError) {
  case iterator {
    EveryOccurrences(plan, boundary) -> {
      use next <- result.try(every_next(plan, boundary))
      let at = ValidDateTime(next)
      Ok(#(Yield(at, EveryOccurrences(plan, Exclusive(at))), budget))
    }
    OnceOccurrences(at, True) ->
      Ok(#(Yield(ValidDateTime(at), OnceOccurrences(at, False)), budget))
    OnceOccurrences(_, False) -> Ok(#(Done, budget))
    CronOccurrences(plan, boundary) -> {
      use #(found, budget) <- result.try(cron_search(plan, boundary, budget))
      Ok(#(
        case found {
          None -> Done
          Some(value) -> {
            let at = ValidDateTime(value)
            Yield(at, CronOccurrences(plan, Exclusive(at)))
          }
        },
        budget,
      ))
    }
    RRuleOccurrences(plan, boundary, count) -> {
      recurrence_step(plan, boundary, count, budget)
    }
  }
}

fn cron_search(
  plan: CronPlan,
  boundary: Boundary,
  budget: SearchBudget,
) -> Result(#(Option(DateTime), SearchBudget), ScheduleError) {
  let #(start, _) = boundary_position(boundary)
  cron_search_days(plan, boundary, CivilPosition(..start, second: 0), 0, budget)
}

fn cron_search_days(
  plan: CronPlan,
  boundary: Boundary,
  day: CivilPosition,
  empty_days: Int,
  budget: SearchBudget,
) -> Result(#(Option(DateTime), SearchBudget), ScheduleError) {
  case cron_inspect_day(plan, boundary, day, empty_days, budget) {
    Error(error) -> Error(error)
    Ok(SearchFinished(found, budget)) -> Ok(#(found, budget))
    Ok(SearchContinue(next, count, budget)) ->
      cron_search_days(plan, boundary, next, count, budget)
  }
}

fn cron_values(values: CronSelection) -> List(Int) {
  case values {
    SelectedCronValues(values) -> values
    AnyCronValue(min, max) -> cron_validator_inclusive_range(min, max)
  }
}

fn cron_day_matches(plan: CronPlan, candidate: DateTime) -> Bool {
  cron_evaluator_matches_day(
    plan,
    cron_evaluator_int_set_contains(plan.day_of_month, candidate.date.day),
    cron_evaluator_int_set_contains(
      plan.day_of_week,
      internal_calendar_day_of_week_number(candidate),
    ),
  )
}

type SearchProgress {
  SearchFinished(Option(DateTime), SearchBudget)
  SearchContinue(CivilPosition, Int, SearchBudget)
}

type ScanProgress {
  ScanFinished(PeriodScan)
  ScanContinue(CivilPosition, Bool, SearchBudget)
}

fn recurrence_inspect_period(
  plan: RecurrencePlan,
  boundary: Boundary,
  start: CivilPosition,
  empty_periods: Int,
  cycle: Int,
  budget: SearchBudget,
) -> Result(SearchProgress, ScheduleError) {
  case empty_periods >= cycle || recurrence_after_until(plan, start) {
    True -> Ok(SearchFinished(None, budget))
    False -> {
      recurrence_scan_active_period(
        plan,
        boundary,
        start,
        empty_periods,
        cycle,
        budget,
      )
    }
  }
}

fn cron_inspect_day(
  plan: CronPlan,
  boundary: Boundary,
  day: CivilPosition,
  empty_days: Int,
  budget: SearchBudget,
) -> Result(SearchProgress, ScheduleError) {
  case empty_days >= 146_097 {
    True -> Ok(SearchFinished(None, budget))
    False -> {
      cron_search_active_day(plan, boundary, day, empty_days, budget)
    }
  }
}

fn recurrence_inspect_day(
  plan: RecurrencePlan,
  boundary: Boundary,
  start: CivilPosition,
  end: CivilPosition,
  day: CivilPosition,
  has_candidate: Bool,
  budget: SearchBudget,
) -> Result(ScanProgress, ScheduleError) {
  case civil_position_compare(day, end) != Lt {
    True -> Ok(ScanFinished(PeriodScan(None, !has_candidate, budget)))
    False -> {
      recurrence_scan_active_day(
        plan,
        boundary,
        start,
        end,
        day,
        has_candidate,
        budget,
      )
    }
  }
}

fn rrule_validate_integer(
  part: RulePart,
  value: Int,
) -> Result(Nil, RruleValidationError) {
  case civil_integer_is_exact(value) {
    True -> Ok(Nil)
    False -> Error(RruleIntegerOutOfRange(part, value))
  }
}

fn retry_admit_duration(value: duration.Duration) -> Result(Nil, RetryError) {
  let #(seconds, nanoseconds) = duration.to_seconds_and_nanoseconds(value)
  case seconds < 0 {
    True -> Error(NegativeDuration(seconds, nanoseconds))
    False ->
      case nanoseconds % 1_000_000 != 0 {
        True -> Error(FractionalMilliseconds(seconds, nanoseconds))
        False ->
          case
            seconds > 9_007_199_254_740
            || seconds == 9_007_199_254_740
            && nanoseconds > 991_000_000
          {
            True -> Error(DurationOverflow(seconds, nanoseconds))
            False -> Ok(Nil)
          }
      }
  }
}

type IcalEmission {
  IcalLine(String)
  IcalPropertyLine(String, List(IcalParameter), String)
  IcalDateLine(PropertyForm, String, List(DateTime), Option(String))
}

fn ical_emit_line(emission: IcalEmission) -> Result(String, IcalEncodeError) {
  use line <- result.try(case emission {
    IcalLine(line) -> Ok(line)
    IcalPropertyLine(name, params, value) -> {
      use Nil <- result.try(ical_admit_parameters(name, params))
      Ok(name <> ical_emitter_render_parameters(params) <> ":" <> value)
    }
    IcalDateLine(form, name, values, tzid) -> {
      use Nil <- result.try(list.try_each(values, ical_admit_date(name, _)))
      let params = ical_emitter_dt_parameters(form, tzid)
      use Nil <- result.try(ical_admit_parameters(name, params))
      Ok(ical_emitter_format_dt_values(form, name, values, params))
    }
  })
  case string.contains(line, "\r") || string.contains(line, "\n") {
    True -> Error(IcalPhysicalNewline(line))
    False -> Ok(line)
  }
}

// A parameter value has no escape mechanism for DQUOTE, so such a value
// cannot be written in a form that parses again.
fn ical_admit_parameters(
  property: String,
  params: List(IcalParameter),
) -> Result(Nil, IcalEncodeError) {
  list.try_each(params, fn(param) {
    case string.contains(param.value, "\"") {
      True ->
        Error(IcalInvalidParameterValue(property, param.name, param.value))
      False -> Ok(Nil)
    }
  })
}

fn ical_admit_date(
  name: String,
  value: DateTime,
) -> Result(Nil, IcalEncodeError) {
  use _ <- result.try(
    datetime_validate(value)
    |> result.map_error(fn(error) { IcalInvalidDateValue(name, value, error) }),
  )
  case value.date.year < -999 || value.date.year > 9999 {
    True -> Error(IcalYearNotRepresentable(name, value.date.year))
    False -> Ok(Nil)
  }
}

fn ical_emitter_render_dt_values(
  form: PropertyForm,
  name: String,
  values: List(DateTime),
  tzid: Option(String),
) -> IcalEmission {
  IcalDateLine(form, name, values, tzid)
}

fn ical_wire_year(year: Int) -> String {
  case year < 0 {
    True -> "-" <> string.pad_start(int.to_string(0 - year), 3, "0")
    False -> internal_digits_pad4(year)
  }
}

fn ical_repeated_values(
  props: List(IcalRawProperty),
  name: String,
) -> List(#(String, PropertyForm)) {
  list.fold(props, [], fn(values, property) {
    case property.name == name {
      False -> values
      True -> [
        #(
          property.raw_value,
          PropertyForm(
            ..ical_validator_utc_form,
            parameters: property.parameters,
          ),
        ),
        ..values
      ]
    }
  })
}

fn ical_repeated_parsed(
  props: List(IcalRawProperty),
  name: String,
  parse: fn(String) -> Result(List(a), IcalError),
  values: List(#(a, PropertyForm)),
) -> Result(List(#(a, PropertyForm)), IcalError) {
  case props {
    [] -> Ok(values)
    [property, ..rest] if property.name != name ->
      ical_repeated_parsed(rest, name, parse, values)
    [property, ..rest] ->
      case ical_parse_repeated_property(property, parse) {
        Error(error) -> Error(error)
        Ok(pairs) -> {
          let values =
            list.fold(pairs, values, fn(values, pair) { [pair, ..values] })
          ical_repeated_parsed(rest, name, parse, values)
        }
      }
  }
}

fn ical_repeated_in_order(values: List(#(a, PropertyForm))) -> List(a) {
  values |> list.reverse |> list.map(fn(pair) { pair.0 })
}

fn ical_timezone_rule_form(
  property: IcalRawComponent,
) -> Dict(String, PropertyForm) {
  let forms = ical_validator_forms_of(property.properties)
  case ical_validator_find_prop(property.properties, "DTSTART") {
    Some(start) ->
      dict.insert(
        forms,
        "DTSTART",
        ical_validator_value_form("DTSTART", start.parameters, start.raw_value),
      )
    None -> forms
  }
}

fn cron_parse_step_range(
  field: CronField,
  base: String,
  min: Int,
  max: Int,
  aliases: CronAliases,
) -> Result(CronStepBase, CronValidationError) {
  case string.split(base, "-") {
    [start_text, end_text] if start_text != "" && end_text != "" -> {
      use start <- result.try(cron_validator_parse_value(
        field,
        start_text,
        min,
        max,
        aliases,
      ))
      use end <- result.try(cron_validator_parse_value(
        field,
        end_text,
        min,
        max,
        aliases,
      ))
      case start <= end {
        True -> Ok(CronStepRange(start, end))
        False -> Error(CronInvalidRange(field, base))
      }
    }
    _ -> Error(CronInvalidRange(field, base))
  }
}

fn rrule_weekday_ordinal(
  prefix: String,
  weekday: calendar.DayOfWeek,
) -> Result(WeekdaySpecifier, Nil) {
  case prefix {
    "" -> Ok(EveryWeekday(weekday))
    _ -> {
      use ordinal <- result.try(int.parse(prefix))
      case ordinal == 0 {
        True -> Error(Nil)
        False -> Ok(NthWeekday(ordinal, weekday))
      }
    }
  }
}

fn ical_parse_calendar_body(
  first: IcalRawProperty,
  rest: List(IcalRawProperty),
) -> Result(IcalRawCalendar, IcalError) {
  case
    first.name == "BEGIN" && string.uppercase(first.raw_value) == "VCALENDAR"
  {
    False -> Error(IcalUnexpectedEnd(first.line))
    True -> {
      use #(calendar, leftover) <- result.try(
        ical_parser_consume_component("VCALENDAR", first.line, rest, [], []),
      )
      case leftover {
        [] -> Ok(IcalRawCalendar(calendar.properties, calendar.children))
        [property, ..] -> Error(IcalUnexpectedEnd(property.line))
      }
    }
  }
}

fn recurrence_matches(
  plan: RecurrencePlan,
  at: ValidDateTime,
) -> Result(Bool, ScheduleError) {
  let raw = at.value

  case
    internal_calendar_less_than(raw, plan.anchor)
    || !rrule_evaluator_within_until(plan.end_condition, raw)
    || !rrule_evaluator_base_match(plan, raw)
  {
    True -> Ok(False)
    False ->
      case plan.end_condition {
        Forever | Until(_) -> Ok(True)
        Count(limit) -> {
          use #(count, _) <- result.try(recurrence_count_from_anchor(
            plan,
            Inclusive(at),
            limit,
            SearchBudget(1_000_000),
          ))
          Ok(count < limit)
        }
      }
  }
}

fn recurrence_initial_count(
  plan: RecurrencePlan,
  boundary: Boundary,
  budget: SearchBudget,
) -> Result(#(Int, SearchBudget), ScheduleError) {
  case plan.end_condition {
    Count(limit) -> {
      let #(target, exclusive) = boundary_position(boundary)
      case civil_position_compare(target, civil_position(plan.anchor)) {
        Lt -> Ok(#(0, budget))
        Eq if !exclusive -> Ok(#(0, budget))
        Eq | Gt -> recurrence_count_from_anchor(plan, boundary, limit, budget)
      }
    }
    Forever | Until(_) -> Ok(#(0, budget))
  }
}

fn recurrence_step(
  plan: RecurrencePlan,
  boundary: Boundary,
  count: Int,
  budget: SearchBudget,
) -> Result(#(IterStep, SearchBudget), ScheduleError) {
  let exhausted = case plan.end_condition {
    Count(limit) -> count >= limit
    Forever | Until(_) -> False
  }
  case exhausted {
    True -> Ok(#(Done, budget))
    False -> {
      use #(found, budget) <- result.try(recurrence_find(plan, boundary, budget))
      Ok(#(recurrence_yield(plan, count, found), budget))
    }
  }
}

fn recurrence_scan_active_period(
  plan: RecurrencePlan,
  boundary: Boundary,
  start: CivilPosition,
  empty_periods: Int,
  cycle: Int,
  budget: SearchBudget,
) -> Result(SearchProgress, ScheduleError) {
  // A virtual period may start just before the minimum representable year.
  // Only its candidates need materializing; future periods above the maximum
  // have no representable candidate, and must report an explicit failure.
  let #(target, _) = boundary_position(boundary)
  use _ <- result.try(case civil_position_compare(start, target) == Gt {
    True -> civil_datetime(start) |> result.map(fn(_) { Nil })
    False -> Ok(Nil)
  })
  let end = civil_shift_period(start, plan.frequency, 1)
  let #(end, ends_at_until) = case recurrence_until_position(plan) {
    None -> #(end, False)
    Some(limit) -> {
      let after_limit = civil_position_add_seconds(limit, 1)
      case civil_position_compare(after_limit, end) != Gt {
        True -> #(after_limit, True)
        False -> #(end, False)
      }
    }
  }
  use scan <- result.try(recurrence_scan_period(
    plan,
    boundary,
    start,
    end,
    CivilPosition(..start, second: 0),
    False,
    budget,
  ))
  recurrence_after_scan(plan, start, empty_periods, cycle, ends_at_until, scan)
}

fn recurrence_after_scan(
  plan: RecurrencePlan,
  start: CivilPosition,
  empty_periods: Int,
  cycle: Int,
  ends_at_until: Bool,
  scan: PeriodScan,
) -> Result(SearchProgress, ScheduleError) {
  case scan.found {
    Some(found) -> {
      use value <- result.try(civil_datetime(found))
      Ok(SearchFinished(Some(value), scan.budget))
    }
    None -> {
      let empty_periods = case scan.whole_empty {
        True -> empty_periods + 1
        False -> 0
      }
      case ends_at_until || empty_periods >= cycle {
        True -> Ok(SearchFinished(None, scan.budget))
        False -> {
          use budget <- result.try(search_spend(scan.budget))
          let #(next, periods) = recurrence_next_period(plan, start)
          Ok(SearchContinue(next, empty_periods + periods - 1, budget))
        }
      }
    }
  }
}

fn cron_search_active_day(
  plan: CronPlan,
  boundary: Boundary,
  day: CivilPosition,
  empty_days: Int,
  budget: SearchBudget,
) -> Result(SearchProgress, ScheduleError) {
  use date <- result.try(civil_datetime(day))
  use budget <- result.try(search_spend(budget))
  let matches =
    cron_evaluator_int_set_contains(
      plan.month,
      calendar.month_to_int(date.date.month),
    )
    && cron_day_matches(plan, date)
  case matches {
    True -> {
      cron_search_time(plan, boundary, day, budget)
    }
    False -> {
      use budget <- result.try(search_spend(budget))
      let next = case
        cron_evaluator_int_set_contains(
          plan.month,
          calendar.month_to_int(date.date.month),
        )
      {
        True -> civil_add_days_to_position(day, 1)
        False ->
          civil_shift_period(
            civil_position_month_start(
              day.era,
              civil_year_in_era(day.day, 0, 399),
              calendar.month_to_int(date.date.month),
            ),
            Monthly,
            1,
          )
      }
      let skipped = { next.era - day.era } * 146_097 + next.day - day.day
      Ok(SearchContinue(next, empty_days + skipped, budget))
    }
  }
}

fn cron_search_time(
  plan: CronPlan,
  boundary: Boundary,
  day: CivilPosition,
  budget: SearchBudget,
) -> Result(SearchProgress, ScheduleError) {
  let #(target, exclusive) = boundary_position(boundary)
  let low = case day.era == target.era && day.day == target.day {
    True ->
      target.second
      + case exclusive {
        True -> 1
        False -> 0
      }
    False -> 0
  }
  case
    recurrence_first_time(
      cron_values(plan.hour),
      cron_values(plan.minute),
      [0],
      low,
      86_400,
    )
  {
    Some(second) -> {
      use budget <- result.try(search_spend(budget))
      use value <- result.try(civil_datetime(
        CivilPosition(..day, second: second),
      ))
      Ok(SearchFinished(Some(value), budget))
    }
    None -> {
      use budget <- result.try(search_spend(budget))
      Ok(SearchContinue(civil_add_days_to_position(day, 1), 0, budget))
    }
  }
}

fn recurrence_scan_active_day(
  plan: RecurrencePlan,
  boundary: Boundary,
  start: CivilPosition,
  end: CivilPosition,
  day: CivilPosition,
  has_candidate: Bool,
  budget: SearchBudget,
) -> Result(ScanProgress, ScheduleError) {
  use budget <- result.try(search_spend(budget))
  let date = civil_cycle_date(day)
  case rrule_evaluator_day_matches(plan, date) {
    False ->
      Ok(ScanContinue(civil_add_days_to_position(day, 1), has_candidate, budget))
    True -> {
      recurrence_scan_times(
        plan,
        boundary,
        start,
        end,
        day,
        has_candidate,
        budget,
      )
    }
  }
}

fn recurrence_scan_times(
  plan: RecurrencePlan,
  boundary: Boundary,
  start: CivilPosition,
  end: CivilPosition,
  day: CivilPosition,
  has_candidate: Bool,
  budget: SearchBudget,
) -> Result(ScanProgress, ScheduleError) {
  let low = case day.era == start.era && day.day == start.day {
    True -> start.second
    False -> 0
  }
  let high = case day.era == end.era && day.day == end.day {
    True -> end.second
    False -> 86_400
  }
  case
    recurrence_first_time(plan.by_hour, plan.by_minute, plan.seconds, low, high)
  {
    None ->
      Ok(ScanContinue(civil_add_days_to_position(day, 1), has_candidate, budget))
    Some(first) -> {
      recurrence_compare_time(plan, boundary, day, low, high, first, budget)
    }
  }
}

fn recurrence_compare_time(
  plan: RecurrencePlan,
  boundary: Boundary,
  day: CivilPosition,
  low: Int,
  high: Int,
  first: Int,
  budget: SearchBudget,
) -> Result(ScanProgress, ScheduleError) {
  use budget <- result.try(search_spend(budget))
  let first = CivilPosition(..day, second: first)
  let anchor = civil_position(plan.anchor)
  let #(target, exclusive) = boundary_position(boundary)
  let target = case civil_position_compare(target, anchor) {
    Lt -> anchor
    Eq | Gt ->
      civil_position_add_seconds(target, case exclusive {
        True -> 1
        False -> 0
      })
  }
  case civil_position_compare(first, target) != Lt {
    True -> Ok(ScanFinished(PeriodScan(Some(first), False, budget)))
    False -> {
      let next_day = civil_add_days_to_position(day, 1)
      let eligible = case civil_position_compare(target, next_day) != Lt {
        True -> None
        False ->
          recurrence_first_time(
            plan.by_hour,
            plan.by_minute,
            plan.seconds,
            int.max(low, target.second),
            high,
          )
      }
      case eligible {
        Some(second) -> {
          use budget <- result.try(search_spend(budget))
          Ok(
            ScanFinished(PeriodScan(
              Some(CivilPosition(..day, second: second)),
              False,
              budget,
            )),
          )
        }
        None -> Ok(ScanContinue(next_day, True, budget))
      }
    }
  }
}

fn ical_parse_repeated_property(
  property: IcalRawProperty,
  parse: fn(String) -> Result(List(a), IcalError),
) -> Result(List(#(a, PropertyForm)), IcalError) {
  use parsed <- result.try(parse(property.raw_value))
  let forms = case property.name {
    "RDATE" | "EXDATE" ->
      string.split(property.raw_value, ",")
      |> list.map(ical_validator_value_form(
        property.name,
        property.parameters,
        _,
      ))
    _ ->
      list.map(parsed, fn(_) {
        PropertyForm(..ical_validator_utc_form, parameters: property.parameters)
      })
  }
  Ok(list.zip(parsed, forms))
}

fn recurrence_yield(
  plan: RecurrencePlan,
  count: Int,
  found: Option(DateTime),
) -> IterStep {
  case found {
    None -> Done
    Some(value) -> {
      let at = ValidDateTime(value)
      let count = case plan.end_condition {
        Count(_) -> count + 1
        Forever | Until(_) -> 0
      }
      Yield(at, RRuleOccurrences(plan, Exclusive(at), count))
    }
  }
}

fn recurrence_subdaily_difference(
  first: CivilPosition,
  last: CivilPosition,
  unit: Int,
) -> #(Int, Int, Int) {
  let local =
    { last.day - first.day }
    * { 86_400 / unit }
    + last.second
    / unit
    - first.second
    / unit
  #(last.era - first.era, local, 12_622_780_800 / unit)
}

fn recurrence_subdaily_unit(frequency: Frequency) -> Option(Int) {
  case frequency {
    Secondly -> Some(1)
    Minutely -> Some(60)
    Hourly -> Some(3600)
    Daily | Weekly | Monthly | Yearly -> None
  }
}

// Return the next period to inspect and how many interval steps it skips.
// Sub-daily rules jump over periods that contain no instant allowed by the
// day, hour, minute, and second filters.
fn recurrence_next_period(
  plan: RecurrencePlan,
  start: CivilPosition,
) -> #(CivilPosition, Int) {
  let periods = case recurrence_subdaily_unit(plan.frequency) {
    Some(unit) if plan.interval <= 2 * 86_400 / unit -> {
      // The next candidate is at least one period away, so the gap is
      // never shorter than the unit.
      let bound =
        recurrence_candidate_bound(
          plan,
          civil_position_add_seconds(start, unit),
        )
      let gap =
        { bound.era - start.era }
        * 12_622_780_800
        + { bound.day - start.day }
        * 86_400
        + bound.second
        - start.second
      { gap - unit } / { plan.interval * unit } + 1
    }
    _ -> 1
  }
  #(civil_shift_period(start, plan.frequency, periods * plan.interval), periods)
}

// The first instant at or after `from` allowed by the filters on the same
// day, or the start of the next day.
fn recurrence_candidate_bound(
  plan: RecurrencePlan,
  from: CivilPosition,
) -> CivilPosition {
  let next_day = CivilPosition(..civil_add_days_to_position(from, 1), second: 0)
  case rrule_evaluator_day_matches(plan, civil_cycle_date(from)) {
    False -> next_day
    True ->
      case
        recurrence_first_time(
          plan.by_hour,
          plan.by_minute,
          plan.seconds,
          from.second,
          86_400,
        )
      {
        Some(second) -> CivilPosition(..from, second: second)
        None -> next_day
      }
  }
}

// Sub-daily periods start at a fixed set of times of day. A rule whose
// filters select no instant in any of those periods has no occurrences.
fn recurrence_time_reachable(
  frequency: Frequency,
  interval: Int,
  anchor: DateTime,
  by_hour: List(Int),
  by_minute: List(Int),
  seconds: List(Int),
) -> Bool {
  case recurrence_subdaily_unit(frequency) {
    None -> True
    Some(unit) -> {
      let phase = recurrence_gcd(86_400, interval % { 86_400 / unit } * unit)
      let anchor_second =
        anchor.time.hours
        * 3600
        + anchor.time.minutes
        * 60
        + anchor.time.seconds
      let first = anchor_second / unit * unit
      let in_phase = fn(at) {
        civil_divmod(at / unit * unit - first, phase).1 == 0
      }
      list.any(by_hour, fn(hour) {
        list.any(by_minute, recurrence_minute_in_phase(
          hour,
          _,
          seconds,
          in_phase,
        ))
      })
    }
  }
}

fn recurrence_minute_in_phase(
  hour: Int,
  minute: Int,
  seconds: List(Int),
  in_phase: fn(Int) -> Bool,
) -> Bool {
  list.any(seconds, fn(second) { in_phase(hour * 3600 + minute * 60 + second) })
}
