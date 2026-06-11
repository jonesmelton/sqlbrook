(* Glue closing delimiters and commas to the previous token, glue after an
   open paren, glue a function name to its open paren; else single spaces. *)
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
let shift (n : int) (lines : string list) : string list = List.map (( ^ ) (pad n)) lines

(* Shared recursive body-emitter: a statement as unindented lines. Subquery
   blocks and CTE bodies are the same call, shifted right by the caller, so
   relative indents compose under nesting. *)
let rec stmt_lines (stmt : Skeleton.stmt) : string list =
  match stmt with
  | Skeleton.Passthrough { source; _ } -> [ source ]
  | Skeleton.Dml { clauses; semi } ->
    let width = Measure.river_width stmt in
    let lines = ref [] in
    let line s = lines := s :: !lines in
    List.iter
      (fun { Skeleton.kw; items } ->
         List.iteri
           (fun i { Skeleton.expr; alias } ->
              let lead =
                if i = 0
                then pad (width - String.length kw) ^ kw ^ " "
                else pad (width - 1) ^ ", "
              in
              List.iter line (item_lines width lead expr);
              match alias with
              | Some a -> line (pad (width - 2) ^ "as " ^ a)
              | None -> ())
           items)
      clauses;
    if semi then line (pad (width + 1) ^ ";");
    List.rev !lines
  | Skeleton.Cte { name; cols; body; outer } ->
    let r = Measure.river_width stmt in
    let lines = ref [] in
    let line s = lines := s :: !lines in
    (match cols with
     | [] -> line ("with " ^ name ^ " as (")
     | cols ->
       line ("with " ^ name);
       List.iteri
         (fun i { Skeleton.expr; _ } ->
            let lead = if i = 0 then "( " else ", " in
            List.iter line (item_lines r (pad (r - 1) ^ lead) expr))
         cols;
       line (pad (r - 1) ^ ") as ("));
    List.iter line (shift (r + 2) (stmt_lines body));
    line (pad (r + 1) ^ ")");
    List.iter line (stmt_lines outer);
    List.rev !lines
  | Skeleton.Insert { verb; table; cols; vals; returning; semi } ->
    let r = Measure.river_width stmt in
    let lines = ref [] in
    let line s = lines := s :: !lines in
    let block close items =
      List.iteri
        (fun i { Skeleton.expr; _ } ->
           let lead = if i = 0 then "( " else ", " in
           List.iter line (item_lines r (pad (r - 1) ^ lead) expr))
        items;
      line close
    in
    (* header *)
    if String.equal verb "insert"
    then line (verb ^ " into " ^ render_tokens table)
    else (
      line verb;
      line (pad (r - 4) ^ "into " ^ render_tokens table));
    (* column block: closing paren always on its own line *)
    block (pad (r - 1) ^ ")") cols;
    line (pad (r - 6) ^ "values");
    (* value block: the closing paren shares its line with returning, or with
       the semicolon when there is no returning; otherwise stands alone *)
    let close =
      match returning, semi with
      | true, _ -> pad (r - 1) ^ ") returning *"
      | false, true -> pad (r - 1) ^ ") ;"
      | false, false -> pad (r - 1) ^ ")"
    in
    block close vals;
    (* The no-returning semicolon is glued to the closing paren ([") ;"]); only
       returning statements need the semicolon on its own content-column line. *)
    if semi && returning then line (pad (r + 1) ^ ";");
    List.rev !lines

(* One item after its [lead] (always width+1 chars): a blob stays on the
   line; a subquery opens its paren there, recurses with its own river
   shifted under the paren, and closes in the parent content column. *)
and item_lines (width : int) (lead : string) (body : Skeleton.item_body) : string list =
  match body with
  | Skeleton.Blob toks -> [ lead ^ render_tokens toks ]
  | Skeleton.Sub inner ->
    ((lead ^ "(") :: shift (width + 2) (stmt_lines inner)) @ [ pad (width + 1) ^ ")" ]
;;

let render_stmt (stmt : Skeleton.stmt) : string = String.concat "\n" (stmt_lines stmt)
