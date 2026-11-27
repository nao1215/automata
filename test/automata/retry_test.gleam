import automata as a
import gleam/int
import gleam/list
import gleam/result
import gleam/time/duration
import gleeunit/should

fn ms(milliseconds: Int) -> duration.Duration {
  let assert Ok(d) = make_milliseconds(milliseconds: milliseconds)
  d
}

pub fn from_milliseconds_rejects_negative_test() {
  make_milliseconds(milliseconds: -1)
  |> should.equal(
    Error(a.NegativeDuration(seconds: -1, nanoseconds: 999_000_000)),
  )
}

pub fn from_milliseconds_rejects_overflow_test() {
  // Construct the boundary value at runtime to keep the source
  // literal inside JavaScript's safe integer range.
  let just_over_safe = 9_007_199_254_740_991 + 1
  make_milliseconds(milliseconds: just_over_safe)
  |> should.equal(
    Error(a.DurationOverflow(
      seconds: 9_007_199_254_740,
      nanoseconds: 992_000_000,
    )),
  )
}

pub fn from_seconds_converts_to_milliseconds_test() {
  let assert Ok(d) = make_seconds(seconds: 30)
  duration.to_milliseconds(d) |> should.equal(30_000)
}

pub fn from_minutes_converts_to_milliseconds_test() {
  let assert Ok(d) = make_minutes(minutes: 2)
  duration.to_milliseconds(d) |> should.equal(120_000)
}

pub fn duration_to_string_renders_milliseconds_test() {
  duration_string(duration: ms(750))
  |> should.equal("750ms")
}

pub fn fixed_rejects_zero_max_attempts_test() {
  a.retry_fixed(delay: ms(100), max_attempts: 0)
  |> should.equal(Error(a.MaxAttemptsMustBePositive(actual: 0)))
}

pub fn exponential_rejects_zero_initial_test() {
  a.retry_exponential(initial: ms(0), multiplier: 2, max_attempts: 5)
  |> should.equal(Error(a.InitialDelayMustBePositive(actual_milliseconds: 0)))
}

pub fn exponential_rejects_multiplier_below_two_test() {
  let assert Ok(d) = make_milliseconds(milliseconds: 100)
  a.retry_exponential(initial: d, multiplier: 1, max_attempts: 5)
  |> should.equal(Error(a.MultiplierMustBeAtLeastTwo(actual: 1)))
}

pub fn capped_exponential_rejects_cap_below_initial_test() {
  a.retry_capped_exponential(
    initial: ms(200),
    multiplier: 2,
    cap: ms(100),
    max_attempts: 5,
  )
  |> should.equal(
    Error(a.CapMustNotBeLessThanInitial(
      cap_milliseconds: 100,
      initial_milliseconds: 200,
    )),
  )
}

pub fn capped_exponential_ms_matches_manual_construction_test() {
  let assert Ok(via_ms) =
    capped_milliseconds(
      initial_ms: 50,
      multiplier: 2,
      cap_ms: 1000,
      max_attempts: 5,
    )
  let assert Ok(via_duration) =
    a.retry_capped_exponential(
      initial: ms(50),
      multiplier: 2,
      cap: ms(1000),
      max_attempts: 5,
    )
  via_ms |> should.equal(via_duration)
}

pub fn capped_exponential_ms_rejects_negative_initial_test() {
  capped_milliseconds(
    initial_ms: -1,
    multiplier: 2,
    cap_ms: 1000,
    max_attempts: 5,
  )
  |> should.equal(
    Error(a.NegativeDuration(seconds: -1, nanoseconds: 999_000_000)),
  )
}

pub fn capped_exponential_ms_rejects_negative_cap_test() {
  capped_milliseconds(
    initial_ms: 50,
    multiplier: 2,
    cap_ms: -1,
    max_attempts: 5,
  )
  |> should.equal(
    Error(a.NegativeDuration(seconds: -1, nanoseconds: 999_000_000)),
  )
}

