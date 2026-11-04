# SQLite3 FFI demo — toy blog

A self-contained blog (posts, tags, comments) running on top of
SQLite3 via Spinel's FFI. Demonstrates:

- Open / close a database
- DDL via `sqlite3_exec`
- INSERT with `last_insert_rowid` follow-up
- Many-to-many joins (post_tags)
- SELECT with `prepare_v2` / `step` / `finalize` and `column_int` /
  `column_text`
- `:ptr` out-params (`sqlite3 **`, `sqlite3_stmt **`) read back via
  `ffi_buffer` + `ffi_read_ptr`

## Setup

You need SQLite3 development headers and a linker stub:

```sh
# Debian / Ubuntu / WSL
sudo apt install libsqlite3-dev

# Fedora
sudo dnf install sqlite-devel

# macOS (Homebrew)
brew install sqlite
```

Spinel's `ffi_lib "sqlite3"` becomes `-lsqlite3` at link time, so the
runtime library (`libsqlite3.so`/`.dylib`) needs to be on the loader's
search path.

## Build & run

From the repo root:

```sh
./spinel examples/ffi/sqlite/blog.rb
./blog
```

Expected output:

```
Posts (with comment + tag counts):
  [1] Spinel learns to call C  (2 comments, 3 tags)
  [2] Tasting o'tea  (1 comments, 2 tags)
  [3] Hashes vs SymIntHash  (1 comments, 2 tags)

Posts tagged 'spinel':
  - Spinel learns to call C
  - Hashes vs SymIntHash

Comments on the FFI post:
  alice: Wonderful — does it work with libcurl too?
  bob: I tried sqlite3 myself; the bindings are tidy.
```

## Files

- `sqlite3_lib.rb` — minimal FFI bindings + a `Sql.q` helper that
  escapes single quotes for inline string literals.
- `blog.rb` — the demo program.

## Notes

The demo uses inline-quoted SQL with `Sql.q` for escaping, kept as the
minimal path through `prepare_v2` / `step` / `finalize`. For bound
parameters, `sqlite3_bind_text` is supported directly — pass `-1` as
the destructor argument to get `SQLITE_TRANSIENT` (`(void *)-1`); the
FFI accepts an integer literal in a `:ptr` arg slot and emits
`((void *)-1LL)`. See `sqlite3_lib.rb` for the `ffi_func` declaration
and `test/ffi_ptr_int_literal.rb` for the regression test.
