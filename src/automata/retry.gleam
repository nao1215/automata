import automata/retry/internal/prng.{type PrngState}
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/result

/// JavaScript's `Number.MAX_SAFE_INTEGER`. We cap durations at this
/// value so the same arithmetic produces the same result on both the
/// BEAM and the JavaScript target.
@internal
pub const max_safe_milliseconds: Int = 9_007_199_254_740_991

/// Position of a single try inside a retry sequence.
///
/// Counts start at `1`: the very first invocation is attempt `1`, the
/// first retry is attempt `2`, and so on. `max_attempts` therefore
/// means "the total number of tries we are willing to perform" — a
/// `max_attempts: 5` policy gives up after the fifth failed attempt.
pub type Attempt =
  Int

/// Classification a caller assigns to a failed try.
///
/// `automata/retry` does not interpret error values. The caller decides
/// whether a particular failure is worth re-trying (`Transient`) or
/// hopeless (`Permanent`), and the retry module honours that decision.
pub type FailureKind {
  Transient
  Permanent
}

/// Reason a retry sequence stops.
///
/// Each variant carries enough structured context that an LLM or a
/// human operator can understand the decision without parsing prose.
pub type GiveUpReason {
  /// The policy is `no_retry`; failure ends the sequence immediately.
  PolicyDisallowsRetry
  /// We have exhausted the policy's `max_attempts` budget.
  MaxAttemptsReached(attempts: Int, limit: Int)
  /// The caller signalled `Permanent` failure.
  PermanentFailureSignaled(at_attempt: Int)
  /// The next delay would exceed `max_safe_milliseconds` and was
  /// refused before any precision was lost.
  DelayOverflow(at_attempt: Int)
}

/// Construction-time errors for `Duration` and `Policy`.
pub type RetryError {
  NegativeDuration(unit: String, actual: Int)
  DurationOverflow(unit: String, actual: Int)
  MaxAttemptsMustBePositive(actual: Int)
  MultiplierMustBeAtLeastTwo(actual: Int)
  InitialDelayMustBePositive(actual_milliseconds: Int)
  CapMustNotBeLessThanInitial(cap_milliseconds: Int, initial_milliseconds: Int)
}

/// A non-negative span of time, opaque so it can only be built through
/// the validating `from_*` smart constructors.
///
/// Values are stored as integer milliseconds and are guaranteed to lie
/// in `[0, max_safe_milliseconds]`.
pub opaque type Duration {
  Duration(milliseconds: Int)
}

/// Strategy used to spread the base delay computed by a policy.
///
/// Kept as a regular sum (not opaque) so that `decide` can dispatch on
/// it. New strategies (for example a bounded-percentage jitter) would
/// be additive and require existing pattern matches to be exhaustive
/// again.
pub type Jitter {
  /// Use the policy's base delay as-is.
  NoJitter
  /// Spread uniformly across `[0, base]` (AWS "full jitter").
  FullJitter
  /// Spread uniformly across `[base / 2, base]` (AWS "equal jitter").
  EqualJitter
}

/// Build a duration from milliseconds.
pub fn from_milliseconds(
  milliseconds milliseconds: Int,
) -> Result(Duration, RetryError) {
  guard_duration("milliseconds", milliseconds, milliseconds)
}

/// Build a duration from seconds.
pub fn from_seconds(seconds seconds: Int) -> Result(Duration, RetryError) {
  case validate_unit("seconds", seconds, max_safe_milliseconds / 1000) {
    Error(error) -> Error(error)
    Ok(_) -> Ok(Duration(milliseconds: seconds * 1000))
  }
}

/// Build a duration from minutes.
pub fn from_minutes(minutes minutes: Int) -> Result(Duration, RetryError) {
  case validate_unit("minutes", minutes, max_safe_milliseconds / 60_000) {
    Error(error) -> Error(error)
    Ok(_) -> Ok(Duration(milliseconds: minutes * 60_000))
  }
}

/// Recover the raw millisecond value from a duration.
pub fn duration_milliseconds(duration duration: Duration) -> Int {
  duration.milliseconds
}

/// Recover the duration in whole seconds, truncating any sub-second
/// remainder.
pub fn duration_seconds(duration duration: Duration) -> Int {
  duration.milliseconds / 1000
}

/// Render a duration as `"<n>ms"`.
pub fn duration_to_string(duration duration: Duration) -> String {
  int.to_string(duration.milliseconds) <> "ms"
}

