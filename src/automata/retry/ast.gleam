import gleam/int

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
/// Kept as a regular sum (not opaque) so that `automata/retry` can
/// dispatch on it. New strategies (for example a bounded-percentage
/// jitter) would be additive and require existing pattern matches to
/// be exhaustive again.
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

/// Internal back door used by `automata/retry` to wrap freshly
/// computed integer milliseconds without re-running the public
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
