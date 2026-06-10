# sqlbrook formatter — MVP plan

## Scope

A whole-statement SQL formatter for the river style defined in `sql-style.md`. SQLite dialect only. Input is one or more statements; output is token-identical, re-laid-out SQL.

**In scope (MVP)**

- DML: `select`, `insert` (incl. `or replace`), `update`, `delete`, `returning`
- Clause river, leading-comma lists, `as` on its own line
- Insert mirror blocks (`into`-anchored river, `values` on river line)
- CTEs in end-shield form (explicit column list, `) as (`, trailing body paren)
- DDL: `create table`, `create view` (right-aligned names, glued commas, blank-left-of-river continuations)
- Semicolon rules (own line in content column; `) ;` across the river)
- All sqlite placeholders: `:name`, `@name`, `$name`, `?NNN`, `?`

**Cut from MVP (accepted 2026-06-10)**

- Window-function vertical explosion (`filter`/`over`/`window` as river lines) — select items stay on one line up to the alias
- Predicate breaking after column name — one condition per line, whole
- Nested DDL indentation (`on conflict ignore`) — emit at content column + 1, no general rule
- Any semantic rewriting (`=` vs `is`, case of literals)

**Behavioral decisions**

- Comments: `--` lines pass through unchanged as statement separators; never reflowed
- Unknown constructs (`case`, `union`, `having`, anything unparsed): emit the statement unchanged, warn on stderr — never crash, never mangle
- Subqueries: expression position → always inline; clause position (CTE body) → always expanded. No width measurement anywhere in MVP
- River width is measured in bytes. Non-ASCII identifiers will misalign visually; accepted limitation (fixing it needs display-width tables, not a different lexer)

## Architecture

Four stages, pure functions between them:

```
string → token list → statement list → layout IR → string
         (lexer)      (skeleton parser)  (measure + emit)
```

1. **Lexer** (`ocamllex`, byte-oriented). Tokens: keyword (from a fixed multi-word-aware list: `order by`, `insert or replace`, `if not exists`, …), identifier, quoted ident/string, number, operator, placeholder, `(` `)` `,` `;`, comment-line. Keywords matched case-insensitively, emitted lowercase per spec. sedlex was considered and rejected: sqlite's structural grammar is ASCII; non-ASCII bytes (≥ `0x80`) occur only inside literals, quoted identifiers, and bare identifiers, all of which ocamllex handles on raw bytes (`['\x80'-'\xff']` in the ident class) with UTF-8 passing through untouched.
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
  bin/main.ml
  test/
    golden/             (dune diff rules over examples/*.sql)
    test_unit.ml        (ppx_expect inline snapshots + invariants)
```

## Core types (sketch)

```ocaml
type item = { expr : Token.t list; alias : string option }
type clause = { kw : string; items : item list }       (* kw participates in river *)
type stmt =
  | Dml of { cte : cte option; clauses : clause list }
  | Insert of { verb : string list; table : string;
                cols : string list option; values : item list; tail : clause list }
  | Ddl of { table : string; defs : coldef list }
  | Passthrough of Token.t list
```

## Milestones

1. ~~**Lexer + invariants**~~ *(done 2026-06-10)* — tokenize all of `examples/`; property tests: `lex (emit (lex x)) = lex x` once emit exists.
2. ~~**Statement splitter + passthrough**~~ *(done 2026-06-10)* — tool runs end-to-end, output = input (passthrough emits exact source slices via token spans; statements joined by one blank line per spec §Resolved-5). Nonzero exit on passthrough deferred to milestone 7 — it would fail every golden until then.
3. ~~**Core select river**~~ *(done 2026-06-10)* — select/from/where/order by/limit, leading commas, `as` lines, semicolon rules, joins + `on`, `and`/`or` river lines (with `between … and` guard). Golden: `lore.sql`, `items.sql`, `map.sql` (join), `session.sql` selects. Corpus conformed by promotion: predicate breaks joined (cut feature), session.sql "current" river width 9 → 8 per Resolved-2nd-pass #1.
4. **Insert/update/returning** — mirror blocks, `into` anchor, multi-word verb break. Golden: `char.sql`, `vitals.sql` insert-vitals, `session.sql`. *(~1–2 days)*
5. **CTEs** — end-shield form, recursive body layout, inline scalar subqueries. Golden: `bugshield.sql`, `session.sql` play-log. *(~1–2 days)*
6. **DDL** — create table/view. Golden: `init.sql`. *(~1–2 days)*
7. **CLI polish + idempotence sweep** — `fmt (fmt x) = fmt x` over the golden corpus. *(~half day)*

Total: ~7–9 working days. Each milestone leaves a working tool (passthrough degrades gracefully), so the formatter is usable from milestone 3.

## Test strategy

Everything is string comparison, so snapshot testing throughout:

- **Corpus goldens via dune diff rules**: run the formatter over each golden input, `diff` against expected output, `dune promote` to accept changes. Zero test dependencies; the conformed `examples/` files are the spec's executable form (output must equal input byte-for-byte).
- **ppx_expect inline snapshots** for unit-level cases: individual clause layouts, multi-word keyword lexing, passthrough/warning behavior, lexer edge cases (placeholders, quoted identifiers, `\x80`+ bytes).
- **Invariants** (run over corpus + scratch inputs): token preservation (`lex (fmt x) = lex x`), idempotence (`fmt (fmt x) = fmt x`).
- **Negative cases**: a file of unsupported constructs asserting passthrough-with-warning, not mangling.

**Golden-set exception**: `vitals.sql` current-vitals and xp-rate are intentionally left in the cut window-function style. They are excluded from the golden set for MVP and reserved as reference examples for the future window-style feature. The insert-vitals statement in that file is still usable (statement-level golden, or split the file).

## Known risks

- Multi-word keyword lexing (`order by`, `insert or replace into`) — handle in the lexer with lookahead, not the parser; the keyword list is small and closed.
- CTE column list vs body paren disambiguation — directly covered by `bugshield.sql` goldens.
- Byte-width river measurement misaligns on non-ASCII identifiers — accepted for MVP.
