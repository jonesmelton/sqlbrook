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

(* A create-table column def or table constraint: [lead] is the right-aligned
   left-column token, [head_rest] the type/paren group on its line, [segments]
   the trailing constraints each on their own continuation line. *)
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
      { verb : string (* "insert" or "insert or replace" *)
      ; table : Token.t list
      ; cols : item list option (* None when the column list is omitted *)
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
