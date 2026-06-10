(* Byte-oriented lexer for SQLite.

   Tokenizes into Token.t. Keywords (including multi-word forms like
   "order by", "insert or replace", "if not exists") are recognized with
   lookahead against a fixed closed list, matched case-insensitively, and
   emitted lowercase. UTF-8 / non-ASCII bytes pass through inside idents,
   quoted strings, and quoted identifiers via the ['\x80'-'\xff'] class. *)

{
  (* header: helpers available to the rules below *)
}

(* character classes — to be filled in during the lexer milestone *)

rule token = parse
  | eof { failwith "Lexer.token: not implemented" }
  | _   { failwith "Lexer.token: not implemented" }

{
  (* trailer: top-level entry point producing a Token.t list from a string *)

  let tokens_of_string (_s : string) : Token.t list =
    failwith "Lexer.tokens_of_string: not implemented"
}
