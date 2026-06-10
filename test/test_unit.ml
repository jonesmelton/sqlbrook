(* Unit-level snapshots and invariants (ppx_expect).

   Covers: multi-word keyword lexing, placeholder forms, quoted identifiers
   and >= 0x80 bytes, individual clause layouts, passthrough-with-warning
   behavior, and the cross-cutting invariants:
     - token preservation:  lex (fmt x) = lex x
     - idempotence:         fmt (fmt x) = fmt x

   Layout-stage cases are stubbed; bodies land with their milestones. *)

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

(* Render tokens back to flat text: space-separated, newline after comments so
   a comment never swallows the following tokens. Stand-in for fmt until the
   layout milestones land. *)
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

(* Invariant (lexer-level, corpus-wide): re-lexing the flat rendering of the
   token stream reproduces the token stream. Once fmt exists this is
   strengthened to lex (fmt x) = lex x. *)
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

let%expect_test "skeleton: select splits into clauses" =
  ignore Skeleton.parse;
  [%expect {| |}]
;;

let%expect_test "emit: select river layout" =
  ignore Emit.format;
  ignore Measure.river_width;
  [%expect {| |}]
;;

let%expect_test "passthrough: unsupported construct emitted unchanged" =
  ignore Pipeline.format;
  [%expect {| |}]
;;

(* Invariant: tokenizing formatted output yields the same tokens as the input. *)
let%expect_test "invariant: token preservation" = [%expect {| |}]

(* Invariant: formatting is a fixed point after the first application. *)
let%expect_test "invariant: idempotence" = [%expect {| |}]