/// Internal back door used by the policy machinery below to wrap
/// freshly computed integer milliseconds without re-running the public
/// validation. Internal arithmetic already guarantees the value is
/// non-negative and within `max_safe_milliseconds`.
@internal
pub fn unsafe_milliseconds(value value: Int) -> Duration {
  Duration(milliseconds: value)
}

fn guard_duration(
  unit: String,
  raw: Int,
  millis: Int,
) -> Result(Duration, RetryError) {
  case raw < 0 {
    True -> Error(NegativeDuration(unit: unit, actual: raw))
    False ->
      case millis > max_safe_milliseconds {
        True -> Error(DurationOverflow(unit: unit, actual: raw))
        False -> Ok(Duration(milliseconds: millis))
      }
  }
}

fn validate_unit(
  unit: String,
  value: Int,
  upper_bound: Int,
) -> Result(Nil, RetryError) {
  case value < 0 {
    True -> Error(NegativeDuration(unit: unit, actual: value))
    False ->
      case value > upper_bound {
        True -> Error(DurationOverflow(unit: unit, actual: value))
        False -> Ok(Nil)
      }
  }
}

/// A retry policy: pure data describing *how* to retry a failed
/// operation without itself performing any I/O.
///
/// `opaque` so the only way to construct a value is through the
/// validating smart constructors (`no_retry`, `fixed`, `exponential`,
/// `capped_exponential`). This rules out impossible combinations such
/// as `max_attempts <= 0` or a cap below the initial delay, and lets
/// us add new variants (decorrelated jitter, custom backoff, ...)
/// without breaking pattern matches in downstream code.
pub opaque type Policy {
  NoRetry
  Fixed(delay: Duration, max_attempts: Int, jitter: Jitter)
  Exponential(
    initial: Duration,
    multiplier: Int,
    max_attempts: Int,
    jitter: Jitter,
  )
  CappedExponential(
    initial: Duration,
    multiplier: Int,
    cap: Duration,
    max_attempts: Int,
    jitter: Jitter,
  )
}

/// Stateful retry context.
///
/// Bundles the immutable `Policy`, the number of attempts already
/// completed, the cumulative delay charged to the caller so far, and
/// the deterministic PRNG state used by jittered policies. `opaque`
/// because callers must not forge an `attempt` counter or rewind the
/// PRNG mid-sequence.
pub opaque type Context {
  Context(
    policy: Policy,
    attempt: Int,
    cumulative_delay: Duration,
    prng: PrngState,
  )
}

/// Result of asking a `Context` what to do after a failure.
///
/// `Retry` carries the delay the caller should wait *before* the next
/// attempt and the `Context` to use when calling `decide` again.
/// `GiveUp` carries the structured reason the sequence ended.
pub type Decision {
  Retry(delay: Duration, next: Context)
  GiveUp(reason: GiveUpReason)
}

/// Build a policy that never retries. Any failure (transient or
/// permanent) ends the sequence on the first call to `decide`.
pub fn no_retry() -> Policy {
  NoRetry
}

/// Build a fixed-delay policy: every retry waits exactly `delay`,
/// up to `max_attempts` total tries.
pub fn fixed(
  delay delay: Duration,
  max_attempts max_attempts: Int,
) -> Result(Policy, RetryError) {
  case max_attempts <= 0 {
    True -> Error(MaxAttemptsMustBePositive(actual: max_attempts))
    False ->
      Ok(Fixed(delay: delay, max_attempts: max_attempts, jitter: NoJitter))
  }
}

/// Build an unbounded exponential backoff: the next delay is
/// `initial * multiplier ^ (attempt - 1)`, where `attempt` is the
/// upcoming try number (1-based).
pub fn exponential(
  initial initial: Duration,
  multiplier multiplier: Int,
  max_attempts max_attempts: Int,
) -> Result(Policy, RetryError) {
  case validate_exponential_params(initial, multiplier, max_attempts) {
    Error(error) -> Error(error)
    Ok(_) ->
      Ok(Exponential(
        initial: initial,
        multiplier: multiplier,
        max_attempts: max_attempts,
        jitter: NoJitter,
      ))
  }
}

/// Build an exponential backoff that saturates at `cap`. Equivalent
/// to `exponential` with an extra ceiling applied to every computed
/// delay.
pub fn capped_exponential(
  initial initial: Duration,
  multiplier multiplier: Int,
  cap cap: Duration,
  max_attempts max_attempts: Int,
) -> Result(Policy, RetryError) {
  case validate_exponential_params(initial, multiplier, max_attempts) {
    Error(error) -> Error(error)
    Ok(_) ->
      case
        duration_milliseconds(duration: cap)
        < duration_milliseconds(duration: initial)
      {
        True ->
          Error(CapMustNotBeLessThanInitial(
            cap_milliseconds: duration_milliseconds(duration: cap),
            initial_milliseconds: duration_milliseconds(duration: initial),
          ))
        False ->
          Ok(CappedExponential(
            initial: initial,
            multiplier: multiplier,
            cap: cap,
            max_attempts: max_attempts,
            jitter: NoJitter,
          ))
      }
  }
}

