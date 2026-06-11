{
  (* Words are classified Keyword/Ident only after phrase lookahead in the
     trailer, so a raw pre-classification token is needed first. *)
  type raw =
    | RWord of string
    | RQuoted of string
    | RNumber of string
    | ROp of string
    | RPlaceholder of string
    | RLParen
    | RRParen
    | RComma
    | RSemicolon
    | RComment of string
    | REof

  exception Error of string
}

let space = [' ' '\t' '\r' '\n']
let digit = ['0'-'9']
let hex = ['0'-'9' 'a'-'f' 'A'-'F']
let ident_start = ['a'-'z' 'A'-'Z' '_' '\x80'-'\xff']
let ident_char = ['a'-'z' 'A'-'Z' '0'-'9' '_' '$' '\x80'-'\xff']
let bare_ident = ident_start ident_char*
(* Qualified names (schema.table) lex as one word so layout never reasons
   about spacing around dots. *)
let word = bare_ident ('.' bare_ident)*

rule token = parse
  | space+                                  { token lexbuf }
  | "--" [^ '\n']*                          { RComment (Lexing.lexeme lexbuf) }
  | '\'' ([^ '\''] | "''")* '\''            { RQuoted (Lexing.lexeme lexbuf) }
  | '"' ([^ '"'] | "\"\"")* '"'             { RQuoted (Lexing.lexeme lexbuf) }
  | '`' ([^ '`'] | "``")* '`'               { RQuoted (Lexing.lexeme lexbuf) }
  | '[' [^ ']']* ']'                        { RQuoted (Lexing.lexeme lexbuf) }
  | "0x" hex+                               { RNumber (Lexing.lexeme lexbuf) }
  | digit+ ('.' digit*)? (['e' 'E'] ['+' '-']? digit+)?
                                            { RNumber (Lexing.lexeme lexbuf) }
  | '.' digit+ (['e' 'E'] ['+' '-']? digit+)?
                                            { RNumber (Lexing.lexeme lexbuf) }
  | [':' '@' '$'] bare_ident                { RPlaceholder (Lexing.lexeme lexbuf) }
  | '?' digit*                              { RPlaceholder (Lexing.lexeme lexbuf) }
  | word                                    { RWord (Lexing.lexeme lexbuf) }
  | '('                                     { RLParen }
  | ')'                                     { RRParen }
  | ','                                     { RComma }
  | ';'                                     { RSemicolon }
  | "||" | "<>" | "!=" | "<=" | ">=" | "==" | "<<" | ">>"
                                            { ROp (Lexing.lexeme lexbuf) }
  | ['=' '<' '>' '+' '-' '*' '/' '%' '&' '|' '~' '.']
                                            { ROp (Lexing.lexeme lexbuf) }
  | eof                                     { REof }
  (* Near-miss tokens from other dialects: name them so the caller fixes the
     dialect, not a phantom stray byte. SQLite has no :: cast or $$-quoting. *)
  | "::"                                    { raise (Error (Printf.sprintf
                                                "'::' is not SQLite syntax \
                                                 (PostgreSQL cast) at offset %d; \
                                                 dialect is SQLite"
                                                (Lexing.lexeme_start lexbuf))) }
  | "$$"                                    { raise (Error (Printf.sprintf
                                                "'$$' is not SQLite syntax \
                                                 (PostgreSQL dollar-quote) at offset \
                                                 %d; dialect is SQLite"
                                                (Lexing.lexeme_start lexbuf))) }
  | _ as c                                  { raise (Error (Printf.sprintf
                                                "unexpected byte %C at offset %d"
                                                c (Lexing.lexeme_start lexbuf))) }

