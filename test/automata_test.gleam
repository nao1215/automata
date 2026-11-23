import automata as a
import gleeunit
import gleeunit/should

pub fn main() -> Nil {
  gleeunit.main()
}

type Parity {
  Even
  Odd
}

fn parity_machine() -> a.Automaton(Parity, Int) {
  a.Automaton(
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
  initial_state(parity_machine()) |> should.equal(Even)
}

pub fn step_test() {
  let machine = parity_machine()

  transition(machine, Even, 1) |> should.equal(Odd)
  transition(machine, Odd, 1) |> should.equal(Even)
  transition(machine, Even, 0) |> should.equal(Even)
}

pub fn run_test() {
  let machine = parity_machine()

  a.run(machine, [1, 0, 1, 1]) |> should.equal(Odd)
  a.run(machine, [1, 1, 0, 0]) |> should.equal(Even)
}

pub fn accepts_test() {
  let machine = parity_machine()

  a.accepts(machine, []) |> should.equal(True)
  a.accepts(machine, [1]) |> should.equal(False)
  a.accepts(machine, [1, 1, 0, 0]) |> should.equal(True)
}

fn initial_state(machine: a.Automaton(state, symbol)) -> state {
  machine.initial_state
}

fn transition(
  machine: a.Automaton(state, symbol),
  state: state,
  symbol: symbol,
) -> state {
  machine.transition(state, symbol)
}