/// Build a capped exponential policy directly from raw millisecond
/// integers, skipping the explicit `from_milliseconds` calls that
/// `capped_exponential/4` would otherwise require. Useful when both
/// the initial delay and the cap are compile-time literals — the
/// common case at a call site.
///
/// Validation runs in the same order as `capped_exponential/4`: the
/// `initial_ms` duration is constructed first, then `cap_ms`, then the
/// underlying `capped_exponential` validates `multiplier`, `max_attempts`,
/// and the `cap >= initial` invariant. A bad value at any step short-
/// circuits with the corresponding `RetryError`.
///
/// Callers that already hold runtime-derived `Duration` values (for
/// example, from a config parser that ran `from_minutes`) should
/// keep using `capped_exponential/4` and pass the values through
/// unchanged.
pub fn capped_exponential_ms(
  initial_ms initial_ms: Int,
  multiplier multiplier: Int,
  cap_ms cap_ms: Int,
  max_attempts max_attempts: Int,
) -> Result(Policy, RetryError) {
  use initial <- result.try(from_milliseconds(milliseconds: initial_ms))
  use cap <- result.try(from_milliseconds(milliseconds: cap_ms))
  capped_exponential(
    initial: initial,
    multiplier: multiplier,
    cap: cap,
    max_attempts: max_attempts,
  )
}

