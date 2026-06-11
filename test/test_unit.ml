open Sqlbrook

let describe = function
  | Token.Keyword s -> "kw    " ^ s
  | Token.Ident s -> "id    " ^ s
  | Token.Quoted s -> "quot  " ^ s
  | Token.Number s -> "num   " ^ s
  | Token.Operator s -> "op    " ^ s
  | Token.Placeholder s -> "ph    " ^ s
  | Token.LParen -> "lparen"
  | Token.RParen -> "rparen"
  | Token.Comma -> "comma"
  | Token.Semicolon -> "semi"
  | Token.Comment s -> "comm  " ^ s
;;

let show s = List.iter (fun t -> print_endline (describe t)) (Lexer.tokens_of_string s)

(* Flat token text, newline after comments so a comment never swallows the
   following tokens. Used by the lexer-roundtrip invariant. *)
let render toks =
  let buf = Buffer.create 256 in
  List.iter
    (fun t ->
       Buffer.add_string buf (Token.to_string t);
       Buffer.add_char
         buf
         (match t with
          | Token.Comment _ -> '\n'
          | _ -> ' '))
    toks;
  Buffer.contents buf
;;

let%expect_test "lexer: multi-word keyword normalization" =
  show "SELECT x FROM t ORDER  BY y DESC";
  [%expect
    {|
    kw    select
    id    x
    kw    from
    id    t
    kw    order by
    id    y
    kw    desc
    |}];
  show "insert OR replace into t values (1) on conflict ignore";
  [%expect
    {|
    kw    insert or replace
    kw    into
    id    t
    kw    values
    lparen
    num   1
    rparen
    kw    on conflict
    id    ignore
    |}];
  show "create table if not exists s.t (k integer primary key)";
  [%expect
    {|
    kw    create table
    kw    if not exists
    id    s.t
    lparen
    id    k
    id    integer
    kw    primary key
    rparen
    |}];
  (* phrase prefix without the full phrase falls back to single-word rules *)
  show "select \"order\" from orders inner join lines on a.id = b.id";
  [%expect
    {|
    kw    select
    quot  "order"
    kw    from
    id    orders
    kw    inner join
    id    lines
    kw    on
    id    a.id
    op    =
    id    b.id
    |}]
;;

let%expect_test "lexer: placeholder forms (:name @name $name ?NNN ?)" =
  show "select :name, @name, $name, ?17, ? from t";
  [%expect
    {|
    kw    select
    ph    :name
    comma
    ph    @name
    comma
    ph    $name
    comma
    ph    ?17
    comma
    ph    ?
    kw    from
    id    t
    |}]
;;

let%expect_test "lexer: quoted identifiers and non-ascii bytes pass through" =
  show
    "select 'caf\xc3\xa9 ''quoted''', \"tabl\xc3\xa9\", `tick`, [bracket], \
     r\xc3\xa9sum\xc3\xa9 from t";
  [%expect
    {|
    kw    select
    quot  'café ''quoted'''
    comma
    quot  "tablé"
    comma
    quot  `tick`
    comma
    quot  [bracket]
    comma
    id    résumé
    kw    from
    id    t
    |}]
;;

let%expect_test "lexer: comments, operators, numbers" =
  show
    "--name: find\n\
     select a || '%', 1.5, 0x1f, .5 from t where a <> b and c >= 2 - 1\n\
     -- trailing";
  [%expect
    {|
    comm  --name: find
    kw    select
    id    a
    op    ||
    quot  '%'
    comma
    num   1.5
    comma
    num   0x1f
    comma
    num   .5
    kw    from
    id    t
    kw    where
    id    a
    op    <>
    id    b
    kw    and
    id    c
    op    >=
    num   2
    op    -
    num   1
    comm  -- trailing
    |}]
;;