{
  (* Closed and small on purpose: window-frame words (rows/range/preceding)
     lex as identifiers, which is harmless for passthrough. *)
  let keywords =
    [ "select"; "from"; "where"; "and"; "or"; "on"; "as"; "set"; "update"
    ; "delete"; "insert"; "into"; "values"; "returning"; "with"; "limit"
    ; "having"; "union"; "like"; "glob"; "not"; "null"; "is"; "in"; "between"
    ; "exists"; "case"; "when"; "then"; "else"; "end"; "join"; "unique"
    ; "default"; "references"; "filter"; "over"; "window"; "distinct"
    ; "recursive"; "desc"; "asc"; "collate"; "all" ]

  let phrases =
    [ [ "insert"; "or"; "replace" ]
    ; [ "left"; "outer"; "join" ]
    ; [ "right"; "outer"; "join" ]
    ; [ "full"; "outer"; "join" ]
    ; [ "if"; "not"; "exists" ]
    ; [ "create"; "table" ]
    ; [ "create"; "view" ]
    ; [ "order"; "by" ]
    ; [ "group"; "by" ]
    ; [ "partition"; "by" ]
    ; [ "inner"; "join" ]
    ; [ "left"; "join" ]
    ; [ "cross"; "join" ]
    ; [ "primary"; "key" ]
    ; [ "foreign"; "key" ]
    ; [ "on"; "conflict" ]
    ; [ "union"; "all" ]
    ]

  (* Longest first: phrases are matched greedily. *)
  let phrases =
    List.sort (fun a b -> compare (List.length b) (List.length a)) phrases

  (* Each token carries its (start, end) byte span; passthrough statements are
     emitted as exact source slices from those spans, not re-rendered tokens. *)
  let assemble raws =
    let rec go toks acc =
      match toks with
      | [] -> List.rev acc
      | (RWord w, (s, e)) :: rest ->
          let lw = String.lowercase_ascii w in
          let try_phrase phrase =
            match phrase with
            | first :: more when String.equal first lw ->
                let rec eat needed toks last_end =
                  match needed, toks with
                  | [], toks -> Some (toks, last_end)
                  | n :: ns, (RWord w', (_, e')) :: ts
                    when String.equal n (String.lowercase_ascii w') ->
                      eat ns ts e'
                  | _ -> None
                in
                (match eat more rest e with
                 | Some (rest', e') ->
                     Some (String.concat " " phrase, rest', e')
                 | None -> None)
            | _ -> None
          in
          (match List.find_map try_phrase phrases with
           | Some (kw, rest', e') ->
               go rest' ((Token.Keyword kw, (s, e')) :: acc)
           | None ->
               if List.mem lw keywords
               then go rest ((Token.Keyword lw, (s, e)) :: acc)
               else go rest ((Token.Ident w, (s, e)) :: acc))
      | (RQuoted s, sp) :: rest -> go rest ((Token.Quoted s, sp) :: acc)
      | (RNumber s, sp) :: rest -> go rest ((Token.Number s, sp) :: acc)
      | (ROp s, sp) :: rest -> go rest ((Token.Operator s, sp) :: acc)
      | (RPlaceholder s, sp) :: rest -> go rest ((Token.Placeholder s, sp) :: acc)
      | (RLParen, sp) :: rest -> go rest ((Token.LParen, sp) :: acc)
      | (RRParen, sp) :: rest -> go rest ((Token.RParen, sp) :: acc)
      | (RComma, sp) :: rest -> go rest ((Token.Comma, sp) :: acc)
      | (RSemicolon, sp) :: rest -> go rest ((Token.Semicolon, sp) :: acc)
      | (RComment s, sp) :: rest -> go rest ((Token.Comment s, sp) :: acc)
      | (REof, _) :: rest -> go rest acc
    in
    go raws []

  let tokens_with_spans (s : string) : (Token.t * (int * int)) list =
    let lexbuf = Lexing.from_string s in
    let rec loop acc =
      match token lexbuf with
      | REof -> List.rev acc
      | r ->
          loop ((r, (Lexing.lexeme_start lexbuf, Lexing.lexeme_end lexbuf)) :: acc)
    in
    assemble (loop [])

  let tokens_of_string (s : string) : Token.t list =
    List.map fst (tokens_with_spans s)
}
