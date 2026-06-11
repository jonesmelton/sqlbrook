(* Glue closing delimiters and commas to the previous token, glue after an
   open paren, glue a function name to its open paren; else single spaces.
   Shared by emit (line bodies) and measure (left-column widths). *)
let render_tokens (toks : Token.t list) : string =
  let buf = Buffer.create 64 in
  let emit prev t =
    let glued =
      match prev, t with
      | Some Token.LParen, _ -> true
      | Some (Token.Ident _), Token.LParen -> true
      | Some _, (Token.RParen | Token.Comma | Token.Semicolon) -> true
      | _ -> false
    in
    (match prev with
     | Some _ when not glued -> Buffer.add_char buf ' '
     | _ -> ());
    Buffer.add_string buf (Token.to_string t)
  in
  ignore
    (List.fold_left
       (fun prev t ->
          emit prev t;
          Some t)
       None
       toks);
  Buffer.contents buf
;;
