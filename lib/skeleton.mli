type item_body =
  | Blob of Token.t list (* opaque expression, rendered on one line *)
  | Sub of stmt (* parenthesized select, laid out recursively *)

and item =
  { expr : item_body
  ; alias : string option
  }

and clause =
  { kw : string
  ; items : item list
  }

and stmt =
  | Dml of
      { clauses : clause list
      ; semi : bool
      }
  | Insert of
      { verb : string (* "insert" or "insert or replace" *)
      ; table : Token.t list
      ; cols : item list
      ; vals : item list
      ; returning : bool
      ; semi : bool
      }
  | Cte of
      { name : string
      ; cols : item list
      ; body : stmt
      ; outer : stmt (* trailing update/select; carries the semicolon *)
      }
  | Passthrough of
      { source : string (* exact source slice, emitted verbatim *)
      ; kind : string (* leading keyword, lowercased, for diagnostics *)
      ; offset : int (* byte offset of the statement's first token *)
      }

type parsed =
  { comments : string list
  ; stmt : stmt
  }

type span = int * int

(* Plain selects become Dml; everything else is Passthrough (the source slice
   from the chunk's first token to its last). *)
val parse : string -> (Token.t * span) list -> parsed list
