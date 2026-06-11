# sqlbrook

A whole-statement SQL formatter for the "river" style: lowercase everything,
clause keywords right-aligned to a common river column, leading commas, one
expression per line. SQLite dialect only.

The style is specified in [`sql-style.md`](sql-style.md). The conformed files
under `examples/` are the spec's executable form — formatting them is a
byte-for-byte no-op.

## Usage

```sh
sqlbrook file.sql ...     # format files, write to stdout
sqlbrook < file.sql       # or read stdin
sqlbrook -w file.sql ...  # rewrite files in place
sqlbrook -o out.sql *.sql # concatenate formatted output to a file
sqlbrook --check *.sql    # exit 1 if any file isn't already formatted (CI)
```

Run `sqlbrook --help` for the full flag list and exit codes.

Select statements are laid out in full; constructs the formatter does not yet
handle (insert, update, CTEs, DDL) are emitted unchanged, with a warning on
stderr.

## Development

Requires OCaml >= 5.4 and dune; `ppx_expect` for tests. The repo assumes a
local opam switch (`_opam/`). Tasks run through [`just`](https://just.systems):

| recipe | what it does |
| --- | --- |
| `just build` | compile everything |
| `just test` | unit/expect tests, invariants, golden diffs |
| `just promote` | accept current output as the new golden expectation |
| `just watch` | rerun tests on file changes |
| `just fmt [files...]` | run the formatter (stdin if no files) |
| `just clean` | remove build artifacts |

Tests are golden diffs over `examples/*.sql` plus inline `ppx_expect`
snapshots in `test/test_unit.ml`, including two corpus-wide invariants: token
preservation (`lex (fmt x) = lex x`) and idempotence (`fmt (fmt x) = fmt x`).
`examples/vitals.sql` is excluded from the goldens; its window-function
statements use a style outside the current scope.