pub fn capped_exponential_ms_rejects_cap_below_initial_test() {
  capped_milliseconds(
    initial_ms: 200,
    multiplier: 2,
    cap_ms: 100,
    max_attempts: 5,
  )
  |> should.equal(
    Error(a.CapMustNotBeLessThanInitial(
      cap_milliseconds: 100,
      initial_milliseconds: 200,
    )),
  )
}

pub fn capped_exponential_ms_rejects_multiplier_below_two_test() {
  capped_milliseconds(
    initial_ms: 50,
    multiplier: 1,
    cap_ms: 1000,
    max_attempts: 5,
  )
  |> should.equal(Error(a.MultiplierMustBeAtLeastTwo(actual: 1)))
}

pub fn capped_exponential_ms_rejects_zero_max_attempts_test() {
  capped_milliseconds(
    initial_ms: 50,
    multiplier: 2,
    cap_ms: 1000,
    max_attempts: 0,
  )
  |> should.equal(Error(a.MaxAttemptsMustBePositive(actual: 0)))
}

pub fn no_retry_refuses_transient_failure_test() {
  let ctx = a.retry_start(policy: a.retry_no_retry(), seed: 1)

  a.retry_decide(ctx: ctx, failure: a.Transient)
  |> should.equal(a.GiveUp(reason: a.PolicyDisallowsRetry))
}

pub fn no_retry_short_circuits_permanent_failure_test() {
  let ctx = a.retry_start(policy: a.retry_no_retry(), seed: 1)

  a.retry_decide(ctx: ctx, failure: a.Permanent)
  |> should.equal(a.GiveUp(reason: a.PermanentFailureSignaled(at_attempt: 1)))
}

pub fn fixed_emits_constant_delay_until_exhausted_test() {
  let assert Ok(policy) = a.retry_fixed(delay: ms(250), max_attempts: 3)
  let ctx0 = a.retry_start(policy: policy, seed: 1)

  let assert a.Retry(delay: d1, next: ctx1) =
    a.retry_decide(ctx: ctx0, failure: a.Transient)
  duration.to_milliseconds(d1) |> should.equal(250)
  a.retry_current_attempt(ctx: ctx1) |> should.equal(1)

  let assert a.Retry(delay: d2, next: ctx2) =
    a.retry_decide(ctx: ctx1, failure: a.Transient)
  duration.to_milliseconds(d2) |> should.equal(250)
  a.retry_current_attempt(ctx: ctx2) |> should.equal(2)

  a.retry_decide(ctx: ctx2, failure: a.Transient)
  |> should.equal(a.GiveUp(reason: a.MaxAttemptsReached(attempts: 3, limit: 3)))
}

pub fn exponential_emits_growing_delays_test() {
  let assert Ok(policy) =
    a.retry_exponential(initial: ms(100), multiplier: 2, max_attempts: 5)
  let ctx0 = a.retry_start(policy: policy, seed: 1)

  let delays = collect_transient_delays(ctx0, 4, [])
  delays |> should.equal([100, 200, 400, 800])
}

pub fn exponential_yields_max_attempts_reached_after_budget_test() {
  let assert Ok(policy) =
    a.retry_exponential(initial: ms(100), multiplier: 2, max_attempts: 3)
  let ctx0 = a.retry_start(policy: policy, seed: 1)

  let assert a.Retry(delay: _, next: ctx1) =
    a.retry_decide(ctx: ctx0, failure: a.Transient)
  let assert a.Retry(delay: _, next: ctx2) =
    a.retry_decide(ctx: ctx1, failure: a.Transient)

  a.retry_decide(ctx: ctx2, failure: a.Transient)
  |> should.equal(a.GiveUp(reason: a.MaxAttemptsReached(attempts: 3, limit: 3)))
}

pub fn capped_exponential_saturates_at_cap_test() {
  let assert Ok(policy) =
    a.retry_capped_exponential(
      initial: ms(100),
      multiplier: 2,
      cap: ms(500),
      max_attempts: 6,
    )
  let ctx0 = a.retry_start(policy: policy, seed: 1)

  let delays = collect_transient_delays(ctx0, 5, [])
  delays |> should.equal([100, 200, 400, 500, 500])
}

