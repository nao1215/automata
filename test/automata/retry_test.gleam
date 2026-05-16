import automata/retry
import automata/retry/ast
import gleeunit/should

fn ms(milliseconds: Int) -> ast.Duration {
  let assert Ok(d) = ast.from_milliseconds(milliseconds: milliseconds)
  d
}

pub fn from_milliseconds_rejects_negative_test() {
  ast.from_milliseconds(milliseconds: -1)
  |> should.equal(Error(ast.NegativeDuration(unit: "milliseconds", actual: -1)))
}

pub fn from_milliseconds_rejects_overflow_test() {
  // Construct the boundary value at runtime to keep the source
  // literal inside JavaScript's safe integer range.
  let just_over_safe = 9_007_199_254_740_991 + 1
  ast.from_milliseconds(milliseconds: just_over_safe)
  |> should.equal(
    Error(ast.DurationOverflow(unit: "milliseconds", actual: just_over_safe)),
  )
}

pub fn from_seconds_converts_to_milliseconds_test() {
  let assert Ok(d) = ast.from_seconds(seconds: 30)
  ast.duration_milliseconds(duration: d) |> should.equal(30_000)
}

pub fn from_minutes_converts_to_milliseconds_test() {
  let assert Ok(d) = ast.from_minutes(minutes: 2)
  ast.duration_milliseconds(duration: d) |> should.equal(120_000)
}

pub fn duration_to_string_renders_milliseconds_test() {
  ast.duration_to_string(duration: ms(750))
  |> should.equal("750ms")
}

pub fn fixed_rejects_zero_max_attempts_test() {
  retry.fixed(delay: ms(100), max_attempts: 0)
  |> should.equal(Error(ast.MaxAttemptsMustBePositive(actual: 0)))
}

pub fn exponential_rejects_zero_initial_test() {
  retry.exponential(initial: ms(0), multiplier: 2, max_attempts: 5)
  |> should.equal(Error(ast.InitialDelayMustBePositive(actual_milliseconds: 0)))
}

pub fn exponential_rejects_multiplier_below_two_test() {
  let assert Ok(d) = ast.from_milliseconds(milliseconds: 100)
  retry.exponential(initial: d, multiplier: 1, max_attempts: 5)
  |> should.equal(Error(ast.MultiplierMustBeAtLeastTwo(actual: 1)))
}

pub fn capped_exponential_rejects_cap_below_initial_test() {
  retry.capped_exponential(
    initial: ms(200),
    multiplier: 2,
    cap: ms(100),
    max_attempts: 5,
  )
  |> should.equal(
    Error(ast.CapMustNotBeLessThanInitial(
      cap_milliseconds: 100,
      initial_milliseconds: 200,
    )),
  )
}

pub fn capped_exponential_ms_matches_manual_construction_test() {
  let assert Ok(via_ms) =
    retry.capped_exponential_ms(
      initial_ms: 50,
      multiplier: 2,
      cap_ms: 1000,
      max_attempts: 5,
    )
  let assert Ok(via_duration) =
    retry.capped_exponential(
      initial: ms(50),
      multiplier: 2,
      cap: ms(1000),
      max_attempts: 5,
    )
  via_ms |> should.equal(via_duration)
}

pub fn capped_exponential_ms_rejects_negative_initial_test() {
  retry.capped_exponential_ms(
    initial_ms: -1,
    multiplier: 2,
    cap_ms: 1000,
    max_attempts: 5,
  )
  |> should.equal(Error(ast.NegativeDuration(unit: "milliseconds", actual: -1)))
}

pub fn capped_exponential_ms_rejects_negative_cap_test() {
  retry.capped_exponential_ms(
    initial_ms: 50,
    multiplier: 2,
    cap_ms: -1,
    max_attempts: 5,
  )
  |> should.equal(Error(ast.NegativeDuration(unit: "milliseconds", actual: -1)))
}

pub fn capped_exponential_ms_rejects_cap_below_initial_test() {
  retry.capped_exponential_ms(
    initial_ms: 200,
    multiplier: 2,
    cap_ms: 100,
    max_attempts: 5,
  )
  |> should.equal(
    Error(ast.CapMustNotBeLessThanInitial(
      cap_milliseconds: 100,
      initial_milliseconds: 200,
    )),
  )
}

