(* Emit pass: render a parsed statement to formatted SQL text.

   Manual right-padding into a Buffer — no Format boxes, since the river needs
   exact column control. Implements: clause river with leading-comma lists,
   `as` on its own line, and the semicolon rule (own line in content column).
   Insert mirror blocks, CTE end-shield form, and DDL land with their
   milestones. Passthrough statements are emitted verbatim. *)

(* Render an opaque expression blob on one line. Spacing rules: glue closing
   delimiters and commas to the previous token, glue after an open paren, and
   glue a function name to its open paren; otherwise single spaces. *)
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

let pad (n : int) : string = String.make (max 0 n) ' '

(* Format a single statement given its precomputed river width. Lines are
   newline-terminated except the last. *)
let emit_stmt (buf : Buffer.t) (width : int) (stmt : Skeleton.stmt) : unit =
  match stmt with
  | Skeleton.Passthrough s -> Buffer.add_string buf s
  | Skeleton.Dml { cte = None; clauses; semi } ->
    let lines = ref [] in
    let line s = lines := s :: !lines in
    List.iter
      (fun { Skeleton.kw; items } ->
         List.iteri
           (fun i { Skeleton.expr; alias } ->
              let body = render_tokens expr in
              if i = 0
              then line (pad (width - String.length kw) ^ kw ^ " " ^ body)
              else line (pad (width - 1) ^ ", " ^ body);
              match alias with
              | Some a -> line (pad (width - 2) ^ "as " ^ a)
              | None -> ())
           items)
      clauses;
    if semi then line (pad (width + 1) ^ ";");
    Buffer.add_string buf (String.concat "\n" (List.rev !lines))
  | Skeleton.Dml { cte = Some _; _ } | Skeleton.Insert _ | Skeleton.Ddl _ ->
    failwith "Emit.emit_stmt: not implemented"
;;

(* Render one statement, measuring its river width. *)
let render_stmt (stmt : Skeleton.stmt) : string =
  let buf = Buffer.create 256 in
  emit_stmt buf (Measure.river_width stmt) stmt;
  Buffer.contents buf
;;
