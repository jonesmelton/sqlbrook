(* Recursive descent, no menhir, no expression parsing. Splits the token
   stream into statements and each statement into clauses/items, tracking
   paren depth; paren-balanced spans become opaque expression blobs. Anything
   it can't classify becomes Passthrough. *)

type item_body =
  | Blob of Token.t list
  | Sub of stmt (* a parsed inner select; always laid out as a nested block *)

and item =
  { expr : item_body
  ; alias : string option
  }

and clause =
  { kw : string
  ; items : item list
  }

(* One create-table column def or table constraint. [lead] is the left-column
   token (column name, or a `primary key`/`foreign key`/`unique` keyword);
   [head_rest] is the type / paren group on the same line; [segments] are
   trailing constraints, each emitted on its own continuation line. *)
and ddl_item =
  { lead : Token.t
  ; head_rest : Token.t list
  ; segments : Token.t list list
  }

and stmt =
  | Dml of
      { clauses : clause list
      ; semi : bool
      }
  | Insert of
      { verb : string
      ; table : Token.t list
      ; cols : item list option
      ; vals : item list
      ; returning : bool
      ; semi : bool
      }
  | CreateTable of
      { header : Token.t list (* create table [if not exists] *)
      ; name : Token.t list (* table name (one word token; schema-qualified ok) *)
      ; defs : ddl_item list
      ; semi : bool
      }
  | CreateView of
      { header : Token.t list (* create view [if not exists] <name> *)
      ; body : stmt (* the defining select; carries the semicolon *)
      }
  | Cte of
      { name : string
      ; cols : item list
      ; body : stmt
      ; outer : stmt
      }
  | Passthrough of
      { source : string
      ; kind : string
      ; offset : int
      }

type parsed =
  { comments : string list
  ; stmt : stmt
  }

type span = int * int

(* Comments attach to the following statement; a trailing comment with no
   following statement forms its own chunk. *)
let split (toks : (Token.t * span) list) : (Token.t * span) list list =
  let rec go toks depth cur chunks =
    match toks with
    | [] ->
      let chunks =
        match cur with
        | [] -> chunks
        | _ -> List.rev cur :: chunks
      in
      List.rev chunks
    | ((Token.Semicolon, _) as t) :: rest when depth = 0 ->
      go rest 0 [] (List.rev (t :: cur) :: chunks)
    | ((Token.LParen, _) as t) :: rest -> go rest (depth + 1) (t :: cur) chunks
    | ((Token.RParen, _) as t) :: rest -> go rest (max 0 (depth - 1)) (t :: cur) chunks
    | t :: rest -> go rest depth (t :: cur) chunks
  in
  go toks 0 [] []
;;

exception Unsupported

let clause_starters =
  [ "select"
  ; "update"
  ; "set"
  ; "returning"
  ; "from"
  ; "where"
  ; "group by"
  ; "having"
  ; "order by"
  ; "limit"
  ; "on"
  ; "join"
  ; "inner join"
  ; "left join"
  ; "cross join"
  ; "left outer join"
  ; "right outer join"
  ; "full outer join"
  ]
;;

(* Keywords allowed inside an expression blob at depth 0; anything else at
   depth 0 is a construct we don't lay out yet. *)
let expr_kws =
  [ "is"
  ; "not"
  ; "null"
  ; "like"
  ; "glob"
  ; "in"
  ; "between"
  ; "exists"
  ; "desc"
  ; "asc"
  ; "distinct"
  ; "collate"
  ; "all"
  ]
;;

(* In predicate context `and`/`or` split clauses (one condition per line);
   elsewhere they sit inside the expression blob. *)
let predicate_kw = function
  | "where" | "having" | "on" | "and" | "or" -> true
  | _ -> false
;;

(* Split a clause into (kw, body) at depth-0 clause keywords; in predicate
   context also at `and`/`or`, except the `and` paired with a depth-0
   `between`. Raises Unsupported outside the supported grammar. *)
let to_segments (toks : Token.t list) : (string * Token.t list) list =
  let rec go toks depth after_between kw body segs =
    let close () = (kw, List.rev body) :: segs in
    match toks with
    | [] -> List.rev (close ())
    | Token.Keyword k :: rest when depth = 0 && List.mem k clause_starters ->
      go rest 0 false k [] (close ())
    | Token.Keyword (("and" | "or") as k) :: rest when depth = 0 && predicate_kw kw ->
      if after_between && String.equal k "and"
      then go rest 0 false kw (Token.Keyword k :: body) segs
      else go rest 0 false k [] (close ())
    | Token.Keyword "between" :: rest when depth = 0 ->
      go rest 0 true kw (Token.Keyword "between" :: body) segs
    | Token.Keyword "as" :: rest when depth = 0 ->
      (* validated during item splitting; only legal as a select-item alias *)
      go rest 0 after_between kw (Token.Keyword "as" :: body) segs
    | Token.Keyword k :: rest when depth = 0 && List.mem k expr_kws ->
      go rest 0 after_between kw (Token.Keyword k :: body) segs
    | Token.Keyword _ :: _ when depth = 0 -> raise Unsupported
    | Token.Comment _ :: _ -> raise Unsupported
    | Token.RParen :: _ when depth = 0 -> raise Unsupported
    | (Token.LParen as t) :: rest -> go rest (depth + 1) after_between kw (t :: body) segs
    | (Token.RParen as t) :: rest -> go rest (depth - 1) after_between kw (t :: body) segs
    | t :: rest -> go rest depth after_between kw (t :: body) segs
  in
  match toks with
  | Token.Keyword k :: rest when List.mem k clause_starters -> go rest 0 false k [] []
  | _ -> raise Unsupported
;;

(* Consume a parenthesized group at the head of [toks]; return its inner
   tokens (parens stripped) and the remainder. Raises Unsupported if [toks]
   does not start with a balanced group. *)
let take_paren_group (toks : Token.t list) : Token.t list * Token.t list =
  match toks with
  | Token.LParen :: rest ->
    let rec go depth acc = function
      | Token.RParen :: rest when depth = 0 -> List.rev acc, rest
      | (Token.LParen as t) :: rest -> go (depth + 1) (t :: acc) rest
      | (Token.RParen as t) :: rest -> go (depth - 1) (t :: acc) rest
      | t :: rest -> go depth (t :: acc) rest
      | [] -> raise Unsupported
    in
    go 0 [] rest
  | _ -> raise Unsupported
;;

(* An item that is exactly one balanced paren group whose first token is
   `select` is a subquery; `foo(...)` and `(a + b) * c` have a different head
   or a non-empty remainder and stay blobs. *)
let subquery_tokens (toks : Token.t list) : Token.t list option =
  match toks with
  | Token.LParen :: _ ->
    (match take_paren_group toks with
     | (Token.Keyword "select" :: _ as inner), [] -> Some inner
     | _ -> None)
  | _ -> None
;;

(* Split a comma-list clause body into items at depth-0 commas. A trailing
   `as <name>` at depth 0 becomes the item alias (select lists only). *)
let rec to_items ~(aliases : bool) (body : Token.t list) : item list =
  let split_commas toks =
    let rec go toks depth cur items =
      match toks with
      | [] -> List.rev (List.rev cur :: items)
      | Token.Comma :: rest when depth = 0 -> go rest 0 [] (List.rev cur :: items)
      | (Token.LParen as t) :: rest -> go rest (depth + 1) (t :: cur) items
      | (Token.RParen as t) :: rest -> go rest (depth - 1) (t :: cur) items
      | t :: rest -> go rest depth (t :: cur) items
    in
    go toks 0 [] []
  in
  split_commas body
  |> List.map (fun toks ->
    let expr, alias =
      match List.rev toks with
      | Token.Ident a :: Token.Keyword "as" :: rev_expr when aliases ->
        List.rev rev_expr, Some a
      | _ -> toks, None
    in
    let has_as =
      List.exists
        (function
          | Token.Keyword "as" -> true
          | _ -> false)
        (let rec strip_parens depth acc = function
           | [] -> List.rev acc
           | Token.LParen :: rest -> strip_parens (depth + 1) acc rest
           | Token.RParen :: rest -> strip_parens (depth - 1) acc rest
           | t :: rest -> strip_parens depth (if depth = 0 then t :: acc else acc) rest
         in
         strip_parens 0 [] expr)
    in
    if has_as || expr = [] then raise Unsupported;
    match subquery_tokens expr with
    | Some inner -> { expr = Sub (parse_select inner); alias }
    | None -> { expr = Blob expr; alias })

and parse_select (toks : Token.t list) : stmt =
  let toks, semi =
    match List.rev toks with
    | Token.Semicolon :: rev_rest -> List.rev rev_rest, true
    | _ -> toks, false
  in
  let clauses =
    to_segments toks
    |> List.map (fun (kw, body) ->
      let items =
        if predicate_kw kw
        then (
          match to_items ~aliases:false body with
          | [ item ] -> [ item ]
          | _ -> raise Unsupported)
        else to_items ~aliases:(String.equal kw "select") body
      in
      { kw; items })
  in
  Dml { clauses; semi }
;;

(* insert [or replace] into <table> ( cols ) values ( vals ) [returning *] [;] *)
let parse_insert (toks : Token.t list) : stmt =
  let toks, semi =
    match List.rev toks with
    | Token.Semicolon :: rev_rest -> List.rev rev_rest, true
    | _ -> toks, false
  in
  let verb, rest =
    match toks with
    | Token.Keyword (("insert" | "insert or replace") as v) :: rest -> v, rest
    | _ -> raise Unsupported
  in
  let rest =
    match rest with
    | Token.Keyword "into" :: rest -> rest
    | _ -> raise Unsupported
  in
  (* table = tokens up to the column-list open paren or the `values` keyword
     (the column list is optional) *)
  let rec take_table acc = function
    | (Token.LParen :: _ | Token.Keyword "values" :: _) as rest -> List.rev acc, rest
    | t :: rest -> take_table (t :: acc) rest
    | [] -> raise Unsupported
  in
  let table, rest = take_table [] rest in
  if table = [] then raise Unsupported;
  let cols, rest =
    match rest with
    | Token.LParen :: _ ->
      let col_toks, rest = take_paren_group rest in
      Some (to_items ~aliases:false col_toks), rest
    | _ -> None, rest
  in
  let rest =
    match rest with
    | Token.Keyword "values" :: rest -> rest
    | _ -> raise Unsupported
  in
  let val_toks, rest = take_paren_group rest in
  let returning =
    match rest with
    | [ Token.Keyword "returning"; Token.Operator "*" ] -> true
    | [] -> false
    | _ -> raise Unsupported
  in
  let vals = to_items ~aliases:false val_toks in
  Insert { verb; table; cols; vals; returning; semi }
;;

(* with <name> [( cols )] as ( body ) <outer dml> [;]
   Single CTE only; multiple CTEs are Unsupported and pass through. *)
let parse_cte (toks : Token.t list) : stmt =
  let name, rest =
    match toks with
    | Token.Keyword "with" :: Token.Ident name :: rest -> name, rest
    | _ -> raise Unsupported
  in
  let cols, rest =
    match rest with
    | Token.LParen :: _ ->
      let col_toks, rest = take_paren_group rest in
      to_items ~aliases:false col_toks, rest
    | _ -> [], rest
  in
  let body_toks, rest =
    match rest with
    | Token.Keyword "as" :: rest -> take_paren_group rest
    | _ -> raise Unsupported
  in
  (match body_toks with
   | Token.Keyword "select" :: _ -> ()
   | _ -> raise Unsupported);
  let outer =
    match rest with
    | Token.Keyword ("select" | "update") :: _ -> parse_select rest
    | Token.Keyword ("insert" | "insert or replace") :: _ -> parse_insert rest
    | _ -> raise Unsupported
  in
  Cte { name; cols; body = parse_select body_toks; outer }
;;

(* Split a token list at depth-0 commas (parens protect inner commas). *)
let comma_split (toks : Token.t list) : Token.t list list =
  let rec go toks depth cur acc =
    match toks with
    | [] -> List.rev (List.rev cur :: acc)
    | Token.Comma :: rest when depth = 0 -> go rest 0 [] (List.rev cur :: acc)
    | (Token.LParen as t) :: rest -> go rest (depth + 1) (t :: cur) acc
    | (Token.RParen as t) :: rest -> go rest (depth - 1) (t :: cur) acc
    | t :: rest -> go rest depth (t :: cur) acc
  in
  go toks 0 [] []
;;

(* Keywords that start a fresh continuation line inside a column def or table
   constraint (`not null`, `default ...`, `references ...`, `on conflict ...`). *)
let ddl_break = function
  | "not" | "default" | "references" | "collate" | "check" | "unique" | "primary key"
  | "foreign key" | "on conflict" -> true
  | _ -> false
;;

(* A create-table item: lead token, the head remainder up to the first depth-0
   break keyword, then one segment per subsequent break keyword. *)
let parse_ddl_item (toks : Token.t list) : ddl_item =
  let lead, rest =
    match toks with
    | (Token.Ident _ as t) :: rest -> t, rest
    | (Token.Quoted _ as t) :: rest -> t, rest
    | (Token.Keyword ("primary key" | "foreign key" | "unique") as t) :: rest -> t, rest
    | _ -> raise Unsupported
  in
  (* Collect one segment: the leading break keyword plus everything up to the
     next depth-0 break keyword. *)
  let rec take_seg depth acc = function
    | Token.Keyword k :: _ as toks when depth = 0 && ddl_break k -> List.rev acc, toks
    | (Token.LParen as t) :: r -> take_seg (depth + 1) (t :: acc) r
    | (Token.RParen as t) :: r -> take_seg (depth - 1) (t :: acc) r
    | t :: r -> take_seg depth (t :: acc) r
    | [] -> List.rev acc, []
  in
  let rec segs = function
    | [] -> []
    | Token.Keyword k :: rest when ddl_break k ->
      let seg, rest = take_seg 0 [ Token.Keyword k ] rest in
      seg :: segs rest
    | _ -> raise Unsupported
  in
  let head_rest, after = take_seg 0 [] rest in
  { lead; head_rest; segments = segs after }
;;

(* create table [if not exists] <name> ( defs ) [;] *)
let parse_create_table (toks : Token.t list) : stmt =
  let toks, semi =
    match List.rev toks with
    | Token.Semicolon :: rev_rest -> List.rev rev_rest, true
    | _ -> toks, false
  in
  let header, rest =
    match toks with
    | (Token.Keyword "create table" as t) :: (Token.Keyword "if not exists" as t2) :: rest ->
      [ t; t2 ], rest
    | (Token.Keyword "create table" as t) :: rest -> [ t ], rest
    | _ -> raise Unsupported
  in
  let rec take_name acc = function
    | Token.LParen :: _ as rest -> List.rev acc, rest
    | t :: rest -> take_name (t :: acc) rest
    | [] -> raise Unsupported
  in
  let name, rest = take_name [] rest in
  if name = [] then raise Unsupported;
  let body_toks, after = take_paren_group rest in
  if after <> [] then raise Unsupported;
  let defs = List.map parse_ddl_item (comma_split body_toks) in
  if defs = [] then raise Unsupported;
  CreateTable { header; name; defs; semi }
;;

(* create view [if not exists] <name> as <select> [;]
   The header is everything up to the depth-0 `as`; the body is a plain select
   laid out as a normal top-level statement. *)
let parse_create_view (toks : Token.t list) : stmt =
  let rec take_header depth acc = function
    | Token.Keyword "as" :: rest when depth = 0 -> List.rev acc, rest
    | (Token.LParen as t) :: r -> take_header (depth + 1) (t :: acc) r
    | (Token.RParen as t) :: r -> take_header (depth - 1) (t :: acc) r
    | t :: r -> take_header depth (t :: acc) r
    | [] -> raise Unsupported
  in
  let header, body_toks = take_header 0 [] toks in
  (match header with
   | Token.Keyword "create view" :: _ :: _ -> ()
   | _ -> raise Unsupported);
  (match body_toks with
   | Token.Keyword "select" :: _ -> ()
   | _ -> raise Unsupported);
  CreateView { header; body = parse_select body_toks }
;;

(* Plain selects become Dml; everything else is Passthrough (the source slice
   from the chunk's first token to its last). *)
let parse (src : string) (toks : (Token.t * span) list) : parsed list =
  split toks
  |> List.map (fun chunk ->
    let passthrough body =
      let start, _ = snd (List.hd chunk) in
      let _, stop = snd (List.hd (List.rev chunk)) in
      let kind =
        match body with
        | (Token.Keyword k, _) :: _ -> k
        | (tok, _) :: _ -> Token.to_string tok
        | [] -> ""
      in
      let source = String.sub src start (stop - start) in
      { comments = []; stmt = Passthrough { source; kind; offset = start } }
    in
    let rec strip_comments acc = function
      | (Token.Comment c, _) :: rest -> strip_comments (c :: acc) rest
      | body -> List.rev acc, body
    in
    let comments, body = strip_comments [] chunk in
    match body with
    | (Token.Keyword ("select" | "update"), _) :: _ ->
      (try { comments; stmt = parse_select (List.map fst body) } with
       | Unsupported -> passthrough body)
    | (Token.Keyword ("insert" | "insert or replace"), _) :: _ ->
      (try { comments; stmt = parse_insert (List.map fst body) } with
       | Unsupported -> passthrough body)
    | (Token.Keyword "with", _) :: _ ->
      (try { comments; stmt = parse_cte (List.map fst body) } with
       | Unsupported -> passthrough body)
    | (Token.Keyword "create table", _) :: _ ->
      (try { comments; stmt = parse_create_table (List.map fst body) } with
       | Unsupported -> passthrough body)
    | (Token.Keyword "create view", _) :: _ ->
      (try { comments; stmt = parse_create_view (List.map fst body) } with
       | Unsupported -> passthrough body)
    | _ -> passthrough body)
;;