(* Re-lexing the flat rendering of the token stream reproduces it. *)
let%expect_test "invariant: lexer roundtrip over examples corpus" =
  let dir = "../examples" in
  Sys.readdir dir
  |> Array.to_list
  |> List.sort compare
  |> List.iter (fun f ->
    if Filename.check_suffix f ".sql"
    then (
      let ic = open_in_bin (Filename.concat dir f) in
      let src = really_input_string ic (in_channel_length ic) in
      close_in ic;
      let toks = Lexer.tokens_of_string src in
      let toks' = Lexer.tokens_of_string (render toks) in
      let ok =
        List.length toks = List.length toks' && List.for_all2 Token.equal toks toks'
      in
      Printf.printf
        "%-15s %4d tokens  roundtrip %s\n"
        f
        (List.length toks)
        (if ok then "ok" else "FAILED")));
  [%expect
    {|
    bugshield.sql    215 tokens  roundtrip ok
    char.sql          28 tokens  roundtrip ok
    init.sql         285 tokens  roundtrip ok
    items.sql         16 tokens  roundtrip ok
    lore.sql          54 tokens  roundtrip ok
    map.sql           31 tokens  roundtrip ok
    session.sql      153 tokens  roundtrip ok
    vitals.sql       320 tokens  roundtrip ok
    |}]
;;

let show_stmts src =
  Skeleton.parse src (Lexer.tokens_with_spans src)
  |> List.iter (fun (p : Skeleton.parsed) ->
    match p.stmt with
    | Skeleton.Passthrough { source; _ } -> Printf.printf "passthrough %S\n" source
    | _ -> print_endline "parsed")
;;

let%expect_test "skeleton: statements split at top-level semicolons" =
  show_stmts "select 1;\n\nselect (2);";
  [%expect
    {|
    parsed
    parsed
    |}];
  (* a semicolon inside parens is not a boundary; a missing final semicolon
     still closes the last statement *)
  show_stmts "select f(';') ; select 2";
  [%expect
    {|
    parsed
    parsed
    |}];
  (* comments attach to the following statement; a trailing comment forms its
     own chunk *)
  show_stmts "--name: a\nselect 1;\n-- tail";
  [%expect
    {|
    parsed
    passthrough "-- tail"
    |}];
  show_stmts "";
  [%expect {| |}]
;;

(* Unwrap a format expected to succeed; the lex-error path has its own test. *)
let ok src =
  match Pipeline.format src with
  | Ok r -> r
  | Error msg -> failwith ("unexpected lex error: " ^ msg)
;;

let fmt src = print_string (ok src).output

let%expect_test "emit: select river layout" =
  (* river width from the longest clause keyword; leading commas; semicolon
     on its own line in the content column *)
  fmt "select a, b, c from t where x = 1 order by ts desc limit 1;";
  [%expect
    {|
    select a
         , b
         , c
      from t
     where x = 1
  order by ts desc
     limit 1
           ;
    |}];
  (* no trailing semicolon in, none out *)
  fmt "select a from t";
  [%expect
    {|
    select a
      from t
    |}]
;;

(* Embedded-query convention: queries live in a leading-newline string literal
   (sql`\n...`) so the river sits at column 0 and the agent never re-indents.
   The leading newline must be absorbed — output identical to the bare query —
   and the result must itself start at column 0. *)
let%expect_test "emit: leading newline absorbed (embedded-query convention)" =
  let bare = (ok "select a, b from t where x = :x;").output in
  let lead = (ok "\nselect a, b from t where x = :x;\n").output in
  Printf.printf "identical %b\n" (String.equal bare lead);
  Printf.printf "starts at col 0 %b\n" (String.length lead > 0 && lead.[0] <> ' ');
  [%expect
    {|
    identical true
    starts at col 0 true
    |}]
;;

let%expect_test "emit: as on its own line, river-aligned" =
  fmt "select printf('%-18s', short_name) as short_name, full_name as f from t;";
  [%expect
    {|
    select printf('%-18s', short_name)
        as short_name
         , full_name
        as f
      from t
           ;
    |}]
;;

