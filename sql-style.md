# SQL style conventions

The river style, as realized in `examples/*.sql`.

## Core principles

1. Keywords are emitted lowercase but identifiers pass through as written.
2. Top-level clause keywords are right-aligned to a common column, forming a vertical "river" of whitespace after them.
3. 
   ```sql
     select size
          , species
       from bugshields
      where end_time is null
   order by ts desc
      limit 1
   ```

   The river column is set by the longest expression occupying the left
   column in the query.
3. commas align in their own column under the start of the first item, with one space between comma and expression:

   ```sql
   select name
        , alignment
        , burden
   ```
6. The formatter arranges whitespace; it does not enforce token choices like `=` vs `is`.

## Select lists and aliases

- `as` is broken onto its own continuation line, indented so the alias hangs
  under the expression:

  ```sql
  select printf('%-18s', short_name)
      as short_name
       , printf('%-46s', full_name)
      as full_name
  ```
- Complex expressions (window functions, `filter`, `over`) are split across
  lines, with `over`, `filter`, `as`, `window` each starting a line and
  participating in the river:

  ```sql
  select xp
       , min(xp)
  filter (where ts > datetime('now', '-1 hour'))
    over last_hour
      as min_xp
  ```

## Predicates

- One condition per line; `and`/`or` right-aligned into the river:

  ```sql
   where area = :area
     and full_name
           like '%' || :term || '%'
  ```

## Joins

- Explicit join keywords (`inner join`), river-aligned, with `on` on its own
  indented line:

  ```sql
        from rooms r
  inner join maps m
          on r.map_id = m.map_id
  ```
- Table aliases are bare (no `as`), single-letter, prefixing every column
  reference when a join is present.

## Insert statements

- The river column is the right edge of `into`; the table name sits in the
  content column. Column list in parens, one column per line with leading
  commas; the open paren takes the place of the comma on the first line
  (`( capname`). `values` gets its own river-aligned line, and the values
  block mirrors the column block exactly, line for line:

  ```sql
  insert into bugshields
            ( initial_size
            , size
            )
       values
            ( :size
            , :size
            ) returning *
              ;
  ```
- When the verb phrase is longer than `insert` (e.g. `insert or replace`),
  break after it so `into` starts its own river line and the river doesn't
  drift right:

  ```sql
  insert or replace
    into charstate
       ( char_name
       , name
       )
  values
       ( :char_name
       , :name
       ) returning *
         ;
  ```

## CTEs

Canonical form is `bugshield.sql` end-shield:

```sql
     with current
        ( rowid
        , ts
        , end_time
        ) as (
   select rowid
        , ts
        , end_time
     from bugshields
    where end_time is null
 order by ts desc
  limit 1 )
   update bugshields
      set end_time = time('now')
    where rowid = (select rowid from current)
returning *
          ;
```

- `with name` on a river line; the explicit column list uses the same
  leading-comma paren block as inserts, aligned to the statement river.
- `) as (` closes the column list and opens the body on one line.
- The body is river-formatted; its closing paren trails the last line
  (`limit 1 )`).

## Subqueries

A parenthesized `select` — as a derived table in `from`, an `in (...)` /
`exists (...)` predicate operand, or a scalar in the select list — is
formatted by **recursing the river**: the inner query is laid out exactly as
a top-level query, with its own river computed from its own clauses, then the
whole block is shifted right so it nests under the parent.

The rule is uniform across every position a subquery can appear, and there is
no flattening: a subquery **always breaks** onto its own lines, regardless of
length. One algorithm, no width threshold, no special cases.

```sql
  select text
    from (
            select id, text
              from lines
             where type = 'command'
               and character_name = ?
          order by id desc
             limit 500
         )
order by id asc
```

- The clause keyword holding the subquery (`from`, `where ... in`, a select
  item) is emitted normally; the open paren trails it on the same line.
- The inner query starts on the next line. Its river is **independent** —
  computed from the inner query's own longest left-column item — and the
  whole inner block is indented so that river sits to the right of the parent
  content column. The inner query is therefore self-similar: read on its own,
  it is a correctly river-formatted statement.
- The closing paren sits on its own line, left-aligned to the inner query's
  river column.
- Nesting composes: a subquery inside a subquery applies the same rule again,
  each level shifting right relative to its parent.

This is the same mechanism as a CTE body (`) as (` … river-formatted body …
`)`), generalized to any parenthesized select. The only difference is the
CTE's closing paren trails the last body line (`limit 1 )`) for historical
reasons; subqueries put the closing paren on its own line.

## Returning and semicolons

- `returning *` joins the river (it is usually the longest keyword, so it sits
  at the left margin of the statement).
- The terminating `;` goes on its own line, indented past the river into the
  content column:

  ```sql
  returning *
            ;
  ```
- Exception: when the statement ends with a closing paren, the paren and the
  semicolon share a line, on either side of the river:

  ```sql
            ) ;
  ```

## DDL (init.sql)

DDL uses a distinct convention. Canonical form is create-table-skills:

```sql
create table if not exists
   skills (
char_name text
          not null
    ,tree text
          not null
    ,leaf text
  ,levels integer
          not null
   ,bonus integer
          not null
      ,ts datetime
          default current_timestamp
  ,unique (char_name, tree, leaf, bonus)
           on conflict ignore
        ) ;
```

- `create table if not exists` sits alone at the left margin; the table name
  right-aligns to the river on the next line.
- Column *names* are right-aligned to the river (so the type column lines
  up), with the leading comma glued directly to the name. The river width is
  the longest left-column item: column name (with comma), table name, or
  table-constraint keyword (`,primary key`) — whichever is longest.
- One level of indentation is a line with nothing on the left side of the
  river: constraints/defaults sit on lines that are blank up to the river,
  with content in the content column (`not null`, `default ...`).
- `primary key` / `foreign key` / `unique` table constraints join the same
  right-aligned column as the column names.
- Closing follows the DML rule: `) ;` across the river, paren right-aligned
  to the river column.
- Nested indentation (e.g. `on conflict ignore` under `unique`) is punted
  for now.

## Statement separation

- Exactly one blank line between statements; no blank lines at the start of a
  file; one trailing newline at the end.
- Comment lines (`--`) belong to the statement they precede.

## Divergences from Holywell (sqlstyle.guide)

| Topic | Holywell | This style |
|---|---|---|
| Keyword case | UPPERCASE keywords | all lowercase |
| Commas | trailing, end of line | leading, own column |
| `AS` for column aliases | same line as expression | own continuation line below |
| `AS` for table aliases | required (`staff AS s1`) | omitted (`rooms r`) |
| Semicolon | end of last line | own line (usually) |
| River | keywords right-aligned, river after | same concept — this is the main point of agreement |
| DDL | left-aligned names, trailing commas | right-aligned names, glued leading commas |
| Table aliases | meaningful correlations | single letters (`r`, `m`) |
