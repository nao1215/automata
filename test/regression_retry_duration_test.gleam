import automata as a
import gleam/list
import gleam/time/duration as d
import gleeunit/should

fn pair(seconds, nanoseconds) -> d.Duration {
  d.add(d.seconds(seconds), d.nanoseconds(nanoseconds))
}

fn expect_delay(value: d.Duration, expected: #(Int, Int)) -> Nil {
  let assert Ok(policy) = a.retry_fixed(delay: value, max_attempts: 2)
  let context = a.retry_start(policy: policy, seed: 42)
  let assert a.Retry(delay, next) =
    a.retry_decide(ctx: context, failure: a.Transient)
  d.to_seconds_and_nanoseconds(delay) |> should.equal(expected)
  a.retry_cumulative_delay(ctx: next)
  |> d.to_seconds_and_nanoseconds
  |> should.equal(expected)
  a.retry_current_attempt(ctx: context) |> should.equal(0)
  a.retry_current_attempt(ctx: next) |> should.equal(1)
}

pub fn fixed_accepts_zero_and_whole_millisecond_boundaries_test() {
  list.each(
    [
      #(0, 0),
      #(0, 1_000_000),
      #(9_007_199_254_740, 990_000_000),
      #(9_007_199_254_740, 991_000_000),
    ],
    fn(expected) { expect_delay(pair(expected.0, expected.1), expected) },
  )
}

pub fn negative_nanosecond_reports_normalized_pair_test() {
  a.retry_fixed(delay: d.nanoseconds(-1), max_attempts: 2)
  |> should.equal(Error(a.NegativeDuration(-1, 999_999_999)))
}

pub fn fractional_milliseconds_are_not_truncated_test() {
  list.each([1, 999_999], fn(nanos) {
    a.retry_fixed(delay: d.nanoseconds(nanos), max_attempts: 2)
    |> should.equal(Error(a.FractionalMilliseconds(0, nanos)))
  })
}

pub fn max_milliseconds_plus_one_nanosecond_is_fractional_first_test() {
  a.retry_fixed(delay: pair(9_007_199_254_740, 991_000_001), max_attempts: 2)
  |> should.equal(
    Error(a.FractionalMilliseconds(9_007_199_254_740, 991_000_001)),
  )
}

pub fn whole_milliseconds_above_max_are_overflow_test() {
  a.retry_fixed(delay: pair(9_007_199_254_740, 992_000_000), max_attempts: 2)
  |> should.equal(Error(a.DurationOverflow(9_007_199_254_740, 992_000_000)))
  a.retry_fixed(delay: d.seconds(9_007_199_254_740_991), max_attempts: 2)
  |> should.equal(Error(a.DurationOverflow(9_007_199_254_740_991, 0)))
}

pub fn fixed_checks_attempts_before_duration_admission_test() {
  a.retry_fixed(delay: d.nanoseconds(-1), max_attempts: 0)
  |> should.equal(Error(a.MaxAttemptsMustBePositive(0)))
}

pub fn exponential_admission_precedes_other_arguments_test() {
  a.retry_exponential(
    initial: d.nanoseconds(-1),
    multiplier: 1,
    max_attempts: 0,
  )
  |> should.equal(Error(a.NegativeDuration(-1, 999_999_999)))
  a.retry_exponential(initial: d.nanoseconds(1), multiplier: 1, max_attempts: 0)
  |> should.equal(Error(a.FractionalMilliseconds(0, 1)))
}

pub fn exponential_zero_precedes_multiplier_and_attempts_test() {
  a.retry_exponential(initial: d.seconds(0), multiplier: 1, max_attempts: 0)
  |> should.equal(Error(a.InitialDelayMustBePositive(0)))
}

pub fn exponential_multiplier_precedes_attempts_test() {
  a.retry_exponential(
    initial: d.milliseconds(1),
    multiplier: 1,
    max_attempts: 0,
  )
  |> should.equal(Error(a.MultiplierMustBeAtLeastTwo(1)))
  a.retry_exponential(
    initial: d.milliseconds(1),
    multiplier: 2,
    max_attempts: 0,
  )
  |> should.equal(Error(a.MaxAttemptsMustBePositive(0)))
}

pub fn capped_initial_admission_precedes_cap_admission_test() {
  a.retry_capped_exponential(
    initial: d.nanoseconds(-1),
    multiplier: 1,
    cap: d.nanoseconds(1),
    max_attempts: 0,
  )
  |> should.equal(Error(a.NegativeDuration(-1, 999_999_999)))
}

pub fn capped_cap_admission_precedes_zero_initial_test() {
  a.retry_capped_exponential(
    initial: d.seconds(0),
    multiplier: 1,
    cap: d.nanoseconds(-1),
    max_attempts: 0,
  )
  |> should.equal(Error(a.NegativeDuration(-1, 999_999_999)))
  a.retry_capped_exponential(
    initial: d.seconds(0),
    multiplier: 1,
    cap: d.nanoseconds(1),
    max_attempts: 0,
  )
  |> should.equal(Error(a.FractionalMilliseconds(0, 1)))
}

pub fn capped_zero_multiplier_attempts_and_cap_order_test() {
  a.retry_capped_exponential(
    initial: d.seconds(0),
    multiplier: 1,
    cap: d.seconds(0),
    max_attempts: 0,
  )
  |> should.equal(Error(a.InitialDelayMustBePositive(0)))
  a.retry_capped_exponential(
    initial: d.milliseconds(2),
    multiplier: 1,
    cap: d.milliseconds(1),
    max_attempts: 0,
  )
  |> should.equal(Error(a.MultiplierMustBeAtLeastTwo(1)))
  a.retry_capped_exponential(
    initial: d.milliseconds(2),
    multiplier: 2,
    cap: d.milliseconds(1),
    max_attempts: 0,
  )
  |> should.equal(Error(a.MaxAttemptsMustBePositive(0)))
  a.retry_capped_exponential(
    initial: d.milliseconds(2),
    multiplier: 2,
    cap: d.milliseconds(1),
    max_attempts: 2,
  )
  |> should.equal(Error(a.CapMustNotBeLessThanInitial(1, 2)))
}
