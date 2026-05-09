import automata/fsnotify/ast.{
  Directory, EmptyOptionalField, EntryFieldOverflow, File, NegativeEntryField,
  Symlink,
}
import automata/fsnotify/entry
import automata/fsnotify/path
import gleam/option.{None, Some}
import gleeunit/should

const max_safe_int: Int = 9_007_199_254_740_991

fn p(s: String) {
  let assert Ok(value) = path.normalize(path: s)
  value
}

pub fn entry_file_with_valid_inputs_test() {
  let assert Ok(e) =
    entry.entry_file(
      path: p("/var/log/app.log"),
      size: 1024,
      mtime: 1_700_000_000,
      mode: 0o644,
      content_hash: Some("deadbeef"),
      file_id: Some("inode-1"),
    )
  entry.entry_kind(entry: e) |> should.equal(File)
  entry.entry_size(entry: e) |> should.equal(1024)
  entry.entry_mtime(entry: e) |> should.equal(1_700_000_000)
  entry.entry_mode(entry: e) |> should.equal(0o644)
  entry.entry_content_hash(entry: e) |> should.equal(Some("deadbeef"))
  entry.entry_file_id(entry: e) |> should.equal(Some("inode-1"))
}

pub fn entry_file_zero_size_allowed_test() {
  let assert Ok(_) =
    entry.entry_file(
      path: p("/tmp/empty"),
      size: 0,
      mtime: 1,
      mode: 0,
      content_hash: None,
      file_id: None,
    )
}

pub fn entry_file_negative_size_rejected_test() {
  case
    entry.entry_file(
      path: p("/tmp/x"),
      size: -1,
      mtime: 0,
      mode: 0,
      content_hash: None,
      file_id: None,
    )
  {
    Error(NegativeEntryField(field: "size", actual: -1)) -> Nil
    _ -> should.fail()
  }
}

pub fn entry_file_negative_mtime_rejected_test() {
  case
    entry.entry_file(
      path: p("/tmp/x"),
      size: 0,
      mtime: -1,
      mode: 0,
      content_hash: None,
      file_id: None,
    )
  {
    Error(NegativeEntryField(field: "mtime", actual: -1)) -> Nil
    _ -> should.fail()
  }
}

pub fn entry_file_size_overflow_rejected_test() {
  let too_big = max_safe_int + 1
  case
    entry.entry_file(
      path: p("/tmp/x"),
      size: too_big,
      mtime: 0,
      mode: 0,
      content_hash: None,
      file_id: None,
    )
  {
    Error(EntryFieldOverflow(field: "size", actual: _)) -> Nil
    _ -> should.fail()
  }
}

pub fn entry_file_mtime_overflow_rejected_test() {
  let too_big = max_safe_int + 1
  case
    entry.entry_file(
      path: p("/tmp/x"),
      size: 0,
      mtime: too_big,
      mode: 0,
      content_hash: None,
      file_id: None,
    )
  {
    Error(EntryFieldOverflow(field: "mtime", actual: _)) -> Nil
    _ -> should.fail()
  }
}

pub fn entry_file_size_at_max_safe_int_allowed_test() {
  let assert Ok(_) =
    entry.entry_file(
      path: p("/tmp/x"),
      size: max_safe_int,
      mtime: max_safe_int,
      mode: 0,
      content_hash: None,
      file_id: None,
    )
}

pub fn entry_file_empty_hash_rejected_test() {
  case
    entry.entry_file(
      path: p("/tmp/x"),
      size: 0,
      mtime: 0,
      mode: 0,
      content_hash: Some(""),
      file_id: None,
    )
  {
    Error(EmptyOptionalField(field: "content_hash")) -> Nil
    _ -> should.fail()
  }
}

pub fn entry_file_empty_file_id_rejected_test() {
  case
    entry.entry_file(
      path: p("/tmp/x"),
      size: 0,
      mtime: 0,
      mode: 0,
      content_hash: None,
      file_id: Some(""),
    )
  {
    Error(EmptyOptionalField(field: "file_id")) -> Nil
    _ -> should.fail()
  }
}

pub fn entry_directory_no_size_field_test() {
  let assert Ok(e) =
    entry.entry_directory(
      path: p("/var/log"),
      mtime: 1,
      mode: 0o755,
      file_id: Some("dir-inode"),
    )
  entry.entry_kind(entry: e) |> should.equal(Directory)
  // Directories never carry a size; differ ignores it.
  entry.entry_size(entry: e) |> should.equal(0)
  entry.entry_content_hash(entry: e) |> should.equal(None)
}

pub fn entry_symlink_round_trip_test() {
  let assert Ok(e) =
    entry.entry_symlink(
      path: p("/usr/bin/python"),
      mtime: 1,
      mode: 0o777,
      file_id: None,
    )
  entry.entry_kind(entry: e) |> should.equal(Symlink)
  entry.entry_size(entry: e) |> should.equal(0)
}

pub fn entry_directory_negative_mtime_rejected_test() {
  case
    entry.entry_directory(
      path: p("/var/log"),
      mtime: -1,
      mode: 0,
      file_id: None,
    )
  {
    Error(NegativeEntryField(field: "mtime", actual: -1)) -> Nil
    _ -> should.fail()
  }
}
