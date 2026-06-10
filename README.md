# sqlbrook

A whole-statement SQL formatter for the "river" style: lowercase everything,
clause keywords right-aligned to a common river column, leading commas, one
expression per line. SQLite dialect only.

The style is specified in [`sql-style.md`](sql-style.md); the implementation
plan and milestone status live in [`plan.md`](plan.md). The conformed files
under `examples/` are the spec's executable form — formatting them must be a
byte-for-byte no-op.

**Status:** milestone 2 of 7. The tool runs end-to-end but every statement
currently passes through unchanged (with a warning on stderr). Layout starts
landing with milestone 3 (select river).

## Usage

```sh
sqlbrook file.sql ...   # format files, write to stdout
sqlbrook < file.sql     # or read stdin
```

Statements the formatter doesn't understand are emitted unchanged, never
mangled, with a warning on stderr. In-place editing (`-i`) and a nonzero
exit code for passthrough (CI gating) are planned but not yet wired.

## Development

Requires OCaml >= 5.4 and dune; `ppx_expect` for tests. The repo assumes a
local opam switch (`_opam/`). Tasks are driven by [`just`](https://just.systems):

| recipe | what it does |
| --- | --- |
| `just build` | compile everything |
| `just test` | unit/expect tests, invariants, golden diffs |
| `just promote` | accept current output as the new golden expectation |
| `just watch` | rerun tests on file changes |
| `just fmt [files...]` | run the formatter (stdin if no files) |
| `just clean` | remove build artifacts |

### Test layout

- **Golden corpus** (`test/dune`): each `examples/*.sql` is formatted and
  diffed against itself. `just promote` accepts intentional changes —
  examples are conformed by decree, so a promote is a spec decision and
  should be reflected in `sql-style.md`.
- **Expect tests** (`test/test_unit.ml`): lexer cases, skeleton splitting,
  passthrough behavior, plus two corpus-wide invariants — token preservation
  (`lex (fmt x) = lex x`) and idempotence (`fmt (fmt x) = fmt x`).
- `examples/vitals.sql` is excluded from the goldens: its window-function
  statements deliberately keep a style that is cut from the MVP.