/// Decorate an existing policy with a jitter strategy.
///
/// `no_retry` is unaffected (jitter has nothing to spread).
pub fn with_jitter(policy policy: Policy, jitter jitter: Jitter) -> Policy {
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

/// Begin a new retry sequence.
///
/// `seed` deterministically drives any jitter the policy applies. Use
/// the same seed twice and you get the same delay sequence, on the
/// BEAM and on the JavaScript target alike.
pub fn start(policy policy: Policy, seed seed: Int) -> Context {
  Context(
    policy: policy,
    attempt: 0,
    cumulative_delay: unsafe_milliseconds(value: 0),
    prng: prng.new(seed: seed),
  )
}

/// Number of attempts already completed in this sequence.
pub fn current_attempt(ctx ctx: Context) -> Int {
  ctx.attempt
}

/// Total of the delays the policy has handed out so far. Useful for
/// applying an upper-bound deadline at the call site.
pub fn cumulative_delay(ctx ctx: Context) -> Duration {
  ctx.cumulative_delay
}

/// Recover the policy a context was started from.
pub fn policy(ctx ctx: Context) -> Policy {
  ctx.policy
}

/// Decide what to do after a failed attempt.
///
/// `Permanent` short-circuits regardless of the policy. `Transient`
/// consults the policy: it may yield a retry delay, the context to
/// use next, or a structured reason to stop.
pub fn decide(ctx ctx: Context, failure failure: FailureKind) -> Decision {
  let next_attempt = ctx.attempt + 1
  case failure {
    Permanent ->
      GiveUp(reason: PermanentFailureSignaled(at_attempt: next_attempt))
    Transient ->
      case ctx.policy {
        NoRetry -> GiveUp(reason: PolicyDisallowsRetry)
        Fixed(delay: d, max_attempts: m, jitter: j) ->
          decide_fixed(ctx, d, m, j, next_attempt)
        Exponential(initial: i, multiplier: mu, max_attempts: m, jitter: j) ->
          decide_exponential(ctx, i, mu, None, m, j, next_attempt)
        CappedExponential(
          initial: i,
          multiplier: mu,
          cap: c,
          max_attempts: m,
          jitter: j,
        ) -> decide_exponential(ctx, i, mu, Some(c), m, j, next_attempt)
      }
  }
}

/// Convenience predicate: `True` when `decide` would return `Retry`.
///
/// Does not advance the context — call `decide` if you intend to act
/// on the answer.
pub fn should_retry(ctx ctx: Context, failure failure: FailureKind) -> Bool {
  case decide(ctx: ctx, failure: failure) {
    Retry(delay: _, next: _) -> True
    GiveUp(reason: _) -> False
  }
}

/// Convenience accessor: the delay component of `decide`, or the
/// give-up reason as `Error`.
///
/// Does not advance the context — call `decide` if you intend to act
/// on the answer.
pub fn next_delay(
  ctx ctx: Context,
  failure failure: FailureKind,
) -> Result(Duration, GiveUpReason) {
  case decide(ctx: ctx, failure: failure) {
    Retry(delay: d, next: _) -> Ok(d)
    GiveUp(reason: r) -> Error(r)
  }
}

fn validate_exponential_params(
  initial: Duration,
  multiplier: Int,
  max_attempts: Int,
) -> Result(Nil, RetryError) {
  case duration_milliseconds(duration: initial) <= 0 {
    True ->
      Error(
        InitialDelayMustBePositive(actual_milliseconds: duration_milliseconds(
          duration: initial,
        )),
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

fn decide_fixed(
  ctx: Context,
  delay: Duration,
  max_attempts: Int,
  jitter: Jitter,
  next_attempt: Int,
) -> Decision {
  case next_attempt >= max_attempts {
    True ->
      GiveUp(reason: MaxAttemptsReached(
        attempts: next_attempt,
        limit: max_attempts,
      ))
    False -> {
      let base_ms = duration_milliseconds(duration: delay)
      let #(final_ms, next_prng) = apply_jitter(base_ms, jitter, ctx.prng)
      finish_decision(ctx, final_ms, next_attempt, next_prng)
    }
  }
}

fn decide_exponential(
  ctx: Context,
  initial: Duration,
  multiplier: Int,
  cap: Option(Duration),
  max_attempts: Int,
  jitter: Jitter,
  next_attempt: Int,
) -> Decision {
  case next_attempt >= max_attempts {
    True ->
      GiveUp(reason: MaxAttemptsReached(
        attempts: next_attempt,
        limit: max_attempts,
      ))
    False -> {
      let initial_ms = duration_milliseconds(duration: initial)
      let cap_ms = case cap {
        Some(c) -> Some(duration_milliseconds(duration: c))
        None -> None
      }
      case
        compute_exponential_base(initial_ms, multiplier, next_attempt, cap_ms)
      {
        Error(Nil) -> GiveUp(reason: DelayOverflow(at_attempt: next_attempt))
        Ok(base_ms) -> {
          let #(final_ms, next_prng) = apply_jitter(base_ms, jitter, ctx.prng)
          finish_decision(ctx, final_ms, next_attempt, next_prng)
        }
      }
    }
  }
}

fn compute_exponential_base(
  initial_ms: Int,
  multiplier: Int,
  next_attempt: Int,
  cap_ms: Option(Int),
) -> Result(Int, Nil) {
  exponential_step(initial_ms, multiplier, next_attempt - 1, cap_ms)
}

fn exponential_step(
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
              advance_or_overflow(current, multiplier, remaining_steps, cap_ms)
          }
        None ->
          advance_or_overflow(current, multiplier, remaining_steps, cap_ms)
      }
  }
}

fn advance_or_overflow(
  current: Int,
  multiplier: Int,
  remaining_steps: Int,
  cap_ms: Option(Int),
) -> Result(Int, Nil) {
  case current > max_safe_milliseconds / multiplier {
    True ->
      case cap_ms {
        Some(c) -> Ok(c)
        None -> Error(Nil)
      }
    False ->
      exponential_step(
        current * multiplier,
        multiplier,
        remaining_steps - 1,
        cap_ms,
      )
  }
}

fn apply_jitter(
  base_ms: Int,
  jitter: Jitter,
  state: PrngState,
) -> #(Int, PrngState) {
  case jitter {
    NoJitter -> {
      let #(_, next) = prng.next_u32(state: state)
      #(base_ms, next)
    }
    FullJitter -> prng.bounded(state: state, max_inclusive: base_ms)
    EqualJitter -> {
      let half = base_ms / 2
      let #(extra, next) = prng.bounded(state: state, max_inclusive: half)
      #(half + extra, next)
    }
  }
}

fn finish_decision(
  ctx: Context,
  final_ms: Int,
  next_attempt: Int,
  next_prng: PrngState,
) -> Decision {
  let prev_cum = duration_milliseconds(duration: ctx.cumulative_delay)
  case final_ms > max_safe_milliseconds - prev_cum {
    True -> GiveUp(reason: DelayOverflow(at_attempt: next_attempt))
    False -> {
      let new_cum = unsafe_milliseconds(value: prev_cum + final_ms)
      Retry(
        delay: unsafe_milliseconds(value: final_ms),
        next: Context(
          policy: ctx.policy,
          attempt: next_attempt,
          cumulative_delay: new_cum,
          prng: next_prng,
        ),
      )
    }
  }
}
