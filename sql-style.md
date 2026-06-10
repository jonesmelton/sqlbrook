# SQL style conventions (seed spec)

Derived from `examples/*.sql`. Describes the dominant style; outliers noted at the end.

## Core principles

1. **All lowercase.** Keywords, functions, identifiers — everything. No exceptions in the corpus.
2. **River alignment.** Top-level clause keywords are right-aligned to a common
   column, forming a vertical "river" of whitespace after them. Content starts
   one space after the river.

   ```sql
     select size
          , species
       from bugshields
      where end_time is null
   order by ts desc
      limit 1
   ```

   The river column is set by the longest expression occupying the left
   column in the query — in DML that's the longest keyword (`order by`,
   `returning`, `inner join`); in DDL it's the longest column name (with
   glued comma), table name, or table-constraint keyword. Shorter items get
   left-padded to match.
3. **Leading commas**, one expression per line. Commas align in their own
   column under the start of the first item, with one space between comma and
   expression:

   ```sql
   select name
        , alignment
        , burden
   ```
4. **Parameter placeholders**: the corpus uses `:name`, but the formatter
   must handle every form sqlite accepts: `:name`, `@name`, `$name`, `?NNN`,
   and bare `?`.
5. **snake_case** identifiers throughout.
6. **Layout, not semantics.** The formatter arranges whitespace; it does not
   enforce token choices like `=` vs `is`.

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
- Long predicates may break after the column name, with the operator
  (`like`) on a continuation line, further indented. *(Cut from the MVP
  formatter — see Resolved third pass #1; reserved as a future feature.)*

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

## Resolved decisions

1. **Semicolon**: own line indented past the river; if the statement ends
   with a closing paren, paren and `;` share a line across the river (`) ;`).
2. **`values`**: own river-aligned line (bugshield form), open paren taking
   the comma position on the next line (`( :name`).
3. **Insert river**: ends at the right edge of `into`; multi-word verb
   phrases (`insert or replace`) break before `into`.
4. **CTE**: bugshield end-shield form is canonical.
5. **DDL indentation**: one level = blank left-of-river (create-table-skills
   form); nested indentation punted.

## Resolved (2026-06-10, second pass)

1. **River width** = length of the longest left-column expression in the
   query, in both DML and DDL. No extra padding.
2. **DDL closing** conforms to the DML `) ;` rule; the glued `);` in the
   earlier corpus was an oversight.
3. **`=` vs `is`** and similar token choices are out of scope — the
   formatter is layout-only.
4. **Placeholders**: all sqlite forms must be handled (`:name`, `@name`,
   `$name`, `?NNN`, bare `?`).
5. **Statement separation** (resolved 2026-06-10, milestone 2): exactly one
   blank line between statements, no blank lines at the start of a file, one
   trailing newline at the end. Comment lines (`--`) belong to the statement
   they precede. The leading blank in session.sql and the double blank in
   bugshield.sql were oversights, fixed by promotion.

The example corpus has been edited to conform; previously flagged
inconsistencies are fixed.

## Resolved (2026-06-10, third pass — milestone 3 promotion)

1. **Predicate breaking after the column name is cut from the MVP**: each
   condition is emitted whole on one line. The broken forms in `lore.sql`
   and `items.sql` were joined by promotion; the style remains documented
   above as a future feature.
2. **session.sql "current"** used river width 9 (matching the adjacent
   `end` statement's `returning`) though its own longest keyword is
   `order by` (8). Per second-pass #1 (width = longest keyword in the
   query, no extra padding) it was re-promoted at width 8.

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
