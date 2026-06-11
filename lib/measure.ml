(* River width = max byte-length of the left-column items. Measured in bytes,
   so non-ASCII identifiers misalign visually (accepted). *)
let river_width (stmt : Skeleton.stmt) : int =
  match stmt with
  | Skeleton.Dml { clauses; _ } ->
    List.fold_left
      (fun w (c : Skeleton.clause) -> max w (String.length c.Skeleton.kw))
      0
      clauses
  | Skeleton.Passthrough _ -> 0
  | Skeleton.Insert _ | Skeleton.Ddl _ -> failwith "Measure.river_width: not implemented"
;;