pub fn capped_exponential_ms_rejects_multiplier_below_two_test() {
  retry.capped_exponential_ms(
    initial_ms: 50,
    multiplier: 1,
    cap_ms: 1000,
    max_attempts: 5,
  )
  |> should.equal(Error(ast.MultiplierMustBeAtLeastTwo(actual: 1)))
}

pub fn capped_exponential_ms_rejects_zero_max_attempts_test() {
  retry.capped_exponential_ms(
    initial_ms: 50,
    multiplier: 2,
    cap_ms: 1000,
    max_attempts: 0,
  )
  |> should.equal(Error(ast.MaxAttemptsMustBePositive(actual: 0)))
}

pub fn no_retry_refuses_transient_failure_test() {
  let ctx = retry.start(policy: retry.no_retry(), seed: 1)

  retry.decide(ctx: ctx, failure: ast.Transient)
  |> should.equal(retry.GiveUp(reason: ast.PolicyDisallowsRetry))
}

pub fn no_retry_short_circuits_permanent_failure_test() {
  let ctx = retry.start(policy: retry.no_retry(), seed: 1)

  retry.decide(ctx: ctx, failure: ast.Permanent)
  |> should.equal(
    retry.GiveUp(reason: ast.PermanentFailureSignaled(at_attempt: 1)),
  )
}

pub fn fixed_emits_constant_delay_until_exhausted_test() {
  let assert Ok(policy) = retry.fixed(delay: ms(250), max_attempts: 3)
  let ctx0 = retry.start(policy: policy, seed: 1)

  let assert retry.Retry(delay: d1, next: ctx1) =
    retry.decide(ctx: ctx0, failure: ast.Transient)
  ast.duration_milliseconds(duration: d1) |> should.equal(250)
  retry.current_attempt(ctx: ctx1) |> should.equal(1)

  let assert retry.Retry(delay: d2, next: ctx2) =
    retry.decide(ctx: ctx1, failure: ast.Transient)
  ast.duration_milliseconds(duration: d2) |> should.equal(250)
  retry.current_attempt(ctx: ctx2) |> should.equal(2)

  retry.decide(ctx: ctx2, failure: ast.Transient)
  |> should.equal(
    retry.GiveUp(reason: ast.MaxAttemptsReached(attempts: 3, limit: 3)),
  )
}

pub fn exponential_emits_growing_delays_test() {
  let assert Ok(policy) =
    retry.exponential(initial: ms(100), multiplier: 2, max_attempts: 5)
  let ctx0 = retry.start(policy: policy, seed: 1)

  let delays = collect_transient_delays(ctx0, 4, [])
  delays |> should.equal([100, 200, 400, 800])
}

pub fn exponential_yields_max_attempts_reached_after_budget_test() {
  let assert Ok(policy) =
    retry.exponential(initial: ms(100), multiplier: 2, max_attempts: 3)
  let ctx0 = retry.start(policy: policy, seed: 1)

  let assert retry.Retry(delay: _, next: ctx1) =
    retry.decide(ctx: ctx0, failure: ast.Transient)
  let assert retry.Retry(delay: _, next: ctx2) =
    retry.decide(ctx: ctx1, failure: ast.Transient)

  retry.decide(ctx: ctx2, failure: ast.Transient)
  |> should.equal(
    retry.GiveUp(reason: ast.MaxAttemptsReached(attempts: 3, limit: 3)),
  )
}

pub fn capped_exponential_saturates_at_cap_test() {
  let assert Ok(policy) =
    retry.capped_exponential(
      initial: ms(100),
      multiplier: 2,
      cap: ms(500),
      max_attempts: 6,
    )
  let ctx0 = retry.start(policy: policy, seed: 1)

  let delays = collect_transient_delays(ctx0, 5, [])
  delays |> should.equal([100, 200, 400, 500, 500])
}

pub fn capped_exponential_avoids_overflow_test() {
  // initial * 2^99 would overflow without the cap, but the cap should
  // truncate the running base before any multiplication overflows.
  let assert Ok(policy) =
    retry.capped_exponential(
      initial: ms(1000),
      multiplier: 2,
      cap: ms(60_000),
      max_attempts: 100,
    )
  let ctx0 = retry.start(policy: policy, seed: 1)

  let assert retry.Retry(delay: d, next: _) = drive(ctx0, 50, ast.Transient)
  ast.duration_milliseconds(duration: d) |> should.equal(60_000)
}

