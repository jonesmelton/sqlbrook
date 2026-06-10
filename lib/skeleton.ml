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
      { verb : string list          (* e.g. ["insert"] or ["insert"; "or"; "replace"] *)
      ; table : string
      ; cols : string list option
      ; values : item list
      ; tail : clause list          (* returning, on conflict, etc. *)
      }
  | Ddl of
      { table : string
      ; defs : coldef list
      }
  | Passthrough of Token.t list

(* Split a token stream into statements at top-level semicolons, then classify
   each. Comments are statement separators that pass through unchanged. *)
let parse (_toks : Token.t list) : stmt list =
  failwith "Skeleton.parse: not implemented"
