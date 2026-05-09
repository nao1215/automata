import automata/retry/internal/prng
import gleeunit/should

const u32_ceiling = 4_294_967_295

pub fn next_u32_is_within_unsigned_32_bit_range_test() {
  let state = prng.new(seed: 1)
  let #(value, _) = prng.next_u32(state: state)

  { value >= 0 } |> should.equal(True)
  { value <= u32_ceiling } |> should.equal(True)
}

pub fn next_u32_advances_state_test() {
  let state0 = prng.new(seed: 12_345)
  let #(_, state1) = prng.next_u32(state: state0)
  let #(a, _) = prng.next_u32(state: state0)
  let #(b, _) = prng.next_u32(state: state1)

  { a == b } |> should.equal(False)
}

pub fn same_seed_yields_same_sequence_test() {
  let s1 = prng.new(seed: 42)
  let s2 = prng.new(seed: 42)

  let #(a1, s1b) = prng.next_u32(state: s1)
  let #(a2, s2b) = prng.next_u32(state: s2)
  a1 |> should.equal(a2)

  let #(b1, _) = prng.next_u32(state: s1b)
  let #(b2, _) = prng.next_u32(state: s2b)
  b1 |> should.equal(b2)
}

pub fn zero_seed_is_normalised_to_one_test() {
  let zero_state = prng.new(seed: 0)
  let one_state = prng.new(seed: 1)

  let #(a, _) = prng.next_u32(state: zero_state)
  let #(b, _) = prng.next_u32(state: one_state)
  a |> should.equal(b)
}

pub fn negative_seed_is_folded_into_32_bits_test() {
  let state = prng.new(seed: -1)
  let #(value, _) = prng.next_u32(state: state)

  { value >= 0 } |> should.equal(True)
  { value <= u32_ceiling } |> should.equal(True)
}

pub fn bounded_returns_zero_when_max_is_zero_test() {
  let state = prng.new(seed: 7)
  let #(value, _) = prng.bounded(state: state, max_inclusive: 0)
  value |> should.equal(0)
}

pub fn bounded_returns_zero_when_max_is_negative_test() {
  let state = prng.new(seed: 7)
  let #(value, _) = prng.bounded(state: state, max_inclusive: -5)
  value |> should.equal(0)
}

pub fn bounded_stays_within_range_test() {
  draw_n(prng.new(seed: 999), 100, 50, [])
  |> should.equal(True)
}

fn draw_n(
  state: prng.PrngState,
  remaining: Int,
  bound: Int,
  acc: List(Int),
) -> Bool {
  case remaining <= 0 {
    True -> all_within(acc, bound)
    False -> {
      let #(value, next) = prng.bounded(state: state, max_inclusive: bound)
      draw_n(next, remaining - 1, bound, [value, ..acc])
    }
  }
}

fn all_within(values: List(Int), bound: Int) -> Bool {
  case values {
    [] -> True
    [head, ..tail] ->
      case head >= 0 && head <= bound {
        True -> all_within(tail, bound)
        False -> False
      }
  }
}

pub fn bounded_is_deterministic_for_same_seed_test() {
  let s1 = prng.new(seed: 2026)
  let s2 = prng.new(seed: 2026)

  let #(a, _) = prng.bounded(state: s1, max_inclusive: 1000)
  let #(b, _) = prng.bounded(state: s2, max_inclusive: 1000)
  a |> should.equal(b)
}