pub fn capped_exponential_avoids_overflow_test() {
  // initial * 2^99 would overflow without the cap, but the cap should
  // truncate the running base before any multiplication overflows.
  let assert Ok(policy) =
    a.retry_capped_exponential(
      initial: ms(1000),
      multiplier: 2,
      cap: ms(60_000),
      max_attempts: 100,
    )
  let ctx0 = a.retry_start(policy: policy, seed: 1)

  let assert a.Retry(delay: d, next: _) = drive(ctx0, 50, a.Transient)
  duration.to_milliseconds(d) |> should.equal(60_000)
}

pub fn unbounded_exponential_overflow_is_reported_test() {
  // 2^53 / 4 = 2_251_799_813_685_248.75, so attempt 54 would overflow.
  let assert Ok(policy) =
    a.retry_exponential(initial: ms(1), multiplier: 2, max_attempts: 100)
  let ctx0 = a.retry_start(policy: policy, seed: 1)

  let final = drive(ctx0, 54, a.Transient)
  case final {
    a.GiveUp(reason: a.DelayOverflow(at_attempt: at)) ->
      { at >= 54 } |> should.equal(True)
    other -> other |> should.equal(a.GiveUp(reason: a.PolicyDisallowsRetry))
  }
}

pub fn permanent_failure_short_circuits_exponential_test() {
  let assert Ok(policy) =
    a.retry_exponential(initial: ms(100), multiplier: 2, max_attempts: 100)
  let ctx = a.retry_start(policy: policy, seed: 1)

  a.retry_decide(ctx: ctx, failure: a.Permanent)
  |> should.equal(a.GiveUp(reason: a.PermanentFailureSignaled(at_attempt: 1)))
}

pub fn full_jitter_stays_within_zero_to_base_test() {
  let assert Ok(base_policy) =
    a.retry_exponential(initial: ms(1000), multiplier: 2, max_attempts: 6)
  let policy = a.retry_jitter(policy: base_policy, jitter: a.FullJitter)
  let ctx = a.retry_start(policy: policy, seed: 2026)

  let delays = collect_transient_delays(ctx, 5, [])
  all_in_range(delays, [1000, 2000, 4000, 8000, 16_000])
  |> should.equal(True)
}

pub fn equal_jitter_stays_in_lower_half_to_base_test() {
  let assert Ok(base_policy) =
    a.retry_exponential(initial: ms(1000), multiplier: 2, max_attempts: 6)
  let policy = a.retry_jitter(policy: base_policy, jitter: a.EqualJitter)
  let ctx = a.retry_start(policy: policy, seed: 2026)

  let delays = collect_transient_delays(ctx, 5, [])
  all_in_equal_jitter_range(delays, [1000, 2000, 4000, 8000, 16_000])
  |> should.equal(True)
}

pub fn jitter_is_deterministic_for_same_seed_test() {
  let assert Ok(base_policy) =
    a.retry_exponential(initial: ms(100), multiplier: 2, max_attempts: 8)
  let policy = a.retry_jitter(policy: base_policy, jitter: a.FullJitter)

  let a =
    collect_transient_delays(a.retry_start(policy: policy, seed: 7), 5, [])
  let b =
    collect_transient_delays(a.retry_start(policy: policy, seed: 7), 5, [])
  a |> should.equal(b)
}

pub fn different_seeds_diverge_test() {
  let assert Ok(base_policy) =
    a.retry_exponential(initial: ms(100), multiplier: 2, max_attempts: 8)
  let policy = a.retry_jitter(policy: base_policy, jitter: a.FullJitter)

  let a =
    collect_transient_delays(a.retry_start(policy: policy, seed: 1), 5, [])
  let b =
    collect_transient_delays(a.retry_start(policy: policy, seed: 2), 5, [])
  { a == b } |> should.equal(False)
}

