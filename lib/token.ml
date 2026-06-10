(* Token types emitted by the lexer.

   The lexer is byte-oriented (ocamllex). Keywords are matched
   case-insensitively against a fixed, multi-word-aware list and emitted
   lowercase per the style spec. Non-ASCII bytes (>= 0x80) only occur inside
   literals, quoted identifiers, and bare identifiers, all of which pass
   through untouched. *)

type t =
  | Keyword of string          (* normalized lowercase; may be multi-word, e.g. "order by" *)
  | Ident of string            (* bare identifier *)
  | Quoted of string           (* quoted identifier or string literal, delimiters included *)
  | Number of string
  | Operator of string         (* =, <>, ||, +, etc. *)
  | Placeholder of string      (* :name, @name, $name, ?NNN, ? *)
  | LParen
  | RParen
  | Comma
  | Semicolon
  | Comment of string          (* a -- line comment, text excluding the trailing newline *)

(* Render a token back to its source text. Used by emit and by the
   token-preservation invariant. *)
let to_string (_t : t) : string = failwith "Token.to_string: not implemented"

let equal (_a : t) (_b : t) : bool = failwith "Token.equal: not implemented"
