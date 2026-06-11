# sqlbrook

A whole-statement SQL formatter for my personal variant of the "river" style: lowercase everything, clause keywords right-aligned to a common river column, leading commas, one expression per line. SQLite dialect only.

```sql
  select size
       , species
       , hits
    from bugshields
   where end_time is null
order by ts desc
   limit 1
         ;
```

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

### Exit codes and the stdout/stderr contract

stdout carries only valid formatted SQL (or nothing); all diagnostics go to
stderr. The exit code is the signal to branch on:

| code | meaning |
| --- | --- |
| 0 | all inputs fully formatted / written / checked OK, nothing skipped |
| 1 | `--check` found at least one input that wasn't already formatted |
| 2 | a usage error, or an input that isn't lexable SQLite SQL |
| 3 | some statement passed through unformatted (an unsupported construct) |

The tool is **strict by default**: exit 0 means every statement was fully
formatted. A statement the formatter doesn't implement (insert, update, CTEs,
DDL) is echoed unchanged — so the file stays intact — but the run exits **3** so
a caller can't mistake "skipped it" for "formatted it". The skipped statements
are named on stderr. Precedence when signals combine: a lex/usage error (2)
outranks passthrough (3), which outranks `--check`'s unformatted (1).

Unlexable input (a stray byte, or host-language interpolation that isn't a bind
parameter) is exit 2 with a located message on stderr, never a crash and never
partial output on stdout. Under `-w`, files that fail to lex are left untouched
while the rest are still rewritten.

## Embedded queries

sqlbrook formats the river at column 0 and has no `--indent` option. To keep
queries embedded in host-language source formattable, the project convention is
to put the SQL in a **leading-newline string literal** so the whole statement
starts at column 0:

```js
const q = sql`
  select size
       , species
    from bugshields
   where end_time is null
`;
```

The leading newline is absorbed by the formatter (output is byte-identical to
the bare query), and the trailing delimiter sits on its own line. This means the
agent/CI contract is just **extract the string, run it through sqlbrook, splice
it back verbatim** — no column counting, no per-line re-indentation:

```sh
sqlbrook < query.sql        # format; output already at column 0
```

Use bind parameters (`:name`, `@name`, `$name`, `?`, `?NNN`) rather than
host-language string interpolation. SQLite bind parameters are real SQL tokens:
sqlbrook lexes them as-is and round-trips them untouched, so there is nothing to
substitute. Run `sqlbrook --check` over your extracted queries to enforce the
convention in CI.

## Getting started

```sh
opam switch create . 5.4.0 --no-install   # creates ./_opam
opam install . --deps-only --with-test     # cmdliner, ppx_expect, etc.
dune build
```

Run it directly through dune

```sh
dune exec sqlbrook -- --help
dune exec sqlbrook -- --check examples/lore.sql
```

`dune install` to put `sqlbrook` on your switch's PATH.

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
