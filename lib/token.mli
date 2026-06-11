type t =
  | Keyword of string (* lowercased; may be multi-word, e.g. "order by" *)
  | Ident of string
  | Quoted of string (* delimiters included *)
  | Number of string
  | Operator of string
  | Placeholder of string
  | LParen
  | RParen
  | Comma
  | Semicolon
  | Comment of string (* -- line, excluding the trailing newline *)

(* Source text of a token; for Passthrough this is not used, statements are
   sliced from the original source instead. *)
val to_string : t -> string
val equal : t -> t -> bool
