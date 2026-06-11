let render_tokens = Render.render_tokens
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
  | Skeleton.CreateTable { header; name; defs; semi } ->
    let r = Measure.river_width stmt in
    let lines = ref [] in
    let line s = lines := s :: !lines in
    line (render_tokens header);
    let name_s = render_tokens name in
    line (pad (r - String.length name_s) ^ name_s ^ " (");
    List.iteri
      (fun i { Skeleton.lead; head_rest; segments } ->
         let lead_s = Token.to_string lead in
         let leadcol =
           if i = 0
           then pad (r - String.length lead_s) ^ lead_s
           else pad (r - 1 - String.length lead_s) ^ "," ^ lead_s
         in
         (match head_rest with
          | [] -> line leadcol
          | _ -> line (leadcol ^ " " ^ render_tokens head_rest));
         List.iter
           (fun seg ->
              (* `on conflict ...` nests one column past the content column;
                 every other constraint sits at the content column (river + 1) *)
              let indent =
                match seg with
                | Token.Keyword "on conflict" :: _ -> r + 2
                | _ -> r + 1
              in
              line (pad indent ^ render_tokens seg))
           segments)
      defs;
    line (pad (r - 1) ^ if semi then ") ;" else ")");
    List.rev !lines
  | Skeleton.CreateView { header; body } ->
    let r = Measure.river_width body in
    render_tokens header :: (pad (r - 2) ^ "as") :: stmt_lines body
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
    (* column block: closing paren always on its own line; omitted entirely
       when the statement has no column list *)
    (match cols with
     | Some cols -> block (pad (r - 1) ^ ")") cols
     | None -> ());
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
