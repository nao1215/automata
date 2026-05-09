import automata
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

type Parity {
  Even
  Odd
}

fn parity_machine() -> automata.Automaton(Parity, Int) {
  automata.new(
    initial_state: Even,
    transition: fn(state, symbol) {
      case state, symbol {
        Even, 1 -> Odd
        Odd, 1 -> Even
        _, _ -> state
      }
    },
    accepting: fn(state) { state == Even },
  )
}

pub fn initial_state_test() {
  automata.initial_state(parity_machine()) |> should.equal(Even)
}

pub fn step_test() {
  let machine = parity_machine()

  automata.step(machine, Even, 1) |> should.equal(Odd)
  automata.step(machine, Odd, 1) |> should.equal(Even)
  automata.step(machine, Even, 0) |> should.equal(Even)
}

pub fn run_test() {
  let machine = parity_machine()

  automata.run(machine, [1, 0, 1, 1]) |> should.equal(Odd)
  automata.run(machine, [1, 1, 0, 0]) |> should.equal(Even)
}

pub fn accepts_test() {
  let machine = parity_machine()

  automata.accepts(machine, []) |> should.equal(True)
  automata.accepts(machine, [1]) |> should.equal(False)
  automata.accepts(machine, [1, 1, 0, 0]) |> should.equal(True)
}
