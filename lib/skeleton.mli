type item =
  { expr : Token.t list
  ; alias : string option
  }

type clause =
  { kw : string
  ; items : item list
  }

type stmt =
  | Dml of
      { clauses : clause list
      ; semi : bool
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
