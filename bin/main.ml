(* CLI entry point.

   Reads stdin or file args, writes formatted SQL to stdout. Exits nonzero if
   any statement fell back to passthrough, so it can gate CI eventually.
   In-place editing (-i) is deferred. *)

let read_all (_ic : in_channel) : string =
  failwith "Main.read_all: not implemented"

let () = failwith "Main: not implemented"
