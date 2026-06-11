(* River width = max byte-length of the left-column items. Measured in bytes,
   so non-ASCII identifiers misalign visually (accepted). *)
let river_width (stmt : Skeleton.stmt) : int =
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
  | Skeleton.Passthrough _ -> 0
;;
