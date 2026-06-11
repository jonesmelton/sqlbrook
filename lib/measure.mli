(* River width = max byte-length of the left-column items. Measured in bytes,
   so non-ASCII identifiers misalign visually (accepted). *)
val river_width : Skeleton.stmt -> int