pub fn unbounded_exponential_overflow_is_reported_test() {
  // 2^53 / 4 = 2_251_799_813_685_248.75, so attempt 54 would overflow.
  let assert Ok(policy) =
    retry.exponential(initial: ms(1), multiplier: 2, max_attempts: 100)
  let ctx0 = retry.start(policy: policy, seed: 1)

  let final = drive(ctx0, 54, ast.Transient)
  case final {
    retry.GiveUp(reason: ast.DelayOverflow(at_attempt: at)) ->
      { at >= 54 } |> should.equal(True)
    other ->
      other |> should.equal(retry.GiveUp(reason: ast.PolicyDisallowsRetry))
  }
}

pub fn permanent_failure_short_circuits_exponential_test() {
  let assert Ok(policy) =
    retry.exponential(initial: ms(100), multiplier: 2, max_attempts: 100)
  let ctx = retry.start(policy: policy, seed: 1)

  retry.decide(ctx: ctx, failure: ast.Permanent)
  |> should.equal(
    retry.GiveUp(reason: ast.PermanentFailureSignaled(at_attempt: 1)),
  )
}

pub fn full_jitter_stays_within_zero_to_base_test() {
  let assert Ok(base_policy) =
    retry.exponential(initial: ms(1000), multiplier: 2, max_attempts: 6)
  let policy = retry.with_jitter(policy: base_policy, jitter: ast.FullJitter)
  let ctx = retry.start(policy: policy, seed: 2026)

  let delays = collect_transient_delays(ctx, 5, [])
  all_in_range(delays, [1000, 2000, 4000, 8000, 16_000])
  |> should.equal(True)
}

pub fn equal_jitter_stays_in_lower_half_to_base_test() {
  let assert Ok(base_policy) =
    retry.exponential(initial: ms(1000), multiplier: 2, max_attempts: 6)
  let policy = retry.with_jitter(policy: base_policy, jitter: ast.EqualJitter)
  let ctx = retry.start(policy: policy, seed: 2026)

  let delays = collect_transient_delays(ctx, 5, [])
  all_in_equal_jitter_range(delays, [1000, 2000, 4000, 8000, 16_000])
  |> should.equal(True)
}

pub fn jitter_is_deterministic_for_same_seed_test() {
  let assert Ok(base_policy) =
    retry.exponential(initial: ms(100), multiplier: 2, max_attempts: 8)
  let policy = retry.with_jitter(policy: base_policy, jitter: ast.FullJitter)

  let a = collect_transient_delays(retry.start(policy: policy, seed: 7), 5, [])
  let b = collect_transient_delays(retry.start(policy: policy, seed: 7), 5, [])
  a |> should.equal(b)
}

pub fn different_seeds_diverge_test() {
  let assert Ok(base_policy) =
    retry.exponential(initial: ms(100), multiplier: 2, max_attempts: 8)
  let policy = retry.with_jitter(policy: base_policy, jitter: ast.FullJitter)

  let a = collect_transient_delays(retry.start(policy: policy, seed: 1), 5, [])
  let b = collect_transient_delays(retry.start(policy: policy, seed: 2), 5, [])
  { a == b } |> should.equal(False)
}

pub fn cumulative_delay_accumulates_test() {
  let assert Ok(policy) = retry.fixed(delay: ms(100), max_attempts: 4)
  let ctx0 = retry.start(policy: policy, seed: 1)

  let assert retry.Retry(delay: _, next: ctx1) =
    retry.decide(ctx: ctx0, failure: ast.Transient)
  let assert retry.Retry(delay: _, next: ctx2) =
    retry.decide(ctx: ctx1, failure: ast.Transient)
  let assert retry.Retry(delay: _, next: ctx3) =
    retry.decide(ctx: ctx2, failure: ast.Transient)

  ast.duration_milliseconds(duration: retry.cumulative_delay(ctx: ctx3))
  |> should.equal(300)
}

