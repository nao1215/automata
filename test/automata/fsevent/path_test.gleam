import automata/fsevent/ast.{
  EmptyPath, PathContainsDotSegment, PathContainsNullByte, UncPathNotSupported,
}
import automata/fsevent/path
import gleeunit/should

fn ok(input: String) {
  let assert Ok(value) = path.normalize(path: input)
  value
}

pub fn normalize_empty_returns_error_test() {
  path.normalize(path: "") |> should.equal(Error(EmptyPath))
}

pub fn normalize_root_slash_returns_root_test() {
  let p = ok("/")
  path.path_to_string(p) |> should.equal("/")
  path.path_segments(p) |> should.equal([])
  path.path_is_absolute(p) |> should.equal(True)
}

pub fn normalize_relative_single_segment_test() {
  let p = ok("foo")
  path.path_to_string(p) |> should.equal("foo")
  path.path_segments(p) |> should.equal(["foo"])
  path.path_is_absolute(p) |> should.equal(False)
}

pub fn normalize_absolute_multi_segment_test() {
  let p = ok("/foo/bar/baz")
  path.path_to_string(p) |> should.equal("/foo/bar/baz")
  path.path_segments(p) |> should.equal(["foo", "bar", "baz"])
  path.path_is_absolute(p) |> should.equal(True)
}

pub fn normalize_backslash_to_forward_slash_test() {
  let p = ok("foo\\bar\\baz")
  path.path_to_string(p) |> should.equal("foo/bar/baz")
  path.path_segments(p) |> should.equal(["foo", "bar", "baz"])
}

pub fn normalize_consecutive_slashes_collapsed_test() {
  let p = ok("/foo//bar///baz")
  path.path_to_string(p) |> should.equal("/foo/bar/baz")
}

pub fn normalize_trailing_slash_removed_test() {
  let p = ok("/foo/bar/")
  path.path_to_string(p) |> should.equal("/foo/bar")
}

pub fn normalize_dot_segment_rejected_test() {
  case path.normalize(path: "/foo/.") {
    Error(PathContainsDotSegment(_, ".")) -> Nil
    _ -> should.fail()
  }
}

pub fn normalize_dotdot_segment_rejected_test() {
  case path.normalize(path: "/foo/..") {
    Error(PathContainsDotSegment(_, "..")) -> Nil
    _ -> should.fail()
  }
}

pub fn normalize_dot_alone_rejected_test() {
  case path.normalize(path: ".") {
    Error(PathContainsDotSegment(_, ".")) -> Nil
    _ -> should.fail()
  }
}

pub fn normalize_null_byte_rejected_test() {
  case path.normalize(path: "foo\u{0000}bar") {
    Error(PathContainsNullByte(_)) -> Nil
    _ -> should.fail()
  }
}

pub fn normalize_drive_letter_test() {
  let p = ok("C:\\Users\\Public")
  path.path_to_string(p) |> should.equal("C:/Users/Public")
  path.path_segments(p) |> should.equal(["C:", "Users", "Public"])
  path.path_is_absolute(p) |> should.equal(True)
}

pub fn normalize_lowercase_drive_letter_is_absolute_test() {
  let p = ok("c:/temp")
  path.path_is_absolute(p) |> should.equal(True)
}

pub fn normalize_non_drive_letter_first_segment_is_relative_test() {
  // "1:foo" looks like a drive letter but the prefix is not a letter,
  // so the path stays relative.
  let p = ok("1:foo")
  path.path_is_absolute(p) |> should.equal(False)
}

pub fn normalize_relative_path_is_not_absolute_test() {
  let p = ok("foo/bar")
  path.path_is_absolute(p) |> should.equal(False)
}

pub fn normalize_rejects_forward_slash_unc_path_test() {
  case path.normalize(path: "//server/share") {
    Error(UncPathNotSupported(path: "//server/share")) -> Nil
    _ -> should.fail()
  }
}

pub fn normalize_rejects_backslash_unc_path_test() {
  case path.normalize(path: "\\\\srv\\share\\dir") {
    Error(UncPathNotSupported(path: "\\\\srv\\share\\dir")) -> Nil
    _ -> should.fail()
  }
}

pub fn normalize_rejects_double_slash_only_test() {
  case path.normalize(path: "//") {
    Error(UncPathNotSupported(path: "//")) -> Nil
    _ -> should.fail()
  }
}

pub fn normalize_collapses_triple_slash_to_root_test() {
  let p = ok("///a/b")
  path.path_to_string(p) |> should.equal("/a/b")
  path.path_is_absolute(p) |> should.equal(True)
}

pub fn normalize_idempotent_on_clean_input_test() {
  let p1 = ok("/var/log/app.log")
  let p2 = ok(path.path_to_string(p1))
  path.path_equals(p1, p2) |> should.equal(True)
}

pub fn path_starts_with_self_is_true_test() {
  let p = ok("/var/log")
  path.path_starts_with(path: p, prefix: p) |> should.equal(True)
}

pub fn path_starts_with_proper_prefix_is_true_test() {
  let parent = ok("/var/log")
  let child = ok("/var/log/app/x.log")
  path.path_starts_with(path: child, prefix: parent) |> should.equal(True)
}

pub fn path_starts_with_segment_boundary_test() {
  // "/var/lo" must NOT be a prefix of "/var/log".
  let prefix = ok("/var/lo")
  let path_value = ok("/var/log")
  path.path_starts_with(path: path_value, prefix: prefix) |> should.equal(False)
}

pub fn path_starts_with_unrelated_test() {
  let prefix = ok("/etc")
  let p = ok("/var/log")
  path.path_starts_with(path: p, prefix: prefix) |> should.equal(False)
}

pub fn path_starts_with_absolute_vs_relative_test() {
  let absolute = ok("/foo")
  let relative = ok("foo")
  path.path_starts_with(path: absolute, prefix: relative) |> should.equal(False)
  path.path_starts_with(path: relative, prefix: absolute) |> should.equal(False)
}

pub fn path_equals_is_canonical_test() {
  let a = ok("/foo//bar/")
  let b = ok("/foo/bar")
  path.path_equals(a, b) |> should.equal(True)
}
