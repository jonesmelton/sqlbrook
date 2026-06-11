(* River width = max byte-length of the left-column items. Measured in bytes,
   so non-ASCII identifiers misalign visually (accepted). *)
let rec river_width (stmt : Skeleton.stmt) : int =
  match stmt with
  | Skeleton.Dml { clauses; _ } ->
    List.fold_left
      (fun w (c : Skeleton.clause) -> max w (String.length c.Skeleton.kw))
      0
      clauses
  | Skeleton.Insert { verb; _ } ->
    (* "insert" keeps "into <table>" on its own line, river at the right edge
       of "into"; a longer verb breaks onto its own line and the river falls
       back to "values". *)
    if String.equal verb "insert"
    then String.length "insert into"
    else String.length "values"
  | Skeleton.CreateTable { name; defs; _ } ->
    (* widest left-column item: table name, or a column name / constraint
       keyword (the leading comma adds one byte on every item but the first) *)
    let name_w = String.length (Render.render_tokens name) in
    let lead_w i (d : Skeleton.ddl_item) =
      String.length (Token.to_string d.Skeleton.lead) + if i = 0 then 0 else 1
    in
    List.fold_left max name_w (List.mapi lead_w defs)
  | Skeleton.CreateView { body; _ } ->
    (* the `as` aligns to the body's own river *)
    river_width body
  | Skeleton.Cte _ ->
    (* governs only the header's column block; body and outer statement
       compute their own rivers *)
    String.length "with"
  | Skeleton.Passthrough _ -> 0
;;
