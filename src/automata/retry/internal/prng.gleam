import gleam/int
import gleam/result

/// Deterministic pseudo-random generator state used by the retry
/// module's jitter computations.
///
/// Implementation: 32-bit Xorshift (Marsaglia, 2003) with shift
/// constants `13 / 17 / 5`. Chosen because:
///   * the algorithm uses only XOR and shifts (no 32x32 multiplies),
///     so identical bit patterns are produced on the BEAM and the
///     JavaScript target despite JavaScript's 53-bit Number range;
///   * a single 32-bit state fits comfortably below the 53-bit safe
///     integer ceiling we cap durations at.
///
/// `@internal`: callers should reach the PRNG through `automata/retry`
/// only. This keeps us free to replace the algorithm later without
/// breaking hex-published consumers.
@internal
pub opaque type PrngState {
  PrngState(seed: Int)
}

/// Build a fresh PRNG state from an arbitrary integer seed.
///
/// Negative or out-of-range seeds are accepted and folded into 32 bits.
/// A seed that masks down to zero is replaced with `1` because Xorshift
/// degenerates on a zero state.
@internal
pub fn new(seed seed: Int) -> PrngState {
  case mask32(seed) {
    0 -> PrngState(seed: 1)
    masked -> PrngState(seed: masked)
  }
}

/// Advance the state by one step and return a uniformly distributed
/// 32-bit unsigned value in the range `[0, 2^32 - 1]`.
@internal
pub fn next_u32(state state: PrngState) -> #(Int, PrngState) {
  let x0 = state.seed
  let x1 = mask32(int.bitwise_exclusive_or(x0, int.bitwise_shift_left(x0, 13)))
  let x2 = int.bitwise_exclusive_or(x1, int.bitwise_shift_right(x1, 17))
  let x3 = mask32(int.bitwise_exclusive_or(x2, int.bitwise_shift_left(x2, 5)))
  #(x3, PrngState(seed: x3))
}

/// Advance the state by one step and return an integer in
/// `[0, max_inclusive]`.
///
/// Uses a single 32-bit draw plus modulo: cross-target safe and
/// matches the design requirement that a Decision advances the PRNG
/// by exactly one step regardless of jitter strategy. Modulo bias is
/// negligible for the delays a retry policy yields in practice.
///
/// When `max_inclusive` is non-positive, returns `0` and still
/// advances the state so the call cost is uniform.
@internal
pub fn bounded(
  state state: PrngState,
  max_inclusive max_inclusive: Int,
) -> #(Int, PrngState) {
  let #(raw, next) = next_u32(state: state)
  case max_inclusive <= 0 {
    True -> #(0, next)
    False -> {
      let value =
        int.modulo(raw, by: max_inclusive + 1)
        |> result.unwrap(0)
      #(value, next)
    }
  }
}

fn mask32(value: Int) -> Int {
  int.bitwise_and(value, 0xFFFFFFFF)
}
