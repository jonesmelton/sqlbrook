(* Measure pass: compute the river column width for a statement.

   River width = max byte-length of the left-column items. For DML that's the
   clause keywords (`order by`, `returning`, `inner join`); for DDL it's the
   longest column name (with glued comma), table name, or table-constraint
   keyword. Insert statements anchor at the right edge of `into` instead.

   Width is measured in bytes; non-ASCII identifiers will misalign visually
   (accepted MVP limitation). *)

(* River column width, in bytes, for a parsed statement. *)
let river_width (_stmt : Skeleton.stmt) : int =
  failwith "Measure.river_width: not implemented"
;;
