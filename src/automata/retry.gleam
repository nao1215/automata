import automata/retry/ast.{
  type Duration, type FailureKind, type GiveUpReason, type Jitter,
  type RetryError, CapMustNotBeLessThanInitial, DelayOverflow, EqualJitter,
  FullJitter, InitialDelayMustBePositive, MaxAttemptsMustBePositive,
  MaxAttemptsReached, MultiplierMustBeAtLeastTwo, NoJitter, Permanent,
  PermanentFailureSignaled, PolicyDisallowsRetry, Transient,
}
import automata/retry/internal/prng.{type PrngState}
import gleam/option.{type Option, None, Some}

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
      case ast.duration_milliseconds(cap) < ast.duration_milliseconds(initial) {
        True ->
          Error(CapMustNotBeLessThanInitial(
            cap_milliseconds: ast.duration_milliseconds(cap),
            initial_milliseconds: ast.duration_milliseconds(initial),
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
    cumulative_delay: ast.unsafe_milliseconds(value: 0),
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
  case ast.duration_milliseconds(initial) <= 0 {
    True ->
      Error(
        InitialDelayMustBePositive(
          actual_milliseconds: ast.duration_milliseconds(initial),
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
      let base_ms = ast.duration_milliseconds(delay)
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
      let initial_ms = ast.duration_milliseconds(initial)
      let cap_ms = case cap {
        Some(c) -> Some(ast.duration_milliseconds(c))
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
  case current > ast.max_safe_milliseconds / multiplier {
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
  let prev_cum = ast.duration_milliseconds(ctx.cumulative_delay)
  case final_ms > ast.max_safe_milliseconds - prev_cum {
    True -> GiveUp(reason: DelayOverflow(at_attempt: next_attempt))
    False -> {
      let new_cum = ast.unsafe_milliseconds(value: prev_cum + final_ms)
      Retry(
        delay: ast.unsafe_milliseconds(value: final_ms),
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
