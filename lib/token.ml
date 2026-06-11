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

let to_string = function
  | Keyword s -> s
  | Ident s -> s
  | Quoted s -> s
  | Number s -> s
  | Operator s -> s
  | Placeholder s -> s
  | LParen -> "("
  | RParen -> ")"
  | Comma -> ","
  | Semicolon -> ";"
  | Comment s -> s
;;

let equal (a : t) (b : t) : bool = a = b