pub fn next_delay_returns_delay_or_reason_test() {
  let assert Ok(policy) = retry.fixed(delay: ms(50), max_attempts: 2)
  let ctx0 = retry.start(policy: policy, seed: 1)

  retry.next_delay(ctx: ctx0, failure: ast.Transient)
  |> should.equal(Ok(ms(50)))

  let assert retry.Retry(delay: _, next: ctx1) =
    retry.decide(ctx: ctx0, failure: ast.Transient)

  retry.next_delay(ctx: ctx1, failure: ast.Transient)
  |> should.equal(Error(ast.MaxAttemptsReached(attempts: 2, limit: 2)))
}

pub fn max_attempts_one_gives_up_immediately_test() {
  let assert Ok(policy) = retry.fixed(delay: ms(50), max_attempts: 1)
  let ctx0 = retry.start(policy: policy, seed: 1)

  retry.decide(ctx: ctx0, failure: ast.Transient)
  |> should.equal(
    retry.GiveUp(reason: ast.MaxAttemptsReached(attempts: 1, limit: 1)),
  )
}

pub fn should_retry_matches_decide_test() {
  let assert Ok(policy) = retry.fixed(delay: ms(50), max_attempts: 2)
  let ctx0 = retry.start(policy: policy, seed: 1)

  retry.should_retry(ctx: ctx0, failure: ast.Transient)
  |> should.equal(True)

  retry.should_retry(ctx: ctx0, failure: ast.Permanent)
  |> should.equal(False)

  let no_ctx = retry.start(policy: retry.no_retry(), seed: 1)
  retry.should_retry(ctx: no_ctx, failure: ast.Transient)
  |> should.equal(False)
}

pub fn should_retry_does_not_advance_context_test() {
  let assert Ok(policy) = retry.fixed(delay: ms(50), max_attempts: 3)
  let ctx = retry.start(policy: policy, seed: 1)

  retry.should_retry(ctx: ctx, failure: ast.Transient)
  |> should.equal(True)
  retry.should_retry(ctx: ctx, failure: ast.Transient)
  |> should.equal(True)

  retry.current_attempt(ctx: ctx) |> should.equal(0)
}

pub fn policy_accessor_returns_original_policy_test() {
  let assert Ok(policy) = retry.fixed(delay: ms(50), max_attempts: 2)
  let ctx = retry.start(policy: policy, seed: 1)

  retry.policy(ctx: ctx) |> should.equal(policy)
}

fn collect_transient_delays(
  ctx: retry.Context,
  remaining: Int,
  acc: List(Int),
) -> List(Int) {
  case remaining <= 0 {
    True -> reverse(acc, [])
    False ->
      case retry.decide(ctx: ctx, failure: ast.Transient) {
        retry.Retry(delay: d, next: next) ->
          collect_transient_delays(next, remaining - 1, [
            ast.duration_milliseconds(duration: d),
            ..acc
          ])
        retry.GiveUp(reason: _) -> reverse(acc, [])
      }
  }
}

fn drive(
  ctx: retry.Context,
  remaining: Int,
  failure: ast.FailureKind,
) -> retry.Decision {
  case remaining <= 0 {
    True -> retry.decide(ctx: ctx, failure: failure)
    False ->
      case retry.decide(ctx: ctx, failure: failure) {
        retry.Retry(delay: _, next: next) -> drive(next, remaining - 1, failure)
        give_up -> give_up
      }
  }
}

fn reverse(input: List(Int), acc: List(Int)) -> List(Int) {
  case input {
    [] -> acc
    [head, ..tail] -> reverse(tail, [head, ..acc])
  }
}

fn all_in_range(values: List(Int), bases: List(Int)) -> Bool {
  case values, bases {
    [], _ -> True
    _, [] -> True
    [v, ..vs], [b, ..bs] ->
      case v >= 0 && v <= b {
        True -> all_in_range(vs, bs)
        False -> False
      }
  }
}

fn all_in_equal_jitter_range(values: List(Int), bases: List(Int)) -> Bool {
  case values, bases {
    [], _ -> True
    _, [] -> True
    [v, ..vs], [b, ..bs] -> {
      let half = b / 2
      case v >= half && v <= b {
        True -> all_in_equal_jitter_range(vs, bs)
        False -> False
      }
    }
  }
}
