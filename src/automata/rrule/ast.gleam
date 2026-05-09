pub type RawRulePart {
  RawRulePart(name: String, value: String)
}

pub type RawRRule {
  RawRRule(parts: List(RawRulePart))
}
