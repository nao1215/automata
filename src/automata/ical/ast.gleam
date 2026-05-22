//// Public runtime types for iCalendar (RFC 5545) content lines and their
//// validated component shapes. The parse / encode entry points live in
//// [`automata/ical`](./ical.html). Despite the `ast` suffix, these are
//// the domain types every iCalendar caller needs at runtime —
//// `Parameter`, `ContentLine`, `Component`, etc. — not parser internals.

/// 一つの content line のパラメータ (NAME=VALUE)。
/// NAME は大文字正規化済み。VALUE は囲み quote を剥がした素の値。
pub type Parameter {
  Parameter(name: String, value: String)
}

/// 一つの content line を構造化したもの。
/// name: 大文字正規化済み (例: "DTSTART", "SUMMARY")
/// raw_value: TEXT escape を残したままの値
/// line: 1-origin の論理行番号
pub type RawProperty {
  RawProperty(
    name: String,
    parameters: List(Parameter),
    raw_value: String,
    line: Int,
  )
}

/// BEGIN:X ... END:X の中身。
/// kind は "VEVENT" などの大文字正規化済み文字列。
/// properties は出現順を保持 (round-trip テスト用)。
/// children は VALARM (VEVENT 内) や STANDARD/DAYLIGHT (VTIMEZONE 内) などのネストブロック。
pub type RawComponent {
  RawComponent(
    kind: String,
    properties: List(RawProperty),
    children: List(RawComponent),
    begin_line: Int,
  )
}

/// VCALENDAR ブロックを一個丸ごと表す内部 AST。
pub type RawCalendar {
  RawCalendar(properties: List(RawProperty), components: List(RawComponent))
}
