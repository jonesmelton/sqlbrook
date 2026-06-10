(* Emit pass: render a parsed statement to formatted SQL text.

   Manual right-padding into a Buffer — no Format boxes, since the river needs
   exact column control. Implements: clause river with leading-comma lists,
   `as` on its own line, insert mirror blocks, CTE end-shield form, DDL
   right-aligned names, and the semicolon rules (own line in content column;
   `) ;` across the river). Passthrough statements are emitted verbatim. *)

(* Format a single statement given its precomputed river width. *)
let emit_stmt (_buf : Buffer.t) (_width : int) (_stmt : Skeleton.stmt) : unit =
  failwith "Emit.emit_stmt: not implemented"

(* Format a whole statement list (the public entry point of the library). *)
let format (_stmts : Skeleton.stmt list) : string =
  failwith "Emit.format: not implemented"
