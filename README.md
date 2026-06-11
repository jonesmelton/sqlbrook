# sqlbrook

A whole-statement SQL formatter for my personal variant of the "river" style: lowercase everything, clause keywords right-aligned to a common river column, leading commas, one expression per line. SQLite dialect only.

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

## Getting started

Requires OCaml >= 5.4. From a fresh clone, create a local switch and pull in
the dependencies:

```sh
opam switch create . 5.4.0 --no-install   # creates ./_opam
opam install . --deps-only --with-test     # cmdliner, ppx_expect, etc.
dune build
```

Run it directly through dune (note the `--` separating dune's args from the
program's):

```sh
dune exec sqlbrook -- --help
dune exec sqlbrook -- --check examples/lore.sql
```

Or invoke the built binary at `_build/default/bin/main.exe`, or `dune install`
to put `sqlbrook` on your switch's PATH.

## Development

Tasks run through [`just`](https://just.systems) (optional — each recipe is a
thin wrapper over `dune`):

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
