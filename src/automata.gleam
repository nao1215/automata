import gleam/list

/// Automaton(state, symbol) represents a deterministic finite
/// automaton: a current state, a transition function, and an
/// acceptance predicate.
pub opaque type Automaton(state, symbol) {
  Automaton(
    initial_state: state,
    transition: fn(state, symbol) -> state,
    accepting: fn(state) -> Bool,
  )
}

/// Construct an automaton from its initial state, transition
/// function, and acceptance predicate.
pub fn new(
  initial_state initial_state: state,
  transition transition: fn(state, symbol) -> state,
  accepting accepting: fn(state) -> Bool,
) -> Automaton(state, symbol) {
  Automaton(
    initial_state: initial_state,
    transition: transition,
    accepting: accepting,
  )
}

/// Return the initial state.
pub fn initial_state(automaton: Automaton(state, symbol)) -> state {
  automaton.initial_state
}

/// Apply one transition from the supplied state using one input
/// symbol.
pub fn step(
  automaton: Automaton(state, symbol),
  state: state,
  symbol: symbol,
) -> state {
  automaton.transition(state, symbol)
}

/// Fold a list of input symbols over the automaton's transition
/// function and return the resulting state.
pub fn run(automaton: Automaton(state, symbol), inputs: List(symbol)) -> state {
  list.fold(inputs, automaton.initial_state, fn(state, symbol) {
    automaton.transition(state, symbol)
  })
}

/// Return True when the automaton accepts the supplied input.
pub fn accepts(
  automaton: Automaton(state, symbol),
  inputs: List(symbol),
) -> Bool {
  automaton.accepting(run(automaton, inputs))
}