let%expect_test "emit: predicates one per line, and/or in the river" =
  fmt "select a from t where x = :x and y like '%' || :term || '%' or z is not null;";
  [%expect
    {|
    select a
      from t
     where x = :x
       and y like '%' || :term || '%'
        or z is not null
           ;
    |}];
  (* the `and` belonging to a depth-0 `between` does not split *)
  fmt "select a from t where x between 1 and 2 and y = 3;";
  [%expect
    {|
    select a
      from t
     where x between 1 and 2
       and y = 3
           ;
    |}]
;;

let%expect_test "emit: having joins the river, and/or split like where" =
  fmt
    "select user_id, count(*) as n from events group by user_id having count(*) > 5 and \
     sum(amount) < 100;";
  [%expect
    {|
      select user_id
           , count(*)
          as n
        from events
    group by user_id
      having count(*) > 5
         and sum(amount) < 100
             ;
    |}]
;;

let%expect_test "emit: joins set the river, on gets its own line" =
  fmt
    "select r.room_id, m.filename from rooms r inner join maps m on r.map_id = m.map_id \
     where r.room_id = :room_id;";
  [%expect
    {|
        select r.room_id
             , m.filename
          from rooms r
    inner join maps m
            on r.map_id = m.map_id
         where r.room_id = :room_id
               ;
    |}]
;;

let%expect_test "emit: subquery recurses the river (golden: history query)" =
  fmt
    "select text from (select id, text from lines where type = 'command' and \
     character_name = ? order by id desc limit 500) order by id asc";
  [%expect
    {|
      select text
        from (
                select id
                     , text
                  from lines
                 where type = 'command'
                   and character_name = ?
              order by id desc
                 limit 500
             )
    order by id asc
    |}]
;;

let%expect_test "emit: scalar subqueries in the select list keep their aliases" =
  fmt
    "select (select count(*) from sessions) as total, (select count(*) from sessions \
     where ts > :since) as recent;";
  [%expect
    {|
    select (
            select count(*)
              from sessions
           )
        as total
         , (
            select count(*)
              from sessions
             where ts > :since
           )
        as recent
           ;
    |}]
;;

let%expect_test "emit: nested subqueries shift right level by level" =
  fmt "select a from (select a from (select a, b from t where b > 1) where a < 5)";
  [%expect
    {|
    select a
      from (
            select a
              from (
                    select a
                         , b
                      from t
                     where b > 1
                   )
             where a < 5
           )
    |}]
;;

let%expect_test "emit: function calls and predicate subqueries are not blocks" =
  (* an Ident before the paren keeps a call a blob *)
  fmt "select count(*) from t;";
  [%expect
    {|
    select count(*)
      from t
           ;
    |}];
  (* predicate-position subqueries (in/exists operands) are glued to their
     expression and stay blobs; documented punt in sql-style.md *)
  fmt "select a from t where x in (select x from u);";
  [%expect
    {|
    select a
      from t
     where x in (select x from u)
           ;
    |}]
;;

let%expect_test "emit: cte is the same recursive block (golden: bugshield close)" =
  fmt
    "with current (rowid, ts, end_time) as (select rowid, ts, end_time from bugshields \
     where end_time is null order by ts desc limit 1) update bugshields set end_time = \
     time('now') where rowid = (select rowid from current) returning *;";
  [%expect
    {|
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
             limit 1
         )
       update bugshields
          set end_time = time('now')
        where rowid = (select rowid from current)
    returning *
              ;
    |}]
;;

let%expect_test "emit: create table right-aligns names, glues leading commas" =
  (* river = widest left-column item (here the table name); column names
     right-align to it, the type column lines up, constraints drop to the
     content column on their own line; `) ;` straddles the river *)
  fmt
    "create table if not exists skills (char_name text not null, tree text not null, \
     leaf text, ts datetime default current_timestamp, unique (char_name, tree, leaf) \
     on conflict ignore);";
  [%expect
    {|
    create table if not exists
       skills (
    char_name text
              not null
        ,tree text
              not null
        ,leaf text
          ,ts datetime
              default current_timestamp
      ,unique (char_name, tree, leaf)
               on conflict ignore
            ) ;
    |}]
;;

