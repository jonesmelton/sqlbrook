(* Measure pass: compute the river column width for a statement.

   River width = max byte-length of the left-column items. For DML that's the
   clause keywords (`order by`, `returning`, `inner join`); for DDL it's the
   longest column name (with glued comma), table name, or table-constraint
   keyword. Insert statements anchor at the right edge of `into` instead.

   Width is measured in bytes; non-ASCII identifiers will misalign visually
   (accepted MVP limitation). *)

(* River column width, in bytes, for a parsed statement. *)
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