pub fn cumulative_delay_accumulates_test() {
  let assert Ok(policy) = a.retry_fixed(delay: ms(100), max_attempts: 4)
  let ctx0 = a.retry_start(policy: policy, seed: 1)

  let assert a.Retry(delay: _, next: ctx1) =
    a.retry_decide(ctx: ctx0, failure: a.Transient)
  let assert a.Retry(delay: _, next: ctx2) =
    a.retry_decide(ctx: ctx1, failure: a.Transient)
  let assert a.Retry(delay: _, next: ctx3) =
    a.retry_decide(ctx: ctx2, failure: a.Transient)

  duration.to_milliseconds(a.retry_cumulative_delay(ctx: ctx3))
  |> should.equal(300)
}

pub fn next_delay_returns_delay_or_reason_test() {
  let assert Ok(policy) = a.retry_fixed(delay: ms(50), max_attempts: 2)
  let ctx0 = a.retry_start(policy: policy, seed: 1)

  decision_delay(ctx: ctx0, failure: a.Transient)
  |> should.equal(Ok(ms(50)))

  let assert a.Retry(delay: _, next: ctx1) =
    a.retry_decide(ctx: ctx0, failure: a.Transient)

  decision_delay(ctx: ctx1, failure: a.Transient)
  |> should.equal(Error(a.MaxAttemptsReached(attempts: 2, limit: 2)))
}

pub fn max_attempts_one_gives_up_immediately_test() {
  let assert Ok(policy) = a.retry_fixed(delay: ms(50), max_attempts: 1)
  let ctx0 = a.retry_start(policy: policy, seed: 1)

  a.retry_decide(ctx: ctx0, failure: a.Transient)
  |> should.equal(a.GiveUp(reason: a.MaxAttemptsReached(attempts: 1, limit: 1)))
}

pub fn should_retry_matches_decide_test() {
  let assert Ok(policy) = a.retry_fixed(delay: ms(50), max_attempts: 2)
  let ctx0 = a.retry_start(policy: policy, seed: 1)

  decision_retries(ctx: ctx0, failure: a.Transient)
  |> should.equal(True)

  decision_retries(ctx: ctx0, failure: a.Permanent)
  |> should.equal(False)

  let no_ctx = a.retry_start(policy: a.retry_no_retry(), seed: 1)
  decision_retries(ctx: no_ctx, failure: a.Transient)
  |> should.equal(False)
}

pub fn should_retry_does_not_advance_context_test() {
  let assert Ok(policy) = a.retry_fixed(delay: ms(50), max_attempts: 3)
  let ctx = a.retry_start(policy: policy, seed: 1)

  decision_retries(ctx: ctx, failure: a.Transient)
  |> should.equal(True)
  decision_retries(ctx: ctx, failure: a.Transient)
  |> should.equal(True)

  a.retry_current_attempt(ctx: ctx) |> should.equal(0)
}

pub fn policy_accessor_returns_original_policy_test() {
  let assert Ok(policy) = a.retry_fixed(delay: ms(50), max_attempts: 2)
  let ctx = a.retry_start(policy: policy, seed: 1)

  a.retry_policy(ctx: ctx) |> should.equal(policy)
}

fn collect_transient_delays(
  ctx: a.RetryContext,
  remaining: Int,
  acc: List(Int),
) -> List(Int) {
  case remaining <= 0 {
    True -> reverse(acc, [])
    False ->
      case a.retry_decide(ctx: ctx, failure: a.Transient) {
        a.Retry(delay: d, next: next) ->
          collect_transient_delays(next, remaining - 1, [
            duration.to_milliseconds(d),
            ..acc
          ])
        a.GiveUp(reason: _) -> reverse(acc, [])
      }
  }
}

