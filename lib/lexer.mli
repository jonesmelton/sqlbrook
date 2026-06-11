(* Raised on a byte the lexer cannot classify. *)
exception Error of string

(* Each token carries its (start, end) byte span into the source, so
   passthrough statements can be emitted as exact source slices. *)
val tokens_with_spans : string -> (Token.t * (int * int)) list
val tokens_of_string : string -> Token.t list
