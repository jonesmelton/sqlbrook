(* Flat single-line rendering of a token list: keywords/identifiers separated
   by single spaces, with commas and closing/opening parens glued. *)
val render_tokens : Token.t list -> string