fn drive(
  ctx: a.RetryContext,
  remaining: Int,
  failure: a.FailureKind,
) -> a.RetryDecision {
  case remaining <= 0 {
    True -> a.retry_decide(ctx: ctx, failure: failure)
    False ->
      case a.retry_decide(ctx: ctx, failure: failure) {
        a.Retry(delay: _, next: next) -> drive(next, remaining - 1, failure)
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

fn first_delays(policy: a.RetryPolicy, seeds: List(Int)) -> List(Int) {
  list.map(seeds, fn(seed) {
    let assert a.Retry(delay: d, next: _) =
      a.retry_decide(
        ctx: a.retry_start(policy: policy, seed: seed),
        failure: a.Transient,
      )
    duration.to_milliseconds(d)
  })
}

fn seeds_between(from: Int, to: Int) -> List(Int) {
  case from > to {
    True -> []
    False -> [from, ..seeds_between(from + 1, to)]
  }
}

fn max_of(values: List(Int)) -> Int {
  list.fold(values, 0, int.max)
}

pub fn full_jitter_covers_bases_above_32_bits_test() {
  // 10_000_000_000 ms is above 2^32 - 1; the draw used to come from a
  // single 32-bit value and never exceeded 4_294_967_295.
  let base = 10_000_000_000
  let assert Ok(fixed) = a.retry_fixed(delay: ms(base), max_attempts: 2)
  let policy = a.retry_jitter(policy: fixed, jitter: a.FullJitter)
  let delays = first_delays(policy, seeds_between(1, 200))

  list.all(delays, fn(d) { d >= 0 && d <= base }) |> should.equal(True)
  { max_of(delays) > 4_294_967_295 } |> should.equal(True)
}

pub fn full_jitter_small_seeds_spread_over_range_test() {
  // Seeds 1 to 2000 used to give at most 536_662_045 here, an eighth of
  // the range.
  let base = 4_000_000_000
  let assert Ok(fixed) = a.retry_fixed(delay: ms(base), max_attempts: 2)
  let policy = a.retry_jitter(policy: fixed, jitter: a.FullJitter)
  let delays = first_delays(policy, seeds_between(1, 50))

  { max_of(delays) > base / 2 } |> should.equal(True)
}

pub fn equal_jitter_reaches_odd_base_test() {
  let assert Ok(fixed) = a.retry_fixed(delay: ms(3), max_attempts: 2)
  let policy = a.retry_jitter(policy: fixed, jitter: a.EqualJitter)

  first_delays(policy, seeds_between(1, 200))
  |> list.unique
  |> list.sort(int.compare)
  |> should.equal([1, 2, 3])
}

fn capped_milliseconds(
  initial_ms initial: Int,
  multiplier multiplier: Int,
  cap_ms cap: Int,
  max_attempts max_attempts: Int,
) -> Result(a.RetryPolicy, a.RetryError) {
  a.retry_capped_exponential(
    initial: duration.milliseconds(initial),
    multiplier: multiplier,
    cap: duration.milliseconds(cap),
    max_attempts: max_attempts,
  )
}

fn decision_delay(
  ctx ctx: a.RetryContext,
  failure failure: a.FailureKind,
) -> Result(duration.Duration, a.GiveUpReason) {
  case a.retry_decide(ctx: ctx, failure: failure) {
    a.Retry(delay, _) -> Ok(delay)
    a.GiveUp(reason) -> Error(reason)
  }
}

fn decision_retries(
  ctx ctx: a.RetryContext,
  failure failure: a.FailureKind,
) -> Bool {
  case a.retry_decide(ctx: ctx, failure: failure) {
    a.Retry(_, _) -> True
    a.GiveUp(_) -> False
  }
}

fn duration_string(duration value: duration.Duration) -> String {
  int.to_string(duration.to_milliseconds(value)) <> "ms"
}

fn make_milliseconds(
  milliseconds milliseconds: Int,
) -> Result(duration.Duration, a.RetryError) {
  let value = duration.milliseconds(milliseconds)
  a.retry_fixed(delay: value, max_attempts: 2) |> result.map(fn(_) { value })
}

fn make_minutes(
  minutes minutes: Int,
) -> Result(duration.Duration, a.RetryError) {
  let value = duration.minutes(minutes)
  a.retry_fixed(delay: value, max_attempts: 2) |> result.map(fn(_) { value })
}

fn make_seconds(
  seconds seconds: Int,
) -> Result(duration.Duration, a.RetryError) {
  let value = duration.seconds(seconds)
  a.retry_fixed(delay: value, max_attempts: 2) |> result.map(fn(_) { value })
}

pub fn capped_exponential_accepts_cap_equal_to_initial_test() {
  // "cap at least initial": a cap equal to the initial delay is valid and
  // every retry then waits exactly that long.
  let assert Ok(policy) =
    a.retry_capped_exponential(
      initial: ms(250),
      multiplier: 3,
      cap: ms(250),
      max_attempts: 4,
    )
  let delays = collect_transient_delays(a.retry_start(policy:, seed: 1), 3, [])
  assert delays == [250, 250, 250]
}

pub fn full_jitter_matches_reference_xorshift32_test() {
  // Reference values come from an independent Xorshift32 (13/17/5) model:
  // the context discards three draws, small bases (up to 2^32 - 1) take one
  // draw modulo base + 1, larger bases combine 21 high bits of one draw with
  // a second 32-bit draw before the modulo.
  let jittered_first_delay = fn(base) {
    let assert Ok(fixed) = a.retry_fixed(delay: ms(base), max_attempts: 2)
    let policy = a.retry_jitter(policy: fixed, jitter: a.FullJitter)
    first_delays(policy, [1])
  }
  assert jittered_first_delay(1000) == [403]
  assert jittered_first_delay(4_294_967_295) == [307_599_695]
  assert jittered_first_delay(1_099_511_627_776) == [341_701_100_088]
}

pub fn exponential_base_at_largest_safe_double_is_not_overflow_test() {
  // initial 2^52 - 1 doubled is 2^53 - 2, still within the 2^53 - 1 ceiling,
  // so the second retry is scheduled; the jittered delays are taken from the
  // reference Xorshift32 model for seed 1.
  let assert Ok(base_policy) =
    a.retry_exponential(
      initial: ms(4_503_599_627_370_495),
      multiplier: 2,
      max_attempts: 3,
    )
  let policy = a.retry_jitter(policy: base_policy, jitter: a.FullJitter)
  let delays = collect_transient_delays(a.retry_start(policy:, seed: 1), 2, [])
  assert delays == [1_575_941_863_708_625, 4_323_074_194_420_506]
}

pub fn exponential_base_past_safe_range_overflows_despite_jitter_test() {
  // initial 2^52 doubled is 2^53, one past the ceiling: the base itself is
  // out of range, so jitter must not turn it into a retry.
  let assert Ok(base_policy) =
    a.retry_exponential(
      initial: ms(4_503_599_627_370_496),
      multiplier: 2,
      max_attempts: 3,
    )
  let policy = a.retry_jitter(policy: base_policy, jitter: a.FullJitter)
  list.each([1, 2, 4], fn(seed) {
    let assert a.Retry(delay: _, next: ctx1) =
      a.retry_decide(ctx: a.retry_start(policy:, seed:), failure: a.Transient)
    assert a.retry_decide(ctx: ctx1, failure: a.Transient)
      == a.GiveUp(reason: a.DelayOverflow(at_attempt: 2))
  })
}

pub fn fixed_delay_cumulative_overflow_gives_up_test() {
  // Two 2^52 ms delays sum to 2^53, one past the cumulative ceiling.
  let assert Ok(policy) =
    a.retry_fixed(delay: ms(4_503_599_627_370_496), max_attempts: 5)
  let assert a.Retry(delay: _, next: ctx1) =
    a.retry_decide(ctx: a.retry_start(policy:, seed: 1), failure: a.Transient)
  assert a.retry_decide(ctx: ctx1, failure: a.Transient)
    == a.GiveUp(reason: a.DelayOverflow(at_attempt: 2))
}
