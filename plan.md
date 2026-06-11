# sqlbrook formatter — plan

## Scope

A whole-statement SQL formatter for the river style defined in `sql-style.md`. SQLite dialect only. Input is one or more statements; output is token-identical, re-laid-out SQL.

**In scope**

- DML: `select`, `insert` (incl. `or replace`), `update`, `delete`, `returning`
- Clause river, leading-comma lists, `as` on its own line
- Insert mirror blocks (`into`-anchored river, `values` on river line)
- CTEs in end-shield form (explicit column list, `) as (`, trailing body paren)
- DDL: `create table`, `create view` (right-aligned names, glued commas, blank-left-of-river continuations)
- Semicolon rules (own line in content column; `) ;` across the river)
- All sqlite placeholders: `:name`, `@name`, `$name`, `?NNN`, `?`

**Out of scope**

- Window-function vertical explosion (`filter`/`over`/`window` as river lines) — select items stay on one line up to the alias
- Predicate breaking after column name — one condition per line, whole
- Nested DDL indentation (`on conflict ignore`) — emit at content column + 1, no general rule
- Any semantic rewriting (`=` vs `is`, case of literals)

**Behavioral decisions**

- Comments: `--` lines pass through unchanged as statement separators; never reflowed
- Unknown constructs (`case`, `union`, `having`, anything unparsed): emit the statement unchanged, warn on stderr — never crash, never mangle
- Subqueries: expression position → always inline; clause position (CTE body) → always expanded. No width measurement
- River width is measured in bytes. Non-ASCII identifiers will misalign visually; accepted limitation (fixing it needs display-width tables, not a different lexer)

## Architecture

Four stages, pure functions between them:

```
string → token list → statement list → layout IR → string
         (lexer)      (skeleton parser)  (measure + emit)
```

1. **Lexer** (`ocamllex`, byte-oriented). Tokens: keyword (from a fixed multi-word-aware list: `order by`, `insert or replace`, `if not exists`, …), identifier, quoted ident/string, number, operator, placeholder, `(` `)` `,` `;`, comment-line. Keywords matched case-insensitively, emitted lowercase. sqlite's structural grammar is ASCII; non-ASCII bytes (≥ `0x80`) occur only inside literals, quoted identifiers, and bare identifiers, all handled on raw bytes (`['\x80'-'\xff']` in the ident class) with UTF-8 passing through untouched.
2. **Skeleton parser** (recursive descent, no menhir). Does *not* parse expressions. Splits at top-level clause keywords tracking paren depth; splits clause bodies at top-level commas; captures paren-balanced spans as opaque expression blobs. Recognizes: trailing `as <name>` on list items, CTE prologue (`with name ( cols ) as (`), insert column/values blocks, DDL column defs (`[,]name type constraints…`).
3. **Layout** — two passes per statement:
   - *Measure*: river width = max byte-length of left-column items (DML keywords; DDL names/table/constraint keywords). Insert statements anchor at the right edge of `into` instead.
   - *Emit*: manual right-padding into a `Buffer`. No `Format` boxes — the river needs exact column control.
4. **CLI**: read stdin or file args, write stdout; `-i` in-place later. Exit nonzero if any statement fell back to passthrough (so it can gate CI eventually).

## Project layout

```
sqlbrook/
  dune-project          (ocaml 5.4; ppx_expect for tests, no runtime deps)
  lib/
    lexer.mll
    token.ml
    skeleton.ml         (statement/clause/item types + parser)
    measure.ml
    emit.ml
    pipeline.ml         (stage glue)
  bin/main.ml
  test/
    dune                (golden diff rules over examples/*.sql)
    test_unit.ml        (ppx_expect inline snapshots + invariants)
```

## Core types

```ocaml
type item = { expr : Token.t list; alias : string option }
type clause = { kw : string; items : item list }       (* kw participates in river *)
type stmt =
  | Dml of { cte : cte option; clauses : clause list; semi : bool }
  | Insert of { verb : string list; table : string;
                cols : string list option; values : item list; tail : clause list }
  | Ddl of { table : string; defs : coldef list }
  | Passthrough of string
```

## Milestones

1. **Lexer + invariants** *(done)* — tokenize all of `examples/`; lexer roundtrip property test.
2. **Statement splitter + passthrough** *(done)* — runs end-to-end, passthrough emits exact source slices via token spans; statements joined by one blank line. Nonzero exit on passthrough deferred to milestone 7.
3. **Core select river** *(done)* — select/from/where/order by/limit, leading commas, `as` lines, semicolon rules, joins + `on`, `and`/`or` river lines (with `between … and` guard). Goldens: `lore.sql`, `items.sql`, `map.sql`, `session.sql` selects.
4. **Insert/update/returning** *(done)* — mirror blocks, `into` anchor, multi-word verb break, optional column list. Goldens: `char.sql`, `vitals.sql` insert, `session.sql`.
5. **CTEs** *(done)* — end-shield form, recursive body layout, inline scalar subqueries. Goldens: `bugshield.sql`, `session.sql` play-log.
6. **DDL** *(done)* — create table/view. Golden: `init.sql`.
7. **CLI polish + idempotence sweep** *(done)* — `fmt (fmt x) = fmt x` over the golden corpus; nonzero exit on passthrough; `--check`/`-w`/`-o`/`--man`, exit-code precedence (2 > 3 > 1 > 0).

Each milestone leaves a working tool (passthrough degrades gracefully); the formatter is usable from milestone 3.

## Test strategy

Everything is string comparison, so snapshot testing throughout:

- **Corpus goldens via dune diff rules**: format each golden input, `diff` against expected output, `dune promote` to accept changes. The conformed `examples/` files are the spec's executable form (output must equal input byte-for-byte).
- **ppx_expect inline snapshots** for unit-level cases: clause layouts, multi-word keyword lexing, passthrough/warning behavior, lexer edge cases (placeholders, quoted identifiers, `\x80`+ bytes).
- **Invariants** (over corpus + scratch inputs): token preservation (`lex (fmt x) = lex x`), idempotence (`fmt (fmt x) = fmt x`).

`vitals.sql` current-vitals and xp-rate are in the out-of-scope window-function style; they are excluded from the golden set and reserved as reference examples.

## Known risks

- Multi-word keyword lexing (`order by`, `insert or replace into`) — handled in the lexer with lookahead; the keyword list is small and closed.
- CTE column list vs body paren disambiguation — covered by `bugshield.sql` goldens.
- Byte-width river measurement misaligns on non-ASCII identifiers — accepted.