let%expect_test "emit: table name wider than columns sets the river" =
  fmt
    "create table if not exists world.flyable_npcs (full_name text, area text, note text);";
  [%expect
    {|
    create table if not exists
    world.flyable_npcs (
             full_name text
                 ,area text
                 ,note text
                     ) ;
    |}]
;;

let%expect_test "emit: foreign key constraint, references on the content column" =
  fmt
    "create table if not exists logs (char_name text, primary key (char_name, ts), \
     foreign key (char_state) references vitals(rowid));";
  [%expect
    {|
    create table if not exists
            logs (
       char_name text
    ,primary key (char_name, ts)
    ,foreign key (char_state)
                 references vitals(rowid)
               ) ;
    |}]
;;

let%expect_test "emit: create view header, as line, body laid out as a select" =
  fmt
    "create view if not exists world.npcs_fmt as select printf('%-18s', short_name) as \
     short_name, area from flyable_npcs;";
  [%expect
    {|
    create view if not exists world.npcs_fmt
        as
    select printf('%-18s', short_name)
        as short_name
         , area
      from flyable_npcs
           ;
    |}]
;;

let%expect_test "emit: insert with no column list keeps values aligned" =
  fmt "insert into world.maps values (:map_id, :filename, :domain);";
  [%expect
    {|
    insert into world.maps
         values
              ( :map_id
              , :filename
              , :domain
              ) ;
    |}]
;;

let%expect_test "emit: comments precede the statement unchanged" =
  fmt "--name: find\n--fn: first\nselect a from t;";
  [%expect
    {|
    --name: find
    --fn: first
    select a
      from t
           ;
    |}]
;;

let%expect_test "error: unlexable byte is a clean error, not a crash" =
  (* An agent feeding non-SQL (control chars, stray binary, host interpolation
     that is not a bind parameter) must get a recoverable error with a located
     message, never an uncaught exception. *)
  (match Pipeline.format "select \x01 from t;" with
   | Ok _ -> print_endline "unexpected Ok"
   | Error msg -> Printf.printf "Error: %s\n" msg);
  [%expect {| Error: unexpected byte '\001' at offset 7 |}]
;;

let%expect_test "passthrough: unsupported construct emitted unchanged" =
  let src = "select case when x then 1 else 2 end\n  from t ;\n" in
  let r = ok src in
  Printf.printf "had_passthrough %b\n" r.had_passthrough;
  Printf.printf "unchanged %b\n" (String.equal r.output src);
  [%expect
    {|
    had_passthrough true
    unchanged true
    |}]
;;

let foreach_example f =
  let dir = "../examples" in
  Sys.readdir dir
  |> Array.to_list
  |> List.sort compare
  |> List.iter (fun file ->
    if Filename.check_suffix file ".sql"
    then (
      let ic = open_in_bin (Filename.concat dir file) in
      let src = really_input_string ic (in_channel_length ic) in
      close_in ic;
      f file src))
;;

(* Invariant: tokenizing formatted output yields the same tokens as the input. *)
let%expect_test "invariant: token preservation" =
  foreach_example (fun file src ->
    let toks = Lexer.tokens_of_string src in
    let toks' = Lexer.tokens_of_string (ok src).output in
    let ok =
      List.length toks = List.length toks' && List.for_all2 Token.equal toks toks'
    in
    Printf.printf "%-15s %s\n" file (if ok then "ok" else "FAILED"));
  [%expect
    {|
    bugshield.sql   ok
    char.sql        ok
    init.sql        ok
    items.sql       ok
    lore.sql        ok
    map.sql         ok
    session.sql     ok
    vitals.sql      ok
    |}]
;;

(* Invariant: formatting is a fixed point after the first application. *)
let%expect_test "invariant: idempotence" =
  foreach_example (fun file src ->
    let once = (ok src).output in
    let twice = (ok once).output in
    Printf.printf "%-15s %s\n" file (if String.equal once twice then "ok" else "FAILED"));
  [%expect
    {|
    bugshield.sql   ok
    char.sql        ok
    init.sql        ok
    items.sql       ok
    lore.sql        ok
    map.sql         ok
    session.sql     ok
    vitals.sql      ok
    |}]
;;
