(* Skeleton parser: recursive descent, no menhir, no expression parsing.

   Splits a token stream into statements, and each statement into clauses /
   items, tracking paren depth. Clause bodies split at top-level commas;
   paren-balanced spans are captured as opaque expression blobs. Recognizes:
   trailing `as <name>` on list items, CTE prologue (`with name ( cols ) as (`),
   insert column/values blocks, and DDL column defs. Anything it can't classify
   becomes Passthrough. *)

(* A list item: an opaque expression blob with an optional trailing alias. *)
type item =
  { expr : Token.t list
  ; alias : string option
  }

(* A river-participating clause: the keyword occupies the left column. *)
type clause =
  { kw : string
  ; items : item list
  }

(* A DDL column definition. Name participates in the river; the rest
   (type + constraints) is opaque token text laid out in the content column. *)
type coldef =
  { name : string
  ; rest : Token.t list
  }

(* A CTE prologue in end-shield form: `with name ( cols ) as ( <body> )`. *)
type cte =
  { name : string
  ; cols : string list
  ; body : clause list
  }

type stmt =
  | Dml of
      { cte : cte option
      ; clauses : clause list
      }
  | Insert of
      { verb : string list (* e.g. ["insert"] or ["insert"; "or"; "replace"] *)
      ; table : string
      ; cols : string list option
      ; values : item list
      ; tail : clause list (* returning, on conflict, etc. *)
      }
  | Ddl of
      { table : string
      ; defs : coldef list
      }
  | Passthrough of string (* exact source slice, emitted unchanged *)

type span = int * int (* byte offsets into the source: (start, end) *)

(* Split the token stream into statements at depth-0 semicolons. Comments
   attach to the following statement (they precede it in source order); a
   trailing comment with no following statement forms its own chunk. *)
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

(* Classify each statement. Until the layout milestones land, everything is
   Passthrough: the source slice from the chunk's first token to its last. *)
let parse (src : string) (toks : (Token.t * span) list) : stmt list =
  split toks
  |> List.map (fun chunk ->
    let start, _ = snd (List.hd chunk) in
    let _, stop = snd (List.hd (List.rev chunk)) in
    Passthrough (String.sub src start (stop - start)))
;;
